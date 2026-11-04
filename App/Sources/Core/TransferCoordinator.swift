import Foundation
import Network
import Security
import os

private let logger = Logger(subsystem: "app.airdropwheel2.macos", category: "TransferCoordinator")

public enum TransferState: Equatable, Sendable {
    case idle
    case pending
    case requestingAcceptance(recipientName: String)
    case accepted(recipientName: String)
    case transferring(recipientName: String, progress: Double)
    case completed(recipientName: String)
    case declined(recipientName: String)
    case failed(recipientName: String, reason: String)
    case cancelled
}

@MainActor
public final class TransferCoordinator: ObservableObject {
    @Published public private(set) var state: TransferState = .idle

    private let logger = Logger(subsystem: "app.airdropwheel2.macos", category: "TransferCoordinator")
    private var activeConnection: NWConnection?
    private var transferID: UUID?
    private var currentDecoder = DiscoverHTTPDecoder()
    private var isCancelled = false

    public init() {}

    public func cancel() {
        isCancelled = true
        activeConnection?.cancel()
        activeConnection = nil
        state = .cancelled
    }

    public func send(payload: TransferPayload, to recipient: Recipient) {
        cancel()
        isCancelled = false
        state = .pending

        let tID = UUID()
        self.transferID = tID

        // 1. Setup TLS with strict certificate pinning (must match recipient.certificate)
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let targetCert = recipient.certificate
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, done in
            let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(trustRef) as? [SecCertificate],
                  let leaf = chain.first else {
                done(false)
                return
            }
            let certData = SecCertificateCopyData(leaf) as Data
            done(certData == targetCert)
        }, .main)

        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        params.includePeerToPeer = true
        if case .service(_, _, _, let interface) = recipient.endpoint, let interface {
            params.requiredInterface = interface
        }

        let connection = NWConnection(to: recipient.endpoint, using: params)
        self.activeConnection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] connState in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, !self.isCancelled, self.activeConnection === connection else { return }
                switch connState {
                case .ready:
                    self.sendOffer(connection, payload: payload, recipient: recipient, transferID: tID)
                case .failed(let err):
                    self.fail(recipient: recipient, reason: "連線失敗 (\(err.localizedDescription))")
                case .cancelled:
                    if !self.isCancelled && self.state == .pending {
                        self.fail(recipient: recipient, reason: "連線已中斷")
                    }
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func sendOffer(_ connection: NWConnection, payload: TransferPayload, recipient: Recipient, transferID: UUID) {
        state = .requestingAcceptance(recipientName: recipient.displayName)
        logger.info("Sending /Ask offer to recipient \(recipient.displayName), transferID: \(transferID.uuidString)")

        do {
            let offer = AirDropOffer(transferID: transferID, payload: payload)
            let offerData = try offer.request()

            connection.send(content: offerData, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, !self.isCancelled else { return }
                    if let error {
                        self.logger.error("Failed to send /Ask offer: \(error.localizedDescription)")
                        self.fail(recipient: recipient, reason: "發送請求失敗: \(error.localizedDescription)")
                        return
                    }
                    self.currentDecoder = DiscoverHTTPDecoder()
                    self.readOfferResponse(connection, payload: payload, recipient: recipient, transferID: transferID)
                }
            })
        } catch {
            logger.error("Failed to encode /Ask offer: \(error.localizedDescription)")
            fail(recipient: recipient, reason: "編碼請求時發生錯誤")
        }
    }

    private func readOfferResponse(_ connection: NWConnection, payload: TransferPayload, recipient: Recipient, transferID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, eof, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, !self.isCancelled, self.activeConnection === connection else { return }

                do {
                    if let response = try self.currentDecoder.append(data ?? Data(), eof: eof) {
                        self.logger.info("Received /Ask response from \(recipient.displayName): status \(response.status)")
                        if response.status == 200 {
                            // Accepted by receiver!
                            self.state = .accepted(recipientName: recipient.displayName)

                            switch payload {
                            case .links:
                                // Links mode: native AirDrop opens the URL directly on acceptance!
                                connection.cancel()
                                self.activeConnection = nil
                                self.state = .completed(recipientName: recipient.displayName)

                            case .files(let items):
                                // Files mode: perform chunked upload
                                self.startUpload(connection, items: items, recipient: recipient, transferID: transferID)
                            }
                        } else {
                            // Declined or rejected by receiver
                            self.logger.info("Receiver \(recipient.displayName) declined or rejected the transfer (status: \(response.status))")
                            connection.cancel()
                            self.activeConnection = nil
                            self.state = .declined(recipientName: recipient.displayName)
                        }
                    } else if let error {
                        self.logger.error("Connection error waiting for /Ask response: \(error.localizedDescription)")
                        self.fail(recipient: recipient, reason: "等候對方回應時連線中斷")
                    } else if eof {
                        self.logger.error("Connection closed by peer while waiting for /Ask response")
                        self.fail(recipient: recipient, reason: "等候對方回應時連線中斷")
                    } else {
                        self.readOfferResponse(connection, payload: payload, recipient: recipient, transferID: transferID)
                    }
                } catch {
                    self.logger.error("Failed to decode /Ask response: \(error.localizedDescription)")
                    self.fail(recipient: recipient, reason: "解析對方回應時發生錯誤")
                }
            }
        }
    }

    private func startUpload(_ connection: NWConnection, items: [ValidatedTransferItem], recipient: Recipient, transferID: UUID) {
        let totalBytes = items.reduce(UInt64(0)) { $0 + $1.byteSize }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let archive = try AirDropCPIOArchive.buildArchive(for: items)
                let chunks = AirDropCPIOArchive.makeStreamChunks(from: archive)

                DispatchQueue.main.async {
                    guard let self, !self.isCancelled, self.activeConnection === connection else { return }
                    self.sendChunkedUpload(connection, chunks: chunks, recipient: recipient, transferID: transferID, totalBytes: totalBytes)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.logger.error("Failed to build CPIO archive: \(error.localizedDescription)")
                    self?.fail(recipient: recipient, reason: "封裝檔案時發生錯誤")
                }
            }
        }
    }

    private func sendChunkedUpload(_ connection: NWConnection, chunks: [Data], recipient: Recipient, transferID: UUID, totalBytes: UInt64) {
        let header = "POST /Upload HTTP/1.1\r\nHost: localhost\r\nUser-Agent: AirDrop/1.0\r\nTransferID: \(transferID.uuidString.uppercased())\r\nTotalBytes: \(totalBytes)\r\nContent-Type: application/x-cpio\r\nConnection: keep-alive\r\nTransfer-Encoding: chunked\r\n\r\n"

        logger.info("Starting chunked /Upload to \(recipient.displayName), totalBytes: \(totalBytes), chunksCount: \(chunks.count)")
        self.state = .transferring(recipientName: recipient.displayName, progress: 0.05)

        // 1. Send HTTP request headers
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, !self.isCancelled else { return }
                if let error {
                    self.logger.error("Failed to send /Upload header: \(error.localizedDescription)")
                    self.fail(recipient: recipient, reason: "傳送檔案標頭失敗: \(error.localizedDescription)")
                    return
                }

                // 2. Stream chunks sequentially
                self.sendNextChunk(connection, chunks: chunks, index: 0, recipient: recipient)
            }
        })
    }

    private func sendNextChunk(_ connection: NWConnection, chunks: [Data], index: Int, recipient: Recipient) {
        if index >= chunks.count {
            // Final zero-length chunk
            let zeroChunk = Data("0\r\n\r\n".utf8)
            connection.send(content: zeroChunk, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, !self.isCancelled else { return }
                    if let error {
                        self.logger.error("Failed to send final 0-chunk: \(error.localizedDescription)")
                        self.fail(recipient: recipient, reason: "傳送檔案結尾失敗: \(error.localizedDescription)")
                        return
                    }

                    self.logger.info("All chunks sent successfully, waiting for final /Upload receipt...")
                    self.currentDecoder = DiscoverHTTPDecoder()
                    self.readFinalUploadResponse(connection, recipient: recipient)
                }
            })
            return
        }

        let chunk = chunks[index]
        let hexLen = String(chunk.count, radix: 16)
        var chunkPayload = Data("\(hexLen)\r\n".utf8)
        chunkPayload.append(chunk)
        chunkPayload.append(Data("\r\n".utf8))

        connection.send(content: chunkPayload, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, !self.isCancelled else { return }
                if let error {
                    self.logger.error("Failed to send chunk #\(index): \(error.localizedDescription)")
                    self.fail(recipient: recipient, reason: "傳送檔案資料失敗: \(error.localizedDescription)")
                    return
                }

                let progress = Double(index + 1) / Double(chunks.count)
                self.state = .transferring(recipientName: recipient.displayName, progress: progress)
                self.sendNextChunk(connection, chunks: chunks, index: index + 1, recipient: recipient)
            }
        })
    }

    private func readFinalUploadResponse(_ connection: NWConnection, recipient: Recipient) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, eof, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, !self.isCancelled, self.activeConnection === connection else { return }
                do {
                    if let response = try self.currentDecoder.append(data ?? Data(), eof: eof) {
                        self.logger.info("Received final /Upload response: status \(response.status)")
                        connection.cancel()
                        self.activeConnection = nil
                        if response.status == 200 {
                            self.state = .completed(recipientName: recipient.displayName)
                        } else {
                            self.fail(recipient: recipient, reason: "接收端回報錯誤 (\(response.status))")
                        }
                    } else if let error {
                        self.logger.error("Network error reading final /Upload response: \(error.localizedDescription)")
                        self.fail(recipient: recipient, reason: "傳送完成後確認逾時")
                    } else if eof {
                        self.logger.error("Connection closed by peer before final /Upload response was received")
                        self.fail(recipient: recipient, reason: "傳送完成後連線關閉")
                    } else {
                        self.readFinalUploadResponse(connection, recipient: recipient)
                    }
                } catch {
                    self.logger.error("Failed to parse final /Upload response: \(error.localizedDescription)")
                    self.fail(recipient: recipient, reason: "讀取接收確認時發生錯誤")
                }
            }
        }
    }

    private func fail(recipient: Recipient, reason: String) {
        logger.error("Transfer failed for recipient \(recipient.displayName): \(reason)")
        activeConnection?.cancel()
        activeConnection = nil
        state = .failed(recipientName: recipient.displayName, reason: reason)
    }
}

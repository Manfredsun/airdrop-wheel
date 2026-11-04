import Foundation
import Network
import Security

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
        if case .service(_, _, _, let interface) = recipient.endpoint {
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

        do {
            let offer = AirDropOffer(transferID: transferID, payload: payload)
            let offerData = try offer.request()

            connection.send(content: offerData, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, !self.isCancelled else { return }
                    if let error {
                        self.fail(recipient: recipient, reason: "發送請求失敗: \(error.localizedDescription)")
                        return
                    }
                    self.currentDecoder = DiscoverHTTPDecoder()
                    self.readOfferResponse(connection, payload: payload, recipient: recipient, transferID: transferID)
                }
            })
        } catch {
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
                            connection.cancel()
                            self.activeConnection = nil
                            self.state = .declined(recipientName: recipient.displayName)
                        }
                    } else if error != nil {
                        self.fail(recipient: recipient, reason: "等候對方回應時連線中斷")
                    } else {
                        self.readOfferResponse(connection, payload: payload, recipient: recipient, transferID: transferID)
                    }
                } catch {
                    self.fail(recipient: recipient, reason: "解析對方回應時發生錯誤")
                }
            }
        }
    }

    private func startUpload(_ connection: NWConnection, items: [ValidatedTransferItem], recipient: Recipient, transferID: UUID) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let archive = try AirDropCPIOArchive.buildArchive(for: items)
                let chunks = AirDropCPIOArchive.dvzipChunks(from: archive)

                DispatchQueue.main.async {
                    guard let self, !self.isCancelled, self.activeConnection === connection else { return }
                    self.sendChunkedUpload(connection, chunks: chunks, recipient: recipient, transferID: transferID)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.fail(recipient: recipient, reason: "封裝檔案時發生錯誤")
                }
            }
        }
    }

    private func sendChunkedUpload(_ connection: NWConnection, chunks: [Data], recipient: Recipient, transferID: UUID) {
        let header = "POST /Upload HTTP/1.1\r\nUser-Agent: AirDrop/1.0\r\nTransferID: \(transferID.uuidString)\r\nTotalBytes: 0\r\nContent-Type: application/x-dvzip\r\nConnection: keep-alive\r\nTransfer-Encoding: chunked\r\n\r\n"

        var fullPayload = Data(header.utf8)
        let totalCount = max(1, chunks.count)

        for (index, chunk) in chunks.enumerated() {
            let hexLen = String(chunk.count, radix: 16)
            fullPayload.append(Data("\(hexLen)\r\n".utf8))
            fullPayload.append(chunk)
            fullPayload.append(Data("\r\n".utf8))

            let progress = Double(index + 1) / Double(totalCount)
            self.state = .transferring(recipientName: recipient.displayName, progress: progress)
        }

        // Final zero-length chunk
        fullPayload.append(Data("0\r\n\r\n".utf8))

        connection.send(content: fullPayload, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, !self.isCancelled else { return }
                if let error {
                    self.fail(recipient: recipient, reason: "傳送檔案資料失敗: \(error.localizedDescription)")
                    return
                }

                // Read final HTTP 200 response from receiver
                self.currentDecoder = DiscoverHTTPDecoder()
                self.readFinalUploadResponse(connection, recipient: recipient)
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
                        connection.cancel()
                        self.activeConnection = nil
                        if response.status == 200 {
                            self.state = .completed(recipientName: recipient.displayName)
                        } else {
                            self.fail(recipient: recipient, reason: "接收端回報錯誤 (\(response.status))")
                        }
                    } else if error != nil {
                        self.fail(recipient: recipient, reason: "傳送完成後確認逾時")
                    } else {
                        self.readFinalUploadResponse(connection, recipient: recipient)
                    }
                } catch {
                    self.fail(recipient: recipient, reason: "讀取接收確認時發生錯誤")
                }
            }
        }
    }

    private func fail(recipient: Recipient, reason: String) {
        activeConnection?.cancel()
        activeConnection = nil
        state = .failed(recipientName: recipient.displayName, reason: reason)
    }
}

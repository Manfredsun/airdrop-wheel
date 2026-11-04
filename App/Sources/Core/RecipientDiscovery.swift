import Foundation
import Network
import Security
import AppKit

public enum DeviceKind: String, Sendable, CaseIterable {
    case iPhone
    case iPad
    case mac
    case unknown

    public var systemSymbolName: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "macbook"
        case .unknown: return "display"
        }
    }
}

public struct Recipient: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let modelName: String
    public let kind: DeviceKind
    public let endpoint: NWEndpoint
    public let certificate: Data
    public let lastSeen: Date

    public static func == (lhs: Recipient, rhs: Recipient) -> Bool {
        lhs.id == rhs.id
    }
}

private final class DiscoveryCertBox: @unchecked Sendable {
    var data: Data?
}

@MainActor
public final class LiveRecipientDiscovery: ObservableObject {
    @Published public private(set) var recipients: [Recipient] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private var wakeBrowser: NSObject?
    private var activeConnections: [NWEndpoint: NWConnection] = [:]
    private var knownCertificates: [NWEndpoint: Data] = [:]
    private var recipientMap: [NWEndpoint: Recipient] = [:]
    private var isStarted = false

    public init() {}

    public func startDiscovery() {
        guard !isStarted else { return }
        isStarted = true
        isSearching = true
        startWakeBrowser()
        startBonjourBrowser()
    }

    public func stopDiscovery() {
        isStarted = false
        isSearching = false
        browser?.cancel()
        browser = nil

        if let wake = wakeBrowser {
            _ = wake.perform(NSSelectorFromString("stop"))
            wakeBrowser = nil
        }

        for (_, conn) in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        knownCertificates.removeAll()
        recipientMap.removeAll()
        recipients.removeAll()
    }

    private func startWakeBrowser() {
        guard wakeBrowser == nil else { return }
        if NSClassFromString("SFAirDropBrowser") == nil {
            Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework")?.load()
        }
        guard let cls = NSClassFromString("SFAirDropBrowser") as? NSObject.Type else { return }
        let instance = cls.init()
        wakeBrowser = instance
        _ = instance.perform(NSSelectorFromString("start"))
    }

    private func startBonjourBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let b = NWBrowser(for: .bonjour(type: "_airdrop._tcp", domain: "local."), using: params)
        self.browser = b

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                var currentEndpoints = Set<NWEndpoint>()

                for result in results {
                    let ep = result.endpoint
                    currentEndpoints.insert(ep)
                    if self.recipientMap[ep] == nil && self.activeConnections[ep] == nil {
                        self.probeEndpoint(ep)
                    }
                }

                // Remove stale endpoints
                for ep in Array(self.recipientMap.keys) {
                    if !currentEndpoints.contains(ep) {
                        self.recipientMap.removeValue(forKey: ep)
                        self.knownCertificates.removeValue(forKey: ep)
                    }
                }
                self.publishRecipients()
            }
        }

        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isSearching = true
                case .failed, .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }

        b.start(queue: .main)
    }

    private func probeEndpoint(_ endpoint: NWEndpoint) {
        let tls = NWProtocolTLS.Options()
        let certBox = DiscoveryCertBox()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        // Capture leaf certificate during handshake
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, done in
            let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(trustRef) as? [SecCertificate], let leaf = chain.first {
                certBox.data = SecCertificateCopyData(leaf) as Data
            }
            done(true)
        }, .main)

        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        params.includePeerToPeer = true
        if case .service(_, _, _, let interface) = endpoint {
            params.requiredInterface = interface
        }

        let connection = NWConnection(to: endpoint, using: params)
        activeConnections[endpoint] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, self.isStarted, self.activeConnections[endpoint] === connection else { return }
                switch state {
                case .ready:
                    self.sendDiscoverRequest(connection, endpoint: endpoint, certBox: certBox)
                case .failed, .cancelled:
                    self.activeConnections.removeValue(forKey: endpoint)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)

        // 8-second probe timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak connection] in
            guard let self, let connection, self.activeConnections[endpoint] === connection else { return }
            connection.cancel()
            self.activeConnections.removeValue(forKey: endpoint)
        }
    }

    private func sendDiscoverRequest(_ connection: NWConnection, endpoint: NWEndpoint, certBox: DiscoveryCertBox) {
        do {
            let requestData = try DiscoverReply.request()
            connection.send(content: requestData, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, self.isStarted, error == nil else {
                        self?.activeConnections.removeValue(forKey: endpoint)?.cancel()
                        return
                    }
                    self.readDiscoverResponse(connection, endpoint: endpoint, decoder: DiscoverHTTPDecoder(), certBox: certBox)
                }
            })
        } catch {
            activeConnections.removeValue(forKey: endpoint)?.cancel()
        }
    }

    private func readDiscoverResponse(_ connection: NWConnection, endpoint: NWEndpoint, decoder: DiscoverHTTPDecoder, certBox: DiscoveryCertBox) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, eof, error in
            guard let connection else { return }
            Task { @MainActor in
                guard let self, self.isStarted, self.activeConnections[endpoint] === connection else { return }
                var curDecoder = decoder

                do {
                    if let response = try curDecoder.append(data ?? Data(), eof: eof) {
                        connection.cancel()
                        self.activeConnections.removeValue(forKey: endpoint)

                        guard response.status == 200,
                              let plist = (try? PropertyListSerialization.propertyList(from: response.body, format: nil)) as? [String: Any],
                              let name = plist["ReceiverComputerName"] as? String, !name.isEmpty,
                              let cert = certBox.data else {
                            return
                        }

                        let model = (plist["ReceiverModelName"] as? String ?? "").lowercased()
                        let kind: DeviceKind
                        if model.contains("iphone") {
                            kind = .iPhone
                        } else if model.contains("ipad") {
                            kind = .iPad
                        } else if model.contains("mac") {
                            kind = .mac
                        } else {
                            kind = .unknown
                        }

                        let recipient = Recipient(
                            id: UUID().uuidString,
                            displayName: name,
                            modelName: model,
                            kind: kind,
                            endpoint: endpoint,
                            certificate: cert,
                            lastSeen: Date()
                        )

                        self.knownCertificates[endpoint] = cert
                        self.recipientMap[endpoint] = recipient
                        self.publishRecipients()
                    } else if error != nil {
                        connection.cancel()
                        self.activeConnections.removeValue(forKey: endpoint)
                    } else {
                        self.readDiscoverResponse(connection, endpoint: endpoint, decoder: curDecoder, certBox: certBox)
                    }
                } catch {
                    connection.cancel()
                    self.activeConnections.removeValue(forKey: endpoint)
                }
            }
        }
    }

    private func publishRecipients() {
        self.recipients = Array(recipientMap.values).sorted { $0.displayName < $1.displayName }
    }
}

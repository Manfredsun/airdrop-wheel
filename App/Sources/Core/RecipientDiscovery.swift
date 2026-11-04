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

private final class AirDropWakeDelegate: NSObject {
    @objc func browserWillChangePeople(_ b: AnyObject) {}
    @objc func browserDidChangePeople(_ b: AnyObject) {}
}

@MainActor
public final class LiveRecipientDiscovery: ObservableObject {
    @Published public private(set) var recipients: [Recipient] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private var wakeBrowser: NSObject?
    private var wakeDelegate: AirDropWakeDelegate?
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
            wakeDelegate = nil
        }

        for (_, conn) in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        knownCertificates.removeAll()
        recipientMap.removeAll()
        recipients.removeAll()
    }

    public func updatePayloadURLs(_ urls: [URL]) {
        guard !urls.isEmpty, let wake = wakeBrowser else { return }
        wake.setValue(urls, forKey: "urlsBeingShared")
    }

    private func startWakeBrowser(with urls: [URL] = []) {
        guard wakeBrowser == nil else {
            if !urls.isEmpty {
                wakeBrowser?.setValue(urls, forKey: "urlsBeingShared")
            }
            return
        }
        if NSClassFromString("SFAirDropBrowser") == nil {
            Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework")?.load()
        }
        guard let cls = NSClassFromString("SFAirDropBrowser") as? NSObject.Type else { return }
        let instance = cls.init()
        let del = AirDropWakeDelegate()
        self.wakeDelegate = del
        instance.setValue(del, forKey: "delegate")

        // Set urlsBeingShared so sharingd actively transmits BLE wake pulses for nearby iOS devices
        let targetURLs = !urls.isEmpty ? urls : [URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("airdrop_probe.dat")]
        instance.setValue(targetURLs, forKey: "urlsBeingShared")

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
                    let awdl = result.interfaces.first(where: { $0.name == "awdl0" })
                    let ep: NWEndpoint
                    if case .service(let name, let type, let domain, let iface) = result.endpoint {
                        let chosenIface = (iface?.name == "awdl0" ? iface : awdl) ?? iface
                        ep = .service(name: name, type: type, domain: domain, interface: chosenIface)
                    } else {
                        ep = result.endpoint
                    }

                    currentEndpoints.insert(ep)
                    if self.recipientMap[ep] == nil && self.activeConnections[ep] == nil {
                        self.probeEndpoint(ep)
                    }
                }

                // Remove stale endpoints based on service name
                let currentNames = Set(currentEndpoints.compactMap { ep -> String? in
                    if case .service(let name, _, _, _) = ep { return name }
                    return nil
                })

                for ep in Array(self.recipientMap.keys) {
                    if case .service(let name, _, _, _) = ep, !currentNames.contains(name) {
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
        if case .service(_, _, _, let interface) = endpoint, let interface {
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

                        let rawModel = plist["ReceiverModelName"] as? String ?? ""
                        let model = rawModel.lowercased()
                        let nameLower = name.lowercased()

                        let kind: DeviceKind
                        if model.contains("iphone") || nameLower.contains("iphone") {
                            kind = .iPhone
                        } else if model.contains("ipad") || nameLower.contains("ipad") {
                            kind = .iPad
                        } else if model.contains("mac") || nameLower.contains("mac") {
                            kind = .mac
                        } else if plist["ReceiverMediaCapabilities"] != nil || model.isEmpty {
                            // iOS devices (iPhones) omit ReceiverModelName in /Discover,
                            // but always include ReceiverMediaCapabilities with LivePhoto/HEIC capabilities.
                            kind = .iPhone
                        } else {
                            kind = .unknown
                        }

                        let finalModelName: String
                        if !rawModel.isEmpty {
                            finalModelName = rawModel
                        } else {
                            switch kind {
                            case .iPhone: finalModelName = "iPhone"
                            case .iPad: finalModelName = "iPad"
                            case .mac: finalModelName = "Mac"
                            case .unknown: finalModelName = "Apple Device"
                            }
                        }

                        let recipient = Recipient(
                            id: UUID().uuidString,
                            displayName: name,
                            modelName: finalModelName,
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

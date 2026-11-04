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

    public var iconName: String {
        let m = modelName.lowercased()
        if m.contains("imac") { return "desktopcomputer" }
        if m.contains("mini") || m.contains("studio") || m.contains("mac pro") { return "macmini" }
        if m.contains("macbook") || m.contains("laptop") || m.contains("notebook") || m.contains("筆電") { return "macbook" }
        return kind.systemSymbolName
    }

    public static func == (lhs: Recipient, rhs: Recipient) -> Bool {
        lhs.id == rhs.id
    }
}

private final class DiscoveryCertBox: @unchecked Sendable {
    var data: Data?
}

private final class AirDropWakeDelegate: NSObject {
    var onPeopleChanged: (([NSObject]) -> Void)?

    @objc func browserWillChangePeople(_ b: AnyObject) {}
    @objc func browserDidChangePeople(_ b: AnyObject) {
        if let people = b.value(forKey: "people") as? [NSObject] {
            onPeopleChanged?(people)
        }
    }
}

public enum DeviceClassifier {
    public static func classify(
        computerName: String,
        rawModel: String = "",
        knownModel: String? = nil,
        mediaCapabilities: Any? = nil
    ) -> (kind: DeviceKind, modelName: String) {
        let nameLower = computerName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rawLower = rawModel.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let knownLower = (knownModel ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Apple SFAirDropNode known model match (highest fidelity from system Sharing framework)
        if !knownLower.isEmpty {
            if knownLower.contains("mac") || knownLower.contains("imac") || knownLower.contains("book") {
                return (.mac, knownModel ?? "Mac")
            } else if knownLower.contains("ipad") {
                return (.iPad, knownModel ?? "iPad")
            } else if knownLower.contains("iphone") {
                return (.iPhone, knownModel ?? "iPhone")
            }
        }

        // 2. Explicit rawModel from protocol response
        if !rawLower.isEmpty {
            if rawLower.contains("mac") || rawLower.contains("imac") || rawLower.contains("book") {
                return (.mac, rawModel)
            } else if rawLower.contains("ipad") {
                return (.iPad, rawModel)
            } else if rawLower.contains("iphone") {
                return (.iPhone, rawModel)
            }
        }

        // 3. Multi-lingual keywords for Mac / Laptops / Desktops
        if nameLower.contains("macbook pro") || nameLower.contains("mbp") {
            return (.mac, "MacBook Pro")
        } else if nameLower.contains("macbook air") || nameLower.contains("mba") {
            return (.mac, "MacBook Air")
        } else if nameLower.contains("mac mini") {
            return (.mac, "Mac mini")
        } else if nameLower.contains("mac studio") {
            return (.mac, "Mac Studio")
        } else if nameLower.contains("mac pro") {
            return (.mac, "Mac Pro")
        } else if nameLower.contains("imac") {
            return (.mac, "iMac")
        } else if nameLower.contains("macbook") || nameLower.contains("laptop") || nameLower.contains("notebook") || nameLower.contains("book") || nameLower.contains("筆電") || nameLower.contains("筆記型") {
            return (.mac, "MacBook")
        } else if nameLower.contains("mac") || nameLower.contains("電腦") || nameLower.contains("desktop") || nameLower.contains("pc") {
            return (.mac, "Mac")
        }

        // 4. iPad keywords
        if nameLower.contains("ipad pro") {
            return (.iPad, "iPad Pro")
        } else if nameLower.contains("ipad air") {
            return (.iPad, "iPad Air")
        } else if nameLower.contains("ipad mini") {
            return (.iPad, "iPad mini")
        } else if nameLower.contains("ipad") {
            return (.iPad, "iPad")
        }

        // 5. iPhone keywords
        if nameLower.contains("iphone") {
            return (.iPhone, "iPhone")
        }

        // 6. Safe Neutral Default: If name is pure personal name (e.g. "Muffin"),
        // DO NOT blindly guess iPhone! Return generic Apple Device.
        return (.unknown, "Apple 裝置")
    }
}

@MainActor
public final class LiveRecipientDiscovery: ObservableObject {
    @Published public private(set) var recipients: [Recipient] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private var wakeBrowser: NSObject?
    private var wakeDelegate: AirDropWakeDelegate?
    private var nodeModelCache: [String: String] = [:]
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
        del.onPeopleChanged = { [weak self] people in
            Task { @MainActor in
                self?.handleDiscoveredPeople(people)
            }
        }
        self.wakeDelegate = del
        instance.setValue(del, forKey: "delegate")

        // Set urlsBeingShared so sharingd actively transmits BLE wake pulses for nearby iOS devices
        let targetURLs = !urls.isEmpty ? urls : [URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("airdrop_probe.dat")]
        instance.setValue(targetURLs, forKey: "urlsBeingShared")

        wakeBrowser = instance
        _ = instance.perform(NSSelectorFromString("start"))
    }

    private func handleDiscoveredPeople(_ people: [NSObject]) {
        var updated = false
        for person in people {
            let model = (person.value(forKey: "model") as? String)
                ?? (person.value(forKey: "secondaryName") as? String)
                ?? ""
            guard !model.isEmpty else { continue }

            if let dName = (person.value(forKey: "displayName") as? String) ?? (person.value(forKey: "name") as? String), !dName.isEmpty {
                nodeModelCache[dName.lowercased()] = model
            }
            if let rName = person.value(forKey: "realName") as? String, !rName.isEmpty {
                nodeModelCache[rName.lowercased()] = model
            }
        }

        for (ep, recipient) in recipientMap {
            let nameLower = recipient.displayName.lowercased()
            let direct = nodeModelCache[nameLower]
            let fuzzy = direct ?? nodeModelCache.first(where: { k, _ in
                nameLower.contains(k) || k.contains(nameLower)
            })?.value

            let (newKind, newModel) = DeviceClassifier.classify(
                computerName: recipient.displayName,
                knownModel: fuzzy
            )
            if newKind != recipient.kind || (newModel != recipient.modelName && newModel != "Apple 裝置") {
                let updatedRecipient = Recipient(
                    id: recipient.id,
                    displayName: recipient.displayName,
                    modelName: newModel,
                    kind: newKind,
                    endpoint: recipient.endpoint,
                    certificate: recipient.certificate,
                    lastSeen: recipient.lastSeen
                )
                recipientMap[ep] = updatedRecipient
                updated = true
            }
        }

        if updated {
            publishRecipients()
        }
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
                        let nameLower = name.lowercased()
                        let knownModel = self.nodeModelCache[nameLower] ?? self.nodeModelCache.first(where: { k, _ in
                            nameLower.contains(k) || k.contains(nameLower)
                        })?.value

                        let (kind, finalModelName) = DeviceClassifier.classify(
                            computerName: name,
                            rawModel: rawModel,
                            knownModel: knownModel,
                            mediaCapabilities: plist["ReceiverMediaCapabilities"]
                        )

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

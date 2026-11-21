import Foundation
import Network
import Security
import AppKit
import SystemConfiguration
import os

private let discoveryLogger = Logger(subsystem: "app.airdropwheel.macos", category: "RecipientDiscovery")

public enum DiscoveryHint: Equatable, Sendable {
    case none
    case searching
    case contactsOnlyLikely
}

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

public enum LocalDeviceDetector {
    public static func normalizeName(_ name: String) -> String {
        let lower = name.lowercased()
        let filtered = lower.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    public static func getLocalHostNames() -> Set<String> {
        var names = Set<String>()
        if let loc = Host.current().localizedName {
            names.insert(loc)
        }
        if let comp = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            names.insert(comp)
        }
        if let localHost = SCDynamicStoreCopyLocalHostName(nil) as String? {
            names.insert(localHost)
        }
        let hName = ProcessInfo.processInfo.hostName
        names.insert(hName)
        if hName.hasSuffix(".local") {
            names.insert(String(hName.dropLast(6)))
        }
        return names
    }

    public static func getLocalIPAddresses() -> Set<String> {
        var addresses = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            guard (flags & (IFF_UP|IFF_RUNNING)) == (IFF_UP|IFF_RUNNING) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    let cleanIP = ip.components(separatedBy: "%").first ?? ip
                    addresses.insert(cleanIP.lowercased())
                }
            }
        }
        return addresses
    }

    public static func isSelfName(_ candidate: String) -> Bool {
        let norm = normalizeName(candidate)
        guard !norm.isEmpty else { return false }
        let localHostNorms = Set(getLocalHostNames().map(normalizeName))
        return localHostNorms.contains(norm)
    }

    public static func isSelfConnection(_ path: NWPath?) -> Bool {
        guard let path,
              case .hostPort(let remoteHost, _) = path.remoteEndpoint,
              case .hostPort(let localHost, _) = path.localEndpoint else {
            return false
        }

        if remoteHost == localHost {
            return true
        }

        let remoteIPStr: String
        switch remoteHost {
        case .ipv4(let ip): remoteIPStr = "\(ip)"
        case .ipv6(let ip): remoteIPStr = "\(ip)"
        case .name(let name, _): remoteIPStr = name
        @unknown default: remoteIPStr = ""
        }
        let cleanRemote = remoteIPStr.components(separatedBy: "%").first?.lowercased() ?? remoteIPStr.lowercased()
        if cleanRemote == "127.0.0.1" || cleanRemote == "::1" {
            return true
        }

        if getLocalIPAddresses().contains(cleanRemote) {
            return true
        }

        return false
    }
}

@MainActor
public final class LiveRecipientDiscovery: ObservableObject {
    @Published public private(set) var recipients: [Recipient] = []
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var discoveryHint: DiscoveryHint = .searching

    private var browser: NWBrowser?
    private var wakeBrowser: NSObject?
    private var wakeDelegate: AirDropWakeDelegate?
    private var nodeModelCache: [String: String] = [:]
    private var knownEndpoints: [String: NWEndpoint] = [:]
    private var activeConnections: [String: NWConnection] = [:]
    private var knownCertificates: [String: Data] = [:]
    private var recipientMap: [String: Recipient] = [:]
    private var probeAttempts: [String: Int] = [:]
    private var retryWorkItems: [String: DispatchWorkItem] = [:]
    private var rejectedServiceKeys: Set<String> = []
    private var selfServiceKeys: Set<String> = []
    private var wakePeopleCount: Int = 0
    private var lastWakePulseDate: Date?
    private var isWheelActive: Bool = false
    private var wheelReprobeTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sleepWakeWorkItem: DispatchWorkItem?
    private var isStarted = false

    public init() {}

    public func startDiscovery() {
        guard !isStarted else { return }
        isStarted = true
        isSearching = true
        updateDiscoveryHint()

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.handleSystemWake()
                }
            }
        }

        startWakeBrowser()
        startBonjourBrowser()
    }

    private func handleSystemWake() {
        guard isStarted else { return }
        discoveryLogger.info("System didWakeNotification received; scheduling discovery refresh")
        sleepWakeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.isStarted else { return }
                self.refreshDiscovery()
            }
        }
        sleepWakeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    public func stopDiscovery() {
        isStarted = false
        isSearching = false
        isWheelActive = false

        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        sleepWakeWorkItem?.cancel()
        sleepWakeWorkItem = nil

        wheelReprobeTimer?.invalidate()
        wheelReprobeTimer = nil

        browser?.cancel()
        browser = nil

        if let wake = wakeBrowser {
            _ = wake.perform(NSSelectorFromString("stop"))
            wakeBrowser = nil
            wakeDelegate = nil
        }

        for (_, item) in retryWorkItems {
            item.cancel()
        }
        retryWorkItems.removeAll()

        for (_, conn) in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()

        knownEndpoints.removeAll()
        knownCertificates.removeAll()
        recipientMap.removeAll()
        recipients.removeAll()
        probeAttempts.removeAll()
        rejectedServiceKeys.removeAll()
        selfServiceKeys.removeAll()
        nodeModelCache.removeAll()
        wakePeopleCount = 0
        lastWakePulseDate = nil
        discoveryHint = .searching
    }

    public func updatePayloadURLs(_ urls: [URL]) {
        guard !urls.isEmpty, let wake = wakeBrowser else { return }
        wake.setValue(urls, forKey: "urlsBeingShared")
    }

    public func pulseDiscovery(with urls: [URL] = []) {
        if !isStarted {
            startDiscovery()
        }

        let now = Date()
        let elapsed = lastWakePulseDate.map { now.timeIntervalSince($0) } ?? .infinity
        let shouldRestartWake = elapsed >= 5.0 || (recipients.isEmpty && elapsed >= 2.0)

        if shouldRestartWake {
            startWakeBrowser(with: urls, forceRestart: true)
        } else if !urls.isEmpty {
            updatePayloadURLs(urls)
        }

        for key in knownEndpoints.keys where !selfServiceKeys.contains(key) && recipientMap[key] == nil {
            probeAttempts.removeValue(forKey: key)
        }
        probeUnresolvedEndpoints(includeRejected: true)
    }

    public func setWheelActive(_ active: Bool) {
        isWheelActive = active
        wheelReprobeTimer?.invalidate()
        wheelReprobeTimer = nil

        guard active else { return }
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isStarted, self.isWheelActive else { return }
                self.probeUnresolvedEndpoints(includeRejected: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wheelReprobeTimer = timer
    }

    public func refreshDiscovery() {
        discoveryLogger.info("Manual/wake discovery refresh triggered")
        let wasWheelActive = isWheelActive
        stopDiscovery()
        startDiscovery()
        if wasWheelActive {
            setWheelActive(true)
        }
    }

    private func serviceKey(for endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint {
            return name
        }
        return String(describing: endpoint)
    }

    private func ensureProbeFileURL() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("airdrop_wheel_probe.tmp")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data([0x00]).write(to: url, options: .atomic)
        }
        return url
    }

    private func startWakeBrowser(with urls: [URL] = [], forceRestart: Bool = false) {
        if forceRestart, let existing = wakeBrowser {
            _ = existing.perform(NSSelectorFromString("stop"))
            wakeBrowser = nil
            wakeDelegate = nil
        }

        guard wakeBrowser == nil else {
            if !urls.isEmpty {
                wakeBrowser?.setValue(urls, forKey: "urlsBeingShared")
            }
            return
        }
        if NSClassFromString("SFAirDropBrowser") == nil {
            Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework")?.load()
        }
        guard let cls = NSClassFromString("SFAirDropBrowser") as? NSObject.Type else {
            discoveryLogger.warning("SFAirDropBrowser class unavailable")
            return
        }
        let instance = cls.init()
        let del = AirDropWakeDelegate()
        del.onPeopleChanged = { [weak self] people in
            guard let self else { return }
            Task { @MainActor in
                guard self.isStarted else { return }
                self.handleDiscoveredPeople(people)
            }
        }
        self.wakeDelegate = del
        instance.setValue(del, forKey: "delegate")

        // Set urlsBeingShared with an existing file URL so sharingd actively transmits BLE wake pulses for nearby iOS devices
        let targetURLs = !urls.isEmpty ? urls : [ensureProbeFileURL()]
        instance.setValue(targetURLs, forKey: "urlsBeingShared")

        wakeBrowser = instance
        _ = instance.perform(NSSelectorFromString("start"))
        lastWakePulseDate = Date()
        discoveryLogger.info("Started SFAirDropBrowser BLE wake pulse")
    }

    private func handleDiscoveredPeople(_ people: [NSObject]) {
        wakePeopleCount = people.count
        discoveryLogger.info("SFAirDropBrowser reported \(people.count) nearby node(s)")
        var updated = false

        for person in people {
            // Do NOT filter out `me == true`! In Sharing.framework, `me == true` indicates
            // other devices signed into the same Apple ID (e.g., user's own iPhone/iPad), not this Mac.
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

        for (key, recipient) in recipientMap {
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
                recipientMap[key] = updatedRecipient
                updated = true
            }
        }

        updateDiscoveryHint()
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
            guard let self else { return }
            Task { @MainActor in
                guard self.isStarted else { return }
                var nextEndpoints: [String: NWEndpoint] = [:]

                for result in results {
                    let awdl = result.interfaces.first(where: { $0.name == "awdl0" })
                    let ep: NWEndpoint
                    let isAwdl: Bool
                    if case .service(let name, let type, let domain, let iface) = result.endpoint {
                        let chosenIface = (iface?.name == "awdl0" ? iface : awdl) ?? iface
                        ep = .service(name: name, type: type, domain: domain, interface: chosenIface)
                        isAwdl = (chosenIface?.name == "awdl0")
                    } else {
                        ep = result.endpoint
                        isAwdl = false
                    }

                    let key = self.serviceKey(for: ep)
                    if let existing = nextEndpoints[key] {
                        if case .service(_, _, _, let existingIface) = existing, existingIface?.name == "awdl0" {
                            continue
                        }
                        if isAwdl {
                            nextEndpoints[key] = ep
                        }
                    } else {
                        nextEndpoints[key] = ep
                    }
                }

                discoveryLogger.info("Bonjour browse updated: \(nextEndpoints.count) active service(s)")
                self.knownEndpoints = nextEndpoints

                // Remove stale endpoints based on canonical service key
                let validKeys = Set(nextEndpoints.keys)
                let trackedKeys = Set(self.activeConnections.keys)
                    .union(self.retryWorkItems.keys)
                    .union(self.recipientMap.keys)
                    .union(self.knownCertificates.keys)
                    .union(self.probeAttempts.keys)
                    .union(self.rejectedServiceKeys)
                    .union(self.selfServiceKeys)

                for key in trackedKeys where !validKeys.contains(key) {
                    self.activeConnections.removeValue(forKey: key)?.cancel()
                    self.retryWorkItems.removeValue(forKey: key)?.cancel()
                    self.recipientMap.removeValue(forKey: key)
                    self.knownCertificates.removeValue(forKey: key)
                    self.probeAttempts.removeValue(forKey: key)
                    self.rejectedServiceKeys.remove(key)
                    self.selfServiceKeys.remove(key)
                }

                self.probeUnresolvedEndpoints(includeRejected: false)
                self.updateDiscoveryHint()
                self.publishRecipients()
            }
        }

        b.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isSearching = true
                    discoveryLogger.info("NWBrowser ready for _airdrop._tcp")
                case .failed:
                    self.isSearching = false
                    discoveryLogger.error("NWBrowser failed")
                case .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }

        b.start(queue: .main)
    }

    private func probeUnresolvedEndpoints(includeRejected: Bool) {
        for (key, ep) in knownEndpoints {
            guard !selfServiceKeys.contains(key),
                  recipientMap[key] == nil,
                  activeConnections[key] == nil else {
                continue
            }
            if !includeRejected && rejectedServiceKeys.contains(key) {
                continue
            }
            retryWorkItems.removeValue(forKey: key)?.cancel()
            probeEndpoint(key: key, endpoint: ep)
        }
    }

    private func probeEndpoint(key: String, endpoint: NWEndpoint) {
        retryWorkItems.removeValue(forKey: key)?.cancel()

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
        activeConnections[key] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor in
                guard self.isStarted, self.activeConnections[key] === connection else { return }
                switch state {
                case .ready:
                    if LocalDeviceDetector.isSelfConnection(connection.currentPath) {
                        discoveryLogger.info("Filtered self connection over local interface")
                        self.selfServiceKeys.insert(key)
                        connection.cancel()
                        self.activeConnections.removeValue(forKey: key)
                        self.updateDiscoveryHint()
                        return
                    }
                    self.sendDiscoverRequest(connection, key: key, endpoint: endpoint, certBox: certBox)
                case .failed:
                    discoveryLogger.info("Probe connection failed; scheduling retry")
                    self.activeConnections.removeValue(forKey: key)
                    self.scheduleRetry(for: key)
                case .cancelled:
                    self.activeConnections.removeValue(forKey: key)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)

        // 8-second probe timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak connection] in
            guard let self, let connection else { return }
            Task { @MainActor in
                guard self.isStarted, self.activeConnections[key] === connection else { return }
                discoveryLogger.info("Probe connection timed out after 8s; scheduling retry")
                connection.cancel()
                self.activeConnections.removeValue(forKey: key)
                self.scheduleRetry(for: key)
            }
        }
    }

    private func scheduleRetry(for key: String) {
        guard isStarted,
              knownEndpoints[key] != nil,
              !selfServiceKeys.contains(key),
              recipientMap[key] == nil,
              activeConnections[key] == nil else {
            return
        }

        let delays: [TimeInterval] = [1.5, 3.0, 5.0, 8.0]
        let attempt = probeAttempts[key] ?? 0
        guard attempt < delays.count else {
            discoveryLogger.info("Exhausted backoff probe retries (count: \(attempt))")
            return
        }

        probeAttempts[key] = attempt + 1
        let delay = delays[attempt]
        discoveryLogger.info("Scheduling probe retry #\(attempt + 1) in \(delay)s")

        retryWorkItems.removeValue(forKey: key)?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.retryWorkItems.removeValue(forKey: key)
                guard self.isStarted,
                      let ep = self.knownEndpoints[key],
                      !self.selfServiceKeys.contains(key),
                      self.recipientMap[key] == nil,
                      self.activeConnections[key] == nil else {
                    return
                }
                self.probeEndpoint(key: key, endpoint: ep)
            }
        }
        retryWorkItems[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func sendDiscoverRequest(_ connection: NWConnection, key: String, endpoint: NWEndpoint, certBox: DiscoveryCertBox) {
        do {
            let requestData = try DiscoverReply.request()
            connection.send(content: requestData, completion: .contentProcessed { [weak self, weak connection] error in
                guard let self, let connection else { return }
                Task { @MainActor in
                    guard self.isStarted, self.activeConnections[key] === connection else { return }
                    if error != nil {
                        discoveryLogger.info("Failed sending /Discover request; scheduling retry")
                        self.activeConnections.removeValue(forKey: key)?.cancel()
                        self.scheduleRetry(for: key)
                        return
                    }
                    self.readDiscoverResponse(connection, key: key, endpoint: endpoint, decoder: DiscoverHTTPDecoder(), certBox: certBox)
                }
            })
        } catch {
            activeConnections.removeValue(forKey: key)?.cancel()
            scheduleRetry(for: key)
        }
    }

    private func readDiscoverResponse(_ connection: NWConnection, key: String, endpoint: NWEndpoint, decoder: DiscoverHTTPDecoder, certBox: DiscoveryCertBox) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, eof, error in
            guard let self, let connection else { return }
            Task { @MainActor in
                guard self.isStarted, self.activeConnections[key] === connection else { return }
                var curDecoder = decoder

                do {
                    if let response = try curDecoder.append(data ?? Data(), eof: eof) {
                        connection.cancel()
                        self.activeConnections.removeValue(forKey: key)

                        guard response.status == 200,
                              let plist = (try? PropertyListSerialization.propertyList(from: response.body, format: nil)) as? [String: Any],
                              let name = plist["ReceiverComputerName"] as? String, !name.isEmpty,
                              let cert = certBox.data else {
                            self.rejectedServiceKeys.insert(key)
                            self.recipientMap.removeValue(forKey: key)
                            discoveryLogger.info("Endpoint declined /Discover (status: \(response.status)); likely Contacts Only mode")
                            self.updateDiscoveryHint()
                            self.publishRecipients()
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

                        // Filter out local Mac ONLY (never filter iPhone/iPad sharing the same user name or Apple ID)
                        if LocalDeviceDetector.isSelfConnection(connection.currentPath) ||
                           (kind != .iPhone && kind != .iPad && LocalDeviceDetector.isSelfName(name)) {
                            discoveryLogger.info("Filtered self Mac device after /Discover")
                            self.selfServiceKeys.insert(key)
                            self.updateDiscoveryHint()
                            return
                        }

                        self.rejectedServiceKeys.remove(key)
                        self.probeAttempts.removeValue(forKey: key)
                        self.retryWorkItems.removeValue(forKey: key)?.cancel()

                        let recipient = Recipient(
                            id: UUID().uuidString,
                            displayName: name,
                            modelName: finalModelName,
                            kind: kind,
                            endpoint: endpoint,
                            certificate: cert,
                            lastSeen: Date()
                        )

                        self.knownCertificates[key] = cert
                        self.recipientMap[key] = recipient
                        discoveryLogger.info("Discovered recipient kind: \(kind.rawValue, privacy: .public), active count: \(self.recipientMap.count)")
                        self.updateDiscoveryHint()
                        self.publishRecipients()
                    } else if error != nil {
                        connection.cancel()
                        self.activeConnections.removeValue(forKey: key)
                        self.scheduleRetry(for: key)
                    } else {
                        self.readDiscoverResponse(connection, key: key, endpoint: endpoint, decoder: curDecoder, certBox: certBox)
                    }
                } catch {
                    connection.cancel()
                    self.activeConnections.removeValue(forKey: key)
                    self.scheduleRetry(for: key)
                }
            }
        }
    }

    private func updateDiscoveryHint() {
        if !recipientMap.isEmpty {
            discoveryHint = .none
        } else if !rejectedServiceKeys.isEmpty || wakePeopleCount > 0 {
            discoveryHint = .contactsOnlyLikely
        } else {
            discoveryHint = .searching
        }
    }

    private func publishRecipients() {
        self.recipients = recipientMap.values.sorted { $0.displayName < $1.displayName }
    }
}

import AppKit
import Combine

@MainActor
public final class AppController: ObservableObject {
    public static let shared = AppController()

    public let discovery = LiveRecipientDiscovery()
    public let coordinator = TransferCoordinator()
    public let overlay = WheelOverlay()
    public let hud = TransferHUD.shared
    public let dragWatcher = FinderDragWatcher()

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupBindings()
    }

    public func start() {
        // Start background AirDrop discovery
        discovery.startDiscovery()

        // Start global Finder drag watcher
        dragWatcher.isWheelOpen = { [weak self] in
            self?.overlay.isOpen ?? false
        }

        dragWatcher.onTrigger = { [weak self] payload, point in
            self?.showWheel(at: point, payload: payload)
        }

        dragWatcher.onRelease = { [weak self] in
            // Handled inside WheelOverlay via mouseReleased/performDragOperation
        }

        dragWatcher.start()
    }

    public func stop() {
        dragWatcher.stop()
        discovery.stopDiscovery()
        overlay.close()
        coordinator.cancel()
    }

    private func setupBindings() {
        // Forward discovered recipients to WheelOverlay
        discovery.$recipients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.overlay.updateRecipients(list, isSearching: self.discovery.isSearching)
            }
            .store(in: &cancellables)

        // Handle sending when user drops/clicks on a recipient sector
        overlay.onSendToRecipient = { [weak self] payload, recipient in
            guard let self else { return }
            self.hud.show(
                recipientName: recipient.displayName,
                headline: payload.headline,
                onCancel: { [weak self] in
                    self?.coordinator.cancel()
                }
            )
            self.coordinator.send(payload: payload, to: recipient)
        }

        // Forward transfer progress to TransferHUD
        coordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.hud.update(state: state)
            }
            .store(in: &cancellables)
    }

    public func showWheel(at point: NSPoint, payload: TransferPayload) {
        if case .files(let items) = payload {
            discovery.updatePayloadURLs(items.map(\.url))
        }
        overlay.show(at: point, payload: payload, recipients: discovery.recipients)
    }

    public func selectFilesAndOpenWheel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "以 AirDrop Wheel 傳送"

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self, response == .OK, !panel.urls.isEmpty else { return }
            switch TransferPayloadValidator.validate(urls: panel.urls) {
            case .success(let payload):
                let centerPoint: NSPoint
                if let screen = NSScreen.main {
                    centerPoint = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
                } else {
                    centerPoint = NSEvent.mouseLocation
                }
                self.showWheel(at: centerPoint, payload: payload)

            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "無法傳送"
                alert.informativeText = error.message
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

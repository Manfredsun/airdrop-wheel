import AppKit
import SwiftUI

private final class WheelPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onTab: (() -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onEscape?()
        case 48, 14: // Tab, E
            onTab?()
        default:
            super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > 3 || abs(event.scrollingDeltaX) > 3 {
            onScroll?(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

private final class WheelPanelHostView: NSHostingView<WheelView> {
    weak var overlay: WheelOverlay?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        overlay?.updateHover(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        overlay?.updateHover(at: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        overlay?.mouseReleased(at: event.locationInWindow)
    }

    // MARK: - Drag Destination Support
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        overlay?.updateHover(at: sender.draggingLocation)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        overlay?.updateHover(at: sender.draggingLocation)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        overlay?.model.setHoveredIndex(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        overlay?.mouseReleased(at: sender.draggingLocation)
        return true
    }
}

@MainActor
public final class WheelOverlay: ObservableObject {
    public let model = WheelModel()

    private var panel: WheelPanel?
    private var hostView: WheelPanelHostView?
    private let panelSize: CGFloat = 640
    public private(set) var isOpen = false

    public var onSendToRecipient: ((TransferPayload, Recipient) -> Void)?

    public init() {
        model.onSelectRecipient = { [weak self] recipient in
            guard let self, let payload = self.model.payload else { return }
            self.close()
            self.onSendToRecipient?(payload, recipient)
        }

        model.onCancel = { [weak self] in
            self?.close()
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let p = WheelPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize, height: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hasShadow = false

        let host = WheelPanelHostView(rootView: WheelView(model: model))
        host.overlay = self
        host.registerForDraggedTypes([.fileURL, .URL, .string])
        p.contentView = host

        p.onEscape = { [weak self] in self?.close() }
        p.onTab = { [weak self] in self?.model.nextPage() }
        p.onScroll = { [weak self] _ in self?.model.nextPage() }

        self.panel = p
        self.hostView = host
    }

    public func show(at screenPoint: NSPoint, payload: TransferPayload, recipients: [Recipient]) {
        ensurePanel()
        guard let p = panel else { return }

        model.payload = payload
        model.recipients = recipients
        model.page = 0
        model.hoveredIndex = nil

        // Position panel centered at screenPoint
        var origin = CGPoint(x: screenPoint.x - panelSize / 2, y: screenPoint.y - panelSize / 2)

        // Clamp to screen bounds
        if let screen = NSScreen.screens.first(where: { NSPointInRect(screenPoint, $0.frame) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            origin.x = max(frame.minX, min(origin.x, frame.maxX - panelSize))
            origin.y = max(frame.minY, min(origin.y, frame.maxY - panelSize))
        }

        p.setFrameOrigin(origin)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        isOpen = true
    }

    public func updateRecipients(_ list: [Recipient], isSearching: Bool) {
        model.recipients = list
        model.isSearching = isSearching
    }

    public func close() {
        guard isOpen, let p = panel else { return }
        isOpen = false
        model.hoveredIndex = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }

    func updateHover(at windowLocation: NSPoint) {
        let center = CGPoint(x: panelSize / 2, y: panelSize / 2)
        let dx = windowLocation.x - center.x
        let dy = windowLocation.y - center.y
        let dist = hypot(dx, dy)

        // Deadzone: center hub or too far outside wheel
        let deadZone = WheelTheme.innerRadius * 0.9
        let maxRadius = WheelTheme.outerRadius * 1.05

        if dist < deadZone || dist > maxRadius {
            model.setHoveredIndex(nil)
            return
        }

        var theta = atan2(dx, dy)
        if theta < 0 { theta += 2 * .pi }
        let index = Int((theta + .pi / 8.0) / (.pi / 4.0)) % WheelTheme.sectorCount
        model.setHoveredIndex(index)
    }

    func mouseReleased(at windowLocation: NSPoint) {
        updateHover(at: windowLocation)
        if let target = model.hoveredRecipient {
            model.onSelectRecipient?(target)
        } else {
            close()
        }
    }
}

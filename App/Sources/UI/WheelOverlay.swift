import AppKit
import SwiftUI

private final class OverlayPanel: NSPanel {
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

private final class OverlayRootView: NSHostingView<AnyView> {
    weak var overlay: WheelOverlay?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        overlay?.handleMouseLocation(event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        overlay?.handleMouseLocation(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        overlay?.handleMouseRelease(event.locationInWindow)
    }

    // MARK: - Drag Destination Support
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        overlay?.handleMouseLocation(sender.draggingLocation)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        overlay?.handleMouseLocation(sender.draggingLocation)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        overlay?.model.setHoveredIndex(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        overlay?.handleMouseRelease(sender.draggingLocation)
        return true
    }
}

private struct OverlayContainerView: View {
    @ObservedObject var overlay: WheelOverlay
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-screen soft dimming layer
                Color.black
                    .opacity(colorScheme == .dark ? 0.36 : 0.26)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        overlay.close()
                    }

                // Centered Wheel positioned at clamped mouse center
                WheelView(model: overlay.model)
                    .scaleEffect(overlay.popScale)
                    .opacity(overlay.popOpacity)
                    .position(overlay.wheelPositionInView(size: proxy.size))
            }
        }
    }
}

@MainActor
public final class WheelOverlay: ObservableObject {
    public let model = WheelModel()

    @Published var popScale: CGFloat = 0.92
    @Published var popOpacity: Double = 0.0

    private var panel: OverlayPanel?
    private var hostView: OverlayRootView?
    public private(set) var isOpen = false

    private var wheelCenterScreenPoint: NSPoint = .zero
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

    private func ensurePanel(for screen: NSScreen) {
        let frame = screen.frame
        if let p = panel {
            p.setFrame(frame, display: true)
            return
        }

        let p = OverlayPanel(
            contentRect: frame,
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

        let container = OverlayContainerView(overlay: self)
        let host = OverlayRootView(rootView: AnyView(container))
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
        let screen = NSScreen.screens.first(where: { NSPointInRect(screenPoint, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        ensurePanel(for: screen)

        guard let p = panel else { return }

        model.payload = payload
        model.recipients = recipients
        model.page = 0
        model.hoveredIndex = nil

        // Clamp wheel center so that 540px wheel stays fully visible
        let visible = screen.visibleFrame
        let radius = WheelTheme.outerRadius + 50.0 // buffer for badges
        var clampedX = max(visible.minX + radius, min(screenPoint.x, visible.maxX - radius))
        var clampedY = max(visible.minY + radius, min(screenPoint.y, visible.maxY - radius))

        // On small screen where frame < radius * 2, use center
        if visible.width < radius * 2 { clampedX = visible.midX }
        if visible.height < radius * 2 { clampedY = visible.midY }

        self.wheelCenterScreenPoint = NSPoint(x: clampedX, y: clampedY)

        // Reset animation states
        popScale = 0.92
        popOpacity = 0.0

        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()

        withAnimation(.spring(response: 0.18, dampingFraction: 0.74)) {
            self.popScale = 1.0
            self.popOpacity = 1.0
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

        withAnimation(.easeOut(duration: 0.12)) {
            self.popOpacity = 0.0
            self.popScale = 0.95
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.isOpen else { return }
            p.orderOut(nil)
        }
    }

    func wheelPositionInView(size: CGSize) -> CGPoint {
        guard let p = panel else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let winOrigin = p.frame.origin
        let localX = wheelCenterScreenPoint.x - winOrigin.x
        // Convert AppKit bottom-up Y to SwiftUI top-down Y
        let localY = size.height - (wheelCenterScreenPoint.y - winOrigin.y)
        return CGPoint(x: localX, y: localY)
    }

    func handleMouseLocation(_ windowPoint: NSPoint) {
        guard let p = panel else { return }
        let screenY = p.frame.origin.y + windowPoint.y
        let screenX = p.frame.origin.x + windowPoint.x

        let dx = screenX - wheelCenterScreenPoint.x
        let dy = screenY - wheelCenterScreenPoint.y
        let dist = hypot(dx, dy)

        // Inside center hub dead zone -> hover is nil
        if dist < WheelTheme.centerDeadZone {
            model.setHoveredIndex(nil)
            return
        }

        // Sector angle calculation (0 = Top / 12 o'clock, clockwise)
        var theta = atan2(dx, dy)
        if theta < 0 { theta += 2 * .pi }
        let index = Int((theta + .pi / 8.0) / (.pi / 4.0)) % WheelTheme.sectorCount
        model.setHoveredIndex(index)
    }

    func handleMouseRelease(_ windowPoint: NSPoint) {
        handleMouseLocation(windowPoint)
        if let target = model.hoveredRecipient {
            model.onSelectRecipient?(target)
        } else {
            close()
        }
    }
}

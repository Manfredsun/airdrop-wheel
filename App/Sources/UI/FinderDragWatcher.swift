import AppKit

@MainActor
public final class FinderDragWatcher {
    public var onTrigger: ((TransferPayload, NSPoint) -> Void)?
    public var onRelease: (() -> Void)?
    public var isWheelOpen: () -> Bool = { false }

    private let pasteboard = NSPasteboard(name: .drag)
    private var monitors: [Any] = []
    private var timer: Timer?
    private var isDragging = false
    private var isFired = false
    private var lastControl = false
    private var baselineChangeCount = 0

    public init() {}

    public func start() {
        guard monitors.isEmpty else { return }

        if let m1 = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            Task { @MainActor in self?.handleMouseDown() }
        }) {
            monitors.append(m1)
        }

        if let m2 = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            Task { @MainActor in self?.handleMouseDragged() }
        }) {
            monitors.append(m2)
        }
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timer?.invalidate()
        timer = nil
        isDragging = false
        isFired = false
    }

    private func handleMouseDown() {
        baselineChangeCount = pasteboard.changeCount
        isDragging = false
        isFired = false
        lastControl = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
        startTimer()
    }

    private func handleMouseDragged() {
        isDragging = true
        if timer == nil {
            startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        self.timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func poll() {
        // If left mouse button is no longer pressed, end session
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if isFired {
                onRelease?()
            }
            timer?.invalidate()
            timer = nil
            isDragging = false
            isFired = false
            return
        }

        let controlActive = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
        let controlNewlyPressed = controlActive && !lastControl
        lastControl = controlActive

        // Trigger condition: mouse is dragging AND (Control was newly pressed OR Control is held) AND wheel is not open yet
        guard (controlNewlyPressed || (controlActive && isDragging)) && !isFired && !isWheelOpen() else {
            return
        }

        // Read dragged objects from drag pasteboard
        guard pasteboard.changeCount != baselineChangeCount,
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty,
              case .success(let payload) = TransferPayloadValidator.validate(urls: urls) else {
            return
        }

        isFired = true
        let mouseLoc = NSEvent.mouseLocation
        onTrigger?(payload, mouseLoc)
    }
}

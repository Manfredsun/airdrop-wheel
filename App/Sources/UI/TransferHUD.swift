import AppKit
import SwiftUI

@MainActor
public final class TransferHUD: ObservableObject {
    public static let shared = TransferHUD()

    @Published public var isVisible: Bool = false
    @Published public var iconName: String = "hand.raised"
    @Published public var title: String = ""
    @Published public var detail: String = ""
    @Published public var progress: Double? = nil
    @Published public var isTerminal: Bool = false

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var onCancelAction: (() -> Void)?

    public init() {}

    private func ensurePanel() {
        if panel != nil { return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 68),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.hasShadow = true

        let host = NSHostingView(rootView: TransferHUDView(hud: self))
        p.contentView = host
        self.panel = p
    }

    public func show(recipientName: String, headline: String, onCancel: @escaping () -> Void) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        self.onCancelAction = onCancel
        self.isTerminal = false

        self.iconName = "hand.raised"
        self.title = "等候 \(recipientName) 同意"
        self.detail = headline
        self.progress = nil
        self.isVisible = true

        ensurePanel()
        guard let p = panel else { return }

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.maxX - 310
            let y = visible.minY + 30
            p.setFrame(NSRect(x: x, y: y, width: 290, height: 68), display: true)
        }

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            p.animator().alphaValue = 1
        }
    }

    public func update(state: TransferState) {
        guard isVisible else { return }

        switch state {
        case .idle:
            hide()

        case .pending:
            iconName = "clock"
            title = "準備傳送中..."
            progress = nil

        case .requestingAcceptance(let recipientName):
            iconName = "hand.raised"
            title = "等候 \(recipientName) 同意"
            progress = nil

        case .accepted(let recipientName):
            iconName = "checkmark.shield"
            title = "\(recipientName) 已同意接收"
            progress = 0.0

        case .transferring(let recipientName, let pct):
            iconName = "arrow.up"
            let percentInt = Int(pct * 100)
            title = "傳送至 \(recipientName) (\(percentInt)%)"
            progress = pct

        case .completed(let recipientName):
            iconName = "checkmark.circle.fill"
            title = "傳送成功"
            detail = "已傳送至 \(recipientName)"
            progress = 1.0
            isTerminal = true
            scheduleDismiss(after: 2.5)

        case .declined(let recipientName):
            iconName = "hand.raised.slash"
            title = "對方拒絕接收"
            detail = "\(recipientName) 拒絕了傳送請求"
            progress = nil
            isTerminal = true
            scheduleDismiss(after: 2.8)

        case .failed(let recipientName, let reason):
            iconName = "exclamationmark.triangle.fill"
            title = "傳送失敗"
            detail = "\(recipientName): \(reason)"
            progress = nil
            isTerminal = true
            scheduleDismiss(after: 3.5)

        case .cancelled:
            hide()
        }
    }

    public func cancel() {
        onCancelAction?()
        hide()
    }

    public func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        isVisible = false

        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

private struct TransferHUDView: View {
    @ObservedObject var hud: TransferHUD

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: hud.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)

            // Titles
            VStack(alignment: .leading, spacing: 3) {
                Text(hud.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let progress = hud.progress, progress < 1.0 {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: WheelTheme.cyanGlow))
                        .frame(height: 4)
                } else if !hud.detail.isEmpty {
                    Text(hud.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Cancel Button (if not terminal)
            if !hud.isTerminal {
                Button(action: { hud.cancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }

    private var iconColor: Color {
        if hud.iconName.contains("checkmark") {
            return .green
        } else if hud.iconName.contains("exclamation") || hud.iconName.contains("slash") {
            return .orange
        } else {
            return WheelTheme.cyanGlow
        }
    }
}

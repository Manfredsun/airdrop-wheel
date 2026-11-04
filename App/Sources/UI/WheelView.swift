import SwiftUI

public struct RingSectorShape: Shape {
    public let index: Int
    public var count: Int = WheelTheme.sectorCount

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width / 2
        let inner = outer * 0.48
        let step = 360.0 / Double(count)
        let startDeg = Double(index) * step - 90.0 - (step / 2.0) + 1.5
        let endDeg = Double(index) * step - 90.0 + (step / 2.0) - 1.5

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(endDeg), endAngle: .degrees(startDeg), clockwise: true)
        path.closeSubpath()
        return path
    }
}

public struct SectorOuterArcShape: Shape {
    public let index: Int
    public var count: Int = WheelTheme.sectorCount

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width / 2
        let step = 360.0 / Double(count)
        let startDeg = Double(index) * step - 90.0 - (step / 2.0) + 1.5
        let endDeg = Double(index) * step - 90.0 + (step / 2.0) - 1.5

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
        return path
    }
}

public struct WheelView: View {
    @ObservedObject public var model: WheelModel

    public init(model: WheelModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            // Dark vignette background
            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 12) {
                // Top Title Badge
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.cross")
                        .foregroundColor(WheelTheme.cyanGlow)
                    Text("AirDrop Wheel 2")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if model.isSearching {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                // Main Radial Wheel
                ZStack {
                    // Base wheel circle background
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: WheelTheme.wheelDiameter, height: WheelTheme.wheelDiameter)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)

                    // 8 Sectors
                    ForEach(0..<WheelTheme.sectorCount, id: \.self) { idx in
                        sectorView(for: idx)
                    }

                    // Center Hub
                    centerHubView
                }
                .frame(width: WheelTheme.wheelDiameter, height: WheelTheme.wheelDiameter)

                // Bottom Page / Instruction Badge
                if model.totalPages > 1 {
                    HStack(spacing: 8) {
                        Text("第 \(model.page + 1) / \(model.totalPages) 頁")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Text("· 滾輪或 Tab 翻頁")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                } else {
                    Text("拖曳至裝置並放手即傳送 · 移回中心或按 Esc 取消")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                }
            }
        }
    }

    @ViewBuilder
    private func sectorView(for index: Int) -> some View {
        let isHovered = (model.hoveredIndex == index)
        let visible = model.visibleRecipients
        let recipient = (index < visible.count) ? visible[index] : nil

        ZStack {
            // Sector background fill
            RingSectorShape(index: index)
                .fill(
                    isHovered
                        ? (recipient != nil ? WheelTheme.cyanGlow.opacity(0.35) : Color.white.opacity(0.15))
                        : Color.white.opacity(0.04)
                )

            // Outer arc stroke on hover
            if isHovered && recipient != nil {
                SectorOuterArcShape(index: index)
                    .stroke(WheelTheme.cyanGlow, lineWidth: 3.5)
                    .shadow(color: WheelTheme.cyanGlow, radius: 8, x: 0, y: 0)
            }

            // Sector content label positioned around circle
            sectorLabel(for: index, recipient: recipient, isHovered: isHovered)
        }
    }

    private func sectorLabel(for index: Int, recipient: Recipient?, isHovered: Bool) -> some View {
        let angleDeg = Double(index) * (360.0 / Double(WheelTheme.sectorCount)) - 90.0
        let angleRad = angleDeg * .pi / 180.0
        let r = (WheelTheme.outerRadius + WheelTheme.innerRadius) / 2.0
        let x = r * cos(angleRad)
        let y = r * sin(angleRad)

        return Group {
            if let recipient {
                VStack(spacing: 3) {
                    Image(systemName: recipient.kind.systemSymbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isHovered ? .white : .white.opacity(0.85))

                    Text(recipient.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 90)

                    Text("未驗證身分")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                VStack(spacing: 2) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 8, height: 8)
                    Text("搜尋中...")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .offset(x: x, y: y)
    }

    private var centerHubView: some View {
        let isHovered = model.hoveredRecipient != nil
        let hubSize = WheelTheme.innerRadius * 1.8

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: hubSize, height: hubSize)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isHovered ? WheelTheme.cyanGlow.opacity(0.6) : Color.white.opacity(0.15),
                            lineWidth: isHovered ? 2 : 1
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)

            if let target = model.hoveredRecipient {
                VStack(spacing: 4) {
                    Image(systemName: target.kind.systemSymbolName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(WheelTheme.cyanGlow)

                    Text(target.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: hubSize * 0.8)

                    Text("放手即傳送")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(WheelTheme.cyanGlow)
                }
                .transition(.scale.combined(with: .opacity))
            } else if let payload = model.payload {
                VStack(spacing: 4) {
                    Image(systemName: payload.systemSymbolName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))

                    Text(payload.headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: hubSize * 0.8)

                    if let bytesText = payload.totalBytesText {
                        Text(bytesText)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("朝裝置放手傳送")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.5))

                    Text("請拖曳檔案")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .animation(.easeInOut(duration: 0.12), value: model.hoveredIndex)
    }
}

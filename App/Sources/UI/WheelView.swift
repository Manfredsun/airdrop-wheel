import SwiftUI

public struct RingSectorShape: Shape {
    public let index: Int
    public var count: Int = WheelTheme.sectorCount
    public var innerRadius: CGFloat = WheelTheme.innerRadius
    public var outerRadius: CGFloat = WheelTheme.outerRadius

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(count)
        let startDeg = Double(index) * step - 90.0 - (step / 2.0) + 1.2
        let endDeg = Double(index) * step - 90.0 + (step / 2.0) - 1.2

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: .degrees(endDeg), endAngle: .degrees(startDeg), clockwise: true)
        path.closeSubpath()
        return path
    }
}

public struct SectorOuterArcShape: Shape {
    public let index: Int
    public var count: Int = WheelTheme.sectorCount
    public var radius: CGFloat = WheelTheme.outerRadius - (WheelTheme.outerRimWidth / 2.0)

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(count)
        let startDeg = Double(index) * step - 90.0 - (step / 2.0) + 1.0
        let endDeg = Double(index) * step - 90.0 + (step / 2.0) - 1.0

        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
        return path
    }
}

public struct WheelRingBodyShape: Shape {
    public var outerRadius: CGFloat = WheelTheme.outerRadius
    public var innerRadius: CGFloat = WheelTheme.innerRadius

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
        path.addEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        return path
    }
}

public struct WheelDividerShape: Shape {
    public let index: Int
    public var count: Int = WheelTheme.sectorCount
    public var innerRadius: CGFloat = WheelTheme.innerRadius
    public var outerRadius: CGFloat = WheelTheme.outerRadius

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(count)
        let angleDeg = Double(index) * step - 90.0 + (step / 2.0)
        let angleRad = angleDeg * .pi / 180.0

        let p0 = CGPoint(
            x: center.x + innerRadius * cos(angleRad),
            y: center.y + innerRadius * sin(angleRad)
        )
        let p1 = CGPoint(
            x: center.x + outerRadius * cos(angleRad),
            y: center.y + outerRadius * sin(angleRad)
        )

        var path = Path()
        path.move(to: p0)
        path.addLine(to: p1)
        return path
    }
}

public struct WheelView: View {
    @ObservedObject public var model: WheelModel
    @Environment(\.colorScheme) var colorScheme

    public init(model: WheelModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            // Main Wheel Group
            ZStack {
                // 1. Ring Body Background with shadow
                WheelRingBodyShape()
                    .fill(WheelTheme.ringBackgroundColor(for: colorScheme), style: FillStyle(eoFill: true))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.6 : 0.22), radius: 24, x: 0, y: 10)

                // 2. Faint Outer border for tactile realism
                Circle()
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1)
                    .frame(width: WheelTheme.wheelDiameter, height: WheelTheme.wheelDiameter)

                // 3. 8 Radial Divider Lines from Hub to Outer Rim
                ForEach(0..<WheelTheme.sectorCount, id: \.self) { idx in
                    WheelDividerShape(index: idx)
                        .stroke(WheelTheme.dividerColor(for: colorScheme), lineWidth: 1.2)
                }

                // 4. 8 Sectors Content (Discovered devices or empty blank)
                ForEach(0..<WheelTheme.sectorCount, id: \.self) { idx in
                    sectorView(for: idx)
                }

                // 5. Center Hub Readout
                centerHubView
            }
            .frame(width: WheelTheme.wheelDiameter, height: WheelTheme.wheelDiameter)

            // Header Floating Badge
            topHeaderBadge
                .offset(y: -WheelTheme.outerRadius - 40)

            // Footer Floating Badge
            bottomFooterBadge
                .offset(y: WheelTheme.outerRadius + 40)
        }
    }

    // MARK: - Sector View
    @ViewBuilder
    private func sectorView(for index: Int) -> some View {
        let isHovered = (model.hoveredIndex == index)
        let visible = model.visibleRecipients
        let recipient = (index < visible.count) ? visible[index] : nil

        ZStack {
            if let recipient {
                // Background lift
                RingSectorShape(index: index)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))

                // Hover radial glow
                if isHovered {
                    let accent = WheelTheme.accentColor(for: colorScheme)
                    RingSectorShape(index: index)
                        .fill(
                            colorScheme == .dark
                                ? accent.opacity(0.38)
                                : accent.opacity(0.24)
                        )

                    // Thick 6pt Outer Rim Arc
                    SectorOuterArcShape(index: index)
                        .stroke(accent, lineWidth: WheelTheme.outerRimWidth)
                        .shadow(color: accent.opacity(0.8), radius: 10, x: 0, y: 0)
                }

                // Device Label
                sectorLabel(for: index, recipient: recipient, isHovered: isHovered)
            } else {
                // Empty slot: completely blank / faded out (only dividers show)
                Color.clear
            }
        }
    }

    private func sectorLabel(for index: Int, recipient: Recipient, isHovered: Bool) -> some View {
        let step = 360.0 / Double(WheelTheme.sectorCount)
        let angleDeg = Double(index) * step - 90.0
        let angleRad = angleDeg * .pi / 180.0
        let r = (WheelTheme.outerRadius + WheelTheme.innerRadius) / 2.0
        let x = r * cos(angleRad)
        let y = r * sin(angleRad)

        let textColor = WheelTheme.textColor(for: colorScheme)
        let accent = WheelTheme.accentColor(for: colorScheme)

        return VStack(spacing: 4) {
            Image(systemName: recipient.kind.systemSymbolName)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(isHovered ? accent : textColor.opacity(0.9))

            Text(recipient.displayName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(textColor)
                .lineLimit(1)
                .frame(maxWidth: 104)

            Text(recipient.modelName.isEmpty ? "AirDrop 裝置" : recipient.modelName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(WheelTheme.secondaryTextColor(for: colorScheme))
                .lineLimit(1)
                .frame(maxWidth: 104)
        }
        .offset(x: x, y: y)
    }

    // MARK: - Center Hub Readout
    private var centerHubView: some View {
        let isHovered = model.hoveredRecipient != nil
        let accent = WheelTheme.accentColor(for: colorScheme)
        let textColor = WheelTheme.textColor(for: colorScheme)

        return ZStack {
            // Hub background circle
            Circle()
                .fill(WheelTheme.hubBackgroundColor(for: colorScheme))
                .frame(width: WheelTheme.hubDiameter, height: WheelTheme.hubDiameter)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isHovered ? accent : WheelTheme.dividerColor(for: colorScheme),
                            lineWidth: isHovered ? 2.5 : 1.2
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 14, x: 0, y: 7)

            if let target = model.hoveredRecipient {
                // Hovered Target Device Readout
                VStack(spacing: 5) {
                    Image(systemName: target.kind.systemSymbolName)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(accent)

                    Text(target.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .frame(maxWidth: WheelTheme.hubDiameter * 0.82)

                    Text("放手即傳送")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(accent)
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else if let payload = model.payload {
                // Dragged Payload Readout
                VStack(spacing: 5) {
                    Image(systemName: payload.systemSymbolName)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(textColor.opacity(0.95))

                    Text(payload.headline)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .frame(maxWidth: WheelTheme.hubDiameter * 0.82)

                    if let bytesText = payload.totalBytesText {
                        Text(bytesText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(WheelTheme.secondaryTextColor(for: colorScheme))
                    } else {
                        Text("朝裝置放手傳送")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(WheelTheme.secondaryTextColor(for: colorScheme))
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(textColor.opacity(0.55))

                    Text("請拖曳檔案")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textColor.opacity(0.85))

                    Text("或放手至外圈裝置傳送")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(WheelTheme.secondaryTextColor(for: colorScheme))
                }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: model.hoveredIndex)
    }

    // MARK: - Header & Footer Badges
    private var topHeaderBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: "circle.grid.cross")
                .foregroundColor(WheelTheme.accentColor(for: colorScheme))
            Text("AirDrop Wheel 2")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(WheelTheme.textColor(for: colorScheme))
            if model.isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(WheelTheme.hubBackgroundColor(for: colorScheme))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WheelTheme.dividerColor(for: colorScheme), lineWidth: 1))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 8, x: 0, y: 4)
    }

    private var bottomFooterBadge: some View {
        Group {
            if model.totalPages > 1 {
                HStack(spacing: 8) {
                    Text("第 \(model.page + 1) / \(model.totalPages) 頁")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(WheelTheme.textColor(for: colorScheme))
                    Text("· 滾輪或 Tab 翻頁")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(WheelTheme.secondaryTextColor(for: colorScheme))
                }
            } else {
                Text("拖曳至裝置並放手即傳送 · 移回中心或按 Esc 取消")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WheelTheme.secondaryTextColor(for: colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(WheelTheme.hubBackgroundColor(for: colorScheme))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WheelTheme.dividerColor(for: colorScheme), lineWidth: 1))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 8, x: 0, y: 4)
    }
}

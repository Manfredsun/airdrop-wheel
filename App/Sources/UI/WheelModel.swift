import Foundation
import SwiftUI

@MainActor
public final class WheelModel: ObservableObject {
    @Published public var recipients: [Recipient] = []
    @Published public var payload: TransferPayload?
    @Published public var page: Int = 0
    @Published public var hoveredIndex: Int? = nil
    @Published public var isSearching: Bool = true
    @Published public var discoveryHint: DiscoveryHint = .searching

    public var onSelectRecipient: ((Recipient) -> Void)?
    public var onCancel: (() -> Void)?

    public init() {}

    public var totalPages: Int {
        max(1, Int(ceil(Double(recipients.count) / Double(WheelTheme.sectorCount))))
    }

    public var visibleRecipients: [Recipient] {
        let start = page * WheelTheme.sectorCount
        guard start < recipients.count else { return [] }
        let end = min(start + WheelTheme.sectorCount, recipients.count)
        return Array(recipients[start..<end])
    }

    public var hoveredRecipient: Recipient? {
        guard let idx = hoveredIndex else { return nil }
        let visible = visibleRecipients
        guard idx >= 0 && idx < visible.count else { return nil }
        return visible[idx]
    }

    public func setHoveredIndex(_ idx: Int?) {
        if hoveredIndex != idx {
            hoveredIndex = idx
        }
    }

    public func nextPage() {
        if page + 1 < totalPages {
            page += 1
            hoveredIndex = nil
        }
    }

    public func prevPage() {
        if page > 0 {
            page -= 1
            hoveredIndex = nil
        }
    }

    public func selectCurrent() {
        if let target = hoveredRecipient {
            onSelectRecipient?(target)
        }
    }

    public func cancel() {
        onCancel?()
    }
}

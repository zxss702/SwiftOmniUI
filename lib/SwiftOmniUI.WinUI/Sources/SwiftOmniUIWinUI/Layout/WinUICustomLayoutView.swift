// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A container an author's `Layout` arranges: the layout object pulled back
/// over the boundary, its children handed to it as `LayoutSubview`s measuring
/// through this view's items and placing through `place(_:at:)`.
@MainActor
final class WinUICustomLayoutView: WinUITravellingLayout {
    override var hasNativeProposals: Bool { true }
    override var contentSizeDependsOnHeight: Bool { true }

    /// The layout object that arranges the children.
    private var arrangement: LayoutBox?
    private var layoutRevision = -1

    /// The room inside the container's own edge.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// A fresh set of children and the layout that arranges them.
    func setItems(_ items: [WinUILayoutItem], layout: LayoutBox?) {
        let revision = sourceElement?.customLayoutRevision ?? 0
        let layoutChanged = arrangement !== layout || layoutRevision != revision
        layoutRevision = revision
        arrangement = layout
        let childrenChanged = super.setItems(items)
        layout?.update(subviews: subviews())
        if layoutChanged && !childrenChanged { invalidateMeasurements() }
    }

    /// The items as the layout sees them: measured through `size(offered:)`,
    /// placed through this view's arrangement, their `.layoutValue` tags and
    /// guides read back over the boundary.
    private func subviews(placing: ((WinUILayoutItem, Rect) -> Void)? = nil) -> LayoutSubviews {
        // A child riding its removal transition is no subview: it stands where it last stood.
        LayoutSubviews(items.filter { !$0.departing }.map { item in
            LayoutSubview(
                layoutValues: item.codeId.map { CoreLink().layoutValues(for: $0) } ?? [:],
                priority: item.values.priority,
                measureSize: { proposal in
                    let measured = item.size(offered: proposal)
                    return SwiftOmniUICore.Size(width: measured.width, height: measured.height)
                },
                measureDimensions: { proposal in
                    let measured = item.size(offered: proposal)
                    var guides: [Int32: Double] = [:]
                    var explicit: Set<Int32> = []
                    if let guide = item.values.horizontalGuide {
                        guides[guide.slot] = guide.offset
                        explicit.insert(guide.slot)
                    }
                    if let guide = item.values.verticalGuide {
                        guides[guide.slot] = guide.offset
                        explicit.insert(guide.slot)
                    }
                    return ViewDimensions(
                        width: measured.width, height: measured.height,
                        guides: guides, explicitSlots: explicit)
                },
                placeView: { position, anchor, proposal in
                    let measured = item.size(offered: proposal)
                    placing?(item, Rect(
                        x: position.x - anchor.x * measured.width,
                        y: position.y - anchor.y * measured.height,
                        width: measured.width, height: measured.height))
                })
        }, direction: direction)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        contentSize(proposal: ProposedViewSize(width: width))
    }

    override func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        guard let arrangement else { return .zero }
        let offered = ProposedViewSize(
            width: proposal.width.map { max(0, $0 - padding.left - padding.right) },
            height: proposal.height.map { max(0, $0 - padding.top - padding.bottom) })
        let measured = arrangement.measure(
            proposal: offered, subviews: subviews())
        return LayoutSize(
            width: measured.width + padding.left + padding.right,
            height: measured.height + padding.top + padding.bottom)
    }

    /// User layout code runs during Measure, where its child proposals can be
    /// committed to XAML before any native arrangement begins.
    override func makeLayoutPlan(in bounds: Rect) -> [NativeProposal] {
        guard let arrangement else { return [] }
        let room = Rect(
            x: bounds.x + padding.left, y: bounds.y + padding.top,
            width: max(0, bounds.width - padding.left - padding.right),
            height: max(0, bounds.height - padding.top - padding.bottom))
        var plan: [NativeProposal] = []
        arrangement.place(
            in: room,
            proposal: ProposedViewSize(width: room.width, height: room.height),
            subviews: subviews { item, place in
                plan.append(NativeProposal(view: item.view, place: place))
            })
        return plan
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(in: bounds)
        let arrangedItems = Dictionary(uniqueKeysWithValues: items.filter { !$0.departing }.map {
            (ObjectIdentifier($0.view), $0)
        })
        for proposal in preparedLayoutPlan(in: bounds) {
            guard let view = proposal.view,
                  let item = arrangedItems[ObjectIdentifier(view)] else { continue }
            place(item, at: proposal.place)
        }
    }
}

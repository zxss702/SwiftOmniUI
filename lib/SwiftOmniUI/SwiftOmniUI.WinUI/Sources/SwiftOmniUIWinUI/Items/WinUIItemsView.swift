// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// An List: a SwiftOmniUI layout holding WinUI's own List over the list's identities, a cell holding each
/// entry's subtree as the list asks for it (`ItemsCells`). WinUI scrolls, reuses its containers, chooses, invokes and
/// tells Narrator; SwiftOmniUI builds what a cell holds. The list is a room: it asks for none, and stands where it is put.
/// Design: docs/design/platforms/winui/items.md
@MainActor
final class WinUIItemsView: WinUILayoutView {
    let cells: ItemsCells

    /// WinUI's own list, which the relay's callbacks name.
    let list = WinUIItemsList()

    private var shape = ItemsLayout.list()
    private var hasAppliedLayout = false
    private var style = ListStyleKind.automatic
    private var choice: Choice?

    /// Every cell the list asked for: the relay keeps each container for the list's life, so each cell is the list's.
    private var made: [WinUIItemCell] = []

    /// Whether the list left the tree: what WinUI still says is heard by nobody.
    private var released = false
    private var barsInsets = EdgeInsets(0)
    private var pendingInsets: EdgeInsets?
    private var commitPending = false

    /// Whether the animation of a scroll the tree asks for is left out.
    private let reducesMotion: () -> Bool

    private struct Choice: Equatable {
        var chosen: [String]
        var mode: SelectionMode
        var invokable: Bool
    }

    init(cells: ItemsCells, reducesMotion: @escaping () -> Bool) {
        self.cells = cells
        self.reducesMotion = reducesMotion
        super.init()
        list.owner = self
        // ItemsView's template puts this padding on the ItemsRepeater inside
        // its ScrollView, so it scrolls with the content and leaves bars flush.
        swiftomniui_winui_set_padding(list.handle, 8, 8, 8, 8)
        list.placingLayout = self
        setChildren([list])
    }

    // MARK: - What the tree says

    /// The entries, the layout, how many may be chosen and which are. A
    /// `.sidebar` list sits on the platform's muted layer, a `.plain` one on
    /// no ground.
    func apply(layout: ItemsLayout, style: ListStyleKind, mode: SelectionMode) {
        if style != self.style {
            self.style = style
            swiftomniui_winui_items_set_style(list.handle, style.rawValue)
        }
        if !hasAppliedLayout || layout != shape {
            hasAppliedLayout = true
            shape = layout
            let (kind, spacing, minimum): (Int32, Double, Double) = switch layout {
            case .list(let spacing): (0, spacing, 0)
            case .row(let spacing): (1, spacing, 0)
            case .grid(let minimum, let spacing): (2, spacing, minimum)
            }
            swiftomniui_winui_items_set_layout(list.handle, kind, spacing, minimum)
            invalidateMeasurements()
        }
        if let changes = cells.takeEntries() { writeEntries(changes) }
        write(Choice(chosen: cells.selected, mode: mode, invokable: cells.element?.handler(.itemActivated) != nil))
    }

    /// Shows `choice` where it differs from what WinUI was last given, or always when `again`.
    private func write(_ choice: Choice, again: Bool = false) {
        guard again || choice != self.choice else { return }
        self.choice = choice
        WinUIStrings.withCStrings(choice.chosen) { chosen in
            swiftomniui_winui_items_set_choice(
                list.handle, choice.mode.rawValue, chosen, Int32(choice.chosen.count), choice.invokable)
        }
    }

    /// The identities with their kinds, and the changes as runs.
    private func writeEntries(_ changes: ItemsChanges) {
        let entries = cells.entries
        var edges = Set([entries.header, entries.footer].compactMap(\.self))
        for section in entries.sections { edges.formUnion([section.header, section.footer].compactMap(\.self)) }
        let identities = cells.identities
        let kinds = identities.map { edges.contains($0) ? Int32(1) : 0 }
        let runs = { (runs: [Range<Int>]) in runs.flatMap { [Int32($0.lowerBound), Int32($0.count)] } }
        let (removed, inserted) = (runs(changes.removedRuns), runs(changes.insertedRuns))
        WinUIStrings.withCStrings(identities) { names in
            swiftomniui_winui_items_set_entries(
                list.handle, names, kinds, Int32(identities.count), removed, Int32(removed.count), inserted,
                Int32(inserted.count))
        }
    }

    /// The tree's entries changed: every cell shows the subtree its entry has now (`ItemsCells.childrenChanged`).
    func childrenChanged() {
        cells.childrenChanged()
    }

    /// WinUI's list places the items, so it takes the element's direction; this layout stands left to right.
    /// Design: docs/design/platforms/winui/layout.md#right-to-left
    override func setDirection(_ direction: LayoutDirection) {
        super.setDirection(direction)
        self.direction = direction
        list.setDirection(direction)
    }

    override var directionHolder: WinUIView? { list }

    /// An entry's size would change: the cell holding it is measured again.
    func remeasure(_ item: MountedElement) {
        guard let identity = cells.identity(of: item) else { return }
        (cells.holding(of: identity) as? WinUIItemCell)?.invalidateMeasurements()
    }

    // MARK: - Its room

    /// As wide as it is offered and as tall as nothing asks: its room is what its layout gives it.
    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 0, height: 0)
    }

    override var hasNativeProposals: Bool { true }

    /// The list is a viewport spanning safe-area bars; its item repeater reserves their insets.
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        let viewport = resolve(in: Rect(0, 0, width ?? size.width, size.height))
        return [NativeProposal(view: list, place: viewport)]
    }

    override func restoreLayoutContext(in bounds: Rect, proposals: [NativeProposal]) {
        _ = resolve(in: bounds)
    }

    override func backgroundBounds(in bounds: Rect) -> Rect {
        let orientation: Axis = shape.isAcross ? .horizontal : .vertical
        return box.clips ? bounds : layoutSafeArea(in: bounds).viewport(in: bounds, axes: orientation)
    }

    override func safeAreaChanged() {
        if let context = safeAreaContext { _ = resolve(in: context.layout) }
        super.safeAreaChanged()
    }

    private func resolve(in bounds: Rect) -> Rect {
        let orientation: Axis = shape.isAcross ? .horizontal : .vertical
        let context = layoutSafeArea(in: bounds)
        let viewport = box.clips ? bounds : context.viewport(in: bounds, axes: orientation)
        let insets = SafeAreaContext.insets(of: context.safe, in: viewport)
        if barsInsets != insets { pendingInsets = insets }
        barsInsets = insets
        if pendingInsets != nil, !commitPending {
            commitPending = true
            WinUIDoorbell.afterPass { [weak self] in
                guard let self else { return }
                self.commitPending = false
                guard !self.released, let insets = self.pendingInsets else { return }
                self.pendingInsets = nil
                swiftomniui_winui_set_padding(
                    self.list.handle, 8 + insets.left, 8 + insets.top, 8 + insets.right, 8 + insets.bottom)
            }
        }
        return viewport
    }

    override func arrange(in bounds: Rect) {
        for proposal in preparedLayoutPlan(in: bounds) { proposal.view?.layout(proposal.place) }
    }

    // MARK: - What the list says

    /// A new cell, of an item or of a header or a footer; the list keeps it.
    func makeCell(item: Bool) -> WinUIItemCell {
        let cell = WinUIItemCell()
        cell.across = shape.isAcross
        cell.owner = self
        made.append(cell)
        return cell
    }

    func held(_ identity: String, in number: Int64) {
        guard !released, let cell = WinUIView.find(number) as? WinUIItemCell else { return }
        cell.across = shape.isAcross
        cells.hold(identity, in: cell)
    }

    func letGo(_ number: Int64) {
        guard !released, let cell = WinUIView.find(number) as? WinUIItemCell else { return }
        cells.endShowing(in: cell)
    }

    /// What the user chose. WinUI's container cannot refuse a header's or a footer's choosing, so a choice holding one
    /// is not the user's: WinUI shows the tree's choice again.
    func chose(_ identities: [String]) {
        guard !released else { return }
        guard identities.allSatisfy(cells.isItem) else {
            guard let choice else { return }
            write(Choice(chosen: cells.selected, mode: choice.mode, invokable: choice.invokable), again: true)
            return
        }
        cells.userChose(identities)
    }

    func invoked(_ identity: String) {
        guard !released else { return }
        cells.userActivated(identity)
    }

    func showing(_ places: ClosedRange<Int>) {
        guard !released else { return }
        let identities = cells.identities
        cells.showing(places.clamped(to: 0...max(identities.count - 1, 0)).compactMap {
            identities.indices.contains($0) ? identities[$0] : nil
        })
    }

    // MARK: - Acts

    /// Brings the item of `identity` where `anchor` says.
    func scroll(to identity: String, anchor: ScrollAnchor) {
        guard let place = cells.identities.firstIndex(of: identity) else { return }
        swiftomniui_winui_items_scroll_to(list.handle, Int32(place), anchor.rawValue, !reducesMotion())
    }

    /// The list left: WinUI lets its cells go, and they leave with it.
    override func detach() {
        super.detach()
        released = true
        pendingInsets = nil
        swiftomniui_winui_items_release(list.handle)
        made.removeAll()
    }

    // MARK: - For the tests

    /// The items WinUI holds chosen, in the order they show.
    var selectedForTesting: [String] {
        let chosen = Set(WinUIStrings.read { swiftomniui_winui_items_chosen(list.handle, $0, $1) }
            .split(separator: "\n").map(String.init))
        return cells.identities.filter(chosen.contains)
    }

    /// How many items WinUI lets the user choose.
    var modeForTesting: SelectionMode {
        SelectionMode(rawValue: swiftomniui_winui_items_mode(list.handle)) ?? .none
    }

    /// The item at `place` among all the items chosen, or let go where it was chosen and many may be - as a click does.
    func chooseForTesting(_ place: Int) {
        let items = cells.entries.sections.flatMap(\.items)
        guard items.indices.contains(place), let index = cells.identities.firstIndex(of: items[place]) else { return }
        swiftomniui_winui_items_choose_as_user(list.handle, Int32(index))
    }

    /// Opens the item of `identity` as Narrator does; false where no cell holds it.
    func activateForTesting(_ identity: String) -> Bool {
        guard let cell = cells.holding(of: identity) as? WinUIItemCell else { return false }
        return swiftomniui_winui_items_invoke_as_user(cell.handle)
    }

    /// Scrolls to `target`, as far as the list reaches: WinUI's compositor moves the view a moment later.
    func scrollForTesting(to target: Point) {
        swiftomniui_winui_items_scroll_as_user(list.handle, target.x, target.y)
    }

    /// Where the list's view stands, and the farthest it reaches, in DIPs.
    var standingForTesting: (offset: Point, reach: Point) {
        var values = [0.0, 0.0, 0.0, 0.0]
        swiftomniui_winui_items_offset(list.handle, &values)
        return (Point(x: values[0], y: values[1]), Point(x: values[2], y: values[3]))
    }
}

/// WinUI's own List, which the relay's callbacks name by its number and which hands them to its list.
@MainActor
final class WinUIItemsList: WinUIView {
    weak var owner: WinUIItemsView?

    override var takesDirection: Bool { true }

    init() {
        super.init(allocation: { swiftomniui_winui_hosted_viewport_make($0) }) { number in swiftomniui_winui_items_make(number) }
    }

    /// The List holding the list a callback names; nil once it has left.
    static func owner(of number: Int64) -> WinUIItemsView? {
        (WinUIView.find(number) as? WinUIItemsList)?.owner
    }
}

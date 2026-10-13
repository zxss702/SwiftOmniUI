// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A SwiftOmniUI layout over the relay's panel: WinUI asks it to measure and arrange, and the core's arithmetic answers.
/// Design: docs/design/platforms/winui/layout.md#a-layout-is-a-panel
@MainActor
class WinUILayoutView: WinUIView {
    /// The sizes measured in the pass under way, by the width offered.
    let measurements = MeasurementCache()

    /// XAML keeps only its last native proposal. Reuse preparation while the arithmetic
    /// and its children's native measures still stand at that same width and revision.
    private var preparedMeasure: (width: Double, revision: Int)?
    private var preparingMeasure = false
    private var measurementsAreDirty = false
    private var measurementInvalidationSent = false
    private var sizeFeedbackPending = false

    /// The children, in order.
    private(set) var items: [WinUILayoutItem] = []

    /// The direction the children are laid out in, the element's; a turn lays them out again.
    var direction = LayoutDirection.leftToRight {
        didSet { if direction != oldValue { invalidateMeasurements() } }
    }

    /// The layout's own box: what fills it, its outline, its shape and whether it cuts what it shows.
    struct Box: Equatable {
        var fill: HostValue?
        var stroke: HostValue?
        var width: Double?
        var shape: HostValue?
        var clips = false
    }

    /// The box as the element says it.
    private(set) var box = Box()

    /// The shape drawn behind the children; nil while the box paints nothing.
    private(set) var boxView: WinUIShapeView?

    /// The cut last written, over the size it was written at.
    private var cut: (outline: ContainerShape, width: Double, height: Double)?

    /// The elements the panel holds, in the order it draws them, back to front.
    private var held: [WinUIView] = []
    private var heldBox: WinUIShapeView?
    private var nativeArrangePending = false
    private(set) var allocatedBounds = Rect(0, 0, 0, 0)
    private var pendingChildren: [WinUIView]?
    private var childrenCommitPending = false
    private var preparationPending = false

    init() {
        super.init { number in swiftomniui_winui_panel_make(number) }
    }

    /// Puts `items` in the panel, in order, where they differ from the children it holds; whether they did.
    @discardableResult
    func setItems(_ items: [WinUILayoutItem]) -> Bool {
        guard items.count != self.items.count
            || !zip(items, self.items).allSatisfy({ $0.arranges(like: $1) })
        else { return false }

        self.items = items
        for item in items { item.view.placingLayout = self }
        holdChildren()
        invalidateMeasurements()
        return true
    }

    /// The views the panel holds, in the order it draws them: every child's, unless a layout shows fewer.
    func heldViews() -> [WinUIView] {
        items.map(\.view)
    }

    /// Holds the views this layout shows now.
    func holdChildren() {
        setChildren(heldViews())
    }

    /// Holds `views` in the panel in this order, the one it draws them in, over the box.
    var allowsNativeSafeBars = false

    func setChildren(_ proposed: [WinUIView]) {
        let views = allowsNativeSafeBars ? proposed : proposed.filter { $0.nativeSafeBarOwner == nil }
        let changed = boxView !== heldBox || views.count != held.count || !zip(views, held).allSatisfy({ $0 === $1 })
        // A later proposal can cancel an earlier pending change. Compare
        // before posting work; an unchanged drawing order needs no turn.
        guard changed else { pendingChildren = nil; return }
        if WinUIView.arranging > 0 || WinUIView.measuring > 0 {
            pendingChildren = proposed
            guard !childrenCommitPending else { return }
            childrenCommitPending = true
            WinUIDoorbell.afterPass { [weak self] in
                guard let self else { return }
                self.childrenCommitPending = false
                let children = self.pendingChildren
                self.pendingChildren = nil
                guard !self.isDetached, let children else { return }
                self.setChildren(children)
                self.invalidateArrange()
            }
            return
        }
        pendingChildren = nil
        let handles: [SwiftOmniUIObjectRef?] = (boxView.map { [$0.handle] } ?? []) + views.map(\.handle)
        swiftomniui_winui_panel_set_children(handle, handles, Int32(handles.count))
        held = views
        heldBox = boxView
    }

    /// What fills the box: a colour or a brush; nil for nothing.
    func setBackground(_ value: HostValue?) {
        box.fill = value
        paintBox()
    }

    /// The box's outline, its shape, and whether it cuts what the layout shows to that shape.
    func setOutline(stroke: HostValue?, width: Double?, shape: HostValue?, clips: Bool) {
        box.stroke = stroke
        box.width = width
        box.shape = shape
        box.clips = clips
        paintBox()
    }

    /// Paints the box behind the children, made, remade for another outline, or let go of, and asks for an
    /// arrangement to place it and its cut.
    /// Design: docs/design/platforms/winui/drawing.md#a-box-and-its-brush
    private func paintBox() {
        let outline = BoxArithmetic.outline(box.shape)
        let fill = WinUIBrush(box.fill)
        let stroke = WinUIBrush(box.stroke)
        let width = BoxArithmetic.outlineWidth(stroke: box.stroke, width: box.width)

        if fill == .none, stroke == .none || width == 0 {
            boxView = nil
        } else {
            let ellipse = outline == .ellipse
            if boxView?.isEllipse != ellipse { boxView = WinUIShapeView(ellipse: ellipse) }
            boxView?.paint(radius: outline.relay.radius, fill: fill, stroke: stroke, width: width)
        }
        // Painting during a mount must not replace the pending new rows
        // with the old native child list.
        setChildren(pendingChildren ?? held)
        invalidateArrange()
    }

    /// Asks WinUI to arrange the children again: a place in the air lands in the pass it asks for.
    func invalidateArrange() {
        guard WinUIView.arranging == 0, WinUIView.measuring == 0 else {
            guard !nativeArrangePending else { return }
            nativeArrangePending = true
            WinUIDoorbell.afterPass { [weak self] in
                guard let self, !self.isDetached, self.nativeArrangePending else { return }
                self.nativeArrangePending = false
                self.invalidateArrange()
            }
            return
        }
        nativeArrangePending = false
        swiftomniui_winui_invalidate_arrange(handle)
    }

    /// Forgets the kept sizes and asks WinUI to measure again.
    func invalidateMeasurements() {
        guard invalidateLocalMeasurements() else { return }
        ((self as? WinUIScrollDocument)?.scrollView ?? placingLayout)?.invalidateMeasurements()
    }

    /// A mounted ancestor walk uses this without crossing native List or
    /// popover boundaries. Repeated changes before the next sizing invalidate
    /// each affected layout once.
    @discardableResult
    func invalidateLocalMeasurements() -> Bool {
        guard !measurementInvalidationSent else { return false }
        measurementInvalidationSent = true
        forgetMeasurements()
        invalidateMeasure()
        return true
    }

    private var measurementCommitPending = false

    /// Discard affected arithmetic and request one native measure/arrange at
    /// the placed root. XAML supplies the real proposal in its next pass;
    /// preparing the root with an invented unbounded height loses that order.
    func commitMeasurementChange() {
        invalidateMeasurements()
        var root = self
        while let parent = (root as? WinUIScrollDocument)?.scrollView ?? root.placingLayout {
            root = parent
        }
        guard !root.measurementCommitPending else { return }
        root.measurementCommitPending = true
        WinUIDoorbell.afterPass { [weak root] in
            guard let root, !root.isDetached else { return }
            root.measurementCommitPending = false
            root.invalidateArrange()
        }
    }

    /// Forgets the sizes this layout keeps.
    func forgetMeasurements() {
        preparedMeasure = nil
        guard !measurementsAreDirty else { return }
        measurementsAreDirty = true
        measurements.invalidate()
    }

    /// Marks this panel measured at its allocated width without discarding the natural
    /// sizes the arithmetic just computed. An independent XAML measure still refreshes them.
    func prepareMeasure(width: Double) {
        guard WinUIView.arranging == 0 else { return }
        let width = Double(Float(width))
        if preparedMeasure?.width == width, preparedMeasure?.revision == measurementRevision {
            // A size query may have asked a leaf for another proposal. Restore
            // actual native child proposals without forgetting arithmetic.
            prepareChildren(width: width)
            return
        }
        let wasPreparing = preparingMeasure
        preparingMeasure = true
        defer { preparingMeasure = wasPreparing }
        prepareChildren(width: width)
        prepareNativeMeasure(width: width, height: nil)
        preparedMeasure = (width, measurementRevision)
    }

    /// A width first discovered by Arrange is completed once, using the
    /// newest allocation. Keep that child's result when notifying its parent.
    func prepareAfterPass() {
        guard !preparationPending else { return }
        preparationPending = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.preparationPending = false
            guard !self.isDetached, let width = self.standsAt else { return }
            self.prepareMeasure(width: width)
            self.placingLayout?.commitMeasurementChange()
        }
    }

    /// Only a native preparation selects the widths children will stand at.
    /// An intrinsic/arithmetic query must not prepare every nested panel or
    /// replace a lazy container's committed row geometry.
    func prepareChildren(width: Double) {
        let offered = width.isFinite ? width : nil
        for item in items where item.isShown {
            let natural = item.size(offered: offered)
            let available = offered.map { max(0, $0 - item.values.margin.left - item.values.margin.right) }
            let expands = item.values.flex != nil || item.values.expandingAxes == .horizontal || item.values.expandingAxes == .both
            let allocated = Extent.of(option: expands ? 3 : item.values.horizontal,
                                     stated: item.values.width, natural: natural.width,
                                     available: available ?? natural.width,
                                     minimum: item.values.minimumWidth, maximum: item.values.maximumWidth)
            prepareChild(item, at: Rect(0, 0, allocated, natural.height))
        }
    }

    func prepareChild(_ item: WinUILayoutItem, at place: Rect) {
        if let layout = item.view as? WinUILayoutView {
            let revision = layout.measurementRevision
            let before = layout.naturalSize(width: place.width)
            layout.prepareMeasure(width: place.width)
            // A lazy child's initial answer can be an estimate. Commit its
            // mounted rows before retaining that estimate in this parent's
            // arithmetic, then let the same preparation carry changes upward.
            if revision != layout.measurementRevision || before != layout.naturalSize(width: place.width) {
                invalidateLocalMeasurements()
            }
        } else {
            item.view.prepareNativeMeasure(width: place.width, height: nil)
        }
    }

    /// Answers WinUI's measure, every child measured again: no room where a SwiftOmniUI layout places this one, which
    /// reads its size from `naturalSize(width:)`, and otherwise the room the children take, within the room offered.
    /// Design: docs/design/platforms/winui/layout.md#no-room-asked
    func measure(width: Double, height: Double) -> LayoutSize {
        // WinUI arranging a marked element measures it first, inside the pass: the size it already measured
        // stands, and no child is measured - measuring one now marks it, and the marked element is arranged
        // again for ever.
        guard WinUIView.arranging == 0 else { return desiredSize }

        Self.arithmeticMeasuring += 1
        WinUIView.measuring += 1
        defer {
            Self.arithmeticMeasuring -= 1
            WinUIView.measuring -= 1
        }

        let offered = width.isFinite ? width : nil
        if !preparingMeasure {
            forgetMeasurements()
            prepareChildren(width: width)
        }
        _ = boxView?.measure(width: width, height: height)
        let size = naturalSize(width: offered)
        reportChange(of: size, offered: offered)
        guard placingLayout == nil else { return .zero }
        // Native content presenters do not have a LayoutItem to apply the
        // root frame's bounds. A label's own fixed frame must still survive
        // when a button, page or native container measures this panel directly.
        let framed = sourceElement?.layoutValues.sized(size, offered: offered) ?? size
        return LayoutSize(width: min(framed.width, width), height: min(framed.height, height))
    }

    /// How many SwiftOmniUI layouts are measuring, one inside another.
    private static var arithmeticMeasuring = 0

    /// The width of the place this layout was last put in; nil before its first.
    var standsAt: Double?

    /// The natural size last measured, and the width it was offered.
    private var measured: (offered: Double?, size: LayoutSize)?

    /// A natural size that changed outside the placing layout's own measure - a picture loaded, a word changed -
    /// asks that layout to measure again: WinUI hears no change from a layout that asks it for no room.
    /// Design: docs/design/platforms/winui/layout.md#a-change-told-upward
    private func reportChange(of size: LayoutSize, offered: Double?) {
        defer { measured = (offered, size) }
        guard let placingLayout, Self.arithmeticMeasuring == 1, let measured, measured.offered == offered, measured.size != size
        else { return }

        measurementRevision &+= 1
        guard !sizeFeedbackPending else { return }
        sizeFeedbackPending = true
        WinUIDoorbell.afterPass { [weak self, weak placingLayout] in
            guard let self else { return }
            self.sizeFeedbackPending = false
            guard self.placingLayout === placingLayout else { return }
            placingLayout?.commitMeasurementChange()
        }
    }

    /// The room the children take for the width offered, in DIPs, kept until a change beneath marks the layout.
    func naturalSize(width: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        return measurements.size(offering: width) {
            Self.sizings += 1
            measurementsAreDirty = false
            measurementInvalidationSent = false
            let startedAt = WinUIView.provisionalMeasureRevision
            let size = contentSize(width: width)
            if startedAt != WinUIView.provisionalMeasureRevision {
                // The next deferred proposal completes this result. Do not
                // let a previous DesiredSize become a row's natural extent.
                measurements.invalidate()
                measurementsAreDirty = true
                preparedMeasure = nil
            }
            return size
        }
    }

    /// How many times a layout has sized its children - what a test counts.
    static var sizings = 0

    /// Answers WinUI's arrange: places the box and every child in `width` by `height` DIPs, inside the pass.
    func arrange(width: Double, height: Double) {
        WinUIView.arranging += 1
        defer { WinUIView.arranging -= 1 }
        allocatedBounds = Rect(0, 0, width, height)
        boxView?.layout(backgroundBounds(in: Rect(0, 0, width, height)))
        writeCut(width: width, height: height)
        arrange(in: Rect(x: 0, y: 0, width: width, height: height))
        holdDeparting()
    }

    /// Stands every child riding its removal transition where it last stood: it takes no room, but WinUI
    /// arranges each child it draws in every pass, and its transition draws over that place.
    private func holdDeparting() {
        for item in items where item.departing { item.view.layout(item.view.placedFrame) }
    }

    /// A layout skipped with its children hides from assistive technology all that stands in it.
    override func setAccessibility(_ words: AccessibilityWords) {
        super.setAccessibility(words)
        swiftomniui_winui_panel_hide_children(handle, words.presence == .hiddenWithChildren)
    }

    /// Cuts what the layout shows to its outline at its size, written only where it differs.
    private func writeCut(width: Double, height: Double) {
        let outline = BoxArithmetic.outline(box.shape)
        let wanted = box.clips ? (outline, width, height) : nil
        guard wanted?.0 != cut?.outline || wanted?.1 != cut?.width || wanted?.2 != cut?.height else { return }

        cut = wanted
        swiftomniui_winui_set_clip(handle, box.clips, outline.relay.outline, outline.relay.radius, width, height)
    }

    /// The room the children take for the width offered, in DIPs.
    func contentSize(width: Double?) -> LayoutSize {
        .zero
    }

    func backgroundBounds(in bounds: Rect) -> Rect { bounds }

    /// Context inherited by a placed child. Special modifiers override this;
    /// ordinary overlays only inherit the region and reserve no space.
    func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        layoutSafeArea(in: allocatedBounds).child(
            in: place, preservingOutsets: child.sourceElement?.observesSafeArea == true)
    }

    /// Places the children in `bounds`, in DIPs.
    func arrange(in bounds: Rect) {}
}

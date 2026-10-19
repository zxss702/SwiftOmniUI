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

    /// XAML keeps only its last native proposal. Arithmetic probes can select
    /// another width without invalidating Swift's size answers by proposal.
    private var lastSizingWidth: Double?
    private var hasSizing = false

    struct NativeProposal {
        weak var view: WinUIView?
        let width: Double
    }
    private struct Preparation {
        let width: Double?
        let size: LayoutSize
        let proposals: [NativeProposal]
    }
    private var preparations: [Preparation] = []

    /// Layouts with placement arithmetic can prepare XAML directly from those
    /// proposals. Specialized layouts with measurement side effects keep their
    /// contentSize pass until they provide this contract explicitly.
    var hasNativeProposals: Bool { false }
    func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] { [] }

    /// Arithmetic probes do not select the native subtree's layout proposal.
    static var queryingSize = 0

    static func querySize<Result>(_ query: @MainActor () -> Result) -> Result {
        queryingSize += 1
        defer { queryingSize -= 1 }
        return query()
    }

    /// The children, in order.
    private(set) var items: [WinUILayoutItem] = []
    private var itemMeasurementRevisions: [Int] = []

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
    private var clipCommands: [Double]?
    private var clipEvenOdd = false
    private var pathClip: SwiftOmniUIObjectRef?

    isolated deinit { if let pathClip { swiftomniui_winui_release(pathClip) } }

    func setPathClip(_ commands: [Double]?, evenOdd: Bool) {
        guard commands != clipCommands || evenOdd != clipEvenOdd else { return }
        clipCommands = commands
        clipEvenOdd = evenOdd
        if let commands {
            if pathClip == nil { pathClip = swiftomniui_winui_path_clip_make(handle) }
            if let pathClip {
                swiftomniui_winui_path_clip_update(pathClip, commands, Int32(commands.count), evenOdd)
                swiftomniui_winui_path_clip_attach(handle, pathClip)
            }
        } else {
            swiftomniui_winui_path_clip_attach(handle, nil)
            if let pathClip { swiftomniui_winui_release(pathClip) }
            pathClip = nil
            cut = nil
            if let placed { writeCut(width: placed.width, height: placed.height) }
        }
    }

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

    init() {
        super.init { number in swiftomniui_winui_panel_make(number) }
    }

    override init(_ make: (_ number: Int64) -> SwiftOmniUIObjectRef?) {
        super.init(make)
    }

    /// Puts `items` in the panel, in order, where they differ from the children it holds; whether they did.
    @discardableResult
    func setItems(_ items: [WinUILayoutItem]) -> Bool {
        let sameArrangement = items.count == self.items.count
            && zip(items, self.items).allSatisfy { $0.arranges(like: $1) }
        let revisions = items.map { $0.view.parentMeasurementRevision }
        guard !sameArrangement || revisions != itemMeasurementRevisions else { return false }

        if !sameArrangement {
            let surviving = Set(items.map { ObjectIdentifier($0.view) })
            for previous in self.items where !surviving.contains(ObjectIdentifier(previous.view))
                && previous.view.placingLayout === self {
                previous.view.placingLayout = nil
            }
        }
        self.items = items
        itemMeasurementRevisions = revisions
        for item in items { item.view.placingLayout = self }
        if !sameArrangement { holdChildren() }
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
        let childrenChanged = views.count != held.count || !zip(views, held).allSatisfy({ $0 === $1 })
        // Compare before deferring: an unchanged proposal completes no work,
        // and a return to the mounted list cancels an older pending replacement.
        guard boxView !== heldBox || childrenChanged else {
            pendingChildren = nil
            return
        }
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
            }
            return
        }
        pendingChildren = nil

        let handles: [SwiftOmniUIObjectRef?] = (boxView.map { [$0.presentationHandle] } ?? []) + views.map(\.presentationHandle)
        holdNativeChildren(handles)
        held = views
        heldBox = boxView
        // Native content must be attached before its size is queried again.
        // Invalidate on an actual child change, never on a deferred no-op.
        if childrenChanged { invalidateMeasurements() }
        invalidateArrange()
    }

    /// Commits a native child list after the normal identity and pass checks.
    /// Specialized compositing containers retain the same layout bookkeeping.
    func holdNativeChildren(_ handles: [SwiftOmniUIObjectRef?]) {
        swiftomniui_winui_panel_set_children(handle, handles, Int32(handles.count))
    }

    /// What fills the box: a colour or a brush; nil for nothing.
    func setBackground(_ value: HostValue?) {
        guard box.fill != value else { return }
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
        writeCut(width: allocatedBounds.width, height: allocatedBounds.height)
    }

    /// Paint-only changes update the existing shape. Adding or replacing the
    /// shape changes the native children and requests an arrangement there.
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
        // A brush/outline update must preserve the newest structural proposal,
        // including children waiting for the native layout pass to finish.
        setChildren(pendingChildren ?? held)
    }

    /// Asks WinUI to arrange the children again: a place in the air lands in the pass it asks for.
    func invalidateArrange() {
        guard !WinUILayoutUpdates.enqueue(self, measure: false) else { return }
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
        swiftomniui_winui_invalidate_arrange(presentationHandle)
    }

    /// Forgets the kept sizes and asks WinUI to measure again.
    func invalidateMeasurements() {
        invalidateOwnMeasurements()
        if self is WinUILazyView { return }
        ((self as? WinUIScrollDocument)?.scrollView ?? placingLayout)?.invalidateMeasurements()
    }

    /// One layout's caches and native pass, without revisiting a shared
    /// ancestor. A batch of independently loaded labels uses this once per
    /// affected layout while ordinary changes still recurse as above.
    func invalidateOwnMeasurements() {
        invalidateMeasure()
        // These panels report zero DesiredSize to their placing parents.
        // New content still needs new places when the native size stays zero.
        invalidateArrange()
        // A promoted bar keeps its logical placingLayout, but its actual XAML
        // parent has an independent size cache. Invalidate both ownership paths
        // when descendants change, even before a new logical place is reported.
        (nativeSafeBarOwner as? WinUISafeAreaBarHost)?.invalidateOwnMeasurements()
        // Native page owners do not appear in placingLayout. A change of
        // intrinsic size (not just replacing children) must arrange their
        // content again even when XAML still sees zero DesiredSize here.
        nativeLayoutOwner?.invalidateArrange()
    }

    /// Native TextBlock.Loaded may arrive for many labels in the same pass.
    /// Refresh only the distinct layouts above labels whose measured sizes
    /// actually moved; a shared ancestor is invalidated exactly once.
    static func commitAttachedTextMeasurements(_ starting: [WinUILayoutView]) {
        var visited: Set<ObjectIdentifier> = []
        for layout in starting {
            var next: WinUILayoutView? = layout
            while let current = next {
                guard visited.insert(ObjectIdentifier(current)).inserted else { break }
                let parent = (current as? WinUIScrollDocument)?.scrollView ?? current.placingLayout
                if !current.isDetached { current.invalidateOwnMeasurements() }
                if current is WinUILazyView { break }
                next = parent
            }
        }
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
        measurements.invalidate()
        preparations.removeAll(keepingCapacity: true)
        forgetNativePreparation()
    }

    override func discardMeasurementResults() {
        super.discardMeasurementResults()
        forgetMeasurements()
    }

    func forgetNativePreparation() {
        hasSizing = false
    }

    /// Restores the allocated native proposal. XAML decides whether its
    /// measurement is still valid, including changes from native descendants.
    override func prepareMeasure(width: Double) {
        guard WinUIView.arranging == 0, Self.queryingSize == 0 else { return }
        let width = Double(Float(width))
        let currentSizing = hasSizing && lastSizingWidth == (width.isFinite ? width : nil)

        // A speculative width can have measured the children since this panel's last
        // native pass. Even if XAML still holds this width, that subtree must be prepared again.
        if !currentSizing { swiftomniui_winui_invalidate_measure(presentationHandle) }
        // Always enter XAML Measure: unchanged constraints are already a native
        // fast path. Our revision cannot see native dirty paths, template changes
        // or a subtree returning from Collapsed, so it cannot skip that check.
        _ = super.measure(width: width, height: nil)
    }

    /// Answers WinUI's measure, every child measured again: no room where a SwiftOmniUI layout places this one, which
    /// reads its size from `naturalSize(width:)`, and otherwise the room the children take, within the room offered.
    /// Design: docs/design/platforms/winui/layout.md#no-room-asked
    func measure(width: Double, height: Double) -> LayoutSize {
        // Arrange may invoke Measure for a dirty child. Its previous DesiredSize
        // is provisional; preserve the proposal through the shared deferred-measure path.
        guard WinUIView.arranging == 0 else {
            _ = super.measure(width: Optional(width), height: Optional(height))
            return desiredSize
        }
        // This is the native pass itself, rather than a request to measure.
        // It consumes older queued invalidations without scheduling itself again.
        WinUILayoutUpdates.beganNativeMeasure(self)

        Self.arithmeticMeasuring += 1
        WinUIView.measuring += 1
        defer {
            Self.arithmeticMeasuring -= 1
            WinUIView.measuring -= 1
        }

        let offered = width.isFinite ? width : nil
        let previous = measurements.cachedSize(offering: offered)
            ?? (measured?.offered == offered ? measured?.size : nil)
        // Reaching MeasureOverride means XAML rejected its previous result.
        // That applies equally to an explicit preparation and a native pass;
        // keeping arithmetic here would answer a new measure with old content.
        forgetMeasurements()
        _ = boxView?.measure(width: width, height: height)
        let startedAt = WinUIView.provisionalMeasureRevision
        var size: LayoutSize
        if hasNativeProposals {
            func preparation(for size: LayoutSize) -> Preparation {
                if let kept = preparations.first(where: { $0.width == offered && $0.size == size }) {
                    return kept
                }
                let plan = Preparation(width: offered, size: size,
                                       proposals: Self.querySize { nativeProposals(width: offered, size: size) })
                if preparations.count == 4 { preparations.removeFirst() }
                preparations.append(plan)
                return plan
            }
            func prepare(_ plan: Preparation) {
                let querying = Self.queryingSize
                Self.queryingSize = 0
                defer { Self.queryingSize = querying }
                for proposal in plan.proposals { proposal.view?.prepareMeasure(width: proposal.width) }
            }
            var plan = preparation(for: naturalSize(width: offered))
            while true {
                let before = WinUIView.nativeSizeRevision
                prepare(plan)
                size = plan.size
                guard before != WinUIView.nativeSizeRevision else { break }

                // A child's corrected size may redistribute its siblings' widths.
                // Commit those proposals before returning this MeasureOverride,
                // rather than arranging new arithmetic over last pass's native sizes.
                forgetMeasurements()
                let updated = preparation(for: naturalSize(width: offered))
                if updated.proposals.count == plan.proposals.count,
                   zip(updated.proposals, plan.proposals).allSatisfy({
                       $0.view === $1.view && $0.width == $1.width
                   }) {
                    // Arithmetic probes may have selected other native widths.
                    // Restore the final proposals even when their geometry is unchanged.
                    prepare(updated)
                    size = updated.size
                    break
                }
                plan = updated
            }
        } else {
            // Lazy/custom/native layouts also commit geometry during this pass.
            // Run it once; an initial naturalSize call would duplicate the work.
            let querying = Self.queryingSize
            Self.queryingSize = 0
            size = contentSize(width: offered)
            Self.queryingSize = querying
        }
        lastSizingWidth = offered
        hasSizing = startedAt == WinUIView.provisionalMeasureRevision
        if !hasSizing {
            forgetMeasurements()
        } else {
            if measurements.store(size, offering: offered) {
                preparations.removeAll(keepingCapacity: true)
            }
        }
        if let previous, previous != size { WinUIView.nativeSizeRevision &+= 1 }
        reportChange(of: size, offered: offered, previous: previous)
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
    private func reportChange(of size: LayoutSize, offered: Double?, previous: LayoutSize?) {
        defer { measured = (offered, size) }
        guard !(self is WinUILazyView), let placingLayout,
              Self.arithmeticMeasuring == 1, let previous, previous != size
        else { return }

        measurementRevision &+= 1
        // A query later in this pass must not see the old parent's arithmetic.
        // Native requests still defer until MeasureOverride has returned.
        ProgramWrite.perform {
            placingLayout.invalidateMeasurements()
        }
    }

    /// The room the children take for the width offered, in DIPs, kept until a change beneath marks the layout.
    func naturalSize(width: Double?) -> LayoutSize {
        WinUILayoutUpdates.measured(self)
        let width = width.map { Double(Float($0)) }
        return measurements.size(offering: width) {
            Self.sizings += 1
            Self.queryingSize += 1
            defer { Self.queryingSize -= 1 }
            let startedAt = WinUIView.provisionalMeasureRevision
            let size = contentSize(width: width)
            if startedAt != WinUIView.provisionalMeasureRevision {
                // The next deferred proposal completes this result. Do not
                // let a previous DesiredSize become a row's natural extent.
                measurements.invalidate()
                forgetNativePreparation()
            }
            return size
        }
    }

    /// How many times a layout has sized its children - what a test counts.
    static var sizings = 0

    /// Answers WinUI's arrange: places the box and every child in `width` by `height` DIPs, inside the pass.
    func arrange(width: Double, height: Double) {
        nativeArrangePending = false
        WinUILayoutUpdates.beganNativeArrange(self)
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
        guard clipCommands == nil else { return }
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

    private struct SafeAreaInput: Equatable {
        let insets: EdgeInsets
        let consumed: EdgeInsets
    }
    private var lastSafeAreaInput: SafeAreaInput?

    override func safeAreaChanged() {
        // Safe-area context is Swift layout input, invisible to XAML's cached
        // Arrange rectangle. A page swap can change it at the same size. Ask
        // this panel to propagate the new region even when no resize occurs.
        // Do not invalidate ancestors: the parent has already supplied it.
        // The inherited context describes the incoming allocation, whereas
        // allocatedBounds still describes the previous Arrange. Allocation size
        // is already a measurement proposal; only changed insets invalidate it.
        let context = layoutSafeArea(in: safeAreaContext?.layout ?? allocatedBounds)
        let input = SafeAreaInput(insets: SafeAreaContext.insets(of: context.safe, in: context.layout),
                                  consumed: context.consumed)
        guard input != lastSafeAreaInput else { return }
        lastSafeAreaInput = input
        forgetMeasurements()
        invalidateArrange()
    }

    /// Context inherited by a placed child. Special modifiers override this;
    /// ordinary overlays only inherit the region and reserve no space.
    func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        layoutSafeArea(in: allocatedBounds).child(
            in: place, preservingOutsets: child.sourceElement?.observesSafeArea == true)
    }

    /// Places the children in `bounds`, in DIPs.
    func arrange(in bounds: Rect) {}
}

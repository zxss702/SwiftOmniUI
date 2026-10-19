// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A SwiftOmniUI layout over the relay's panel: WinUI asks it to measure and arrange, and the core's arithmetic answers.
/// Design: docs/design/platforms/winui/layout.md#a-layout-is-a-panel
@MainActor
class WinUILayoutView: WinUIView {
    /// Intrinsic answers by width; height-sensitive queries use proposedSizes.
    let measurements = MeasurementCache()

    /// XAML keeps only its last native proposal. Arithmetic probes can select
    /// another width without invalidating Swift's size answers by proposal.
    private var lastSizingWidth: Double?
    private var lastSizingHeight: Double?
    private var hasSizing = false
    private var nativePreparationDepth = 0
    private var preparingUnchangedProposal = false
    private var validatedArithmeticEpoch: UInt64?
    private static var validationSequence: UInt64 = 0
    static var nativeValidationEpoch: UInt64?

    struct NativeProposal {
        weak var view: WinUIView?
        let place: Rect
    }
    @MainActor
    private struct Dependency {
        weak var view: WinUIView?
        let revision: Int
        let hierarchy: Int
        let attached: Bool

        init(_ view: WinUIView) {
            self.view = view
            revision = view.parentMeasurementRevision
            hierarchy = view.hierarchyRevision
            attached = view.isAttached
        }

        var isCurrent: Bool {
            guard let view, !view.isDetached else { return false }
            return revision == view.parentMeasurementRevision && hierarchy == view.hierarchyRevision
                && attached == view.isAttached
        }
    }

    private struct LayoutPlan {
        let bounds: Rect
        let revision: Int
        let hierarchy: Int
        let values: LayoutValues
        let safeArea: SafeAreaContext
        let proposals: [NativeProposal]
        let dependencies: [Dependency]
    }
    private var layoutPlans: [LayoutPlan] = []
    private var activeLayoutPlan: LayoutPlan?
    private var proposedSizes: [(proposal: ProposedViewSize, size: LayoutSize)] = []

    /// Layouts with placement arithmetic can prepare XAML directly from those
    /// proposals. Specialized layouts with measurement side effects keep their
    /// contentSize pass until they provide this contract explicitly.
    var hasNativeProposals: Bool { false }
    func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] { [] }

    /// Only height-sensitive arithmetic needs distinct intrinsic answers for
    /// each height. Every native allocation and placement still uses both axes.
    var contentSizeDependsOnHeight: Bool { false }

    /// Both axes reach author-defined layouts; existing arithmetic uses width.
    func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        contentSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil })
    }

    func makeLayoutPlan(in bounds: Rect) -> [NativeProposal] {
        nativeProposals(width: bounds.width, size: LayoutSize(width: bounds.width, height: bounds.height))
    }

    /// Placement consumes the completed plan selected by the native callback.
    func preparedLayoutPlan(in bounds: Rect) -> [NativeProposal] {
        precondition(activeLayoutPlan?.bounds == bounds, "placement requires a plan for its actual bounds")
        return activeLayoutPlan!.proposals
    }

    /// Specialized safe-area layouts restore context when reusing a plan.
    func restoreLayoutContext(in bounds: Rect, proposals: [NativeProposal]) {}

    func forgetLayoutPlans() {
        layoutPlans.removeAll(keepingCapacity: true)
    }

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
    private var preparingBounds: Rect?
    private(set) var measurementHeight: Double?
    var contextBounds: Rect { preparingBounds ?? allocatedBounds }
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
        let previous = held
        holdNativeChildren(handles)
        for view in previous where !views.contains(where: { $0 === view }) { view.nativeParentChanged() }
        for view in views where !previous.contains(where: { $0 === view }) { view.nativeParentChanged() }
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
        // A promoted bar keeps its logical placingLayout, but its actual XAML
        // parent has an independent size cache. Invalidate both ownership paths
        // when descendants change, even before a new logical place is reported.
        (nativeSafeBarOwner as? WinUISafeAreaBarHost)?.invalidateOwnMeasurements()
        // Native page owners do not appear in placingLayout. Their placement
        // arithmetic must also refresh when a page's intrinsic size changes.
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
        layoutPlans.removeAll(keepingCapacity: true)
        proposedSizes.removeAll(keepingCapacity: true)
        forgetNativePreparation()
    }

    override func discardMeasurementResults() {
        super.discardMeasurementResults()
        forgetMeasurements()
    }

    func forgetNativePreparation() {
        hasSizing = false
    }

    /// Restore the real allocation without discarding other intrinsic proposals.
    override func prepareMeasure(width: Double, height: Double? = nil) {
        precondition(!isNativeArranging, "an arranging panel cannot measure itself")
        let proposal = Self.normalized(ProposedViewSize(
            width: width.isFinite ? width : nil, height: height.flatMap { $0.isFinite ? $0 : nil }))
        let currentSizing = hasSizing && lastSizingWidth == proposal.width && lastSizingHeight == proposal.height
        // Measure already observes new constraints and native dirtiness. A
        // proposal change is not content invalidation: explicitly invalidating
        // here also dirties an ancestor that may currently be arranging us.
        let previousPreparation = preparingUnchangedProposal
        preparingUnchangedProposal = currentSizing
        nativePreparationDepth += 1
        defer { nativePreparationDepth -= 1; preparingUnchangedProposal = previousPreparation }
        super.prepareMeasure(width: width, height: height)
        if hasNativeProposals,
           !hasSizing || lastSizingWidth != proposal.width || lastSizingHeight != proposal.height {
            // An intrinsic probe can change a descendant's last native
            // proposal without changing this panel's own cached Measure.
            // Restore its child plan directly instead of forcing another
            // MeasureOverride and invalidating the native ancestor chain.
            let previousHeight = measurementHeight
            measurementHeight = proposal.height
            defer { measurementHeight = previousHeight }
            _ = prepareNaturalLayout(proposal: proposal)
            lastSizingWidth = proposal.width
            lastSizingHeight = proposal.height
            hasSizing = true
        }
    }

    /// A genuine native Measure owns this view's phase, even beneath an
    /// ancestor's Arrange. Global depths continue to protect tree mutations.
    func measure(width: Double, height: Double) -> LayoutSize {
        withNativeMeasure {
            WinUILayoutUpdates.beganNativeMeasure(self)
            let proposal = Self.normalized(ProposedViewSize(
                width: width.isFinite ? width : nil, height: height.isFinite ? height : nil))
            let previousHeight = measurementHeight
            let previousValidation = Self.nativeValidationEpoch
            // An independent XAML pass, or a dirty callback at unchanged
            // constraints, must validate native-only resource changes too.
            // A new allocation alone retains its intrinsic answers.
            if previousValidation == nil, nativePreparationDepth == 0 || preparingUnchangedProposal {
                Self.validationSequence &+= 1
                Self.nativeValidationEpoch = Self.validationSequence
            }
            measurementHeight = proposal.height
            Self.arithmeticMeasuring += 1
            defer {
                measurementHeight = previousHeight
                Self.nativeValidationEpoch = previousValidation
                Self.arithmeticMeasuring -= 1
            }

            let previous = (measured?.proposal == proposal ? measured?.size : nil)
                ?? (proposal.height == nil ? measurements.cachedSize(offering: proposal.width)
                    : proposedSizes.first(where: { $0.proposal == proposal })?.size)
            // Independent XAML measurement can originate in native resources.
            // Explicit preparation keeps proposal-keyed arithmetic, then checks
            // every selected native child and refines any changed answer.
            if nativePreparationDepth == 0 { forgetMeasurements() }
            _ = boxView?.measure(width: width, height: height)
            var size: LayoutSize
            if hasNativeProposals {
                size = prepareNaturalLayout(proposal: proposal)
            } else {
                // Lazy/native containers commit their own measurement geometry.
                let querying = Self.queryingSize
                Self.queryingSize = 0
                size = contentSize(proposal: proposal)
                Self.queryingSize = querying
            }
            lastSizingWidth = proposal.width
            lastSizingHeight = proposal.height
            hasSizing = true
            if !contentSizeDependsOnHeight || proposal.height == nil { measurements.store(size, offering: proposal.width) }
            if let previous, previous != size { WinUIView.nativeSizeRevision &+= 1 }
            recordMeasurement(size, proposal: proposal, previous: previous)
            let values = sourceElement?.winUI.resolvedLayoutValues ?? LayoutValues()
            let framed = values.sized(size, offered: proposal.width)
            return LayoutSize(width: min(framed.width, width), height: min(framed.height, height))
        }
    }

    static func normalized(_ proposal: ProposedViewSize) -> ProposedViewSize {
        func axis(_ value: Double?) -> Double? {
            value.map {
                precondition(!$0.isNaN, "a layout proposal cannot contain NaN")
                return Double(Float(max(0, $0)))
            }
        }
        return ProposedViewSize(width: axis(proposal.width), height: axis(proposal.height))
    }

    private func planBounds(proposal: ProposedViewSize, natural: LayoutSize) -> Rect {
        let values = sourceElement?.winUI.resolvedLayoutValues ?? LayoutValues()
        let framed = values.sized(natural, offered: proposal.width)
        return Rect(0, 0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? framed.width,
                    proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? framed.height)
    }

    /// Unspecified axes follow the corrected intrinsic extent. Both a real
    /// MeasureOverride and a cached Measure restore the same completed plan.
    private func prepareNaturalLayout(proposal: ProposedViewSize) -> LayoutSize {
        while true {
            let size = naturalSize(proposal: proposal)
            let bounds = planBounds(proposal: proposal, natural: size)
            _ = prepareLayoutPlan(in: bounds)
            let current = naturalSize(proposal: proposal)
            if planBounds(proposal: proposal, natural: current) == bounds { return current }
        }
    }

    private func keepLayoutPlan(in bounds: Rect, proposals: [NativeProposal]) {
        layoutPlans.removeAll { $0.bounds == bounds }
        if layoutPlans.count == 4 { layoutPlans.removeFirst() }
        layoutPlans.append(LayoutPlan(
            bounds: bounds, revision: measurementRevision, hierarchy: hierarchyRevision,
            values: sourceElement?.winUI.resolvedLayoutValues ?? LayoutValues(),
            safeArea: layoutSafeArea(in: bounds), proposals: proposals,
            dependencies: proposals.compactMap { $0.view.map { Dependency($0) } }))
    }

    private func completedLayoutPlan(in bounds: Rect) -> LayoutPlan {
        let values = sourceElement?.winUI.resolvedLayoutValues ?? LayoutValues()
        let context = layoutSafeArea(in: bounds)
        if let plan = layoutPlans.first(where: {
            $0.bounds == bounds && $0.revision == measurementRevision && $0.hierarchy == hierarchyRevision
                && $0.values == values && $0.safeArea == context && $0.dependencies.allSatisfy({ $0.isCurrent })
        }) { return plan }
        let previousBounds = preparingBounds
        preparingBounds = bounds
        let proposals = Self.querySize { makeLayoutPlan(in: bounds) }
        preparingBounds = previousBounds
        keepLayoutPlan(in: bounds, proposals: proposals)
        return layoutPlans.last!
    }

    private func prepareLayoutPlan(in bounds: Rect) -> LayoutPlan {
        var plan = completedLayoutPlan(in: bounds)
        while true {
            let before = WinUIView.nativeSizeRevision
            let revision = measurementRevision
            prepareChildren(plan)
            if before == WinUIView.nativeSizeRevision && revision == measurementRevision
                && plan.dependencies.allSatisfy({ $0.isCurrent }) {
                keepLayoutPlan(in: bounds, proposals: plan.proposals)
                return layoutPlans.last!
            }
            // Preparation may resolve an attached template or inherited font.
            // Recompute before giving those child rectangles to Arrange.
            forgetMeasurements()
            plan = completedLayoutPlan(in: bounds)
        }
    }

    private func prepareChildren(_ plan: LayoutPlan) {
        let querying = Self.queryingSize
        let previousBounds = preparingBounds
        Self.queryingSize = 0
        preparingBounds = plan.bounds
        restoreLayoutContext(in: plan.bounds, proposals: plan.proposals)
        defer { Self.queryingSize = querying; preparingBounds = previousBounds }
        for proposal in plan.proposals {
            guard let view = proposal.view else { continue }
            // A promoted bar remains an arithmetic dependency of its logical
            // page. Its actual XAML owner alone selects the native proposal.
            guard view.nativeSafeBarOwner == nil || view.nativeSafeBarOwner === self else { continue }
            if view.nativeSafeBarOwner == nil {
                view.safeAreaContext = context(for: view, at: proposal.place).ignoring(view.sourceElement?.ignoresSafeArea)
            }
            let room = view.wordsRoom ?? proposal.place
            view.prepareMeasure(width: room.width, height: room.height)
        }
    }

    /// How many SwiftOmniUI layouts are measuring, one inside another.
    private static var arithmeticMeasuring = 0

    /// The width of the place this layout was last put in; nil before its first.
    var standsAt: Double?

    /// The natural size last measured and its complete native proposal.
    private var measured: (proposal: ProposedViewSize, size: LayoutSize)?
    private var measuredSizeCommitPending = false

    /// Retains the natural-size revision used by logical row caches. XAML
    /// propagates native DesiredSize changes after MeasureOverride returns;
    /// invalidating the parent here would restart the pass still computing it.
    private func recordMeasurement(_ size: LayoutSize, proposal: ProposedViewSize, previous: LayoutSize?) {
        defer { measured = (proposal, size) }
        guard !(self is WinUILazyView), placingLayout != nil,
              Self.arithmeticMeasuring == 1, let previous, previous != size
        else { return }

        measurementRevision &+= 1
        // A parent actively completing its plan consumes the correction now.
        guard placingLayout?.isNativeMeasuring != true, placingLayout?.isNativeArranging != true else { return }
        // An independent native measurement leaves idle logical arithmetic
        // holding the previous answer. Publish the change
        // after XAML exits Measure, without invalidating the active native pass.
        guard !measuredSizeCommitPending else { return }
        measuredSizeCommitPending = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.measuredSizeCommitPending = false
            guard !self.isDetached else { return }
            self.placingLayout?.commitMeasurementChange()
        }
    }

    /// Intrinsic answers and native allocation are separate. Cache both axes
    /// for Custom Layout without changing width-based shared arithmetic.
    func naturalSize(width: Double?) -> LayoutSize {
        naturalSize(proposal: ProposedViewSize(width: width))
    }

    func naturalSize(proposal: ProposedViewSize) -> LayoutSize {
        WinUILayoutUpdates.measured(self)
        let proposal = Self.normalized(proposal)
        if let epoch = Self.nativeValidationEpoch, validatedArithmeticEpoch != epoch {
            measurements.invalidate()
            proposedSizes.removeAll(keepingCapacity: true)
            layoutPlans.removeAll(keepingCapacity: true)
            validatedArithmeticEpoch = epoch
        }
        func compute() -> LayoutSize {
            Self.sizings += 1
            return Self.querySize { contentSize(proposal: proposal) }
        }
        if !contentSizeDependsOnHeight || proposal.height == nil {
            return measurements.size(offering: proposal.width, measure: compute)
        }
        if let kept = proposedSizes.first(where: { $0.proposal == proposal }) { return kept.size }
        let revision = measurementRevision
        let size = compute()
        if revision == measurementRevision {
            if proposedSizes.count == 4 { proposedSizes.removeFirst() }
            proposedSizes.append((proposal, size))
        }
        return size
    }

    /// How many times a layout has sized its children - what a test counts.
    static var sizings = 0

    /// Answers WinUI's arrange: places the box and every child in `width` by `height` DIPs, inside the pass.
    func arrange(width: Double, height: Double) {
        withNativeArrange {
            nativeArrangePending = false
            WinUILayoutUpdates.beganNativeArrange(self)
            let bounds = Rect(0, 0, width, height)
            allocatedBounds = bounds
            let previousHeight = measurementHeight
            measurementHeight = height
            let previousPlan = activeLayoutPlan
            defer { measurementHeight = previousHeight; activeLayoutPlan = previousPlan }
            if hasNativeProposals {
                // Native-owned roots can receive new final bounds without a
                // Measure. Prepare only descendants, never this active panel.
                activeLayoutPlan = prepareLayoutPlan(in: bounds)
            }
            boxView?.layout(backgroundBounds(in: bounds))
            writeCut(width: width, height: height)
            arrange(in: bounds)
            holdDeparting()
        }
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
        invalidateMeasure()
        invalidateArrange()
    }

    /// Context inherited by a placed child. Special modifiers override this;
    /// ordinary overlays only inherit the region and reserve no space.
    func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        layoutSafeArea(in: contextBounds).child(
            in: place, preservingOutsets: child.sourceElement?.observesSafeArea == true)
    }

    /// Places the children in `bounds`, in DIPs.
    func arrange(in bounds: Rect) {}
}

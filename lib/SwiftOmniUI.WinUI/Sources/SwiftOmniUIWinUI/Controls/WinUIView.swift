// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A WinUI element Swift holds, and the number the relay calls back with.
/// Design: docs/design/platforms/winui/relay.md#a-view-and-its-number
@MainActor
class WinUIView {
    /// The element, held until this is released.
    let handle: SwiftOmniUIObjectRef

    /// Parents attach the drawing boundary when one is needed; control APIs
    /// continue to use `handle`, preserving the actual native control identity.
    var presentationHandle: SwiftOmniUIObjectRef { blurPresenter ?? nativeAllocation ?? handle }
    /// A native control can consume SOUI allocation through its own boundary
    /// while its control handle, editing state and event identity stay intact.
    private let nativeAllocation: SwiftOmniUIObjectRef?
    /// Native viewport controls can update their registered content without
    /// invalidating the size of their enclosing SOUI layout.
    var registeredPropertiesAffectSize: Bool { true }
    /// Registered properties that change native child allocation even when
    /// the enclosing control's requested size is independent of its content.
    var registeredLayoutProperties: Set<Prop> = []
    private var blurPresenter: SwiftOmniUIObjectRef?
    private(set) var blur = 0.0
    private var inheritedBlur = 0.0
    private var writtenBlur = 0.0
    private var blurCommitPending = false

    /// The number the relay's callbacks name this view by.
    let number: Int64

    /// The layout that places this view, which a place written between passes asks to arrange again.
    weak var placingLayout: WinUILayoutView? {
        didSet { if placingLayout !== oldValue { nativeParentChanged() } }
    }
    /// Native controls own arbitrary SwiftUI label roots without placing them
    /// through a SOUI stack. Size corrections must cross that ownership edge.
    weak var nativeContentOwner: WinUIView? {
        didSet { if nativeContentOwner !== oldValue { nativeParentChanged() } }
    }
    /// A native container such as SplitView places a page without a Swift
    /// placingLayout. Structural changes inside that page still need a fresh
    /// native arrangement at the same window size.
    weak var nativeLayoutOwner: WinUILayoutView? {
        didSet { if nativeLayoutOwner !== oldValue { nativeParentChanged() } }
    }

    /// Logical ancestry survives native toolbar hosting.
    weak var sourceElement: MountedElement?
    var safeAreaContext: SafeAreaContext? {
        didSet { if safeAreaContext != oldValue { safeAreaChanged() } }
    }
    private(set) var isReceivingLayoutContext = false
    private(set) var layoutContextRevision = 0

    /// A parent supplies proposal-dependent regions as part of its current
    /// plan. This is layout input, not another content/environment mutation.
    func setLayoutContext(_ context: SafeAreaContext?) {
        withLayoutContext { safeAreaContext = context }
    }

    func withLayoutContext<Result>(_ body: () -> Result) -> Result {
        let previous = isReceivingLayoutContext
        isReceivingLayoutContext = true
        defer { isReceivingLayoutContext = previous }
        return body()
    }

    func layoutContextChanged() {
        layoutContextRevision &+= 1
        (placingLayout as? WinUILazyView)?.rowMeasurementChanged(self)
    }
    var rootSafeAreaContext: ((Rect) -> SafeAreaContext)?
    /// A native toolbar owns the widget, while the source modifier still owns
    /// its layout contribution, animation ancestry and parent-space report.
    weak var nativeSafeBarOwner: AnyObject? {
        didSet { if nativeSafeBarOwner !== oldValue { nativeParentChanged() } }
    }
    private struct PromotedBar {
        weak var view: WinUIView?
    }
    private var promotedBars: [Int64: PromotedBar] = [:]

    func followPromotedBar(_ bar: WinUIView) {
        promotedBars[bar.number] = PromotedBar(view: bar)
    }

    func unfollowPromotedBar(_ bar: WinUIView) {
        promotedBars.removeValue(forKey: bar.number)
    }
    private(set) var safeBarDrawing: HostMatrix?

    func recordSafeBarPlace(_ place: Rect, context: SafeAreaContext) {
        placed = place
        setLayoutContext(context)
        (nativeSafeBarOwner as? WinUISafeAreaBarHost)?.sourcePlaced(place)
        updateSafeBarDrawing()
    }

    func clearSafeBarDrawing() {
        safeBarDrawing = nil
        inheritedBlur = 0
        writeBlur()
        setPlacedDrawing(nil, opacity: 1)
        writeTransform()
    }

    func updateSafeBarDrawing() {
        guard nativeSafeBarOwner != nil else { return }
        (nativeSafeBarOwner as? WinUIView)?.setIgnoresInput(sourceElement?.safeBarAllowsInput == false)
        var matrix = HostMatrix.identity
        var opacity = 1.0
        var blurVariance = 0.0
        var x = placedFrame.x, y = placedFrame.y
        var totalX = 0.0, totalY = 0.0
        var next = sourceElement?.parent
        while let element = next {
            if let view = (element.native as? WinUIElement)?.view {
                let frame = view.placedFrame
                var moved = HostMatrix.identity
                moved.m41 = x
                moved.m42 = y
                totalX += x
                totalY += y
                matrix = matrix * moved * view.drawing.matrix(width: frame.width, height: frame.height)
                opacity *= view.opacity * view.placedOpacity
                blurVariance += view.blur * view.blur
                x = frame.x
                y = frame.y
            }
            next = element.parent
        }
        var unmoved = HostMatrix.identity
        unmoved.m41 = -totalX
        unmoved.m42 = -totalY
        safeBarDrawing = matrix * unmoved
        inheritedBlur = blurVariance.squareRoot()
        writeBlur()
        setPlacedDrawing(placedDrawing, opacity: opacity)
        writeTransform()
    }

    /// An ancestor opacity/offset animation need not cause layout. Mirror it
    /// to promoted descendants when drawing changes as well as when arranging.
    func refreshNativeSafeBarDrawing() {
        // Promotion registers its actual drawing dependencies. Most animated
        // rows have none; they must not search their entire subtree per frame.
        for (number, entry) in promotedBars {
            if let bar = entry.view, bar.nativeSafeBarOwner != nil { bar.updateSafeBarDrawing() }
            else { promotedBars.removeValue(forKey: number) }
        }
    }

    func layoutSafeArea(in bounds: Rect) -> SafeAreaContext {
        let context = safeAreaContext ?? rootSafeAreaContext?(bounds) ?? SafeAreaContext(bounds: bounds)
        // The inherited regions belong to the last allocation. Measurement
        // probes and animation frames may already use a different proposal.
        // Keep each edge's distance from the allocation, not its old size.
        return context.resizedLayout(to: bounds).ignoring(sourceElement?.ignoresSafeArea)
    }

    /// Update document arithmetic before its presenter measures; native
    /// invalidations and margins are committed outside the layout pass.
    func safeAreaChanged() {}

    private var nativeHeightChanged: (() -> Void)?
    private var watchingNativeHeight = false

    func watchNativeHeight(_ changed: @escaping () -> Void) {
        nativeHeightChanged = changed
        guard !watchingNativeHeight else { return }
        watchingNativeHeight = true
        swiftomniui_winui_on_height_changed(handle, number) { number in
            MainActor.assumeIsolated { WinUIView.find(number)?.nativeHeightChanged?() }
        }
    }

    /// Toolbar controls share the title bar's transparent trigger appearance.
    var isToolbarControl = false

    /// How deep the layout passes under way stand: a place written inside one lands at once.
    static var arranging = 0
    static var measuring = 0
    /// A native owner changed its allocated room, independently of the Swift
    /// animation sample. Descendants follow that proposal immediately.
    static var allocatingNativeRoom = 0

    private var nativeMeasureDepth = 0
    private var nativeArrangeDepth = 0
    private(set) var hierarchyRevision = 0
    var isNativeMeasuring: Bool { nativeMeasureDepth > 0 }
    var isNativeArranging: Bool { nativeArrangeDepth > 0 }

    /// Global depth protects native tree mutations; per-view depth permits a
    /// parent in Arrange to measure a child before that child enters Arrange.
    func withNativeMeasure<Result>(_ body: () -> Result) -> Result {
        nativeMeasureDepth += 1
        Self.measuring += 1
        defer { nativeMeasureDepth -= 1; Self.measuring -= 1 }
        return body()
    }

    func withNativeArrange<Result>(_ body: () -> Result) -> Result {
        nativeArrangeDepth += 1
        Self.arranging += 1
        defer { nativeArrangeDepth -= 1; Self.arranging -= 1 }
        return body()
    }

    func nativeParentChanged() {
        WinUILayoutDiagnostics.record("parent.changed", view: self)
        hierarchyRevision &+= 1
        discardMeasurementResults()
    }

    /// Where the view was last placed, in DIPs of its parent; nil before its first place.
    private(set) var placed: Rect?

    /// Geometry committed with the native allocation, distinct from the next
    /// presentation sample waiting for its parent's Arrange.
    private(set) var committedFrame: Rect?

    /// How opaque the view's own property draws it, and whether it shows, as the host last wrote them.
    private(set) var opacity = 1.0
    private(set) var isShown = true
    private(set) var isDetached = false

    /// How the view's own properties move, turn and scale it.
    private var transform = HostDrawingTransform.identity

    /// How a placing layout draws the view over the place it gave, and how opaque; nil and 1 for as the view says.
    private var placedDrawing: HostDrawingTransform?
    private var placedOpacity = 1.0

    /// The tip last laid on the element; nil for none.
    private var writtenTip: HostMatrix?

    /// The opacity, the drawing order and the direction last written.
    private var writtenOpacity = 1.0
    private var writtenZIndex: Int32 = 0
    private var writtenRightToLeft = false

    /// What the view paints with brushes that follow its size, by what they paint.
    private var paintsBySize: [String: (LayoutSize) -> Void] = [:]

    /// Native sizes by proposal. DesiredSize alone belongs only to the last Measure call: a grid can ask for
    /// both an unconstrained size and a wrapped size before arranging either one.
    /// Only changed dependencies discard these answers; entering another
    /// native layout pass must not force an intrinsic probe to replace a
    /// descendant's prepared allocation again.
    private var measuredSizes: [(width: Double?, height: Double?, size: LayoutSize)] = []
    private var nativeMeasurePending = false
    /// Changes when properties or a native size change invalidate this view, not on a repeated Measure query.
    var measurementRevision = 0 {
        didSet { (placingLayout as? WinUILazyView)?.rowMeasurementChanged(self) }
    }
    /// The size revision visible to a placing parent. A virtualizing layout
    /// can change its internal rows without changing the size it returns.
    var parentMeasurementRevision: Int { measurementRevision }
    /// Native preparation can discover a changed answer to a previously queried
    /// proposal. Enclosing arithmetic must then discard that answer as well.
    static var nativeSizeRevision = 0

    private static let live = LiveViews<WinUIView>()

    /// Takes the next number and holds the element `make` makes, handed that number.
    init(allocation: ((SwiftOmniUIObjectRef) -> SwiftOmniUIObjectRef?)? = nil,
         _ make: (_ number: Int64) -> SwiftOmniUIObjectRef?) {
        number = Self.live.reserve()
        guard let handle = make(number) else { fatalError("the relay made no element - its log says why") }
        self.handle = handle
        if let allocation {
            guard let boundary = allocation(handle) else { fatalError("the relay made no allocation boundary") }
            nativeAllocation = boundary
        } else { nativeAllocation = nil }
        Self.live.hold(self, as: number)
        // A control's style aligns it inside its place; a SwiftOmniUI layout decides the place, so it fills it.
        // Design: docs/design/platforms/winui/layout.md#a-place-filled
        swiftomniui_winui_fill_place(handle)
        if let nativeAllocation { swiftomniui_winui_fill_place(nativeAllocation) }
        // System controls do not expose ArrangeOverride to Swift. Their
        // committed size notification publishes drawing geometry directly;
        // SOUI-owned slots have already committed it during parent Arrange.
        swiftomniui_winui_on_size_changed(nativeAllocation ?? handle, number) { number, width, height in
            MainActor.assumeIsolated {
                guard let view = WinUIView.find(number) else { return }
                if view.placingLayout == nil { view.commitNativeAllocation(width: width, height: height) }
                if let editor = view as? WinUITextEditorView {
                    editor.recordAllocation("editor.native", frame: view.placedFrame,
                                            room: Rect(0, 0, width, height))
                }
            }
        }
    }

    isolated deinit {
        Self.live.release(number)
        if let blurPresenter {
            swiftomniui_winui_blur_clear(blurPresenter)
            swiftomniui_winui_release(blurPresenter)
        }
        if let nativeAllocation { swiftomniui_winui_release(nativeAllocation) }
        swiftomniui_winui_release(handle)
    }

    /// The live view a callback names; nil once it has left.
    static func find(_ number: Int64) -> WinUIView? {
        live.find(number)
    }

    /// How many views Swift holds - what a test counts to see every one let go.
    static var liveCount: Int { live.count }

    // MARK: - What every view takes

    func setShown(_ shown: Bool) {
        isShown = shown
        swiftomniui_winui_set_shown(presentationHandle, shown)
    }

    /// How opaque the view's own property draws it, with a placing layout's opacity over it; written only where
    /// it differs from what was.
    func setOpacity(_ opacity: Double) {
        self.opacity = opacity
        let drawn = opacity * placedOpacity * controlStateOpacity
        guard drawn != writtenOpacity else { return }
        writtenOpacity = drawn
        swiftomniui_winui_set_opacity(presentationHandle, drawn)
        refreshNativeSafeBarDrawing()
    }

    /// Prepare before insertion where a declared modifier or transition needs
    /// blur. Adding a modifier later creates the same retained native boundary.
    func prepareBlur() {
        guard blurPresenter == nil, !isDetached else { return }
        guard Self.arranging == 0, Self.measuring == 0 else {
            scheduleBlurCommit()
            return
        }
        blurPresenter = swiftomniui_winui_blur_make(nativeAllocation ?? handle)
        if blurPresenter != nil { nativeParentChanged() }
    }

    func setBlur(_ radius: Double) {
        let radius = radius.isFinite ? max(0, radius) : 0
        guard radius != blur else { return }
        blur = radius
        writeBlur()
        refreshNativeSafeBarDrawing()
    }

    private func scheduleBlurCommit() {
        guard !blurCommitPending else { return }
        blurCommitPending = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.blurCommitPending = false
            guard !self.isDetached else { return }
            self.writeBlur()
        }
    }

    private func writeBlur() {
        let radius = (blur * blur + inheritedBlur * inheritedBlur).squareRoot()
        guard radius != writtenBlur else { return }
        // Creating a presenter changes native ownership exactly once. Never
        // change parent/child relationships during Measure or Arrange.
        if blurPresenter == nil, radius > 0 {
            guard Self.arranging == 0, Self.measuring == 0 else {
                scheduleBlurCommit()
                return
            }
            prepareBlur()
        }
        guard let blurPresenter else { return }
        let transition = sourceElement?.transition
        let reserve = max(radius, max(sourceElement?.resolvedValue(.blur)?.number ?? 0,
                                     max(transition?.insertion.blur ?? 0, transition?.removal.blur ?? 0)))
        if swiftomniui_winui_blur_set(blurPresenter, radius, reserve) { writtenBlur = radius }
    }

    /// How a placing layout draws the view over the place it gave, and how opaque; nil and 1 for as the view says.
    /// Design: docs/design/platforms/winui/drawing.md#a-placed-child
    func setPlacedDrawing(_ drawing: HostDrawingTransform?, opacity: Double) {
        guard drawing != placedDrawing || opacity != placedOpacity else { return }

        placedDrawing = drawing
        placedOpacity = opacity
        writeTransform()
        setOpacity(self.opacity)
        refreshNativeSafeBarDrawing()
    }

    /// Whether clicks and touches go through the view to what is behind it.
    func setIgnoresInput(_ ignores: Bool) {
        ignoresInput = ignores
        updateHitTesting()
    }

    private(set) var enabled = true
    private var ignoresInput = false

    /// A control style can dim an authored label without replacing its opacity
    /// modifier or an insertion/removal transition's presentation.
    var controlStateOpacity: Double { 1 }

    /// Controls enter their native Disabled state. Panels have no IsEnabled,
    /// but still stop pointer input; descendants receive the same environment.
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        swiftomniui_winui_set_enabled(handle, enabled)
        updateHitTesting()
        setOpacity(opacity)
    }

    private func updateHitTesting() {
        swiftomniui_winui_set_hit_testable(presentationHandle, enabled && !ignoresInput)
    }

    /// Whether the view lays itself out and writes in its element's direction: a control does; a layout, whose
    /// places the host layer's arithmetic mirrors, and a drawing, which no direction turns, stand left to right.
    /// Design: docs/design/platforms/winui/layout.md#right-to-left
    var takesDirection: Bool { false }

    /// The view WinUI holds the element's direction in: this one where it takes it; nil where it stands left to right.
    var directionHolder: WinUIView? { takesDirection ? self : nil }

    /// Lays the view out in `direction` where it takes one, else left to right: written either way, as WinUI hands
    /// an element's direction down to what stands in it.
    func setDirection(_ direction: LayoutDirection) {
        writtenRightToLeft = takesDirection && direction == .rightToLeft
        swiftomniui_winui_set_flow_direction(handle, writtenRightToLeft)
    }

    /// Where the view is drawn among its layout's children, written only where it differs.
    func setZIndex(_ z: Int32) {
        guard z != writtenZIndex else { return }
        writtenZIndex = z
        swiftomniui_winui_set_z_index(presentationHandle, z)
    }

    /// Moves, turns and scales the view where its layout put it, in DIPs and degrees.
    func setTransform(_ transform: HostDrawingTransform) {
        guard transform != self.transform else { return }
        self.transform = transform
        writeTransform()
        refreshNativeSafeBarDrawing()
    }

    /// How the view is drawn over its place: its own transform with a placing layout's over it
    /// (`HostDrawingTransform.under`).
    var drawing: HostDrawingTransform {
        transform.under(placedDrawing)
    }

    /// Writes how the view is drawn about its pivot in the size it was last placed at: moved, turned and scaled flat
    /// by its render transform, then tipped by a projection where it tips (`HostDrawingTransform.tip`).
    /// Design: docs/design/platforms/winui/drawing.md#a-tipped-view
    private func writeTransform() {
        let drawn = drawing
        let size = committedFrame ?? Rect(x: 0, y: 0, width: 0, height: 0)
        swiftomniui_winui_set_transform(
            presentationHandle, drawn.translationX, drawn.translationY, drawn.rotation,
            drawn.scaleX, drawn.scaleY, drawn.pivotX * size.width, drawn.pivotY * size.height)
        let ownTip = drawn.tip(width: size.width, height: size.height)
        let tip = safeBarDrawing.map { (ownTip ?? .identity) * $0 } ?? ownTip
        guard tip != writtenTip else { return }
        writtenTip = tip
        guard let tip else { return swiftomniui_winui_set_projection(presentationHandle, nil) }
        let numbers = [
            tip.m11, tip.m12, tip.m13, tip.m14, tip.m21, tip.m22, tip.m23, tip.m24,
            tip.m31, tip.m32, tip.m33, tip.m34, tip.m41, tip.m42, tip.m43, tip.m44,
        ]
        swiftomniui_winui_set_projection(presentationHandle, numbers)
    }

    /// Asks WinUI to measure this element again, and every panel above it.
    func invalidateMeasure(file: StaticString = #fileID, line: UInt = #line) {
        WinUILayoutDiagnostics.record("invalidate.measure", view: self, "programWrite=\(ProgramWrite.isWriting)",
                                      file: file, line: line)
        guard WinUILayoutUpdates.invalidate(self) else { return }
        discardMeasurementResults()
        guard !WinUILayoutUpdates.enqueue(self, measure: true) else { return }
        requestNativeMeasure()
    }

    func discardMeasurementResults() {
        measurementRevision &+= 1
        measuredSizes.removeAll(keepingCapacity: true)
    }

    /// A real MeasureOverride consumes requests made before it started.
    /// Invalidations raised during this measurement can still enqueue a new pass.
    func beganNativeMeasure() {
        nativeMeasurePending = false
    }

    func requestNativeMeasure() {
        WinUILayoutDiagnostics.record("invalidate.native.request", view: self, "pending=\(nativeMeasurePending)")
        guard Self.arranging == 0, Self.measuring == 0 else {
            guard !nativeMeasurePending else { return }
            nativeMeasurePending = true
            WinUIDoorbell.afterPass { [weak self] in
                guard let self, !self.isDetached, self.nativeMeasurePending else { return }
                self.nativeMeasurePending = false
                self.invalidateNativeMeasure()
            }
            return
        }
        nativeMeasurePending = false
        invalidateNativeMeasure()
    }

    /// Native invalidation is separate from discarding Swift's arithmetic:
    /// a viewport notice may update the tree inside ArrangeOverride.
    func invalidateNativeMeasure() {
        WinUILayoutDiagnostics.record("invalidate.native.commit", view: self)
        swiftomniui_winui_invalidate_measure(presentationHandle)
    }

    /// Loaded can change a TextBlock's resources after it was measured outside
    /// the XAML tree. Refresh those exact native proposals, without telling the
    /// enclosing layout that its size changed unless a result actually differs.
    /// Other cached proposals must also be refreshed: a later resize may return
    /// to one of them without rebuilding the view.
    func refreshMeasurementsAfterAttachment() -> Bool {
        let previous = measuredSizes
        guard !previous.isEmpty else { return false }
        measuredSizes.removeAll(keepingCapacity: true)
        // Re-read XAML's answer after attachment. Native resource/property
        // changes already invalidate its measure; forcing invalidation here
        // makes every newly realized label repeat a completed layout pass.
        var changed = false
        for proposal in previous {
            let current = measure(width: proposal.width, height: proposal.height)
            if current != proposal.size { changed = true }
        }
        if changed { measurementRevision &+= 1 }
        return changed
    }

    /// Select the real native allocation independently of intrinsic answers.
    /// A parent's Arrange may prepare children that have not entered Arrange.
    func prepareMeasure(width: Double, height: Double? = nil) {
        precondition(!isNativeArranging, "an arranging view cannot measure itself")
        _ = measureNative(width: width, height: height)
    }

    /// XAML arranges native controls and their templates from the completed
    /// Measure result. A different final slot is not another Measure proposal:
    /// measuring a SplitView, scroller or list here changes its DesiredSize
    /// and restarts the parent that is currently arranging it. SOUI panels
    /// prepare descendant plans; native leaf boundaries own internal controls'
    /// preparation without changing the boundary's Measure contract.
    func prepareAllocation(in bounds: Rect) {}

    /// The element's size for the room offered, in DIPs; nil offers any.
    /// Design: docs/design/platforms/winui/layout.md#measured-every-pass
    func measure(width: Double?, height: Double?) -> LayoutSize {
        measureNative(width: width, height: height)
    }

    private func measureNative(width: Double?, height: Double?) -> LayoutSize {
        WinUILayoutUpdates.measured(self)
        // Use XAML's single-precision proposal as the cache key. Unknown
        // proposals are measured on this child, never answered from DesiredSize
        // produced by an unrelated width or height.
        let width = width.map { Double(Float($0)) }
        let height = height.map { Double(Float($0)) }
        if WinUILayoutView.queryingSize > 0,
           let measured = measuredSizes.first(where: {
               $0.width == width && $0.height == height
           }) {
            WinUILayoutDiagnostics.record("probe.cached", view: self,
                "proposal=\(WinUILayoutDiagnostics.proposal(width: width, height: height)) answer=\(WinUILayoutDiagnostics.size(measured.size))")
            return measured.size
        }
        precondition(!isNativeArranging, "native size probes cannot reenter an arranging view")
        if nativeMeasurePending {
            // Consume the queued request before this Measure, not after it completed.
            nativeMeasurePending = false
            invalidateNativeMeasure()
        }
        let contentRevision = measurementRevision
        let trace = WinUILayoutDiagnostics.begin("native.measure", view: self,
            "proposal=\(WinUILayoutDiagnostics.proposal(width: width, height: height))")
        var size = [0.0, 0.0]
        withNativeMeasure {
            swiftomniui_winui_measure(presentationHandle, width ?? .infinity, height ?? .infinity, &size)
        }
        let measured = LayoutSize(width: size[0], height: size[1])
        WinUILayoutDiagnostics.end(trace, view: self, "desired=\(WinUILayoutDiagnostics.size(measured))")
        guard contentRevision == measurementRevision else {
            measuredSizes.removeAll(keepingCapacity: true)
            return measured
        }
        if let previous = measuredSizes.first(where: { $0.width == width && $0.height == height }),
           previous.size != measured {
            WinUILayoutDiagnostics.record("probe.corrected", view: self,
                "proposal=\(WinUILayoutDiagnostics.proposal(width: width, height: height)) previous=\(WinUILayoutDiagnostics.size(previous.size)) current=\(WinUILayoutDiagnostics.size(measured))")
            // A changed answer at the same proposal invalidates all intrinsic
            // answers for the old native content, not just this allocation.
            measuredSizes.removeAll(keepingCapacity: true)
            measurementRevision &+= 1
            Self.nativeSizeRevision &+= 1
        }
        if WinUILayoutView.queryingSize > 0 {
            // A new intrinsic proposal changed XAML's last measurement. Only
            // native preparation is stale; arithmetic answers by width remain valid.
            var parent = placingLayout
            while let layout = parent {
                layout.forgetNativePreparation()
                parent = (layout as? WinUIScrollDocument)?.scrollView ?? layout.placingLayout
            }
        }
        measuredSizes.removeAll { $0.width == width && $0.height == height }
        // Only a few proposals are active at a time. Resizing must not retain every width ever visited.
        if measuredSizes.count == 8 { measuredSizes.removeFirst() }
        measuredSizes.append((width, height, measured))
        return measured
    }

    /// What the element last measured at, read from WinUI without marking it.
    var desiredSize: LayoutSize {
        var size = [0.0, 0.0]
        swiftomniui_winui_desired_size(presentationHandle, &size)
        return LayoutSize(width: size[0], height: size[1])
    }

    /// Places the element at `place`, in DIPs of its parent: at once inside a pass, and between passes by asking
    /// the layout for one. Its size is its words' room while its place travels.
    /// Design: docs/design/platforms/winui/layout.md#a-place-between-passes
    func layout(_ place: Rect) {
        let moved = placed != place
        if nativeSafeBarOwner == nil { placed = place }
        if Self.arranging > 0 {
            if nativeSafeBarOwner == nil, let placingLayout {
                setLayoutContext(placingLayout.context(for: self, at: place)
                    .ignoring(sourceElement?.ignoresSafeArea))
            }
            let resized = committedFrame.map { $0.width != place.width || $0.height != place.height } ?? true
            let editorGeometryChanged = sourceElement?.type == .textEditor && committedFrame != place
            let room = wordsRoom ?? place
            WinUILayoutDiagnostics.record("place", view: self,
                "frame=\(WinUILayoutDiagnostics.rect(place)) measureRoom=\(WinUILayoutDiagnostics.rect(room)) resized=\(resized)")
            // Complete placement input, preserving the native Measure result.
            // The same contract applies to SOUI and native XAML containers.
            prepareAllocation(in: Rect(0, 0, room.width, room.height))
            if let layout = self as? WinUILayoutView, placingLayout != nil {
                layout.standsAt = place.width
            }
            commitAllocationGeometry(in: place)
            withNativeArrange {
                swiftomniui_winui_arrange(presentationHandle, place.x, place.y, room.width, room.height)
            }
            if editorGeometryChanged, let editor = self as? WinUITextEditorView {
                editor.recordAllocation("editor.commit", frame: place, room: room)
            }
        } else if moved {
            // The parent's next Arrange prepares the latest presentation slot.
            // No queued measurement from an older animation frame can overwrite it.
            placingLayout?.invalidateArrange()
        }
    }

    /// A native owner can arrange this view without going through `layout`.
    /// SOUI placement has already committed its presentation size before
    /// entering XAML, which can use a different destination room for words.
    func commitNativeAllocation(width: Double, height: Double) {
        guard !isNativeArranging else { return }
        let bounds = Rect(0, 0, width, height)
        guard committedFrame != bounds else { return }
        withNativeArrange { commitAllocationGeometry(in: bounds) }
    }

    /// Publishes drawing geometry only: never measures, arranges or invalidates
    /// ancestors. Both native ownership and SOUI placement enter here.
    private func commitAllocationGeometry(in bounds: Rect) {
        let resized = committedFrame.map { $0.width != bounds.width || $0.height != bounds.height } ?? true
        committedFrame = bounds
        commitGeometry(in: bounds)
        if resized, transform != .identity || placedDrawing != nil { writeTransform() }
        if resized {
            for what in paintsBySize.keys.sorted() {
                paintsBySize[what]?(LayoutSize(width: bounds.width, height: bounds.height))
            }
        }
    }

    /// Size-dependent drawing committed with the actual native Arrange.
    func commitGeometry(in bounds: Rect) {}

    /// Paints `what` with `paint` at the view's size now, and again at each new size where its brushes follow the
    /// size of what they paint (`WinUIBrush.followsSize`).
    /// Design: docs/design/platforms/winui/drawing.md#a-box-and-its-brush
    func paint(_ what: String, followsSize: Bool, _ paint: @escaping (LayoutSize) -> Void) {
        paintsBySize[what] = followsSize ? paint : nil
        let frame = committedFrame ?? Rect(0, 0, 0, 0)
        paint(LayoutSize(width: frame.width, height: frame.height))
    }

    /// Nothing of the view's own follows where its place travels.
    func travels(to destination: Rect?) {}

    /// The size the view's words are laid out at while its place travels; nil for its place's.
    var wordsRoom: Rect? { nil }

    /// Where the element's top left corner stands in its window's content, in DIPs.
    var origin: Point {
        var corner = [0.0, 0.0]
        swiftomniui_winui_origin(handle, &corner)
        return Point(x: corner[0], y: corner[1])
    }

    /// The position produced by Arrange relative to a native ancestor.
    /// RenderTransform and composition animations do not change layout input.
    func layoutOffset(relativeTo ancestor: WinUIView) -> Point? {
        var offset = [0.0, 0.0]
        guard swiftomniui_winui_layout_offset(handle, ancestor.handle, &offset) else { return nil }
        return Point(offset[0], offset[1])
    }

    /// Where the view stands, in DIPs: its frame in its parent, its place in the window, and the frame the
    /// window's content - clear of its chrome - stands in there.
    func frameReport(safeArea: Rect) -> [Double] {
        let corner = origin
        let local = safeAreaContext?.safe
        let safe = local.map { Rect(corner.x + $0.x, corner.y + $0.y, $0.width, $0.height) } ?? safeArea
        var frame = placedFrame
        let actual = laidOutFrame
        frame.width = actual.width
        frame.height = actual.height
        return MountedElement.frameNumbers(place: frame, corner: corner, safeArea: safe)
    }

    /// Where WinUI laid the element out in its parent, in DIPs.
    var laidOutFrame: Rect {
        var frame = [0.0, 0.0, 0.0, 0.0]
        swiftomniui_winui_frame(presentationHandle, &frame)
        return Rect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
    }

    var isAttached: Bool { swiftomniui_winui_is_attached(handle) }

    /// The control's one accent colour; nil for the platform's.
    /// Design: docs/design/platforms/winui/controls.md#a-controls-accent
    func setTint(_ tint: HostValue?) {
        let argb = tint?.argb
        swiftomniui_winui_set_tint(handle, argb ?? 0, argb != nil, PressedFill.underPointer, PressedFill.pressed)
    }

    /// What assistive technology meets of the view: nil words and presence for the control's own, a heading level
    /// of 0 for none.
    /// Design: docs/design/platforms/winui/controls.md#what-assistive-technology-meets
    func setAccessibility(_ words: AccessibilityWords) {
        let met: Int32 = switch words.presence {
        case nil: 0
        case .met: 1
        case .hidden: 2
        // A control's parts are its template's, left out with it; a layout holds its children back itself.
        case .hiddenWithChildren: self is WinUILayoutView ? 2 : 3
        }
        swiftomniui_winui_set_accessibility(handle, words.identifier, words.label, words.hint, words.headingLevel, met)
    }

    /// The user clicked the view.
    func clicked() {}

    /// The user turned the view on or off: a switch, a check box, a button
    /// that stays pressed.
    func toggled(_ on: Bool) {}

    /// The user chose one of the view's entries by its place: an action of the window's chrome, or its way back (-1)
    /// or sidebar toggle (-2); a tab.
    func chose(_ index: Int) {}

    /// What the view presents opened or closed of WinUI's accord: a split view's sidebar, a picker's list, a date
    /// picker's calendar, a context menu, a menu button's menu, a popover's card.
    ///
    /// A popup standing over the pointer holds the hover of what it stands over, so the base counts each by the view
    /// that presents it, and reads from that view what the popup holds of the element tree - its own content, which
    /// the popup does not stand over; a view that overrides this and does not call it - a split view's sidebar, which
    /// opens beside the pointer - is no popup over it.
    /// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
    func presented(_ open: Bool) {
        if open {
            WinUIHoverHold.began(self)
        } else {
            WinUIHoverHold.ended(self)
        }
    }

    /// The user picked a day - its year, month and day - or a time of day - its hour, minute and 0.
    func picked(_ first: Int32, _ second: Int32, _ third: Int32) {}

    /// What the items of the menus the view offers do, in their order: its context menu's, or a menu bar's.
    var menuActions: [() -> Void] = []

    /// Gives the view `menu` as its context menu; an empty one takes it away.
    /// Design: docs/design/platforms/winui/pages.md#menus
    func setContextMenu(_ menu: WinUIMenu) {
        menuActions = menu.actions
        WinUIStrings.withCStrings(menu.titles) { titles in
            WinUIStrings.withCStrings(menu.identifiers) { identifiers in
                menu.kinds.withUnsafeBufferPointer { kinds in
                    menu.enabled.withUnsafeBufferPointer { enabled in
                        swiftomniui_winui_set_context_menu(
                            handle, number, kinds.baseAddress, titles, enabled.baseAddress, identifiers,
                            menu.mounts, Int32(kinds.count))
                    }
                }
            }
        }
    }

    /// The user holds the view down or lets it go: a scroller taken hold of, a button's press.
    func held(_ holding: Bool) {}

    /// What the view does when the keyboard comes into it or leaves; nil hears nothing.
    private var onFocusChanged: ((Bool) -> Void)?

    /// Hears the keyboard come into the view and leave it, while `action` is set.
    func setFocusChanged(_ action: ((Bool) -> Void)?) {
        if (action != nil) != (onFocusChanged != nil) { swiftomniui_winui_hear_focus(handle, number, action != nil) }
        onFocusChanged = action
    }

    /// The keyboard came into the view or left it.
    func focusChanged(_ focused: Bool) {
        onFocusChanged?(focused)
    }

    /// The user chose the item at `index` of the view's menus.
    func menuChosen(_ index: Int) {
        if menuActions.indices.contains(index) { menuActions[index]() }
    }

    /// What of the user's input the view listens for; what hears it.
    private(set) var hearing: Hearing = []
    private var onHeard: ((HeardInput) -> Void)?

    /// The press the view heard, on its way to a drag by the host layer's rule.
    private var press = DragRecognition(distance: WinUIView.dragDistance)

    /// The system's drag distance, in DIPs.
    private static let dragDistance: DragRecognition.Distance = {
        var distance = [4.0, 4.0]
        swiftomniui_winui_drag_distance(&distance)
        return .eachAxis(x: distance[0], y: distance[1])
    }()

    /// Listens for what `hearing` names, `heard` hearing it; the relay is told only a change, in its bits, which
    /// are `Hearing`'s.
    /// Design: docs/design/platforms/winui/input.md
    func hear(_ hearing: Hearing, _ heard: @escaping (HeardInput) -> Void) {
        onHeard = hearing.isEmpty ? nil : heard
        guard hearing != self.hearing else { return }

        self.hearing = hearing
        swiftomniui_winui_hear(handle, number, hearing.rawValue)
    }

    /// What the relay says the view heard.
    ///
    /// A popup standing over the pointer takes the pointer with it, so WinUI tells the views under it that it left -
    /// which it did not. That exit is withheld while a popup stands over the view; a pointer coming back on the view
    /// drops what was withheld, since its hover never left either. A popup standing over one layer is no popup over
    /// the layer it opens in: what stands in a popup - its own card's content, where the pointer is - hears the
    /// pointer's own exits, and so does a card's content while a popup opened from inside it stands over the card.
    /// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
    func heard(_ heard: HeardInput) {
        if case .pointer(let event, _) = heard {
            if event == .pointerEntered {
                WinUIHoverHold.resumed(self)
            } else if event == .pointerExited, WinUIHoverHold.standsOver(self) {
                WinUIHoverHold.withhold(heard, for: self)
                return
            }
        }
        deliver(heard)
    }

    /// What the view heard, past the hold above - what the hold itself uses when a popup's going settles it.
    func deliver(_ heard: HeardInput) {
        onHeard?(heard)
    }

    /// A press the relay tells - down, moved, let go or taken away, at `point` of the window's content: a drag by the
    /// host layer's rule, and as it becomes one the view holds the pointer.
    /// Design: docs/design/platforms/winui/input.md#a-press-dragged
    func heardPress(phase: Int32, at point: Point) {
        switch phase {
        case 0:
            press.pressed(at: point)
        case 1:
            let wasDragging = press.isDragging
            let told = press.moved(to: point)
            if press.isDragging, !wasDragging { swiftomniui_winui_press_dragged(number) }
            for each in told { heard(each) }
        default:
            if let end = press.ended(letGo: phase == 2) { heard(end) }
        }
    }

    /// The element left the tree: the view lets go of everything that would call back into it. A view that
    /// overrides this lets go of what every view holds first, then of its own.
    func detach() {
        isDetached = true
        WinUIHoverHold.letGo(of: self)
        // The popups it presented stood with it, and their going settles what they held.
        WinUIHoverHold.ended(self)
        if let blurPresenter { swiftomniui_winui_blur_clear(blurPresenter) }
        hear([]) { _ in }
        setFocusChanged(nil)
        menuActions = []
        paintsBySize = [:]
    }
}

extension WinUIView: PlacedView {
    /// Where the view stands in its parent, in DIPs - where the host last placed it, or where WinUI has it.
    var placedFrame: Rect {
        get { placed ?? laidOutFrame }
        set { layout(newValue) }
    }
}

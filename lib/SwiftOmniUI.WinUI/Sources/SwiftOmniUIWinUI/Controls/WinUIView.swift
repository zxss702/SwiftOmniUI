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

    /// The number the relay's callbacks name this view by.
    let number: Int64

    /// The layout that places this view, which a place written between passes asks to arrange again.
    weak var placingLayout: WinUILayoutView?

    /// Logical ancestry survives native toolbar hosting.
    weak var sourceElement: MountedElement?
    var safeAreaContext: SafeAreaContext? {
        didSet { if safeAreaContext != oldValue { safeAreaChanged() } }
    }
    var rootSafeAreaContext: ((Rect) -> SafeAreaContext)?

    /// A native toolbar owns the widget, while the source modifier still owns
    /// its layout contribution, animation ancestry and parent-space report.
    weak var nativeSafeBarOwner: AnyObject?
    private(set) var safeBarDrawing: HostMatrix?

    func recordSafeBarPlace(_ place: Rect, context: SafeAreaContext) {
        placed = place
        safeAreaContext = context
        (nativeSafeBarOwner as? WinUISafeAreaBarHost)?.sourcePlaced(place)
        updateSafeBarDrawing()
    }

    func clearSafeBarDrawing() {
        safeBarDrawing = nil
        setPlacedDrawing(nil, opacity: 1)
        writeTransform()
    }

    func updateSafeBarDrawing() {
        guard nativeSafeBarOwner != nil else { return }
        (nativeSafeBarOwner as? WinUIView)?.setIgnoresInput(sourceElement?.safeBarAllowsInput == false)
        var matrix = HostMatrix.identity
        var opacity = 1.0
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
                x = frame.x
                y = frame.y
            }
            next = element.parent
        }
        var unmoved = HostMatrix.identity
        unmoved.m41 = -totalX
        unmoved.m42 = -totalY
        safeBarDrawing = matrix * unmoved
        setPlacedDrawing(placedDrawing, opacity: opacity)
        writeTransform()
    }

    /// An ancestor opacity/offset animation need not cause layout. Mirror it
    /// to promoted descendants when drawing changes as well as when arranging.
    func refreshNativeSafeBarDrawing() {
        func visit(_ element: MountedElement) {
            for child in element.children {
                if let view = (child.native as? WinUIElement)?.view, view.nativeSafeBarOwner != nil {
                    view.updateSafeBarDrawing()
                } else {
                    visit(child)
                }
            }
        }
        if let sourceElement { visit(sourceElement) }
    }

    func layoutSafeArea(in bounds: Rect) -> SafeAreaContext {
        (safeAreaContext ?? rootSafeAreaContext?(bounds) ?? SafeAreaContext(bounds: bounds))
            .ignoring(sourceElement?.ignoresSafeArea)
    }

    /// Update document arithmetic before its presenter measures; native
    /// invalidations and margins are committed outside the layout pass.
    func safeAreaChanged() {}

    /// Toolbar controls share the title bar's transparent trigger appearance.
    var isToolbarControl = false

    /// How deep the layout passes under way stand: a place written inside one lands at once.
    static var arranging = 0
    static var measuring = 0

    /// Where the view was last placed, in DIPs of its parent; nil before its first place.
    private(set) var placed: Rect?

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
    private var measuredSizes: [(width: Double?, height: Double?, size: LayoutSize)] = []
    /// The constraint actually prepared in XAML, separate from the several
    /// proposals the arithmetic can query without changing that constraint.
    private var nativeProposal: (width: Double?, height: Double?)?
    private var pendingMeasures: [(width: Double?, height: Double?)] = []
    private var nativeMeasurePending = false
    /// Only views whose size changes are explicitly reported by the host can
    /// keep native answers between passes. Controls with native content or
    /// user edits let XAML's own dirty flags decide whether to measure again.
    var reusesNativeMeasurements: Bool { false }
    /// Any arithmetic that encountered an unprepared native proposal is
    /// provisional; ancestors must not retain it as a completed measurement.
    static var provisionalMeasureRevision = 0
    /// Changes when properties or a native size change invalidate this view, not on a repeated Measure query.
    var measurementRevision = 0

    private static let live = LiveViews<WinUIView>()

    /// Takes the next number and holds the element `make` makes, handed that number.
    init(_ make: (_ number: Int64) -> SwiftOmniUIObjectRef?) {
        number = Self.live.reserve()
        guard let handle = make(number) else { fatalError("the relay made no element - its log says why") }
        self.handle = handle
        Self.live.hold(self, as: number)
        // A control's style aligns it inside its place; a SwiftOmniUI layout decides the place, so it fills it.
        // Design: docs/design/platforms/winui/layout.md#a-place-filled
        swiftomniui_winui_fill_place(handle)
    }

    isolated deinit {
        Self.live.release(number)
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
        swiftomniui_winui_set_shown(handle, shown)
    }

    /// How opaque the view's own property draws it, with a placing layout's opacity over it; written only where
    /// it differs from what was.
    func setOpacity(_ opacity: Double) {
        self.opacity = opacity
        let drawn = opacity * placedOpacity
        guard drawn != writtenOpacity else { return }
        writtenOpacity = drawn
        swiftomniui_winui_set_opacity(handle, drawn)
        refreshNativeSafeBarDrawing()
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
        swiftomniui_winui_set_hit_testable(handle, !ignores)
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
        swiftomniui_winui_set_z_index(handle, z)
    }

    /// Moves, turns and scales the view where its layout put it, in DIPs and degrees.
    func setTransform(_ transform: HostDrawingTransform) {
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
        let size = placed ?? Rect(x: 0, y: 0, width: 0, height: 0)
        swiftomniui_winui_set_transform(
            handle, drawn.translationX, drawn.translationY, drawn.rotation,
            drawn.scaleX, drawn.scaleY, drawn.pivotX * size.width, drawn.pivotY * size.height)
        let ownTip = drawn.tip(width: size.width, height: size.height)
        let tip = safeBarDrawing.map { (ownTip ?? .identity) * $0 } ?? ownTip
        guard tip != writtenTip else { return }
        writtenTip = tip
        guard let tip else { return swiftomniui_winui_set_projection(handle, nil) }
        let numbers = [
            tip.m11, tip.m12, tip.m13, tip.m14, tip.m21, tip.m22, tip.m23, tip.m24,
            tip.m31, tip.m32, tip.m33, tip.m34, tip.m41, tip.m42, tip.m43, tip.m44,
        ]
        swiftomniui_winui_set_projection(handle, numbers)
    }

    /// Asks WinUI to measure this element again, and every panel above it.
    func invalidateMeasure() {
        measurementRevision &+= 1
        measuredSizes.removeAll(keepingCapacity: true)
        nativeProposal = nil
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
        swiftomniui_winui_invalidate_measure(handle)
    }

    /// The element's size for the room offered, in DIPs; nil offers any.
    /// Design: docs/design/platforms/winui/layout.md#measured-every-pass
    func measure(width: Double?, height: Double?) -> LayoutSize {
        // An arrangement asking a child's size reads what this proposal measured: measuring an element
        // while WinUI arranges marks it, and the marked element is measured and arranged again for ever -
        // XAML aborts the eighth such pass with a layout cycle.
        // WinUI receives single-precision proposals. Use that same value for the cache key so a width
        // travelling through Measure and Arrange does not become two different proposals.
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let height = height.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        if reusesNativeMeasurements || Self.arranging > 0,
           let measured = measuredSizes.first(where: { $0.width == width && $0.height == height }) {
            return measured.size
        }
        if Self.arranging > 0 {
            // Pixel rounding can narrow a text's arranged proposal slightly. A wider measurement whose
            // complete lines still fit has exactly the same wrapping; it needs no deferred repair.
            if self is WinUILabelView, let width,
               let measured = measuredSizes.last(where: {
                   $0.height == height && ($0.width ?? .infinity) >= width && $0.size.width <= width
               }) {
                return measured.size
            }

            // A new width can first appear during arrangement (a centred child, a resized column). Complete
            // that proposal after this pass and discard the ancestors' provisional arithmetic. Coalesce all
            // proposals for this view into one turn; once measured, the same arrangement posts nothing.
            Self.provisionalMeasureRevision &+= 1
            if !pendingMeasures.contains(where: { $0.width == width && $0.height == height }) {
                let scheduled = !pendingMeasures.isEmpty
                pendingMeasures.append((width, height))
                if !scheduled {
                    WinUIDoorbell.afterPass { [weak self] in
                        guard let self, !self.isDetached else { return }
                        let proposals = self.pendingMeasures
                        self.pendingMeasures.removeAll(keepingCapacity: true)
                        for proposal in proposals {
                            _ = self.measure(width: proposal.width, height: proposal.height)
                        }
                        self.placingLayout?.commitMeasurementChange()
                    }
                }
            }
            return desiredSize
        }
        return measureNative(width: width, height: height)
    }

    /// Prepare the final proposal even if its arithmetic answer is cached.
    /// Querying an ideal size must not repeatedly switch the native subtree
    /// away from its allocated width, or discard other width-keyed answers.
    func prepareNativeMeasure(width: Double?, height: Double?) {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let height = height.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        guard Self.arranging == 0 else {
            _ = measure(width: width, height: height)
            return
        }
        if reusesNativeMeasurements, let nativeProposal,
           nativeProposal.width == width, nativeProposal.height == height { return }
        _ = measureNative(width: width, height: height)
    }

    private func measureNative(width: Double?, height: Double?) -> LayoutSize {
        // This explicit preparation consumes the invalidation left by the
        // preceding pass; its queued invalidation must not discard it again.
        if nativeMeasurePending {
            nativeMeasurePending = false
            invalidateNativeMeasure()
        }
        let startedAt = Self.provisionalMeasureRevision
        let contentRevision = measurementRevision
        var size = [0.0, 0.0]
        Self.measuring += 1
        defer { Self.measuring -= 1 }
        swiftomniui_winui_measure(handle, width ?? .infinity, height ?? .infinity, &size)
        let measured = LayoutSize(width: size[0], height: size[1])
        guard startedAt == Self.provisionalMeasureRevision, contentRevision == measurementRevision else { return measured }
        nativeProposal = (width, height)
        measuredSizes.removeAll { $0.width == width && $0.height == height }
        // Only a few proposals are active at a time. Resizing must not retain every width ever visited.
        if measuredSizes.count == 8 { measuredSizes.removeFirst() }
        measuredSizes.append((width, height, measured))
        return measured
    }

    /// What the element last measured at, read from WinUI without marking it.
    var desiredSize: LayoutSize {
        var size = [0.0, 0.0]
        swiftomniui_winui_desired_size(handle, &size)
        return LayoutSize(width: size[0], height: size[1])
    }

    /// Places the element at `place`, in DIPs of its parent: at once inside a pass, and between passes by asking
    /// the layout for one. Its size is its words' room while its place travels.
    /// Design: docs/design/platforms/winui/layout.md#a-place-between-passes
    func layout(_ place: Rect) {
        if nativeSafeBarOwner == nil, let placingLayout {
            safeAreaContext = placingLayout.context(for: self, at: place)
                .ignoring(sourceElement?.ignoresSafeArea)
        }
        let resized = placed.map { $0.width != place.width || $0.height != place.height } ?? true
        if nativeSafeBarOwner == nil { placed = place }
        if Self.arranging > 0 {
            // A layout of SwiftOmniUI's is measured at the width it stands at; a new width is measured once the
            // pass ends - measuring an element while WinUI arranges marks it for another pass, for ever.
            // Design: docs/design/platforms/winui/layout.md#measured-every-pass
            if let layout = self as? WinUILayoutView, placingLayout != nil {
                if layout.standsAt != place.width,
                   !measuredSizes.contains(where: { $0.width == Double(Float(place.width)) && $0.height == nil }) {
                    layout.prepareAfterPass()
                }
                layout.standsAt = place.width
            }
            let room = wordsRoom ?? place
            swiftomniui_winui_arrange(handle, place.x, place.y, room.width, room.height)
        } else {
            placingLayout?.invalidateArrange()
        }
        if resized, transform != .identity || placedDrawing != nil { writeTransform() }
        if resized {
            for what in paintsBySize.keys.sorted() { paintsBySize[what]?(LayoutSize(width: place.width, height: place.height)) }
        }
    }

    /// Paints `what` with `paint` at the view's size now, and again at each new size where its brushes follow the
    /// size of what they paint (`WinUIBrush.followsSize`).
    /// Design: docs/design/platforms/winui/drawing.md#a-box-and-its-brush
    func paint(_ what: String, followsSize: Bool, _ paint: @escaping (LayoutSize) -> Void) {
        paintsBySize[what] = followsSize ? paint : nil
        let frame = placedFrame
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
        swiftomniui_winui_frame(handle, &frame)
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
    /// picker's calendar.
    func presented(_ open: Bool) {}

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
                            Int32(kinds.count))
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
    func heard(_ heard: HeardInput) {
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

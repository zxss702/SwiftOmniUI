// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A ScrollView: a SwiftOmniUI layout holding WinUI's own scroller around the document it moves.
/// Design: docs/design/platforms/winui/layout.md#scrolling
@MainActor
final class WinUIScrollView: WinUILayoutView {
    /// Says, on a display frame, where the user moved the scroller from and to, in DIPs.
    var onOffsetChanged: ((Point, Point) -> Void)?

    /// Says, on a display frame, that the user's movement came to rest.
    var onScrollStopped: (() -> Void)?

    /// Asks for the display's frames: the scroller moves, or has something to say.
    var onFramesWanted: (() -> Void)?

    private(set) var orientation = Axis.vertical

    /// Where the scroller stands, in DIPs, as it last said.
    private(set) var offset = Point(x: 0, y: 0)

    /// The user's movement, and its rest.
    private let movement = ScrollMovement()
    private var horizontalSamples = WinUILazyPrefetch.MotionSamples()
    private var lazyMotionStart: (offset: Point, time: Double)?
    private var verticalSamples = WinUILazyPrefetch.MotionSamples()
    private var lazyVelocity = Point(0, 0)
    private var lazyAcceleration = Point(0, 0)
    private var lazyInterval = Point(0, 0)
    private var lazyObservationLead = Point(0, 0)
    private var lazyPreparation = Point(0, 0)
    private var precedingLazyPreparation = Point(0, 0)

    /// An incoming nested lazy panel has no timing sample of its own yet.
    /// Reuse the last neighbouring batches in this scroller until it has one;
    /// zero would incorrectly predict that its first subtree is ready instantly.
    func recordLazyPreparation(_ duration: Double, on axis: StackArithmetic.Axis) {
        if axis == .vertical {
            lazyPreparation.y = max(duration, precedingLazyPreparation.y)
            precedingLazyPreparation.y = duration
        } else {
            lazyPreparation.x = max(duration, precedingLazyPreparation.x)
            precedingLazyPreparation.x = duration
        }
    }

    func preparationTime(on axis: StackArithmetic.Axis) -> Double {
        axis == .vertical ? lazyPreparation.y : lazyPreparation.x
    }

    let scroller = WinUIScrollerView()
    private let document = WinUIScrollDocument()

    /// Holds the content in a stack where the scroller was given more than one child.
    private let wrapper = WinUIStackView(axis: .vertical)
    private var wraps = false

    /// Where the program moved the scroller, until the scroller says it stands there.
    /// Design: docs/design/platforms/winui/layout.md#the-programs-move
    private var programTarget: Point?
    private weak var readerRoot: MountedElement?
    private weak var readerLazy: WinUILazyView?
    private var readerIdentity: String?
    private var readerDestination: (name: String, x: Double?, y: Double?)?
    private var readerMove: Point?
    private var resolvingReader = false

    /// The offset the tree writes, kept for the first layout where it comes before it.
    private var writtenOffset = WrittenScrollOffset()

    /// Content and indicators resolve the same remaining region. These are
    /// arithmetic values; native margin writes are committed after layout.
    private var writtenPadding = EdgeInsets(0)
    private var barsInsets = EdgeInsets(0)
    private var pendingInsets: EdgeInsets?
    private var commitPending = false
    private var detached = false

    private var bars = (vertical: ScrollIndicatorVisibility.automatic, horizontal: ScrollIndicatorVisibility.automatic)

    override init() {
        super.init()
        wrapper.spacing = 0
        movement.onFramesWanted = { [weak self] in self?.onFramesWanted?() }
        scroller.onScrolled = { [weak self] standing in
            guard let self else { return }
            self.scrolled(to: standing)
        }
        scroller.onHeld = { [weak self] holding in self?.scrollerHeld(holding) }
        scroller.placingLayout = self
        document.scrollView = self
        setChildren([scroller])
        configure()
    }

    /// The content: one child, or several stacked down.
    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        if items.count > 1 { wraps = true }

        var changed = false
        if wraps {
            changed = wrapper.setItems(items)
            changed = document.setItems([WinUILayoutItem(view: wrapper)]) || changed
        } else {
            changed = document.setItems(items)
        }
        if changed { invalidateMeasurements() }
        return changed
    }

    override func forgetMeasurements() {
        super.forgetMeasurements()
        document.forgetMeasurements()
        wrapper.forgetMeasurements()
    }

    /// A lazy descendant can change the document's extent without changing this
    /// ScrollView's allocated frame. Make the native presenter read that extent
    /// again so its scroll range and thumb follow the same geometry as the rows.
    func invalidateContentExtent() {
        document.invalidateOwnMeasurements()
    }

    /// Where a `.defaultScrollAnchor` asks the scroller to begin: fractions
    /// across and down the content and the room. Applied once, on the first
    /// layout with a document to place.
    private var defaultAnchor: (x: Double, y: Double)?
    private var anchoredOnce = false

    /// Whether each axis moves only where the content fills the view: WinUI's `ScrollMode`. Down alone at first:
    /// the scroller's own set leaves a view that names no other way with down alone, and a patch that names no
    /// member of this registration never reaches `apply` to say otherwise.
    private var modes = (vertical: Int32(1), horizontal: Int32(0))

    /// The scroller's orientation, padding, bars, where a reader's default
    /// anchor asks it to begin, and an offset the tree moved it to.
    func apply(
        orientation: Axis, padding: EdgeInsets, verticalBar: ScrollIndicatorVisibility,
        horizontalBar: ScrollIndicatorVisibility, defaultAnchor: UnitPoint?, offset: Point?,
        bounce: ScrollBounceBehavior, bounceAxes: Axis.Set
    ) {
        let mode: Int32 = bounce == .basedOnSize ? 2 : 1
        modes = (
            vertical: orientation == .horizontal || orientation == .neither ? 0
                : (bounceAxes.contains(.vertical) ? mode : 1),
            horizontal: orientation == .vertical || orientation == .neither ? 0
                : (bounceAxes.contains(.horizontal) ? mode : 1))
        if orientation != self.orientation || verticalBar != bars.vertical || horizontalBar != bars.horizontal {
            self.orientation = orientation
            bars = (verticalBar, horizontalBar)
            configure()
        } else {
            scroller.setModes(vertical: modes.vertical, horizontal: modes.horizontal)
        }
        writtenPadding = padding
        let resolvedPadding = SafeAreaArithmetic.physicalInsets(padding, direction: direction) + barsInsets
        if document.layoutPadding != resolvedPadding {
            document.layoutPadding = resolvedPadding
            document.forgetMeasurements()
            wrapper.forgetMeasurements()
        }
        document.orientation = orientation
        if let defaultAnchor { self.defaultAnchor = (defaultAnchor.x, defaultAnchor.y) }

        if let target = writtenOffset.written(offset, standing: self.offset, orientation: orientation) {
            finishReaderDestination()
            move(to: target)
        }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        // No native properties, parent relationships, or invalidations here.
        return document.contentSize(width: width)
    }

    override var hasNativeProposals: Bool { true }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        let viewport = resolve(in: Rect(0, 0, width ?? size.width, size.height))
        return [NativeProposal(view: scroller, place: viewport)]
    }

    override func restoreLayoutContext(in bounds: Rect, proposals: [NativeProposal]) {
        // Cached plans still restore the document's inherited insets before
        // its native presenter measures. The plan's finite bounds already
        // resolve an unspecified axis to its natural extent.
        _ = resolve(in: bounds)
    }

    override func backgroundBounds(in bounds: Rect) -> Rect {
        box.clips ? bounds : layoutSafeArea(in: bounds).viewport(in: bounds, axes: orientation)
    }

    override func safeAreaChanged() {
        if let context = safeAreaContext { _ = resolve(in: context.layout) }
        super.safeAreaChanged()
    }

    private func resolve(in bounds: Rect) -> Rect {
        let context = layoutSafeArea(in: bounds)
        let viewport = box.clips ? bounds : context.viewport(in: bounds, axes: orientation)
        let insets = SafeAreaContext.insets(of: context.safe, in: viewport)
        let consumed = context.consumed + insets
        if document.consumedInsets != consumed {
            document.consumedInsets = consumed
            document.layoutContextChanged()
            document.forgetMeasurements()
        }
        let padding = SafeAreaArithmetic.physicalInsets(writtenPadding, direction: direction) + insets
        if document.layoutPadding != padding {
            document.layoutPadding = padding
            // Resolved padding belongs to this proposal. Commit its native
            // contribution once after layout; selecting another plan must not
            // dirty an ancestor that is still measuring or arranging us.
            document.layoutContextChanged()
            document.forgetMeasurements()
            wrapper.forgetMeasurements()
        }
        if barsInsets != insets || document.padding != padding { pendingInsets = insets }
        barsInsets = insets
        if pendingInsets != nil, !commitPending {
            commitPending = true
            WinUIDoorbell.afterPass { [weak self] in
                guard let self else { return }
                self.commitPending = false
                guard !self.detached, let insets = self.pendingInsets else { return }
                self.pendingInsets = nil
                self.document.padding = SafeAreaArithmetic.physicalInsets(self.writtenPadding, direction: self.direction) + insets
                self.scroller.insetScrollbars(insets)
            }
        }
        return viewport
    }

    /// The native viewport extends under bars; its document alone reserves
    /// their region. Descendants receive a consumed context, independent of
    /// the document's moving origin and of any enclosing scroller.
    override func arrange(in bounds: Rect) {
        for proposal in preparedLayoutPlan(in: bounds) { proposal.view?.layout(proposal.place) }
        // Initial offsets/anchors wait for the resolved document extent.
        guard document.padding == document.layoutPadding else { return }
        if let target = writtenOffset.laidOutNow() {
            move(to: target)
        } else if let defaultAnchor, !anchoredOnce {
            anchoredOnce = true
            let reach = scroller.standing.reach
            move(to: Point(x: defaultAnchor.x * reach.x, y: defaultAnchor.y * reach.y))
        }
    }

    // MARK: - The user's movement

    /// The scroller's view changed: the program's move arriving, or the user's, joined to the moves before it until
    /// the display's next frame.
    private func scrolled(to standing: Point) {
        guard standing != offset else { return }
        let previous = offset
        offset = standing

        if let target = programTarget {
            programTarget = nil
            if !ScrollArithmetic.differs(target, standing) {
                return
            }
        }
        // Suppress binding feedback, not the native position itself. Layout
        // anchoring can change that position while a tree patch is being applied.
        guard !ProgramWrite.isWriting else { return }
        movement.userMoved(from: previous, to: standing)
    }

    /// The user took hold of the scroller, or let go of it and left it to throw on.
    private func scrollerHeld(_ holding: Bool) {
        horizontalSamples = .init()
        verticalSamples = .init()
        lazyVelocity = Point(0, 0)
        lazyAcceleration = Point(0, 0)
        lazyInterval = Point(0, 0)
        lazyObservationLead = Point(0, 0)
        if holding {
            finishReaderDestination()
            programTarget = nil
            movement.holdBegan()
            lazyMotionStart = (scroller.standing.offset, WinUIFrameClock.monotonic())
        } else {
            lazyMotionStart = nil
            movement.holdEnded(rests: false)
        }
        for ear in scroller.ears { ear.moved() }
    }

    /// Whether the scroller needs the display's frames.
    var wantsFrames: Bool { movement.wantsFrames }

    /// Whether the user holds the scroller: a live scroll the compositor sweeps
    /// under its own power, ahead of this thread's notices.
    var held: Bool { movement.holding }

    /// Every lazy descendant follows one physical movement. A newly created
    /// nested panel can use its scroller's existing samples immediately.
    func lazyMotion(on axis: StackArithmetic.Axis) -> (velocity: Double, interval: Double, acceleration: Double) {
        axis == .vertical ? (lazyVelocity.y, lazyInterval.y, lazyAcceleration.y)
            : (lazyVelocity.x, lazyInterval.x, lazyAcceleration.x)
    }

    private func observeLazyMotion(at offset: Point, now: Double) {
        let refresh = WinUIFrameClock.current?.refreshInterval ?? 0
        guard held else { return }
        if let start = lazyMotionStart {
            lazyMotionStart = nil
            // The host's frame clock can use another origin (including a
            // deterministic test clock). Translate the captured start into it,
            // using the measured elapsed interval, rather than discarding the
            // first movement merely to establish an offset baseline.
            let elapsed = max(0, WinUIFrameClock.monotonic() - start.time)
            _ = horizontalSamples.observe(offset: start.offset.x, time: now - elapsed, refreshInterval: refresh)
            _ = verticalSamples.observe(offset: start.offset.y, time: now - elapsed, refreshInterval: refresh)
        }
        // Sample once per display frame. Mixing ViewChanged and Rendering
        // timestamps gives fragments of one movement different time origins,
        // causing the predicted lead to alternately grow and collapse.
        if let sample = horizontalSamples.observe(offset: offset.x, time: now, refreshInterval: refresh) {
            lazyVelocity.x = sample.velocity; lazyInterval.x = sample.interval
            lazyAcceleration.x = sample.acceleration
        }
        if let sample = verticalSamples.observe(offset: offset.y, time: now, refreshInterval: refresh) {
            lazyVelocity.y = sample.velocity; lazyInterval.y = sample.interval
            lazyAcceleration.y = sample.acceleration
        }
    }

    /// Native ViewChanged offsets can lead the transform exposed by XAML.
    /// Compare in document coordinates so nested lazy panels share the same lag.
    func observationLead(on axis: StackArithmetic.Axis) -> Double {
        axis == .vertical ? lazyObservationLead.y : lazyObservationLead.x
    }

    /// One frame of the display: what the scroller has to say, said here and nowhere else.
    func frame(now: Double) {
        if held {
            let offset = scroller.standing.offset
            // This position is read now, rather than at RenderingTime (the
            // frame XAML started earlier). Layout can advance the native
            // offset while delaying that callback. Pairing its newer position
            // with an older frame timestamp invents an acceleration and makes
            // the following realization request still larger.
            observeLazyMotion(at: offset, now: WinUIFrameClock.current?.now() ?? now)
            if case .ready(let rect) = scroller.viewport(of: document) {
                lazyObservationLead = Point(offset.x - rect.x, offset.y - rect.y)
            } else { lazyObservationLead = Point(0, 0) }
        }
        // Keep the visible window current through inertia, independently of
        // how many native ViewChanged notifications arrived between frames.
        scroller.ears.removeAll { $0.owner == nil }
        for ear in scroller.ears {
            if let frame = ear.frame { frame() }
            else { ear.moved() }
        }
        for report in movement.frame(now: now) {
            switch report {
            case .moved(let from, let to): onOffsetChanged?(from, to)
            case .rested: onScrollStopped?()
            }
        }
    }

    override func detach() {
        finishReaderDestination()
        detached = true
        pendingInsets = nil
        super.detach()
        onOffsetChanged = nil
        onScrollStopped = nil
        onFramesWanted = nil
        scroller.detach()
    }

    // MARK: - WinUI's scroller

    /// A reader names logical content, including rows not yet materialized.
    /// Observe completed native layouts rather than consuming an initial zero
    /// allocation or scheduling a second layout to make the request work.
    @discardableResult
    func scroll(to name: String, in root: MountedElement, anchorX: Double?, anchorY: Double?) -> Bool {
        finishReaderDestination()
        func lazyTarget(in element: MountedElement) -> (WinUILazyView, String)? {
            if let view = (element.native as? WinUIElement)?.view as? WinUILazyView,
               let identity = element.lazyRows?.identity(forScrollID: name)
                    ?? (view.cells.position(of: name) != nil ? name : nil) { return (view, identity) }
            for child in element.children {
                if child !== root, (child.native as? WinUIElement)?.view is WinUIScrollView { continue }
                if let found = lazyTarget(in: child) { return found }
            }
            return nil
        }
        let lazy = lazyTarget(in: root)
        guard lazy != nil || root.first(id: .manual(name)) != nil else { return false }
        readerRoot = root
        readerLazy = lazy?.0
        readerIdentity = lazy?.1
        readerDestination = (name, anchorX, anchorY)
        swiftomniui_winui_scroller_watch_layout(scroller.handle, number) { number in
            MainActor.assumeIsolated {
                (WinUIView.find(number) as? WinUIScrollView)?.resolveReaderDestination()
            }
        }
        if let (view, identity) = lazy {
            view.requestReaderTarget(identity, anchor: view.axis == .vertical ? anchorY : anchorX)
        }
        resolveReaderDestination()
        return true
    }

    private func finishReaderDestination() {
        guard readerDestination != nil else { return }
        readerLazy?.readerTarget = nil
        readerLazy = nil
        readerIdentity = nil
        readerRoot = nil
        readerDestination = nil
        readerMove = nil
        swiftomniui_winui_scroller_watch_layout(scroller.handle, number, nil)
    }

    /// An explicit native scrollbar request supersedes an unfinished reader jump.
    func cancelReaderDestination() { finishReaderDestination() }

    private func resolveReaderDestination() {
        guard !resolvingReader, let request = readerDestination, let root = readerRoot else { return }
        resolvingReader = true
        defer { resolvingReader = false }
        func nativeView(_ element: MountedElement) -> WinUIView? {
            if let view = (element.native as? WinUIElement)?.view { return view }
            let children = request.y == 1 ? Array(element.children.reversed()) : element.children
            for child in children { if let view = nativeView(child) { return view } }
            return nil
        }
        let descendant: WinUIView?
        if let identity = readerIdentity, let lazy = readerLazy {
            guard lazy.cells.position(of: identity) != nil else { finishReaderDestination(); return }
            // One logical ForEach row can contain several sibling views.
            // Its native row container supplies their complete bounds.
            descendant = lazy.mounted[identity]?.view
        } else {
            guard let target = root.first(id: .manual(request.name)) else { finishReaderDestination(); return }
            descendant = nativeView(target)
        }
        guard let descendant, descendant.placed != nil else { return }
        let rowsReady = readerLazy.map { $0.cells.requestedItemsAreCurrent && !$0.needsRowMeasurements
            && !$0.cells.needsMeasurement } ?? true
        guard rowsReady else { return }
        var place = [0.0, 0.0]
        var found: Int32 = 0
        swiftomniui_winui_scroller_place_for(
            scroller.handle, descendant.handle, request.x ?? .nan, request.y ?? .nan, &found, &place)
        guard found != 0 else { return }
        let standing = scroller.standing
        let destination = ScrollArithmetic.kept(Point(x: place[0], y: place[1]), reach: standing.reach)
        if !ScrollArithmetic.differs(destination, standing.offset) {
            finishReaderDestination()
        } else if readerMove.map({ ScrollArithmetic.differs($0, destination) }) ?? true {
            readerMove = destination
            move(to: destination)
        }
    }

    private func configure() {
        scroller.set(
            content: document, orientation: orientation, verticalBar: bars.vertical, horizontalBar: bars.horizontal)
        scroller.setModes(vertical: modes.vertical, horizontal: modes.horizontal)
    }

    /// Scrolls until `descendant` stands where the anchors say: fractions
    /// across and down it and the room, an absent one for "only where it is
    /// not wholly in view".
    func scroll(toDescendant descendant: WinUIView, anchorX: Double?, anchorY: Double?) {
        var place = [0.0, 0.0]
        var found: Int32 = 0
        swiftomniui_winui_scroller_place_for(
            scroller.handle, descendant.handle, anchorX ?? .nan, anchorY ?? .nan, &found, &place)
        guard found != 0 else { return }
        move(to: Point(x: place[0], y: place[1]))
    }

    /// Moves the scroller to `target`, kept within what it reaches, as the program's move; one already there is
    /// left alone, as the scroller would say nothing of it.
    private func move(to target: Point) {
        let standing = scroller.standing
        let kept = ScrollArithmetic.kept(target, reach: standing.reach)
        guard ScrollArithmetic.differs(kept, standing.offset) else {
            offset = standing.offset
            return
        }

        programTarget = kept
        scroller.move(to: kept)
    }
}

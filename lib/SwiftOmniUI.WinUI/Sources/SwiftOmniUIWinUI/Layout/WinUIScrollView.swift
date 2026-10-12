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

    let scroller = WinUIScrollerView()
    private let document = WinUIScrollDocument()

    /// Holds the content in a stack where the scroller was given more than one child.
    private let wrapper = WinUIStackView(axis: .vertical)
    private var wraps = false

    /// Where the program moved the scroller, until the scroller says it stands there.
    /// Design: docs/design/platforms/winui/layout.md#the-programs-move
    private var programTarget: Point?

    /// The offset the tree writes, kept for the first layout where it comes before it.
    private var writtenOffset = WrittenScrollOffset()

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
        document.padding = padding
        document.orientation = orientation
        if let defaultAnchor { self.defaultAnchor = (defaultAnchor.x, defaultAnchor.y) }

        if let target = writtenOffset.written(offset, standing: self.offset, orientation: orientation) {
            move(to: target)
        }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        document.contentSize(width: width)
    }

    /// The scroller is measured at the room it stands in and nowhere else: the offer it was measured at is all
    /// the room its presenter bounds the shown room by, and measuring while WinUI arranges defers to after the
    /// pass - the same proposal the next pass finds already measured.
    /// Design: docs/design/platforms/winui/layout.md#scrolling
    /// Stands WinUI's scroller over the whole of the room, then an offset the tree wrote before there was one - or,
    /// first time only, the default anchor a reader asked it to open at.
    override func arrange(in bounds: Rect) {
        // Measured natively at the room it stands in - a no-op until the document changed: the presenter then
        // measures and arranges, holding its anchor, before the document's rows move.
        var measured = [0.0, 0.0]
        swiftomniui_winui_measure(scroller.handle, bounds.width, bounds.height, &measured)
        scroller.layout(bounds)
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
        guard !ProgramWrite.isWriting, standing != offset else { return }

        if let target = programTarget {
            programTarget = nil
            if !ScrollArithmetic.differs(target, standing) {
                offset = standing
                return
            }
        }
        let previous = offset
        offset = standing
        movement.userMoved(from: previous, to: standing)
    }

    /// The user took hold of the scroller, or let go of it and left it to throw on.
    private func scrollerHeld(_ holding: Bool) {
        if holding {
            programTarget = nil
            movement.holdBegan()
        } else {
            movement.holdEnded(rests: false)
        }
    }

    /// Whether the scroller needs the display's frames.
    var wantsFrames: Bool { movement.wantsFrames }

    /// Whether the user holds the scroller: a live scroll the compositor sweeps
    /// under its own power, ahead of this thread's notices.
    var held: Bool { movement.holding }

    /// One frame of the display: what the scroller has to say, said here and nowhere else.
    func frame(now: Double) {
        for report in movement.frame(now: now) {
            switch report {
            case .moved(let from, let to): onOffsetChanged?(from, to)
            case .rested: onScrollStopped?()
            }
        }
    }

    override func detach() {
        super.detach()
        onOffsetChanged = nil
        onScrollStopped = nil
        onFramesWanted = nil
        scroller.detach()
    }

    // MARK: - WinUI's scroller

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

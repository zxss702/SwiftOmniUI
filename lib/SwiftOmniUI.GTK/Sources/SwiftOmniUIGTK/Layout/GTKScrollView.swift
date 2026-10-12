// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A ScrollView: a SwiftOmniUI layout holding GTK's own scroller around the document it moves.
/// Design: docs/design/platforms/gtk/layout.md#scrolling
@MainActor
final class GTKScrollView: GTKLayoutView {
    /// Says, on a display frame, where the user moved the scroller from and to.
    var onOffsetChanged: ((Point, Point) -> Void)?

    /// Says, on a display frame, that the user's movement came to rest.
    var onScrollStopped: (() -> Void)?

    /// Asks for the display's frames: the scroller moves, or has something to say.
    var onFramesWanted: (() -> Void)?

    private(set) var orientation = Axis.vertical

    /// Where the scroller stands, as it last said.
    private(set) var offset = Point(x: 0, y: 0)

    /// The user's movement, and its rest.
    private let movement = ScrollMovement()

    let scroller = GTKScrollerView()
    private let document = GTKScrollDocument()

    /// Holds the content in a stack where the scroller was given more than one child.
    private let wrapper = GTKStackView(axis: .vertical)
    private var wraps = false

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
        scroller.onScrolled = { [weak self] standing in self?.scrolled(to: standing) }
        scroller.onHeld = { [weak self] holding in self?.scrollerHeld(holding) }
        scroller.placingLayout = self
        setChildren([scroller])
        configure()
    }

    /// The content: one child, or several stacked down.
    @discardableResult
    override func setItems(_ items: [GTKLayoutItem]) -> Bool {
        if items.count > 1 { wraps = true }

        var changed = false
        if wraps {
            changed = wrapper.setItems(items)
            changed = document.setItems([GTKLayoutItem(view: wrapper)]) || changed
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

    /// The scroller's orientation, padding, bars, where a reader's default
    /// anchor asks it to begin, and an offset the tree moved it to.
    func apply(
        orientation: Axis, padding: EdgeInsets, verticalBar: ScrollIndicatorVisibility,
        horizontalBar: ScrollIndicatorVisibility, defaultAnchor: UnitPoint?, offset: Point?
    ) {
        if orientation != self.orientation || verticalBar != bars.vertical || horizontalBar != bars.horizontal {
            self.orientation = orientation
            bars = (verticalBar, horizontalBar)
            configure()
        }
        writtenPadding = padding
        document.layoutPadding = padding + barsInsets
        document.orientation = orientation
        if let defaultAnchor { self.defaultAnchor = (defaultAnchor.x, defaultAnchor.y) }

        if let target = writtenOffset.written(offset, standing: self.offset, orientation: orientation) {
            move(to: target)
        }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        // No native properties, parent relationships, or invalidations here.
        return document.contentSize(width: width)
    }

    override func backgroundBounds(in bounds: Rect) -> Rect {
        box.clips ? bounds : layoutSafeArea(in: bounds).viewport(in: bounds, axes: orientation)
    }

    private func resolve(in bounds: Rect) -> Rect {
        let context = layoutSafeArea(in: bounds)
        let viewport = box.clips ? bounds : context.viewport(in: bounds, axes: orientation)
        let insets = SafeAreaContext.insets(of: context.safe, in: viewport)
        barsInsets = insets
        document.consumedInsets = context.consumed + insets
        let padding = SafeAreaArithmetic.physicalInsets(writtenPadding, direction: direction) + insets
        if document.layoutPadding != padding {
            document.layoutPadding = padding
            document.forgetMeasurements()
            wrapper.forgetMeasurements()
        }
        pendingInsets = insets
        if !commitPending {
            commitPending = true
            GTKDoorbell.afterLayout { [weak self] in
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
        let viewport = resolve(in: bounds)
        scroller.layout(viewport)
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

    /// The scroller's view changed: the user's move, joined to the moves before it until the display's next frame;
    /// the program's own move is its write's echo.
    private func scrolled(to standing: Point) {
        guard !ProgramWrite.isWriting, standing != offset else { return }

        let previous = offset
        offset = standing
        movement.userMoved(from: previous, to: standing)
    }

    /// The user took hold of the scroller, or let go of it and left it to throw on.
    private func scrollerHeld(_ holding: Bool) {
        if holding {
            movement.holdBegan()
        } else {
            movement.holdEnded(rests: false)
        }
    }

    /// Whether the scroller needs the display's frames.
    var wantsFrames: Bool { movement.wantsFrames }

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
        detached = true
        pendingInsets = nil
        super.detach()
        onOffsetChanged = nil
        onScrollStopped = nil
        onFramesWanted = nil
        scroller.detach()
    }

    private func configure() {
        scroller.set(
            content: document, orientation: orientation, verticalBar: bars.vertical, horizontalBar: bars.horizontal)
    }

    /// Scrolls until `descendant` stands where the anchors say: fractions
    /// across and down it and the room, an absent one for "only where it is
    /// not wholly in view".
    func scroll(toDescendant descendant: GTKWidget, anchorX: Double?, anchorY: Double?) {
        var bounds = graphene_rect_t()
        guard gtk_widget_compute_bounds(descendant, document.widget, &bounds) != 0 else { return }

        let room = (
            width: Double(gtk_widget_get_width(scroller.widget)),
            height: Double(gtk_widget_get_height(scroller.widget)))
        var place = offset

        if orientation == .horizontal || orientation == .both {
            place.x = Self.target(
                at: Double(bounds.origin.x), length: Double(bounds.size.width),
                in: max(0, room.width - barsInsets.left - barsInsets.right),
                now: offset.x + barsInsets.left, anchor: anchorX) - barsInsets.left
        }
        if orientation == .vertical || orientation == .both {
            place.y = Self.target(
                at: Double(bounds.origin.y), length: Double(bounds.size.height),
                in: max(0, room.height - barsInsets.top - barsInsets.bottom),
                now: offset.y + barsInsets.top, anchor: anchorY) - barsInsets.top
        }
        move(to: place)
    }

    /// Where the room stands for `anchor` - the fraction across the child and
    /// the room - or, absent one, for the child wholly in view the shorter
    /// way, nowhere where it already is.
    private static func target(at start: Double, length: Double, in room: Double, now: Double, anchor: Double?)
        -> Double
    {
        if let anchor { return start + anchor * length - anchor * room }
        if start >= now, start + length <= now + room { return now }
        return start < now ? start : start + length - room
    }

    /// Moves the scroller to `target`, kept within what it reaches, as the program's move.
    private func move(to target: Point) {
        let standing = scroller.standing
        let kept = ScrollArithmetic.kept(target, reach: standing.reach)
        offset = kept
        guard ScrollArithmetic.differs(kept, standing.offset) else { return }

        ProgramWrite.perform { scroller.move(to: kept) }
    }
}

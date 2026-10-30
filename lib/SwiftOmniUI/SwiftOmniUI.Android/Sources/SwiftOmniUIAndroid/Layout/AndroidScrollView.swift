// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIAndroid

/// A ScrollView: a SwiftOmniUI layout holding Android's own scroller - a `ScrollView`, a `HorizontalScrollView`,
/// or the second inside the first for both - around the document it moves.
/// Design: docs/design/platforms/android/layout.md#scrolling
@MainActor
final class AndroidScrollView: AndroidLayoutView {
    /// Says, on a display frame, where the user moved the scroller from and to, in points.
    var onOffsetChanged: ((Point, Point) -> Void)?

    /// Says, on a display frame, that the user's movement came to rest.
    var onScrollStopped: (() -> Void)?

    /// Asks for the display's frames: the scroller moves, or has something to say.
    var onFramesWanted: (() -> Void)?

    private(set) var orientation = Axis.vertical

    /// Where the scroller stands, in points, as it was last seen.
    private(set) var offset = Point(x: 0, y: 0)

    /// The user's movement, and its rest.
    private let movement = ScrollMovement()

    private let document = AndroidScrollDocument()

    /// Holds the content in a stack where the scroller was given more than one child.
    private let wrapper = AndroidStackView(axis: .vertical)
    private var wraps = false

    /// Android's scrollers, the outermost first; the last holds the document.
    private(set) var scrollers: [JavaObject] = []

    /// The offset the tree writes, kept for the scrollers' first layout where it comes before it
    /// (`WrittenScrollOffset`).
    private var writtenOffset = WrittenScrollOffset()

    /// The native scrollers scroll in the element's direction, not the activity's: one right to left starts at its
    /// end, one left to right at its first column.
    override var direction: LayoutDirection {
        didSet { if direction != oldValue { directScrollers() } }
    }

    private func directScrollers() {
        for scroller in scrollers {
            Java.call(scroller.reference, JavaAPI.setLayoutDirection, .int(direction == .rightToLeft ? 1 : 0))
        }
    }

    /// Cuts what it scrolls off at its edges, where every other SwiftOmniUI layout draws past them.
    override init() {
        super.init()
        Java.call(reference, JavaAPI.setClipChildren, .bool(true))
        movement.onFramesWanted = { [weak self] in self?.onFramesWanted?() }
        document.onArranged = { [weak self] in self?.pushLazyWindows() }
        build()
    }

    /// The content: one child, or several stacked down.
    @discardableResult
    override func setItems(_ items: [AndroidLayoutItem]) -> Bool {
        if items.count > 1 { wraps = true }

        var changed = false
        if wraps {
            changed = wrapper.setItems(items)
            changed = document.setItems([AndroidLayoutItem(view: wrapper)]) || changed
        } else {
            changed = document.setItems(items)
        }
        if changed { forgetMeasurements() }
        return changed
    }

    override func forgetMeasurements() {
        super.forgetMeasurements()
        document.forgetMeasurements()
        wrapper.forgetMeasurements()
    }

    /// The scroller's orientation, padding, bars, and an offset the tree moved it to.
    func apply(
        orientation: Axis, padding: EdgeInsets, verticalBar: ScrollIndicatorVisibility,
        horizontalBar: ScrollIndicatorVisibility, offset: Point?
    ) {
        if orientation != self.orientation {
            self.orientation = orientation
            build()
        }
        document.padding = padding
        document.orientation = orientation

        for scroller in scrollers {
            Java.call(scroller.reference, JavaAPI.setVerticalScrollBarEnabled, .bool(verticalBar != .hidden))
            Java.call(scroller.reference, JavaAPI.setHorizontalScrollBarEnabled, .bool(horizontalBar != .hidden))
            Java.call(
                scroller.reference, JavaAPI.setScrollbarFadingEnabled,
                .bool(verticalBar != .visible && horizontalBar != .visible))
        }

        // Design: docs/design/host/layout.md#an-offset-the-tree-writes
        if let target = writtenOffset.written(offset, standing: self.offset, orientation: orientation) {
            move(to: target)
        }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        document.contentSize(width: width)
    }

    /// Stands Android's scroller over the whole of the room, then an offset the tree wrote before there was one.
    override func arrange(width: Int32, height: Int32) {
        guard let outer = scrollers.first else { return }

        Java.call(
            outer.reference, JavaAPI.measure,
            .int(ViewConstants.spec(ViewConstants.exactly, width)),
            .int(ViewConstants.spec(ViewConstants.exactly, height)))
        Java.call(outer.reference, JavaAPI.layout, .int(0), .int(0), .int(width), .int(height))
        if let target = writtenOffset.laidOutNow() {
            move(to: target)
        }
    }

    // MARK: - The user's movement

    /// Android moved the scroller: where to, joined to the moves before it until the display's next frame.
    func scrolled() {
        guard !ProgramWrite.isWriting else { return }

        let standing = standingOffset
        guard standing != offset else { return }
        let previous = offset
        offset = standing
        movement.userMoved(from: previous, to: standing)
        pushLazyWindows()
    }

    /// Every lazy run in the document hears where the window stands: the part
    /// of its run the viewport shows, counted in the run's own room. A scroller
    /// within the document answers its own; this one pushes past none.
    private func pushLazyWindows() {
        guard let size = placedSize else { return }
        let window = Rect(
            x: offset.x, y: offset.y,
            width: Double(size.width) / density, height: Double(size.height) / density)
        tellLazy(in: document, window: window, at: Point(x: 0, y: 0))
    }

    /// The lazy runs under `layout` told their windows; `origin` is where
    /// `layout` stands in the document, each child's place counted from there.
    private func tellLazy(in layout: AndroidLayoutView, window: Rect, at origin: Point) {
        for item in layout.items {
            let frame = item.view.placedFrame
            let corner = Point(x: origin.x + frame.x, y: origin.y + frame.y)
            if let lazy = item.view as? AndroidLazyView, orientation.takes(lazy.axis) {
                let extent = lazy.axis == .vertical ? frame.height : frame.width
                var correction = 0.0
                if let origin = lazy.anchorTarget {
                    lazy.anchorTarget = nil
                    var target = offset
                    if lazy.axis == .vertical {
                        target.y = corner.y + origin
                        correction = target.y - offset.y
                    } else {
                        target.x = corner.x + origin
                        correction = target.x - offset.x
                    }
                    move(to: target)
                }
                let (low, high) = lazy.axis == .vertical
                    ? (window.y - corner.y, window.y + window.height - corner.y)
                    : (window.x - corner.x, window.x + window.width - corner.x)
                let lo = max(0, low + correction), hi = min(extent, high + correction)
                lazy.windowMoved(to: hi > lo ? lo..<hi : nil)
            }
            if let nested = item.view as? AndroidLayoutView, !(nested is AndroidScrollView) {
                tellLazy(in: nested, window: window, at: corner)
            }
        }
    }

    /// A finger took hold of the scroller, or let go of it and left it to throw on.
    override func held(_ holding: Bool) {
        if holding { movement.holdBegan() } else { movement.holdEnded(rests: false) }
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
        super.detach()
        onOffsetChanged = nil
        onScrollStopped = nil
        onFramesWanted = nil
        document.onArranged = nil
    }

    // MARK: - Android's scrollers

    /// The scroller moving down, and the one moving across; nil where the orientation has none.
    private var vertical: JavaObject? { orientation == .horizontal ? nil : scrollers.first }
    private var horizontal: JavaObject? {
        orientation == .horizontal || orientation == .both ? scrollers.last : nil
    }

    /// Where Android's scrollers stand, in points.
    private var standingOffset: Point {
        Point(
            x: horizontal.map { Double(Java.callInt($0.reference, JavaAPI.getScrollX)) / density } ?? 0,
            y: vertical.map { Double(Java.callInt($0.reference, JavaAPI.getScrollY)) / density } ?? 0)
    }

    /// Scrolls until `descendant` stands where the anchors say: fractions
    /// across and down it and the room, an absent one for "only where it is
    /// not wholly in view".
    func scroll(toDescendant descendant: AndroidView, anchorX: Double?, anchorY: Double?) {
        guard let outer = scrollers.first else { return }

        let start = Point(
            x: descendant.cornerInWindow.x - document.cornerInWindow.x,
            y: descendant.cornerInWindow.y - document.cornerInWindow.y)
        let size = Point(
            x: Double(Java.callInt(descendant.reference, JavaAPI.getWidth)) / density,
            y: Double(Java.callInt(descendant.reference, JavaAPI.getHeight)) / density)
        let room = Point(
            x: Double(Java.callInt(outer.reference, JavaAPI.getWidth)) / density,
            y: Double(Java.callInt(outer.reference, JavaAPI.getHeight)) / density)
        var place = offset

        if orientation == .horizontal || orientation == .both {
            place.x = Self.target(at: start.x, length: size.x, in: room.x, now: offset.x, anchor: anchorX)
        }
        if orientation == .vertical || orientation == .both {
            place.y = Self.target(at: start.y, length: size.y, in: room.y, now: offset.y, anchor: anchorY)
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

    /// Moves Android's scrollers to `target` as the program's write; each keeps it within what it can reach.
    private func move(to target: Point) {
        ProgramWrite.perform {
            if let vertical { Java.call(vertical.reference, JavaAPI.scrollTo, .int(0), .int(pixels(target.y))) }
            if let horizontal { Java.call(horizontal.reference, JavaAPI.scrollTo, .int(pixels(target.x)), .int(0)) }
        }
        offset = standingOffset
    }

    /// Makes the scrollers the orientation asks for, each listened to, the document in the innermost.
    private func build() {
        Java.call(reference, JavaAPI.removeAllViews)
        if let parent = Java.callObject(document.reference, JavaAPI.getParent) {
            Java.call(parent, JavaAPI.removeView, .object(document.reference))
            Java.release(local: parent)
        }

        let kinds: [Bool] = switch orientation {
        case .horizontal: [false]
        case .both: [true, false]
        default: [true]
        }
        scrollers = kinds.map { downward in
            let scroller = downward
                ? Java.new(JavaAPI.scrollView, JavaAPI.newScrollView, .object(AndroidRenderer.context))
                : Java.new(JavaAPI.horizontalScrollView, JavaAPI.newHorizontalScrollView, .object(AndroidRenderer.context))
            Java.call(
                scroller.reference, downward ? JavaAPI.setFillViewport : JavaAPI.setHorizontalFillViewport, .bool(true))
            listen(on: scroller.reference, JavaAPI.setOnScrollChangeListener, JavaAPI.setOnTouchListener)
            return scroller
        }

        for (outer, inner) in zip(scrollers, scrollers.dropFirst()) {
            Java.call(outer.reference, JavaAPI.addView, .object(inner.reference), .int(-1), .int(-1))
        }
        Java.call(scrollers.last!.reference, JavaAPI.addView, .object(document.reference), .int(-1), .int(-1))
        Java.call(reference, JavaAPI.addView, .object(scrollers[0].reference), .int(-1), .int(-1))
        directScrollers()
        offset = Point(x: 0, y: 0)
        writtenOffset = WrittenScrollOffset()
    }
}

extension AndroidScrollView: FramedScroller {}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Where an element stands, said to the tree that reads it, the same on every host.
/// Design: docs/design/host/runtime.md#where-a-view-stands
extension MountedElement {
    /// Insets reserved above this reader, measured in the same native layout as its frame.
    public func contentSafeAreaInsets(frameOf: (MountedElement) -> Rect?) -> EdgeInsets {
        return ancestorSafeAreaInsets { element, edge in
            frameOf(element).map { edge == .top || edge == .bottom ? $0.height : $0.width }
        }
    }

    /// The bars over this element, edge by edge: every `.safeAreaInset` ancestor's bar - the
    /// stack's last child, the content its first, this element's way up lying in the first -
    /// its extent on the edge's axis answered by the caller, a frame stood or a measure taken,
    /// with the stack's spacing. A bar floats over the content's whole room and adds itself to
    /// the safe area the content reads: an `ignoresSafeArea` lets the frame under it, the
    /// contribution it tells unchanged.
    public func ancestorSafeAreaInsets(extentOf: (MountedElement, Edge) -> Double?) -> EdgeInsets {
        var insets = EdgeInsets(0), child = self
        while let parent = child.parent {
            // A native scroll document has already resolved its enclosing region.
            if parent.type == .scrollView { break }
            defer { child = parent }

            guard let edge = parent.value(.safeAreaInsetEdge).flatMap(Edge.init(propValue:)) else { continue }

            let children = parent.currentChildren
            guard children.count == 2, children[0] === child,
                  children[1].value(.isVisible)?.bool != false else { continue }

            guard let extent = extentOf(children[1], edge).map({
                $0 + (parent.value(.spacing)?.number ?? 0)
            }) else { continue }

            switch edge {
            case .top: insets.top += extent
            case .bottom: insets.bottom += extent
            case .leading: insets.left += extent
            case .trailing: insets.right += extent
            }
        }
        return insets
    }

    /// Whether this element receives its position, including Text's passive
    /// origin report. Only business geometry reads set `framesRead`.
    public var readsOwnFrame: Bool {
        driven[.frame] != nil || events[.frameChanged] != nil
            || events[.namedFramesChanged] != nil || events[.textFrameChanged] != nil
    }

    /// Says where the element stands - `numbers`, a frame report's ten, and the named spaces enclosing it -
    /// where that changed since it last said: its place in its parent onto the state its frame drives, the
    /// named spaces ahead of the numbers so one pass hears them together, and the whole report to its handler.
    public func reportFrame(_ numbers: [Double], named: [NamedSpaceFrame], in runtime: HostRuntime,
                            contentInsets: EdgeInsets = EdgeInsets(0)) {
        guard readsOwnFrame else { return }
        var numbers = numbers
        if contentInsets != EdgeInsets(0), numbers.count == 10 {
            let top = max(0, numbers[7] - numbers[5]) + contentInsets.top
            let left = max(0, numbers[6] - numbers[4]) + contentInsets.left
            let bottom = max(0, numbers[5] + numbers[3] - numbers[7] - numbers[9]) + contentInsets.bottom
            let right = max(0, numbers[4] + numbers[2] - numbers[6] - numbers[8]) + contentInsets.right
            numbers[6] = numbers[4] + left
            numbers[7] = numbers[5] + top
            numbers[8] = max(0, numbers[2] - left - right)
            numbers[9] = max(0, numbers[3] - top - bottom)
        }
        if named != reportedNamedFrames {
            reportedNamedFrames = named
            if let handler = handler(.namedFramesChanged) {
                runtime.dispatch(handler, payload: [named.propValue])
            }
        }
        guard numbers != reportedFrame else { return }
        reportedFrame = numbers
        if let binding = driven[.frame] {
            runtime.report(.lanes(Array(numbers.prefix(4))), through: binding)
        }
        if let handler = handler(.frameChanged) {
            runtime.dispatch(handler, payload: [.numbers(numbers)])
        }
        if let handler = handler(.textFrameChanged) {
            runtime.dispatch(handler, payload: [.numbers(numbers)])
        }
    }

    /// Says how the typesetter laid the words out, where a handler hears it -
    /// the same report again says nothing (`TextLayoutReport` crossing
    /// `textLayoutChanged`).
    public func reportTextLayout(_ report: TextLayoutReport, in runtime: HostRuntime) {
        guard let handler = handler(.textLayoutChanged), report != reportedTextLayout else { return }
        reportedTextLayout = report
        runtime.dispatch(handler, payload: [report.propValue])
    }

    /// The named coordinate spaces enclosing this element, innermost first - each name an ancestor declared
    /// and that ancestor's frame in window coordinates, `windowRect` answering the latter the host's way.
    public func namedSpaceFrames(windowRect: (MountedElement) -> Rect?) -> [NamedSpaceFrame] {
        var frames: [NamedSpaceFrame] = []
        var element = parent
        while let ancestor = element {
            if let name = ancestor.resolvedValue(.coordinateSpaceName)?.string,
               let frame = windowRect(ancestor) {
                frames.append(NamedSpaceFrame(name: name, frame: frame))
            }
            element = ancestor.parent
        }
        return frames
    }

    /// A frame report's ten numbers for a view standing at `place` in its parent, its top left corner at `corner`
    /// in its window, and the window's content - clear of its chrome - standing at `safeArea` in the window: the
    /// place, the corner in the window, and the safe area's own frame there, whose origin measures the view's
    /// corner in safe-area space and whose size bounds the insets it leaves inside the view.
    public static func frameNumbers(place: Rect, corner: Point, safeArea: Rect) -> [Double] {
        [place.x, place.y, place.width, place.height, corner.x, corner.y,
         safeArea.x, safeArea.y, safeArea.width, safeArea.height]
    }
}

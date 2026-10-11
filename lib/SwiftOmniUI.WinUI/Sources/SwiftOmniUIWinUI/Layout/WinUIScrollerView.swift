// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// WinUI's `ScrollViewer`, which a ScrollView stands over its whole room around the document it moves.
/// Design: docs/design/platforms/winui/layout.md#scrolling
@MainActor
final class WinUIScrollerView: WinUIView {
    /// Says where the view stands after it changed, in DIPs.
    var onScrolled: ((Point) -> Void)?

    /// The next actual viewport during ViewChanging. It is not the inertia's predicted final offset.
    var nextOffset: Point?

    /// Where the view finally lands once a move - inertia's own included - is over, per ViewChanging's own word.
    var finalOffset: Point?

    /// Says the user took hold of the scroller, or let go of it.
    var onHeld: ((Bool) -> Void)?

    /// Besides `onScrolled`, what each move of the view also tells - a lazy
    /// run whose window it is. Weakly held: a dead ear hears nothing and is
    /// dropped.
    var ears: [WinUIScrollEar] = []

    init() {
        super.init { number in swiftomniui_winui_scroller_make(number) }
    }

    /// The document it moves, the ways it scrolls, and its bars.
    func set(
        content: WinUIView, orientation: Axis, verticalBar: ScrollIndicatorVisibility,
        horizontalBar: ScrollIndicatorVisibility
    ) {
        let way: Int32 = switch orientation {
        case .horizontal: 1
        case .both: 2
        case .neither: 3
        default: 0
        }
        swiftomniui_winui_scroller_set(handle, content.handle, way, Self.bar(verticalBar), Self.bar(horizontalBar))
    }

    /// Whether each axis moves at all: WinUI's own `ScrollMode` - 0 off, 1 on, 2 where the content fills the view.
    func setModes(vertical: Int32, horizontal: Int32) {
        swiftomniui_winui_scroller_modes(handle, vertical, horizontal)
    }

    private static func bar(_ visibility: ScrollIndicatorVisibility) -> Int32 {
        switch visibility {
        case .visible: 1
        case .hidden: 2
        default: 0
        }
    }

    /// Moves the view to `target` at once; the scroller says where it stands once it has moved.
    func move(to target: Point) {
        swiftomniui_winui_scroller_move(handle, target.x, target.y, false)
    }

    /// Where the view stands, and the farthest it reaches, in DIPs.
    var standing: (offset: Point, reach: Point) {
        var values = [0.0, 0.0, 0.0, 0.0]
        swiftomniui_winui_scroller_offset(handle, &values)
        return (Point(x: values[0], y: values[1]), Point(x: values[2], y: values[3]))
    }

    /// The presenter inside measures and arranges again too: it picks the anchor it holds the view by before the
    /// document moves.
    override func invalidateMeasure() {
        super.invalidateMeasure()
        swiftomniui_winui_scroller_invalidate_presenter(handle)
    }

    override func held(_ holding: Bool) {
        onHeld?(holding)
    }

    override func detach() {
        super.detach()
        onScrolled = nil
        onHeld = nil
        ears = []
    }
}

/// One that hears a scroller's moves - a lazy run listening for its window.
@MainActor
final class WinUIScrollEar {
    /// Whose ear it is; nil once that view has left.
    weak var owner: AnyObject?

    /// What the move says.
    let moved: () -> Void

    init(owner: AnyObject, moved: @escaping () -> Void) {
        self.owner = owner
        self.moved = moved
    }
}

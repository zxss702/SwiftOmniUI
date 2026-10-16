// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// Holding the hover of what a popup stands over.
///
/// SwiftUI holds a view's `onHover` state while a context menu, a popover or a picker's list stands over the pointer:
/// the pointer did not leave the view it was on, so the view is not told it did. WinUI raises `PointerExited` all the
/// same - a popup is an island of its own and takes the pointer with it - and raises no `PointerEntered` when it goes,
/// since the pointer never moved. So the exit such a popup caused is withheld while any of them stands, and the last
/// one going takes the truth again from the pointer's own place: a view the pointer is still on keeps its hover, and
/// one the pointer has left is handed the exit it was owed.
///
/// Only a view the relay told an exit is ever held, so no walk of the element tree is needed, and a popup's own
/// relatedness to what it covers is never asked.
/// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
@MainActor
enum WinUIHoverHold {
    /// A view whose exit is being withheld, and the exit itself. Weak: the rule holds a view no longer than the view
    /// stands, and a view that left the tree is let go of in `detach()`.
    private struct Held {
        weak var view: WinUIView?
        var exit: HeardInput
    }

    /// How many popups stand over the pointer of WinUI's own accord.
    private static var openPopups = 0

    /// What is being withheld, in the order it was - the pointer's place may fall on more than one.
    private static var withheld: [Held] = []

    /// Where the pointer stands in the window's content, in DIPs; nil where it stands outside the window. The
    /// relay's own answer, which a test stands aside for one of its own.
    static let livePointerPlace: (WinUIView) -> Point? = { view in
        var place = [0.0, 0.0]
        guard swiftomniui_winui_pointer_place(view.handle, &place) else { return nil }
        return Point(x: place[0], y: place[1])
    }

    /// Where the pointer stands, as the rule asks it: a seam for tests, as `Fonts.add` and `PicturePixels.read` are
    /// (`Runtime/SwiftOmniUIWinUI.swift`).
    static var pointerPlace: (WinUIView) -> Point? = livePointerPlace

    /// Whether a popup stands over the pointer - what withholds an exit.
    static var isStanding: Bool { openPopups > 0 }

    /// How many views are holding an exit - what a test reads.
    static var holding: Int { withheld.count }

    /// A popup the user sees stand over the pointer opened.
    static func began() {
        openPopups += 1
    }

    /// A popup went. With the last one, what was withheld is settled: what the popup covered is holding its hover,
    /// and what it does not cover is owed the exit it was denied.
    static func ended() {
        openPopups = max(0, openPopups - 1)
        guard openPopups == 0, !withheld.isEmpty else { return }

        let settling = withheld
        withheld.removeAll(keepingCapacity: true)
        for held in settling {
            guard let view = held.view, !view.isDetached else { continue }
            if let place = pointerPlace(view),
               swiftomniui_winui_content_reaches(view.handle, place.x, place.y) {
                continue  // the pointer is still on the view: its hover never left.
            }
            view.deliver(held.exit)
        }
    }

    /// The pointer was told to leave a view while a popup stood over it: the exit is held until the last one goes.
    static func withhold(_ exit: HeardInput, for view: WinUIView) {
        if let at = withheld.firstIndex(where: { $0.view === view }) {
            withheld[at].exit = exit
        } else {
            withheld.append(Held(view: view, exit: exit))
        }
    }

    /// The pointer came back on the view: nothing is owed it.
    static func resumed(_ view: WinUIView) {
        withheld.removeAll { $0.view === view || $0.view == nil }
    }

    /// The view left the tree: it is owed nothing, and the rule keeps no hold on it.
    static func letGo(of view: WinUIView) {
        withheld.removeAll { $0.view === view || $0.view == nil }
    }
}

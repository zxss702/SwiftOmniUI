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
/// since the pointer never moved. So the exit such a popup caused is withheld while it stands, and a popup going takes
/// the truth again from the pointer's own place: a view the pointer is still on keeps its hover, and one the pointer
/// has left is handed the exit it was owed.
///
/// What is held is the layer a popup opens above, never the popup's own: the pointer is on the popup's content, and
/// its exits are the pointer's own. What a popup holds is read from the element tree as the element its own content
/// stands in - a popover's card, which the tree keeps where the view it hangs off wrote it however WinUI islands it,
/// and a menu's entries, the slot child of the view that offers them. A view that stands in it is on the popup rather
/// than under it, so a menu's own items hear the pointer's own exits, and a popup opened from inside a card holds the
/// card's other views as well, settling them when it goes while the card still stands.
///
/// Only a view the relay told an exit is ever held, so nothing is worked out from where a popup stands; the one
/// question asked of a held exit is whether the view stands in the popups that are standing.
/// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
@MainActor
enum WinUIHoverHold {
    /// A view whose exit is being withheld, and the exit itself. Weak: the rule holds a view no longer than the view
    /// stands, and a view that left the tree is let go of in `detach()`.
    private struct Held {
        weak var view: WinUIView?
        var exit: HeardInput
    }

    /// What a popup holds of the element tree: the element its own content stands in, or nothing at all where its
    /// content is the platform's own and no element of the tree is on it.
    private enum Holds {
        case elements(MountedElement)
        case nothing
    }

    /// The elements a popup's own content stands in: the slot child the view that offers a menu keeps, and the element
    /// a popover's own card is made of - the view the tree keeps wherever the view it hangs off wrote it.
    private static let contentTypes: Set<NodeType> = [.contextMenu, .popover]

    /// The popups standing over the pointer, by the view that presents each, and what each holds of the tree. A
    /// dictionary, because a popup is told it closed in more than one way - by WinUI's own accord, and by the view
    /// leaving the tree with it - and that is still one popup gone, not two.
    private static var standing: [ObjectIdentifier: Holds] = [:]

    /// What is being withheld, in the order it was - the pointer's place may fall on more than one.
    private static var withheld: [Held] = []

    /// Where the pointer stands in the native island's content, in DIPs; nil where it stands outside that island.
    /// The relay's own answer, which a test stands aside for one of its own.
    static let livePointerPlace: (WinUIView) -> Point? = { view in
        var place = [0.0, 0.0]
        guard swiftomniui_winui_pointer_place(view.handle, &place) else { return nil }
        return Point(x: place[0], y: place[1])
    }

    /// Where the pointer stands, as the rule asks it: a seam for tests, as `Fonts.add` and `PicturePixels.read` are
    /// (`Runtime/SwiftOmniUIWinUI.swift`).
    static var pointerPlace: (WinUIView) -> Point? = livePointerPlace

    /// Whether a popup stands over the pointer - what withholds an exit.
    static var isStanding: Bool { !standing.isEmpty }

    /// How many views are holding an exit - what a test reads.
    static var holding: Int { withheld.count }

    /// A popup the user sees stand over the pointer opened, presented by `view`: what it holds of the tree is read
    /// then, since its own content is what it holds for as long as it stands.
    static func began(_ view: WinUIView) {
        standing[ObjectIdentifier(view)] = holds(of: view)
    }

    /// What `view`'s popup holds: the element its own content stands in, read from the element tree - a popover
    /// view's own element, or the popup slot child the view that presents the popup keeps - and nothing where the
    /// popup holds no element of the tree, its content being the platform's own.
    private static func holds(of view: WinUIView) -> Holds {
        guard let element = view.sourceElement else { return .nothing }
        if contentTypes.contains(element.type) { return .elements(element) }
        return element.children.first { contentTypes.contains($0.type) }.map(Holds.elements) ?? .nothing
    }

    /// `view`'s popup went - by WinUI's own accord, by the host taking it away, or with the view leaving the tree.
    /// What it stood over is settled there and then, since the pointer's own place answers for it again: a nested
    /// popup going settles what it stood over inside the card, and leaves what the card itself stands over to the
    /// card's own going.
    static func ended(_ view: WinUIView) {
        guard standing.removeValue(forKey: ObjectIdentifier(view)) != nil else { return }
        settle()
    }

    /// Whether a popup stands over the view - one the view does not stand in. A view that stands in a popup's own
    /// content is on the popup, where the pointer is and its exits are the pointer's own; every other view of the tree
    /// is below it, and a popup holding no element of the tree holds nothing of it, so it stands over all of it.
    /// Walked up the element tree from the view's own element, which a popup the view itself presents is not in.
    static func standsOver(_ view: WinUIView) -> Bool {
        guard !standing.isEmpty else { return false }
        var left: Set<ObjectIdentifier> = []
        for each in standing.values {
            guard case .elements(let element) = each else { return true }
            left.insert(ObjectIdentifier(element))
        }
        var element = view.sourceElement
        while let each = element, !left.isEmpty {
            left.remove(ObjectIdentifier(each))
            element = each.parent
        }
        return !left.isEmpty
    }

    /// What no standing popup stands over is settled against the pointer's own place; what one still stands over
    /// waits for its going.
    private static func settle() {
        guard !withheld.isEmpty else { return }
        var kept: [Held] = []
        kept.reserveCapacity(withheld.count)
        for held in withheld {
            guard let view = held.view, !view.isDetached else { continue }
            if standsOver(view) {
                kept.append(held)
                continue
            }
            if let place = pointerPlace(view),
               swiftomniui_winui_content_reaches(view.handle, place.x, place.y) {
                continue  // the pointer is still on the view: its hover never left.
            }
            view.deliver(held.exit)
        }
        withheld = kept
    }

    /// The pointer was told to leave a view while a popup stood over it: the exit is held until no popup stands over
    /// it any more.
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

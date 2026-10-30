// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWeb

/// A drag between views, in Swift's words: what an element offers and takes, and what its drag listener heard -
/// this boundary's `HeardInput` knows no drag between views, so its kinds stand as `DragHeard`.
/// Design: docs/design/platforms/web/input.md#a-drag-between-views
extension WebRelay {
    /// What a view offers and takes of a drag: whether a drag of it carries words, whether it takes words dropped
    /// on it, and whether it takes files dropped on it from the system.
    struct DragOffer: Equatable {
        /// The words a drag of the view carries; empty where it carries none.
        var words = ""

        /// Whether the view can be dragged at all.
        var draggable = false

        /// Whether the view takes words dropped on it.
        var takesWords = false

        /// Whether the view takes files dropped on it.
        var takesFiles = false

        /// Neither dragged nor taking drops.
        static let none = DragOffer()
    }

    /// The element `element`'s drag carries `offered`'s words, and it takes drops as `offered` says; `listener`
    /// hears it.
    static func offerDrag(_ element: Int32, _ offered: DragOffer, _ listener: Int32) {
        utf8(offered.words) {
            swiftomniui_web_offer_drag(
                element, $0, $1, offered.draggable ? 1 : 0, offered.takesWords ? 1 : 0, offered.takesFiles ? 1 : 0,
                listener)
        }
    }

    /// What a drag listener heard - each kind the relay tells.
    enum DragHeard {
        /// A drag of the view between views started.
        case started

        /// A drag of the view between views ended, wherever it ended.
        case ended

        /// A drag between views is over the view.
        case over

        /// A drag between views went away from the view without being let go.
        case left

        /// A drag between views was let go over the view, carrying these words.
        case dropped(String)

        /// Files the user dragged from the system were let go over the view, each its number and its name.
        case files([(number: Int32, name: String)])
    }

    /// What the drag listener being heard heard.
    static var dragHeard: DragHeard? {
        switch Int(swiftomniui_web_event_number(0)) {
        case 0: .started
        case 1: .ended
        case 2: .over
        case 3: .left
        case 4: .dropped(copyRead(length: swiftomniui_web_drag_words()))
        case 5: .files(files(in: copyRead(length: swiftomniui_web_drag_words())))
        default: nil
        }
    }
}

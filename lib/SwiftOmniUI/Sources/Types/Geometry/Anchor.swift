// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A reference to a view's frame, resolved later against a `GeometryProxy`'s
/// coordinate space - as `.anchorPreference` produces one and
/// `proxy[anchor]` reads it.
///
///     .anchorPreference(key: LayoutKey.self, value: .bounds) { bounds in
///         [MarkdownLayout(blockId: id, bounds: bounds)]
///     }
///
///     GeometryReader { proxy in
///         … proxy[layout.bounds] …
///     }
///
/// The anchor reads nothing until a proxy answers it: what it holds is which
/// element's frame it is and the last frame the host reported for it.
public struct Anchor<Value>: Sendable {
    /// The frame source the anchor watches.
    let box: AnchorBox

    /// How the watched frame becomes `Value`, given the resolving view's own
    /// frame in window coordinates.
    let read: @Sendable (Rect, Rect) -> Value

    /// An anchor over `box` reading through `read`.
    init(box: AnchorBox, read: @escaping @Sendable (Rect, Rect) -> Value) {
        self.box = box
        self.read = read
    }
}

extension Anchor: Equatable {
    /// Two anchors agree when they watch the same element.
    public static func == (one: Anchor, other: Anchor) -> Bool {
        one.box.identity == other.box.identity
    }
}

/// Which part of a view an anchor watches - `.bounds` today, as SwiftUI
/// spells the kind of source.
public struct AnchorSource<Value>: Sendable {
    /// The source kind.
    let kind: Kind

    enum Kind {
        /// The view's whole frame.
        case bounds
    }
}

extension AnchorSource where Value == Rect {
    /// The view's bounds, resolved by a `GeometryProxy` into its own space.
    public static var bounds: AnchorSource<Rect> { AnchorSource(kind: .bounds) }
}

/// The element frame an `Anchor` watches, written by the `frameChanged` event
/// the anchor's modifier hears; `@unchecked Sendable` as every write and read
/// happens on the render's own thread.
final class AnchorBox: @unchecked Sendable {
    private final class Storage {
        var frame: Rect?
        var document: FrameReport.Document?
    }
    private var storage = Storage()

    var identity: ObjectIdentifier { ObjectIdentifier(storage) }

    /// The last frame the host reported, in window coordinates.
    var frame: Rect? {
        get { storage.frame }
        set { storage.frame = newValue; storage.document = nil }
    }

    func update(_ report: FrameReport) {
        storage.frame = report.global
        storage.document = report.document
    }

    func resolve<Value>(against report: FrameReport, read: (Rect, Rect) -> Value) -> Value {
        if let source = storage.document, let target = report.document, source.identity == target.identity {
            return read(source.frame, target.frame)
        }
        return read(storage.frame ?? Rect(0, 0, 0, 0), report.global)
    }

    /// Rebuilding a value does not recreate its mounted element. Both old
    /// preference values and the new frame handler must watch that same frame.
    func inherit(from other: AnchorBox) { storage = other.storage }
}

extension GeometryProxy {
    /// The anchored view's frame in this proxy's coordinate space, or zero
    /// where the host has reported none yet.
    public subscript<Value>(anchor: Anchor<Value>) -> Value {
        anchor.box.resolve(against: report, read: anchor.read)
    }
}

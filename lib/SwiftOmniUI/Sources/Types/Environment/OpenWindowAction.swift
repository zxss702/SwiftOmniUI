// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What opens the application's other windows: the `WindowGroup`s its scenes
/// declare, by the type they were declared under or by the value one stands
/// for.
///
///     @Environment(\.openWindow) private var openWindow
///
///     Button("Settings") { openWindow(id: "setting") }
///     Button("Open") { openWindow(value: folder.url) }
///
/// A `value:` call finds the group declared for the value's own type. Asking
/// outside every scene, or for what no group declares, opens nothing.
public struct OpenWindowAction: Sendable {
    /// The scene's window opening, bridged to calls: the group's kind, the
    /// value's own type, the value, and the value written down.
    private let open: @Sendable (WindowType, Any.Type?, AnyHashable?, String?) -> Void

    /// Which group's `type` opens windows for a value of the type asked, where
    /// one is declared for it.
    private let groupFor: @Sendable (Any.Type) -> WindowType?

    /// An action bridged to `record`'s scene.
    init(record: SceneRecord) {
        open = { type, valueType, value, text in
            do {
                try record.open(type, valueType: valueType, value: value, text: text)
            } catch {
                reportFailure("@Environment(\\.openWindow) could not open \(type): \(error).")
            }
        }
        groupFor = { valueType in
            record.declared.first(where: { $0.value.valueType == valueType })?.key
        }
    }

    /// An action bridged to a scene through an `open`/`groupFor` pair - for a
    /// `.environment(\.openWindow, ...)` of the application's own.
    init(
        open: @escaping @Sendable (WindowType, Any.Type?, AnyHashable?, String?) -> Void,
        groupFor: @escaping @Sendable (Any.Type) -> WindowType?
    ) {
        self.open = open
        self.groupFor = groupFor
    }

    /// An action with no scene behind it opens nothing.
    static let nowhere = OpenWindowAction(
        open: { _, _, _, _ in },
        groupFor: { _ in nil })

    /// Opens a window of the group declared under `id`.
    public func callAsFunction(id: String) {
        open(WindowType(id), nil, nil, nil)
    }

    /// Opens a window of the group declared under `id`, standing for `value`.
    public func callAsFunction<Value: Codable & Hashable>(id: String, value: Value) {
        open(WindowType(id), Value.self, AnyHashable(value), (try? ValueText.write(value)))
    }

    /// Opens a window of the group declared for `value`'s own type.
    public func callAsFunction<Value: Codable & Hashable>(value: Value) {
        guard let type = groupFor(Value.self) else {
            return
        }
        open(type, Value.self, AnyHashable(value), (try? ValueText.write(value)))
    }
}

/// `\.openWindow` reads an `OpenWindowAction`.
struct OpenWindowActionKey: EnvironmentKey {
    static let defaultValue = OpenWindowAction.nowhere
}

extension EnvironmentValues {
    /// The window opening of the scene the view stands in.
    public var openWindow: OpenWindowAction {
        get { self[OpenWindowActionKey.self] }
        set { self[OpenWindowActionKey.self] = newValue }
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Closes a named window, or windows for a value, independently of navigation.
public struct DismissWindowAction: Sendable {
    private let dismiss: @Sendable (WindowType?, Any.Type?, AnyHashable?) -> Void

    init(record: SceneRecord) {
        dismiss = { type, valueType, value in
            record.dismissWindows(type: type, valueType: valueType, value: value)
        }
    }

    private init() { dismiss = { _, _, _ in } }
    static let nowhere = DismissWindowAction()

    /// Closes windows declared under `id`.
    public func callAsFunction(id: String) {
        dismiss(WindowType(id), nil, nil)
    }

    /// Closes windows in the named group for this value.
    public func callAsFunction<Value: Codable & Hashable>(id: String, value: Value) {
        dismiss(WindowType(id), Value.self, AnyHashable(value))
    }

    /// Closes windows whose group and value match the supplied value.
    public func callAsFunction<Value: Codable & Hashable>(value: Value) {
        dismiss(nil, Value.self, AnyHashable(value))
    }
}

struct DismissWindowActionKey: EnvironmentKey {
    static let defaultValue = DismissWindowAction.nowhere
}

extension EnvironmentValues {
    /// The window dismissal action of the scene holding this view.
    public var dismissWindow: DismissWindowAction {
        get { self[DismissWindowActionKey.self] }
        set { self[DismissWindowActionKey.self] = newValue }
    }
}

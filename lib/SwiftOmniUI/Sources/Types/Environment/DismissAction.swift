// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What dismisses the presentation a view stands in: a sheet's or popover's
/// own closer, a pushed navigation page's way back down the stack, or the
/// window holding a root view.
///
///     @Environment(\.dismiss) private var dismiss
///
///     Button("Done") { dismiss() }
///
/// Where no presentation or window holds the view, the call does nothing but say so.
public struct DismissAction: Sendable {
    /// The closer the nearest presentation wired for itself.
    private let act: @Sendable @MainActor () -> Void

    /// An action that does its work when called.
    init(_ act: @escaping @Sendable @MainActor () -> Void) {
        self.act = act
    }

    /// Runs the dismissal.
    @MainActor public func callAsFunction() {
        act()
    }
}

/// `\.dismiss` reads a `DismissAction`.
struct DismissActionKey: EnvironmentKey {
    static let defaultValue = DismissAction {}
}

extension EnvironmentValues {
    /// The dismissal of the nearest presentation the view stands in.
    public var dismiss: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}

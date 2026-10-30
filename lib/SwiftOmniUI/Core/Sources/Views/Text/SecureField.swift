// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A text field whose text is hidden behind the platform's secure-entry
/// marks - a `TextField` marked `isPassword`, given SwiftUI's name for one.
///
///     @State private var apiKey = ""
///
///     SecureField("Paste the key here", text: $apiKey)
///
/// Every `TextField` modifier applies to it - it is one wearing a flag -
/// through the modifiers `View` gives every view; the field's own set is
/// reached through `TextField` itself where `Style<TextField>` needs it.
public struct SecureField: View {
    /// The field, captioned and marked.
    let field: TextField

    /// A secure field captioned `title` while it is empty, two-way on `text`.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        field = TextField(title, text: text).isPassword(true)
    }

    /// The same, its caption looked up.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        field = TextField(titleKey, text: text).isPassword(true)
    }

    /// The field, captioned and marked.
    public var body: some View { field }
}

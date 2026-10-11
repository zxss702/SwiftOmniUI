// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `SearchField`'s own properties, shared by the control and its
/// `Style<SearchField>`.
public protocol SearchFieldProperties: PropertyContainer {}

/// A text field for what to search for, shown as the platform's search field.
///
///     SearchField($query)
///         .placeholder("Search the list")
///         `.onSubmit` { runTheSearch() }
///
/// A TextField that says what it is for: the platform draws the magnifier and the
/// cancel button, and the keyboard's return key searches.
///
/// It goes wherever a view goes - in the page's content, or ON the navigation
/// bar as that page's `titleView`, which is what an application
/// writes when it wants the bar to do the searching.
///
/// Given a binding the field shows the value and writes every edit back; given a
/// plain string it shows that, and `.onTextChanged` is how what is typed gets
/// anywhere.
public struct SearchField: InputView, TextElement, FontElement, TextAlignmentElement, TintElement,
    SearchFieldProperties
{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<SearchField>` is written against.
    public init() {
        node = Node(contract: SearchFieldContract.self)
    }

    /// A search box showing `text`. One-way: what is typed goes nowhere without
    /// `.onTextChanged`.
    public init(_ text: String) {
        node = Node(contract: SearchFieldContract.self)
        node.write(TextElementContract.text, text)
    }

    /// Two-way: shows what the binding holds, and writes back what is typed.
    public init(_ text: Binding<String>) {
        self = SearchField().text(text)
    }

    /// A search box captioned `title` while it is empty, two-way on `text` -
    /// the SwiftUI spelling of `SearchField(text).placeholder(title)`.
    ///
    ///     SearchField("Search", text: $query)
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self = SearchField(text).placeholder(String(title))
    }

    /// The same, its caption looked up - `SearchField("Search", text: $query)`
    /// looks "Search" up, as SwiftUI's does.
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self = SearchField(text).placeholder(titleKey)
    }

    /// The same two-way text as `SearchField($text)`, written as a modifier.
    /// Design: docs/design/views/bindings.md#two-way-controls
    @_spi(Host) public func text(_ value: Binding<String>) -> Modified {
        value.image == nil
            ? described(TextElementContract.text.token, value, on: .textChanged)
            : words(TextElementContract.text.token, by: value, mode: .inOut)
    }

    // MARK: Events

    /// Fires when the search is submitted - the return key, or the magnifier
    /// where a platform draws a button.
    public func onSubmit(_ handler: @escaping EventHandler) -> Self {
        onEvent(SearchFieldContract.submitted, handler)
    }
}

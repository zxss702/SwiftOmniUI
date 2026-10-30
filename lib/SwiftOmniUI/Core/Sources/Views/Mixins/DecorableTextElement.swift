// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A line under the text, through it, or both - worn by `Text` and
/// `TextSpan`.
@preconcurrency @MainActor public protocol DecorableTextElement: PropertyContainer {}

extension DecorableTextElement {
    /// A line under the text, through it, or both.
    ///
    ///     Text("Sold out").textDecorations(.strikethrough)
    @_spi(Host) public func textDecorations(_ value: TextDecorations) -> Modified {
        setValue(DecorableTextElementContract.textDecorations, value)
    }

    /// A line under the text - the SwiftUI spelling.
    ///
    ///     Text("Read more").underline()
    public func underline(_ isActive: Bool = true) -> Modified {
        var worn = node.props[.textDecorations].flatMap(TextDecorations.init(propValue:)) ?? .none
        if isActive { worn.insert(.underline) } else { worn.remove(.underline) }
        return textDecorations(worn)
    }

    /// A line through the text - the SwiftUI spelling.
    public func strikethrough(_ isActive: Bool = true) -> Modified {
        var worn = node.props[.textDecorations].flatMap(TextDecorations.init(propValue:)) ?? .none
        if isActive { worn.insert(.strikethrough) } else { worn.remove(.strikethrough) }
        return textDecorations(worn)
    }
}

extension DecorableTextElement where Self: VisualElement {
    /// `textDecorations` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func textDecorations(_ state: Binding<TextDecorations>) -> Modified {
        plain(DecorableTextElementContract.textDecorations, by: state)
    }

}

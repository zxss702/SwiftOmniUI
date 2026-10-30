// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The height of a text line, relative to the font's own - worn by `Text`
/// and `TextSpan`.
@preconcurrency @MainActor public protocol LineHeightElement: PropertyContainer {}

extension LineHeightElement {
    /// The height of a line, as a MULTIPLE of the font's own - 1.5 for half
    /// again. Said nothing about, the font's own height stands.
    @_spi(Host) public func lineHeight(_ value: Double) -> Modified {
        setValue(LineHeightElementContract.lineHeight, value)
    }

    /// Extra space between every pair of lines, in device units - the SwiftUI
    /// spelling.
    ///
    ///     Text(lyrics).lineSpacing(8)
    public func lineSpacing(_ value: Double) -> Modified {
        setValue(LineHeightElementContract.lineSpacing, value)
    }
}

extension LineHeightElement where Self: VisualElement {
    /// `lineHeight` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    public func lineHeight(_ state: Binding<Double>) -> Modified {
        plain(LineHeightElementContract.lineHeight, by: state)
    }

    /// `lineSpacing` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func lineSpacing(_ state: Binding<Double>) -> Modified {
        plain(LineHeightElementContract.lineSpacing, by: state)
    }
}

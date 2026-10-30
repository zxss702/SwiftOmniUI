// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The space a control keeps inside itself, around its content: worn by
/// every layout, and by the controls that pad their content - Text, Button
/// and ScrollView among them.
@preconcurrency @MainActor public protocol PaddingElement: VisualElementProperties {}

extension PaddingElement {
    /// The space kept inside the view, between its edge and its content.
    /// Margin is the space outside.
    ///
    ///     VStack { … }.contentPadding(24)
    @_spi(Host) public func contentPadding(_ value: EdgeInsets) -> Modified { setValue(PaddingElementContract.contentPadding, value) }

    /// Left and right, then top and bottom.
    @_spi(Host) public func contentPadding(_ horizontalSize: Double, _ verticalSize: Double) -> Modified {
        contentPadding(EdgeInsets(horizontalSize, verticalSize))
    }

    /// Each side in turn: left, top, right, bottom.
    @_spi(Host) public func contentPadding(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> Modified {
        contentPadding(EdgeInsets(left, top, right, bottom))
    }
}

extension PaddingElement where Self: VisualElement {
    /// `padding` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func contentPadding(_ state: Binding<EdgeInsets>) -> Modified {
        journey(PaddingElementContract.contentPadding, by: state)
    }
}

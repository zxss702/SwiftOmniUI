// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The button that shows its scene's inspector and hides it again, for
/// anywhere a view goes - a window's title bar, or a page of its own. See
/// `Inspector`.
///
///     TitleBar().trailingContent { InspectorButton() }
public struct InspectorButton: View {
    /// The scene the button is in, whose inspector it shows.
    @Environment private var scene: SceneSession

    /// The button.
    public init() {}

    /// The button, as a view.
        public var body: some View { AnyView(content) }

        private var content: any View {
        Button("ⓘ")
            .fontSize(16)
            .foregroundStyle(Look.subtle)
            .background(.transparent)
            .contentPadding(10, 2)
            .onClicked { Inspector.toggle(in: scene) }
            .accessibilityIdentifier("swiftomniui.inspector")
            .accessibilityLabel("Inspector")
    }
}

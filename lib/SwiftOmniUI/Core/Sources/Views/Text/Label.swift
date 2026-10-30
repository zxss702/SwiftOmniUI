// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// An icon beside its words - `Label("Star", systemImage: "star")`.
///
/// The icon is a platform symbol or a picture's file; the words any title a
/// row would carry. Drawn as the platform draws a labeled icon, which is why
/// it is one view and not an `HStack`: on a phone the icon leads, inside a
/// menu the title may lead and the icon sit where the platform puts one.
///
///     Label("Star", systemImage: "star")
///     Label("Done") { Image("check.png") }
///
/// `.labelsHidden` shows the icon alone where the context asks for it - a
/// toolbar button whose title is still its accessibility label.
public struct Label: View {
    /// The words.
    let title: any View

    /// The picture - a symbol or a file, or `EmptyView` for a title-only one.
    let icon: any View

    /// The title's key and fallback text, where the label was made from one -
    /// what `.tabItem` names a page's item with.
    private var titleText: (key: LocalizedStringKey, display: String)? = nil

    /// The icon as a source, where the label was made from one - a custom
    /// `icon:` view draws in the label but names no item.
    private var iconSource: ImageSource? = nil

    /// The caption and picture `.tabItem` reads, where the label's own
    /// initializers carried them.
    var semanticParts: (title: (key: LocalizedStringKey, display: String)?, icon: ImageSource?) {
        (titleText, iconSource)
    }

    /// Which halves draw - `.labelsHidden` above writes it.
    @Environment private var style: LabelStyle

    /// A label with its title made by the closure and no icon.
    public init(@ViewBuilder title: () -> any View) {
        self.title = title()
        self.icon = EmptyView()
    }

    /// A label with its title and icon made by the closures.
    public init(@ViewBuilder title: () -> any View, @ViewBuilder icon: () -> any View) {
        self.title = title()
        self.icon = icon()
    }

    /// A label with its words and a platform symbol - SwiftUI's
    /// `Label("Star", systemImage: "star")`.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage: String) {
        self.init(title: { Text(title) }, icon: { Image(systemName: systemImage) })
        titleText = (LocalizedStringKey(pattern: String(title)), String(title))
        iconSource = .symbol(systemImage)
    }

    /// A label with its words looked up and a platform symbol.
    public init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.init(title: { Text(titleKey) }, icon: { Image(systemName: systemImage) })
        titleText = (titleKey, titleKey.displayString)
        iconSource = .symbol(systemImage)
    }

    /// A label with its words and a picture's file.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, image: ImageSource) {
        self.init(title: { Text(title) }, icon: { Image(image) })
        titleText = (LocalizedStringKey(pattern: String(title)), String(title))
        iconSource = image
    }

    /// A label with its words looked up and a picture's file.
    public init(_ titleKey: LocalizedStringKey, image: ImageSource) {
        self.init(title: { Text(titleKey) }, icon: { Image(image) })
        titleText = (titleKey, titleKey.displayString)
        iconSource = image
    }

    /// The row itself. A label with no icon shows its title whatever the
    /// style asks: `.iconOnly` hides words beside a picture, never the label.
    public var body: some View {
        let hasIcon = !(icon is EmptyView)
        return HStack {
            if style.showsIcon { icon }
            if style.showsTitle || !hasIcon { title }
        }
        .spacing(6)
    }
}

/// How every `Label` in a branch draws - its icon beside its title, the icon
/// alone, or the title alone:
///
///     SettingsPane().labelStyle(.iconOnly)
///
/// Written on a view above the labels it shapes; the nearest one wins.
public final class LabelStyle: @unchecked Sendable {
    /// Icon beside the title - the default.
    public static let titleAndIcon = LabelStyle(icon: true, title: true)

    /// The icon alone, the title kept for accessibility - what
    /// `.labelsHidden` writes.
    public static let iconOnly = LabelStyle(icon: true, title: false)

    /// The title alone.
    public static let titleOnly = LabelStyle(icon: false, title: true)

    /// Whether the icon half draws.
    let showsIcon: Bool

    /// Whether the title half draws.
    let showsTitle: Bool

    private init(icon: Bool, title: Bool) {
        self.showsIcon = icon
        self.showsTitle = title
    }
}

extension View {
    /// How every `Label` in this branch arranges its icon against its words:
    ///
    ///     ToolbarRow().labelStyle(.iconOnly)
    public func labelStyle(_ style: LabelStyle) -> ModifiedContent {
        environment(style)
    }

    /// Shows only the icon of every `Label` in this branch - the title stays
    /// its accessibility label.
    public func labelsHidden() -> ModifiedContent {
        labelStyle(.iconOnly)
    }
}

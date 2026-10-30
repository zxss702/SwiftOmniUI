// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A named group of views under a header and over a footer - SwiftUI's
/// `Section`:
///
///     Section {
///         Text("One")
///         Text("Two")
///     } header: {
///         Text("First")
///     } footer: {
///         Text("End of first")
///     }
///
/// Inside a `List` a section is a group the host draws with its own chrome;
/// anywhere else it stands its views in a column - header, content, footer.
public struct Section<Parent: View, Content: View, Footer: View>: View {
    /// What stands before the group's views.
    private let header: Parent

    /// The group's views.
    private let content: Content

    /// What stands after the group's views.
    private let footer: Footer

    /// A section of `content` under `header` and over `footer`.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    /// The group as a column: header, content, footer.
    public var body: some View {
        VStack(alignment: .leading) {
            header
            content
            footer
        }
    }
}

extension Section where Parent == EmptyView {
    /// A section of `content` over `footer`, with no header.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        header = EmptyView()
        self.content = content()
        self.footer = footer()
    }
}

extension Section where Footer == EmptyView {
    /// A section of `content` under `header`, with no footer.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.header = header()
        self.content = content()
        footer = EmptyView()
    }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    /// A section of `content` alone.
    public init(@ViewBuilder content: () -> Content) {
        header = EmptyView()
        self.content = content()
        footer = EmptyView()
    }
}

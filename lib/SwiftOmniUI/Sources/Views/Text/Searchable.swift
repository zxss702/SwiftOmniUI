// SPDX-FileCopyrightText: 2026 Zhiyang and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Preferred location of the search field installed by `searchable`.
/// Desktop hosts put automatic searches in the page's native toolbar.
public struct SearchFieldPlacement: Equatable, Sendable {
    public static let automatic = SearchFieldPlacement()
    public static let toolbar = SearchFieldPlacement()
    private init() {}
}

extension View {
    /// Adds a two-way search field to this page's toolbar. GTK realizes it
    /// as GtkSearchEntry; WinUI uses AutoSuggestBox, including native clear
    /// and keyboard handling. The binding belongs to the modified page.
    public func searchable(
        text: Binding<String>, placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey = "Search"
    ) -> ModifiedContent {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                SearchField(prompt, text: text).frame(width: 240)
            }.id("SwiftOmniUI.search")
        }
    }
}

// SPDX-FileCopyrightText: 2026 Zhiyang and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Preferred location of the search field installed by `searchable`.
/// Desktop hosts put automatic searches in the page's native toolbar.
public struct SearchFieldPlacement: Equatable, Sendable {
    public static let automatic = SearchFieldPlacement()
    public static let toolbar = SearchFieldPlacement()
    private init() {}
}

/// Submission kinds supported by searchable desktop content.
public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let search = SubmitTriggers(rawValue: 1 << 1)
}

private struct SearchSubmitKey: EnvironmentKey {
    static var defaultValue: EventHandler? { nil }
}

extension EnvironmentValues {
    fileprivate var searchSubmit: EventHandler? {
        get { self[SearchSubmitKey.self] }
        set { self[SearchSubmitKey.self] = newValue }
    }
}

private struct SearchableContent<Content: View>: View {
    let content: Content
    let text: Binding<String>
    let prompt: LocalizedStringKey
    @Environment(\.searchSubmit) private var submit

    init(content: Content, text: Binding<String>, prompt: LocalizedStringKey) {
        self.content = content
        self.text = text
        self.prompt = prompt
    }

    var body: some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                SearchField(prompt, text: text)
                    .onSubmit { if let submit { try await submit() } }
                    .frame(width: 240)
            }.id("SwiftOmniUI.search")
        }
    }
}

extension View {
    /// Adds a two-way search field to this page's toolbar. GTK realizes it
    /// as GtkSearchEntry; WinUI uses AutoSuggestBox, including native clear
    /// and keyboard handling. The binding belongs to the modified page.
    public func searchable(
        text: Binding<String>, placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey = "Search"
    ) -> some View {
        SearchableContent(content: self, text: text, prompt: prompt)
    }

    /// Handles Return/search-glyph submission from the enclosed searchable
    /// field. Typing continues to update its binding independently.
    public func onSubmit(of triggers: SubmitTriggers, _ action: @escaping EventHandler) -> ModifiedContent {
        environment(\.searchSubmit, triggers.contains(.search) ? action : nil)
    }
}

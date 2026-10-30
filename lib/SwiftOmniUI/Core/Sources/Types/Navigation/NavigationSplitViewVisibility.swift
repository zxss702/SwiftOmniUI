// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0
//
// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Which of a `NavigationSplitView`'s columns show - as SwiftUI's
/// `NavigationSplitViewVisibility` names them:
///
///     @State private var columns: NavigationSplitViewVisibility = .automatic
///
///     NavigationSplitView(columnVisibility: $columns) {
///         SidebarView()
///     } content: {
///         ContentView()
///     } detail: {
///         DetailView()
///     }
public enum NavigationSplitViewVisibility: Int32, Sendable, HostRepresentable {
    /// The platform decides which columns show - the default.
    case automatic = 0

    /// The detail column alone shows.
    case detailOnly = 1

    /// Two columns show: the content and the detail of a three-column split,
    /// the sidebar and the detail of a two-column one.
    case doubleColumn = 2

    /// Every column shows.
    case all = 3

    /// The member `value` names, or nil for a number it names none of - the
    /// event's answer.
    init?(_ value: PropValue?) {
        guard let value else { return nil }
        self.init(propValue: value)
    }
}

extension NavigationSplitViewVisibility: StateChoice {}

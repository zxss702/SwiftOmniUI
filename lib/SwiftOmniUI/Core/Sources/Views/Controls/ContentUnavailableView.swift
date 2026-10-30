// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What stands where content would, while there is none - a symbol, a title,
/// and where they say more, a description and actions:
///
///     ContentUnavailableView("No Notes", systemImage: "note.text")
///
///     ContentUnavailableView {
///         Label("No Selection", systemImage: "cursorarrow.rays")
///     } description: {
///         Text("Pick a note from the list.")
///     } actions: {
///         Button("New Note") { create() }
///     }
///
/// The label and description a builder makes keep their own styling; the
/// `title:systemImage:` form draws them as SwiftUI does - a large grayed
/// label over smaller grayed words.
public struct ContentUnavailableView: View {
    /// The title and symbol.
    let label: any View

    /// What the empty state says beyond the title.
    let description: any View

    /// What the empty state offers to do.
    let actions: any View

    /// A label alone.
    public init(@ViewBuilder label: () -> any View) {
        self.init(label: label, description: { EmptyView() }, actions: { EmptyView() })
    }

    /// A label and the words under it.
    public init(
        @ViewBuilder label: () -> any View,
        @ViewBuilder description: () -> any View
    ) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }

    /// The whole form - a label, a description, and what the state offers.
    public init(
        @ViewBuilder label: () -> any View,
        @ViewBuilder description: () -> any View,
        @ViewBuilder actions: () -> any View
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    /// The common form - a title and a system symbol.
    public init(_ title: String, systemImage: String) {
        self.init(
            label: {
                VStack {
                    Image(systemName: systemImage)
                        .tint(.secondary)
                    Text(title)
                        .font(.title2)
                }
            },
            description: { EmptyView() },
            actions: { EmptyView() })
    }

    /// The common form - a title, a system symbol, and the words under it.
    public init(_ title: String, systemImage: String, description: String) {
        self.init(
            label: {
                VStack {
                    Image(systemName: systemImage)
                        .tint(.secondary)
                    Text(title)
                        .font(.title2)
                }
            },
            description: {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            },
            actions: { EmptyView() })
    }

    /// The empty state as a padded column: label, description, actions.
    public var body: some View {
        VStack {
            label
            description
            actions
        }
        .padding(24)
    }
}

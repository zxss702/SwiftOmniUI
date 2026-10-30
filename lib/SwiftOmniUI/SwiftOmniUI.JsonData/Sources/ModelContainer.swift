// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Re-exported: this module IS JsonData's bridge to SwiftOmniUI, so the model
// layer's types - `@Model`, `ModelContext`, `ModelContainer` - arrive with
// it, as `import SwiftData` does under SwiftUI.
@_exported import JsonData
import SwiftOmniUICore

// The model context in the environment, as SwiftData hands it down in SwiftUI:
// `.modelContainer(...)` above, `@Environment(\.modelContext)` and `@Query`
// below. The types are whichever `JsonData` exports - SwiftData's where the
// platform has it, JsonDataCore's elsewhere.

/// The `\.modelContext` slot: the nearest container's main context.
private struct ModelContextKey: EnvironmentKey {
    /// An empty-schema in-memory context. A key-path WRITE materializes the
    /// property through its getter before the setter runs, so a fatal default
    /// would crash `.environment(\.modelContext, _)` on write rather than
    /// only reporting a bare read. A scratch context keeps the write working;
    /// a read where no container was written answers a store holding nothing.
    static var defaultValue: ModelContext { Scratch.context }
}

/// The store `\.modelContext` answers where nothing wrote one - an
/// in-memory container over an empty schema, made once on first read.
private enum Scratch {
    /// The context in a box so the shared `let` is `Sendable`: the context
    /// is only ever touched on the UI thread it was made on.
    private final class Context: @unchecked Sendable {
        let context: ModelContext
        init(_ context: ModelContext) { self.context = context }
    }

    private static let box = Context(
        // Reads happen on the UI thread, which is the main actor for every
        // host - the same hop `contextOnMain` performs.
        MainActor.assumeIsolated {
            OnMain(value: try! ModelContainer(
                for: Schema([]),
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]).mainContext)
        }.value)

    static var context: ModelContext { box.context }
}

extension EnvironmentValues {
    /// The model context views beneath read and `@Query` fetches through.
    public var modelContext: ModelContext {
        get { self[ModelContextKey.self] }
        set { self[ModelContextKey.self] = newValue }
    }
}

/// Carries a value out of `MainActor.assumeIsolated`, whose result must be
/// `Sendable` though the value read here never leaves the UI thread it was
/// read on.
private struct OnMain<T>: @unchecked Sendable {
    let value: T
}

extension ModelContainer {
    /// `mainContext`, read where the caller already stands on the UI thread -
    /// the main actor for every host. JsonDataCore's is a plain `let`;
    /// SwiftData's is main-actor-isolated, which is the hop this performs.
    var contextOnMain: ModelContext {
        MainActor.assumeIsolated { OnMain(value: mainContext) }.value
    }
}

extension View {
    /// Hands `container`'s main context to the views beneath, as the
    /// `\.modelContext` value and as an object `@Environment(ModelContext)`
    /// resolves.
    public func modelContainer(_ container: ModelContainer) -> some View {
        environment(container.contextOnMain)
            .environment(\.modelContext, container.contextOnMain)
    }

    /// A container made once for the views beneath - the form previews use,
    /// holding its store in memory when `inMemory`.
    public func modelContainer(
        for types: any PersistentModel.Type...,
        inMemory: Bool = false
    ) -> some View {
        ModelContainerHost(content: self, types: types, inMemory: inMemory)
    }
}

extension Scene {
    /// Hands `container`'s main context to every window of the scene, as a
    /// scene-level `.modelContainer` does in SwiftUI - the `\.modelContext`
    /// value and the `ModelContext` object the windows' views resolve.
    ///
    ///     var body: some Scene {
    ///         Window("设置", id: "setting") { SettingsWindow() }
    ///             .modelContainer(appModelContainer)
    ///     }
    public func modelContainer(_ container: ModelContainer) -> Scene {
        environment(\.modelContext, container.contextOnMain)
            .environment(container.contextOnMain)
    }
}

/// The view that owns a `.modelContainer(for:inMemory:)` container, so the
/// container is made once and kept while the view stands.
private struct ModelContainerHost<Content: View>: View {
    /// The container, made on first build and kept across rebuilds.
    @State private var container: ModelContainer?

    let content: Content
    let types: [any PersistentModel.Type]
    let inMemory: Bool

    var body: some View {
        if container == nil {
            let types = OnMain(value: self.types), inMemory = self.inMemory
            container = MainActor.assumeIsolated {
                OnMain(value: try! ModelContainer(
                    for: Schema(types.value),
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: inMemory)]))
            }.value
        }

        return content.modelContainer(container!)
    }
}

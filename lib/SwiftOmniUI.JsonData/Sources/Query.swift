// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `@Query`, the model layer's table in a view: the rows matching a fetch
// descriptor, re-fetched when the context's store changes. It resolves the
// context from the environment like SwiftUI's - `.modelContainer` above -
// and drives rebuilds through `@Observable` tracking: a build that read
// `items` is rebuilt when the store changes them.
//
// JsonDataCore follows the store with `startObservation`.

import Foundation
import JsonData
import SwiftOmniUICore

/// A value `MainActor.assumeIsolated` hands back, whose result must be
/// `Sendable` though what the UI thread reads never leaves it.
private struct OnMain<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

/// A key path as `SortDescriptor` spells it: Foundation's initializer asks the
/// path itself conform `Sendable`, which `KeyPath` never does - a key path is
/// immutable, so the cast only writes the conformance onto the type. A
/// class-bound existential is one pointer, the bitcast is representation-safe.
private func sendable<Root, Value>(
    _ keyPath: KeyPath<Root, Value>
) -> any KeyPath<Root, Value> & Sendable {
    unsafeBitCast(keyPath, to: (KeyPath<Root, Value> & Sendable).self)
}

/// The rows a `Query` holds: what was last fetched, refetched when the store
/// reports a change. Reading `items` during a build records the dependency.
@MainActor
@Observable
final class QueryResult<Element: PersistentModel> {
    /// What the last fetch answered.
    private(set) var items: [Element] = []

    /// What the query asks for.
    let descriptor: FetchDescriptor<Element>

    /// The animation `Query(..., animation:)` carried - kept for when a
    /// host learns to animate row changes.
    let animation: Animation?

    /// The context the query follows, once the environment answers.
    private(set) weak var context: ModelContext?

    /// The store's observation - a GRDB cancellable under JsonDataCore,
    /// released with the object.
    private var observation: Any?

    nonisolated init(descriptor: FetchDescriptor<Element>, animation: Animation? = nil) {
        self.descriptor = descriptor
        self.animation = animation
    }

    /// Binds the context the environment resolved; idempotent for one context.
    func attach(to context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        refetch()

        observation = context.startObservation(
            descriptor,
            onChange: { [weak self] newItems in
                self?.items = newItems
            })
    }

    /// Fetches again and reports the rows.
    private func refetch() {
        guard let context else { return }
        items = (try? context.fetch(descriptor)) ?? []
    }
}

/// The `filter:` a `Query` takes: `JsonDataCore.Predicate` - `#Predicate`
/// spells into it, so the filter source is platform-neutral.
/// A view's handle on the model layer's rows:
///
///     @Query private var records: [Record]
///     @Query(sort: \Folder.lastAccessedAt, order: .reverse)
///         private var folders: [Folder]
///
/// The context comes from the environment - `.modelContainer(...)` on an
/// ancestor, as SwiftUI's does. Reads re-render when the store changes.
@propertyWrapper
public struct Query<Element: PersistentModel> {
    /// The context `.modelContainer` wrote above - resolved before each build.
    @Environment(\.modelContext) private var context: ModelContext

    /// The rows, kept across rebuilds.
    @State private var result: QueryResult<Element>

    /// Every row of the type, unordered.
    public init() {
        _result = State(wrappedValue: QueryResult(descriptor: FetchDescriptor<Element>()))
    }

    /// The rows ordered by one key.
    public init<Value: Comparable>(
        sort keyPath: KeyPath<Element, Value>,
        order: SortOrder = .forward
    ) {
        _result = State(wrappedValue: QueryResult(
            descriptor: FetchDescriptor(sortBy: [SortDescriptor(sendable(keyPath), order: order)])))
    }

    /// A descriptor of your own - the full SwiftData spelling:
    ///
    ///     _events = Query(descriptor, animation: .snappy)
    ///
    /// `animation` is kept on the result for when the host learns to animate
    /// row changes; today the store's change simply refetches.
    public init(_ descriptor: FetchDescriptor<Element>, animation: Animation? = nil) {
        _result = State(wrappedValue: QueryResult(descriptor: descriptor, animation: animation))
    }

    /// The rows `filter` matches.
    public init(filter: JsonDataCore.Predicate<Element>, animation: Animation? = nil) {
        self.init(FetchDescriptor(predicate: filter), animation: animation)
    }

    /// The rows `filter` matches, ordered by one key - SwiftData's
    /// `Query(filter:sort:order:animation:)`.
    public init<Value: Comparable>(
        filter: JsonDataCore.Predicate<Element>,
        sort keyPath: KeyPath<Element, Value>,
        order: SortOrder = .forward,
        animation: Animation? = nil
    ) {
        self.init(
            FetchDescriptor(
                predicate: filter,
                sortBy: [SortDescriptor(keyPath, order: order)]),
            animation: animation)
    }

    /// The rows `filter` matches, ordered by descriptors - SwiftData's
    /// `Query(filter:sort:animation:)` with a sort list.
    public init(
        filter: JsonDataCore.Predicate<Element>,
        sort descriptors: [JsonDataCore.SortDescriptor<Element>],
        animation: Animation? = nil
    ) {
        self.init(FetchDescriptor(predicate: filter, sortBy: descriptors), animation: animation)
    }

    /// The rows ordered by descriptors.
    public init(sort descriptors: [JsonDataCore.SortDescriptor<Element>], animation: Animation? = nil) {
        _result = State(wrappedValue: QueryResult(
            descriptor: FetchDescriptor(sortBy: descriptors), animation: animation))
    }

    /// The matching rows.
    public var wrappedValue: [Element] {
        // Builds run on the UI thread, which is the main actor for every host.
        let context = _context, result = _result
        return MainActor.assumeIsolated {
            result.wrappedValue.attach(to: context.wrappedValue)
            return OnMain(result.wrappedValue.items)
        }.value
    }
}

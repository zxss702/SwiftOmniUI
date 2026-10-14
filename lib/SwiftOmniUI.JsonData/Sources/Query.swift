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
import JsonDataCore
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

/// Comparable query inputs keep captured predicate/comparator closures out of view diffing.
private struct QueryRequest<Element: PersistentModel>: Equatable {
    let descriptor: FetchDescriptor<Element>

    static func == (left: Self, right: Self) -> Bool {
        let descriptor = left.descriptor, other = right.descriptor
        guard descriptor.fetchLimit == other.fetchLimit, descriptor.fetchOffset == other.fetchOffset,
              descriptor.includePendingChanges == other.includePendingChanges,
              descriptor.propertiesToFetch == other.propertiesToFetch,
              descriptor.relationshipKeyPathsForPrefetching == other.relationshipKeyPathsForPrefetching,
              descriptor.sortBy.count == other.sortBy.count,
              zip(descriptor.sortBy, other.sortBy).allSatisfy({ $0.keyPath == $1.keyPath && $0.order == $1.order })
        else { return false }
        switch (descriptor.predicate, other.predicate) {
        case (nil, nil): return true
        case let (left?, right?):
            return left.sql == right.sql && NSArray(array: left.arguments).isEqual(to: right.arguments)
                && left.joinConditions.count == right.joinConditions.count
                && zip(left.joinConditions, right.joinConditions).allSatisfy {
                    $0.localColumn == $1.localColumn && $0.targetColumn == $1.targetColumn && $0.op == $1.op
                        && NSArray(array: [$0.argument]).isEqual(to: [$1.argument])
                }
        default: return false
        }
    }
}

/// The rows a `Query` holds: what was last fetched, refetched when the store
/// reports a change. Reading `items` during a build records the dependency.
@MainActor
@Observable
final class QueryResult<Element: PersistentModel> {
    /// What the last fetch answered.
    private(set) var items: [Element] = []

    /// What the query asks for.
    @ObservationIgnored private var descriptor: FetchDescriptor<Element>

    /// The transaction applied when membership or order changes.
    @ObservationIgnored private var animation: Animation?

    /// The context the query follows, once the environment answers.
    @ObservationIgnored private(set) weak var context: ModelContext?

    /// The store's observation - a GRDB cancellable under JsonDataCore,
    /// released with the object.
    @ObservationIgnored private var observation: Any?
    @ObservationIgnored private var instances: [ObjectIdentifier] = []
    @ObservationIgnored private var generation = 0

    nonisolated init(descriptor: FetchDescriptor<Element>, animation: Animation? = nil) {
        self.descriptor = descriptor
        self.animation = animation
    }

    func attach(to context: ModelContext) {
        attach(to: context, descriptor: descriptor, animation: animation)
    }

    /// Follows the current context and descriptor without restarting an unchanged query.
    func attach(to context: ModelContext, descriptor: FetchDescriptor<Element>, animation: Animation?) {
        self.animation = animation
        guard self.context !== context || !sameRequest(descriptor) else { return }
        observation = nil
        generation += 1
        let generation = self.generation
        self.context = context
        self.descriptor = descriptor
        refetch()

        observation = context.startObservation(
            descriptor,
            onChange: { [weak self] newItems in
                guard let self, self.generation == generation else { return }
                self.accept(newItems)
            })
    }

    private func sameRequest(_ other: FetchDescriptor<Element>) -> Bool {
        QueryRequest(descriptor: descriptor) == QueryRequest(descriptor: other)
    }

    /// Fetches again and reports the rows.
    private func refetch() {
        guard let context else { return }
        accept((try? context.fetch(descriptor)) ?? [])
    }

    /// The observation's initial delivery often repeats the synchronous fetch.
    /// Model properties have their own Observation dependencies; publish here
    /// only when membership, order or the actual model instances change.
    private func accept(_ newItems: [Element]) {
        let identities = newItems.map(ObjectIdentifier.init)
        guard instances != identities else { return }
        instances = identities
        withAnimation(animation) { items = newItems }
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

    private let request: QueryRequest<Element>
    private let animation: Animation?

    /// Every row of the type, unordered.
    public init() {
        self.init(FetchDescriptor<Element>())
    }

    /// The rows ordered by one key.
    public init<Value: Comparable>(
        sort keyPath: KeyPath<Element, Value>,
        order: SortOrder = .forward
    ) {
        self.init(FetchDescriptor(sortBy: [SortDescriptor(sendable(keyPath), order: order)]))
    }

    /// A descriptor of your own - the full SwiftData spelling:
    ///
    ///     _events = Query(descriptor, animation: .snappy)
    ///
    /// `animation` applies to result membership and order changes.
    public init(_ descriptor: FetchDescriptor<Element>, animation: Animation? = nil) {
        self.request = QueryRequest(descriptor: descriptor)
        self.animation = animation
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
        self.init(FetchDescriptor(sortBy: descriptors), animation: animation)
    }

    /// The matching rows.
    public var wrappedValue: [Element] {
        // Builds run on the UI thread, which is the main actor for every host.
        let context = _context, result = _result
        let descriptor = request.descriptor, animation = animation
        return MainActor.assumeIsolated { [context, result, descriptor, animation] in
            result.wrappedValue.attach(to: context.wrappedValue, descriptor: descriptor, animation: animation)
            return OnMain(result.wrappedValue.items)
        }.value
    }
}

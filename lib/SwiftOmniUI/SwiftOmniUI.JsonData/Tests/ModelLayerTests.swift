// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftOmniUIJsonData
import JsonData
@_spi(Host) @testable import SwiftOmniUICore

/// A model the query tests keep in memory.
@Model
final class Row {
    var name: String
    init(name: String) { self.name = name }
}

struct ModelLayerTests {
    /// The context written by `.modelContainer` comes back through the key.
    @Test @MainActor func modelContextRoundTrips() throws {
        let container = try ModelContainer(
            for: Schema([Row.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])

        var values = EnvironmentValues()
        values.modelContext = container.mainContext

        #expect(values.modelContext === container.mainContext)
    }

    /// A query attaches to the context, fetches, and refetches on save.
    @Test @MainActor func queryFetchesAndFollows() async throws {
        let container = try ModelContainer(
            for: Schema([Row.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext

        let result = QueryResult<Row>(descriptor: FetchDescriptor<Row>())
        result.attach(to: context)

        // JsonDataCore's in-memory configuration resolves to its shared
        // context, which other tests may already have written to.
        let marker = "one-\(UUID().uuidString)"
        context.insert(Row(name: marker))
        try context.save()

        // The store's observation hands the change back on a task; SwiftData
        // reports synchronously. Either way, the rows arrive.
        for _ in 0..<50 where !result.items.contains(where: { $0.name == marker }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(result.items.contains { $0.name == marker })
    }

    /// The same context attaches once; another refetches under it.
    @Test @MainActor func queryAttachIsIdempotent() throws {
        let container = try ModelContainer(
            for: Schema([Row.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])

        let result = QueryResult<Row>(descriptor: FetchDescriptor<Row>())
        result.attach(to: container.mainContext)
        result.attach(to: container.mainContext)

        #expect(result.context === container.mainContext)
    }

    /// Build a real @Query read, including its written descriptor and environment context.
    @Test @MainActor func queryWrappedValueReadsItsWrittenSortOrder() throws {
        let container = try ModelContainer(
            for: Schema([Row.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let marker = "wrapped-query-\(UUID().uuidString)"
        container.mainContext.insert(Row(name: "\(marker)-a"))
        container.mainContext.insert(Row(name: "\(marker)-z"))
        try container.mainContext.save()

        struct Page: View {
            @Query(sort: \Row.name, order: .reverse) private var rows: [Row]
            let marker: String

            init(marker: String) {
                self.marker = marker
            }

            var body: some View {
                Text(rows.filter { $0.name.hasPrefix(marker) }.map(\.name).joined(separator: "|"))
            }
        }

        let node = Page(marker: marker).modelContainer(container).node.built
        #expect(node.type == .text)
        #expect(node.props[.text] == .string("\(marker)-z|\(marker)-a"))
    }

    /// The full spelling an application writes compiles and builds a node.
    @Test func surfaceCompiles() {
        struct Page: View {
            @Environment(\.modelContext) private var context
            @Query(sort: \Row.name) private var rows: [Row]

            var body: some View {
                Text("rows: \(rows.count)")
            }
        }

        _ = Page().node
    }
}

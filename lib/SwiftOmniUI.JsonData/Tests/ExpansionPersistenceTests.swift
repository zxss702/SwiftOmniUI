// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import JsonData

@Model
final class PersistedExpansion {
    @Attribute(.unique) var url: URL
    var expanded: Bool = false

    init(url: URL, expanded: Bool) {
        self.url = url
        self.expanded = expanded
    }
}

/// Exercise the ordinary model API used for saved UI state, independently of
/// Query and the view lifetime. Each test owns an actual, isolated store.
struct ExpansionPersistenceTests {
    @MainActor private func container(at store: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema([PersistedExpansion.self]),
                           configurations: [ModelConfiguration(url: store)])
    }

    @MainActor private func write(to store: URL, urls: [URL]) throws {
        let context = try container(at: store).mainContext
        context.autosaveEnabled = false
        for url in urls { context.insert(PersistedExpansion(url: url, expanded: true)) }
        try context.save()
    }

    @MainActor private func restored(from store: URL) throws -> Set<URL> {
        let context = try container(at: store).mainContext
        return Set(try context.fetch(FetchDescriptor<PersistedExpansion>())
            .filter(\.expanded).map(\.url))
    }

    @Test @MainActor func allExpandedURLsSurviveClosingAndReopeningTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("expansion.sqlite")
        let urls = ["project", "project/空 格", "project/空 格/nested"].map {
            directory.appendingPathComponent($0, isDirectory: true)
        }
        try write(to: store, urls: urls)
        #expect(try restored(from: store) == Set(urls))
        #expect(try restored(from: store) == Set(urls), "restoring must not reset persisted fields")
    }

    @MainActor private func toggleAndAutosave(at store: URL, url: URL) async throws {
        let context = try container(at: store).mainContext
        let rows = try context.fetch(FetchDescriptor<PersistedExpansion>())
        let row = try #require(rows.first { $0.url == url })
        row.expanded = false
        // No explicit save: reopening a page and reopening the process must
        // both see the same field update after autosave has completed.
        var persisted = false
        for _ in 0..<100 {
            if try restored(from: store).contains(url) == false {
                persisted = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(persisted)
        #expect(!context.hasChanges)
        #expect(try context.fetch(FetchDescriptor<PersistedExpansion>()).allSatisfy { !$0.expanded })
    }

    @Test @MainActor func changingAFetchedExpansionIsAutosaved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("expansion.sqlite")
        let url = directory.appendingPathComponent("nested", isDirectory: true)
        try write(to: store, urls: [url])
        try await toggleAndAutosave(at: store, url: url)
        #expect(try restored(from: store).isEmpty)
    }

    @Test @MainActor func insertingExpansionIsVisibleBeforeAndAfterAutosave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("expansion.sqlite")
        let url = directory.appendingPathComponent("project/nested", isDirectory: true)
        let context = try container(at: store).mainContext
        context.insert(PersistedExpansion(url: url, expanded: true))

        #expect(Set(try context.fetch(FetchDescriptor<PersistedExpansion>())
            .filter(\.expanded).map(\.url)) == Set([url]),
            "a reopened sidebar must see pending inserts in the same context")

        var persisted = false
        for _ in 0..<100 {
            if try restored(from: store).contains(url) {
                persisted = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(persisted, "a new process must find the inserted expansion on disk")
    }
}

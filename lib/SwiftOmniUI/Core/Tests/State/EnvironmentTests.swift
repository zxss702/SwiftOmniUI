// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// An object provided above, resolved below - and the rebuilds landing exactly
// where the reads are.
//
// The mechanism is in Environment.swift (the wrapper and the slots),
// Differ.swift (the scope, kept through both walks, and the memo's
// environment snapshot) and Stateful.swift (the slots collected beside
// the state boxes, and the structural `built` path). The promises pinned
// here, each proven to fail without its half of the mechanism:
//
//   - a child resolves the NEAREST provided object of its type, and a nearer
//     `.environment()` overrides for its own branch;
//   - a write IN the object rebuilds the readers and never the provider;
//   - replacing the object itself rebuilds the branch, which then resolves
//     the new one - through the clean walk, deep under clean ancestors;
//   - an unchanged memo token does not carry a subtree past a provider
//     replacement (`RenderedNode.seen` is what the skip compares);
//   - `$context.property` lends one property on, writes included.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private final class Session {
    @State var name = "guest"
    @State var visits = 0
}

/// A second context type: types are independent domains, and a write to one
/// must never rebuild the other's readers.
private final class ColorScheme {
    @State var accent = "violet"
}

/// Counts how often a body ran. A class, so the Mirror walk that collects
/// state boxes and environment slots leaves it alone.
private final class Builds {
    var count = 0
}

/// Reads one property of the session - the view a write should rebuild.
private struct NameLabel: View {
    let builds: Builds
    @Environment var session: Session

    var body: some View {
        builds.count += 1
        return ModifiedContent(node: label(session.name))
    }
}

/// Reads the color scheme - the other domain's reader.
private struct AccentLabel: View {
    let builds: Builds
    @Environment var colorScheme: ColorScheme

    var body: some View {
        builds.count += 1
        return ModifiedContent(node: label(colorScheme.accent))
    }
}

/// Owns the session, provides it, and never reads a property of it.
private struct Provider: View {
    let builds: Builds
    let reader: Builds
    @State var session = Session()

    var body: some View {
        builds.count += 1
        return ModifiedContent(node: stack([NameLabel(builds: reader).environment(session).node]))
    }
}

/// A handler writing through the environment - what an application's button
/// does. The closure captures the view, whose wrapper resolves at fire time
/// to what the walk that built this render filled in.
private struct VisitButton: View {
    @Environment var session: Session

    var body: some View {
        Button("visits \(session.visits)").onClicked { session.visits += 1 }
    }
}

/// A handler lending one property on: `$session.name` is a `Binding<String>`
/// writing through the object, the model rule.
private struct RenameButton: View {
    @Environment var session: Session

    var body: some View {
        Button("rename").onClicked {
            let name: Binding<String> = $session.name
            name.wrappedValue = "typed"
        }
    }
}

/// A provider whose branch holds a reader built with constant inputs - a
/// carry must still follow a provider replacement, which no input can see.
private struct Holder: View {
    let reader: Builds
    @State var session = Session()
    @State var title = "t"

    var body: some View {
        VStack {
            Text(title)
            NameLabel(builds: reader).id("m")
        }
        .environment(session)
    }
}

@MainActor final class EnvironmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    private var changed: Set<ObjectIdentifier> { Renderer.shared.pendingChanges }

    // MARK: - Resolution

    func testAChildResolvesWhatAnAncestorProvided() {
        let renders = Renders()
        let provider = Provider(builds: Builds(), reader: Builds())

        let patch = renders.render(stack([provider.node], id: "root"))

        XCTAssertEqual(
            patch.child(.auto(1))?.child(.auto(2))?.props["text"], .string("guest"))
    }

    func testANearerProviderWinsForItsBranch() {
        let renders = Renders()
        let outer = Session(), inner = Session()
        outer.name = "outer"
        inner.name = "inner"

        struct Pair: View {
            let outer: Session
            let inner: Session

            var body: some View {
                VStack {
                    NameLabel(builds: Builds())
                    NameLabel(builds: Builds()).environment(inner)
                }
                .environment(outer)
            }
        }

        Renderer.shared.clearInvalidation()
        let patch = renders.render(stack([Pair(outer: outer, inner: inner).node], id: "root"))

        // A composed view adds no element of its own: the placeholder IS the
        // VStack it unwraps to, and each NameLabel is its label.
        let row = patch.child(.auto(1))

        XCTAssertEqual(row?.child(.auto(2))?.props["text"], .string("outer"))
        XCTAssertEqual(row?.child(.auto(3))?.props["text"], .string("inner"))
    }

    func testAStructuralReadResolvesTheEnvironment() {
        let provider = Provider(builds: Builds(), reader: Builds())

        // `.built` is what a structural test reads - no differ involved, so
        // it keeps a scope of its own. See Node.built(within:).
        let tree = stack([provider.node], id: "root").built

        XCTAssertEqual(tree.children[0].children[0].props[.text], .string("guest"))
    }

    // MARK: - Who rebuilds

    func testAWriteInTheObjectRebuildsTheReaderAndNotTheProvider() {
        let renders = Renders()
        let owner = Builds(), reader = Builds()
        let provider = Provider(builds: owner, reader: reader)

        renders.render(stack([provider.node], id: "root"))
        XCTAssertEqual(owner.count, 1)
        XCTAssertEqual(reader.count, 1)

        provider.session.name = "anna"

        let patch = renders.revisit(changed: changed)

        XCTAssertEqual(owner.count, 1, "the provider passes a reference and reads no property")
        XCTAssertEqual(reader.count, 2, "the reader's build read what moved")
        XCTAssertEqual(
            patch.child(.auto(1))?.child(.auto(2))?.props["text"], .string("anna"))
    }

    func testContextTypesAreIndependentDomains() {
        let renders = Renders()
        let names = Builds(), accents = Builds()
        let session = Session(), colorScheme = ColorScheme()

        struct Both: View {
            let names: Builds
            let accents: Builds
            let session: Session
            let colorScheme: ColorScheme

            var body: some View {
                VStack {
                    NameLabel(builds: names)
                    AccentLabel(builds: accents)
                }
                .environment(session)
                .environment(colorScheme)
            }
        }

        let view = Both(names: names, accents: accents, session: session, colorScheme: colorScheme)
        renders.render(stack([view.node], id: "root"))

        colorScheme.accent = "orange"
        let patch = renders.revisit(changed: changed)

        XCTAssertEqual(names.count, 1, "the session's reader has no business with the colorScheme")
        XCTAssertEqual(accents.count, 2)
        XCTAssertEqual(
            patch.child(.auto(1))?.child(.auto(3))?.props["text"], .string("orange"))
    }

    func testReplacingTheProvidedObjectReachesTheBranch() {
        let renders = Renders()
        let owner = Builds(), reader = Builds()
        let provider = Provider(builds: owner, reader: reader)

        renders.render(stack([provider.node], id: "root"))

        let old = provider.session
        let fresh = Session()
        fresh.name = "fresh"
        provider.session = fresh

        let patch = renders.revisit(changed: changed)

        XCTAssertEqual(owner.count, 2, "replacing the object writes the @State box the provider reads")
        XCTAssertEqual(reader.count, 2, "a rebuilt provider rebuilds what it writes")
        XCTAssertEqual(
            patch.child(.auto(1))?.child(.auto(2))?.props["text"], .string("fresh"))

        // The reader's reads were re-recorded against the NEW object, so the
        // old one's changes are nobody's business now.
        Renderer.shared.clearInvalidation()
        old.name = "stale"
        let silent = renders.revisit(changed: changed)

        XCTAssertEqual(reader.count, 2, "nothing shown reads the replaced object")
        XCTAssertTrue(silent.isEmpty)
    }

    // MARK: - Handlers

    func testAHandlerWritesThroughTheEnvironment() {
        let renders = Renders()
        let session = Session()

        let first = renders.render(
            stack([VisitButton().environment(session).node], id: "root"))
        let id = first.child(.auto(1))?.events?["clicked"]
        XCTAssertNotNil(id)

        XCTAssertTrue(renders.fire(id!))
        XCTAssertEqual(session.visits, 1, "the handler resolved the provided object")

        let patch = renders.revisit(changed: changed)
        XCTAssertEqual(patch.child(.auto(1))?.props["text"], .string("visits 1"))
    }

    func testTheProjectedValueLendsOnePropertyOn() {
        let renders = Renders()
        let session = Session()

        let first = renders.render(
            stack([RenameButton().environment(session).node], id: "root"))
        let id = first.child(.auto(1))?.events?["clicked"]

        XCTAssertTrue(renders.fire(id!))
        XCTAssertEqual(session.name, "typed",
                       "$session.name writes through the object, the model rule")
    }

    // MARK: - What a carried view compares beside its inputs

    func testAReplacedProviderReachesACarriedView() {
        let renders = Renders()
        let reader = Builds()
        let holder = Holder(reader: reader)

        renders.render(stack([holder.node], id: "root"))
        XCTAssertEqual(reader.count, 1)

        let fresh = Session()
        fresh.name = "fresh"
        holder.session = fresh
        let patch = renders.revisit(changed: changed)

        // The label's inputs are unchanged and say nothing about the
        // provider; the object its `@Environment` resolved to is what tells
        // the two renders apart.
        XCTAssertEqual(reader.count, 2, "a carried view must not keep a replaced provider")
        XCTAssertEqual(
            patch.child(.auto(1))?.child("m")?.props["text"], .string("fresh"))
    }

    func testTheSameProviderLeavesACarriedViewAlone() {
        let renders = Renders()
        let reader = Builds()
        let holder = Holder(reader: reader)

        renders.render(stack([holder.node], id: "root"))

        // The holder rebuilds for its own state; the provider object is the
        // same one, so the label under it is carried.
        holder.title = "T"
        renders.revisit(changed: changed)
        XCTAssertEqual(reader.count, 1, "the same provider is not a reason to build the view")
    }

    // MARK: - Keyed values: `.environment(\.key, _)` and `@Environment(\.key)`

    func testAChildResolvesWhatAnAncestorWrote() {
        let renders = Renders()

        let patch = renders.render(
            stack([TintLabel(builds: Builds()).environment(\.pageTint, "plum").node], id: "root"))

        XCTAssertEqual(patch.child(.auto(1))?.props["text"], .string("plum"))
    }

    func testAKeyedValueReadsItsDefaultWhereNothingWrote() {
        let renders = Renders()

        let patch = renders.render(stack([TintLabel(builds: Builds()).node], id: "root"))

        XCTAssertEqual(patch.child(.auto(1))?.props["text"], .string("gray"))
    }

    func testTheNearerWriteWinsForItsBranch() {
        let renders = Renders()

        let patch = renders.render(
            stack(
                [TintLabel(builds: Builds()).environment(\.pageTint, "inner").node],
                id: "root"
            ).environmentValuesWriting(\.pageTint, "outer"))

        XCTAssertEqual(patch.child(.auto(1))?.props["text"], .string("inner"))
    }

    func testAMovedKeyedValueRebuildsItsReader() {
        let renders = Renders()
        let reader = Builds()
        let holder = TintHolder(reader: reader)

        renders.render(stack([holder.node], id: "root"))
        XCTAssertEqual(reader.count, 1)

        holder.tint = "plum"
        let patch = renders.revisit(changed: changed)

        XCTAssertEqual(reader.count, 2, "a keyed value that moved is a reason to build the view")
        XCTAssertEqual(patch.child(.auto(1))?.child("t")?.props["text"], .string("plum"))
    }

    func testAnUnmovedKeyedValueLeavesACarriedViewAlone() {
        let renders = Renders()
        let reader = Builds()
        let holder = TintHolder(reader: reader)

        renders.render(stack([holder.node], id: "root"))

        holder.title = "T"
        renders.revisit(changed: changed)
        XCTAssertEqual(reader.count, 1, "the same keyed value is not a reason to build the view")
    }

    func testAnOptionalObjectReadsNilWhereNothingProvided() {
        let renders = Renders()

        let patch = renders.render(stack([MaybeSessionLabel().node], id: "root"))

        XCTAssertEqual(patch.child(.auto(1))?.props["text"], .string("none"))
    }

    func testAnOptionalObjectResolvesWhereProvided() {
        let renders = Renders()
        let session = Session()

        let patch = renders.render(stack([MaybeSessionLabel().environment(session).node], id: "root"))

        XCTAssertEqual(patch.child(.auto(1))?.props["text"], .string("guest"))
    }
}

/// The keyed environment's test key: `\.pageTint` writes and reads a `String`.
private struct PageTintKey: EnvironmentKey {
    static let defaultValue = "gray"
}

extension EnvironmentValues {
    /// The tint this branch was written with.
    fileprivate var pageTint: String {
        get { self[PageTintKey.self] }
        set { self[PageTintKey.self] = newValue }
    }
}

/// A `.environment(\.key, _)` spelled on a bare `Node`, for the stack helper's
/// own node (the modifier lives on `View`; a built stack writes directly).
private extension Node {
    func environmentValuesWriting<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value
    ) -> Node {
        var node = self
        node.environmentValues[keyPath: keyPath] = value
        return node
    }
}

/// Reads `\.pageTint` - the keyed environment's reader.
private struct TintLabel: View {
    let builds: Builds
    @Environment(\.pageTint) var tint

    var body: some View {
        builds.count += 1
        return ModifiedContent(node: label(tint))
    }
}

/// Owns a keyed write and an unrelated state - the writer a moved value and
/// an unmoved one are told apart through.
private struct TintHolder: View {
    let reader: Builds
    @State var tint = "gray"
    @State var title = "t"

    var body: some View {
        VStack {
            Text(title)
            TintLabel(builds: reader).id("t")
        }
        .environment(\.pageTint, tint)
    }
}

/// Reads an object that may not be there - `@Environment(T.self) var t: T?`.
private struct MaybeSessionLabel: View {
    @Environment(Session.self) var session: Session?

    var body: some View {
        ModifiedContent(node: label(session?.name ?? "none"))
    }
}

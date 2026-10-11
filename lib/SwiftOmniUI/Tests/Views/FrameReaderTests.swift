// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.onFrameChanged` hands its handler the four values its space means, out of
// the one ten-number report the host sends - and a GeometryReader builds its
// content FROM that measurement, holding it in a @State of its own. See
// GeometryReader.swift.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class FrameReaderTests: XCTestCase {
    /// What the last handler run was given, shared with the assert the way a
    /// state box would be.
    private final class Heard: @unchecked Sendable {
        var frames: [Rect] = []
    }

    /// One report, as a host composes it: parent x, y, width, height,
    /// then the corner in the window, then the safe area's frame there -
    /// an origin of (0, 44) leaving the view's corner (110, 176) inside it.
    private let payload: [PropValue] = [.numbers([10, 20, 300, 400, 110, 220, 0, 44, 400, 600])]

    // MARK: - The modifier

    private func frame(in space: CoordinateSpace) -> Rect? {
        let renders = Renders()
        let heard = Heard()

        let patch = renders.render(
            VStack {
                Text("content")
            }
            .onFrameChanged(in: space) { heard.frames.append($0) }
            .node)

        renders.fire(patch.events?["frameChanged"] ?? -1, with: payload)
        return heard.frames.last
    }

    func testTheParentSpaceIsTheFrameAsTheParentPlacedIt() {
        XCTAssertEqual(frame(in: .parent), Rect(10, 20, 300, 400))
    }

    func testTheGlobalSpaceMovesTheOriginToTheWindow() {
        XCTAssertEqual(frame(in: .global), Rect(110, 220, 300, 400))
    }

    func testTheSafeAreaSpaceMovesItPastTheInsets() {
        XCTAssertEqual(frame(in: .safeArea), Rect(110, 176, 300, 400))
    }

    func testTheLocalSpaceIsTheViewsOwnBounds() {
        XCTAssertEqual(frame(in: .local), Rect(0, 0, 300, 400))
    }

    /// A named space measures the frame from the declaring ancestor's top
    /// left: the window corner less the space's own - which arrives ahead of
    /// the numbers, as the host sends it.
    func testANamedSpaceMeasuresFromItsDeclaringView() {
        let renders = Renders()
        let heard = Heard()

        let patch = renders.render(
            VStack {}
                .onFrameChanged(in: .named("Page")) { heard.frames.append($0) }
                .node)

        renders.fire(patch.events?["namedFramesChanged"] ?? -1, with: [
            .values([.values([.string("Page"), .numbers([100, 200, 800, 600])])])])
        renders.fire(patch.events?["frameChanged"] ?? -1, with: payload)

        XCTAssertEqual(heard.frames.last, Rect(10, 20, 300, 400))
    }

    /// A space no ancestor declared has nothing to answer with: `.zero`.
    func testANamedSpaceNobodyDeclaredReadsZero() {
        XCTAssertEqual(frame(in: .named("Nowhere")), Rect(0, 0, 0, 0))
    }

    /// `.coordinateSpace` writes the name the host walks ancestors for.
    func testACoordinateSpaceWritesItsName() {
        let renders = Renders()

        let patch = renders.render(
            VStack {}
                .coordinateSpace(.named("Page"))
                .node)

        XCTAssertEqual(patch.props["coordinateSpaceName"], .string("Page"))
    }

    /// A proxy answers `.named` from the same two reports the handler reads.
    func testAProxyAnswersANamedSpace() {
        let renders = Renders()

        func tree() -> Node {
            Node(type: "WindowScene", children: [
                VStack {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named("Page"))
                        return Text("\(Int(frame.x)),\(Int(frame.y))")
                    }
                }.node,
            ])
        }

        let first = renders.render(tree())
        let grid = first.children.first?.children.first

        Renderer.shared.clearInvalidation()
        renders.fire(grid?.events?["namedFramesChanged"] ?? -1, with: [
            .values([.values([.string("Page"), .numbers([100, 200, 800, 600])])])])
        renders.fire(grid?.events?["frameChanged"] ?? -1, with: payload)
        let second = renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(
            second.children.first?.children.first?.children.first?.props["text"],
            .string("10,20"))
        Renderer.shared.clearInvalidation()
    }

    /// A reader whose view reaches above and below the safe area reads the
    /// covered strips as insets; sides inside it read zero.
    func testAProxyReadsTheSafeAreasCoverAsInsets() {
        let renders = Renders()

        func tree() -> Node {
            Node(type: "WindowScene", children: [
                VStack {
                    GeometryReader { proxy in
                        Text("\(Int(proxy.safeAreaInsets.top))/\(Int(proxy.safeAreaInsets.bottom))")
                    }
                }.node,
            ])
        }

        let first = renders.render(tree())
        let grid = first.children.first?.children.first

        Renderer.shared.clearInvalidation()
        // A full-window view, its safe area starting 44 down and ending 56 up.
        renders.fire(grid?.events?["frameChanged"] ?? -1,
            with: [.numbers([0, 0, 400, 800, 0, 0, 0, 44, 400, 700])])
        let second = renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(
            second.children.first?.children.first?.children.first?.props["text"],
            .string("44/56"))
        Renderer.shared.clearInvalidation()
    }

    func testTheDefaultSpaceIsTheParent() {
        let renders = Renders()
        let heard = Heard()

        let patch = renders.render(
            VStack {}
                .onFrameChanged { heard.frames.append($0) }
                .node)

        renders.fire(patch.events?["frameChanged"] ?? -1, with: payload)

        XCTAssertEqual(heard.frames.last, Rect(10, 20, 300, 400))
    }

    /// Two handlers on one view hear one report each, in writing order -
    /// `addHandler` runs a later handler BESIDE an earlier one.
    func testEachSpaceReportsToItsOwnHandler() {
        let renders = Renders()
        let heard = Heard()

        let patch = renders.render(
            VStack {}
                .onFrameChanged { heard.frames.append($0) }
                .onFrameChanged(in: .global) { heard.frames.append($0) }
                .node)

        renders.fire(patch.events?["frameChanged"] ?? -1, with: payload)

        XCTAssertEqual(heard.frames, [Rect(10, 20, 300, 400), Rect(110, 220, 300, 400)])
    }

    /// A scroll moves the window origin and nothing else - the report goes
    /// out, and each handler answers only for ITS space: the `.global` one
    /// hears the move, the `.parent` one hears nothing at all.
    func testAHandlerHearsOnlyItsOwnSpaceMove() {
        let renders = Renders()
        let parents = Heard()
        let windows = Heard()

        let patch = renders.render(
            VStack {}
                .onFrameChanged { parents.frames.append($0) }
                .onFrameChanged(in: .global) { windows.frames.append($0) }
                .node)

        let id = patch.events?["frameChanged"] ?? -1

        renders.fire(id, with: [.numbers([10, 20, 300, 400, 110, 220, 0, 44, 400, 600])])

        // What a scroll sends: the same parent frame, a moved window origin.
        renders.fire(id, with: [.numbers([10, 20, 300, 400, 110, 470, 0, 44, 400, 600])])

        XCTAssertEqual(parents.frames, [Rect(10, 20, 300, 400)],
            "the parent-space handler heard a scroll that never changed its answer")
        XCTAssertEqual(windows.frames, [Rect(110, 220, 300, 400), Rect(110, 470, 300, 400)])
    }

    /// The gesture payloads' rule, kept here too: a report this side cannot
    /// read is a version mismatch, not an event, and the handler stays out of
    /// it. Three ways it cannot read - no values, too few numbers, and a value
    /// of the wrong kind entirely.
    func testAPayloadItCannotReadLeavesTheHandlerAlone() {
        let renders = Renders()
        let heard = Heard()

        let patch = renders.render(
            VStack {}
                .onFrameChanged { heard.frames.append($0) }
                .node)

        let id = patch.events?["frameChanged"] ?? -1

        renders.fire(id, with: [])
        renders.fire(id, with: [.numbers([10, 20, 300, 400])])
        renders.fire(id, with: [.bool(true)])

        XCTAssertTrue(heard.frames.isEmpty, "an unreadable report reached the handler")
    }

    /// The handler is a handler: a `@State` write from one asks for a render,
    /// which is what lets the interface follow the measurement.
    func testTheHandlerMayWriteState() {
        let renders = Renders()
        let width = State(0.0)
        let reader = reading { _ = width.get() }
        defer { _ = reader }

        let patch = renders.render(
            VStack {}
                .onFrameChanged { width.wrappedValue = $0.width }
                .node)

        Renderer.shared.clearInvalidation()
        renders.fire(patch.events?["frameChanged"] ?? -1, with: payload)

        XCTAssertEqual(width.wrappedValue, 300)
        XCTAssertFalse(Renderer.shared.pendingChanges.isEmpty,
            "the measurement's write did not ask for a render")

        Renderer.shared.clearInvalidation()
    }

    // MARK: - The container

    /// A GeometryReader's content is built FROM the measurement: zero before the
    /// first report, the measured frame after - the closure running again
    /// because the report wrote the reader's own `@State`.
    func testAReadersContentIsBuiltFromTheMeasurement() {
        let renders = Renders()

        func tree() -> Node {
            Node(type: "WindowScene", children: [
                VStack {
                    GeometryReader { proxy in
                        Text("\(Int(proxy.size.width)) wide")
                    }
                }.node,
            ])
        }

        let first = renders.render(tree())

        // Before any report the closure was handed a zero rectangle.
        let grid = first.children.first?.children.first
        XCTAssertEqual(grid?.props["isGeometryReader"], .bool(true))
        XCTAssertEqual(grid?.children.first?.props["text"], .string("0 wide"))

        Renderer.shared.clearInvalidation()
        renders.fire(grid?.events?["frameChanged"] ?? -1, with: payload)

        // The report wrote the reader's @State; the next render builds the
        // content from the measured frame.
        let second = renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(second.children.first?.children.first?.children.first?.props["text"],
            .string("300 wide"),
            "the content did not follow the measurement")

        Renderer.shared.clearInvalidation()
    }

    /// The reason the container exists at all: the measurement lives in the
    /// READER's `@State`, so a settled frame rebuilds the reader's content and
    /// nothing else - a sibling is carried over untouched.
    func testAMeasurementRebuildsTheReaderAndNotItsSiblings() {
        let renders = Renders()

        func tree() -> Node {
            Node(type: "WindowScene", children: [
                VStack {
                    GeometryReader { proxy in
                        Text("\(Int(proxy.size.width)) wide")
                    }

                    Text("sibling")
                }.node,
            ])
        }

        let first = renders.render(tree())
        let grid = first.children.first?.children.first

        Renderer.shared.clearInvalidation()
        renders.fire(grid?.events?["frameChanged"] ?? -1, with: payload)

        // The tracked path, exactly what the host takes after the handler's
        // write: only the views whose recorded reads moved are built again.
        let patch = renders.revisit(changed: Renderer.shared.pendingChanges)

        func names(in patch: HostPatch) -> [NodeType] {
            [patch.type] + patch.children.flatMap { names(in: $0) }
        }

        let touched = names(in: patch)
        XCTAssertTrue(touched.contains("Text"), "the reader's content was not rebuilt")
        XCTAssertFalse(
            patch.children.first?.children.contains { $0.props["text"] == .string("sibling") } ?? false,
            "the sibling was rebuilt for a measurement it never read")

        Renderer.shared.clearInvalidation()
    }
}

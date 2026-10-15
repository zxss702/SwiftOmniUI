// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest
import CSwiftOmniUIGTK

/// The modified source mirrors a file tree beside an ordinary settings card.
@MainActor private final class ModifiedLazyBuilds {
    var calls = 0
    var numbers: Set<Int> = []
    var rows: [Int: ModifiedLazyInputRow] = [:]
}

private struct ModifiedLazyInputRow: View {
    let number: Int
    @State var words: String
    @FocusState var focused: Bool

    init(number: Int) {
        self.number = number
        _words = State(wrappedValue: "Row \(number)")
    }

    var body: some View {
        TextField("", text: $words)
            .focused($focused)
            .frame(height: 40)
            .id("row-\(number)")
    }
}

private struct ModifiedLazyPage: View {
    let items: [Int]
    let builds: ModifiedLazyBuilds

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("Settings")
                VStack(spacing: 4) {
                    ForEach(0..<2) { group in
                        Picker("Model \(group)", selection: Binding(get: { 0 }, set: { _ in })) {
                            ForEach(0..<12) { option in Text("Option \(option)").tag(option) }
                                .transition(.opacity)
                        }
                    }
                }
                .frame(height: 64)
                ForEach(items) { number in
                    builds.numbers.insert(number)
                    let row = ModifiedLazyInputRow(number: number)
                    builds.rows[number] = row
                    return row
                }
                .transition(.blur.combined(with: .offset(y: -48)))
            }
            .padding(8)
        }
        .frame(width: 320, height: 320)
    }
}

/// A `LazyVStack` on GTK answers the same window questions as everywhere:
/// the rows the scroller's reach holds are mounted, and no more.
final class GTKLazyTests: XCTestCase {
    func testFolderChangesShareSourcesAndKeepNativeWorkBoundedAsTheTreeGrows() throws {
        try onUIThread {
            for count in [10_000, 100_000] {
                let rows = State(wrappedValue: Array(0..<count))
                let builds = ModifiedLazyBuilds()
                let host = GTKRenderer.running(reducesMotion: true) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows.wrappedValue) { number in
                                builds.numbers.insert(number)
                                return Text("File \(number)").frame(height: 28)
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(width: 320, height: 240)
                }
                for _ in 0..<12 { host.step(); host.frame() }
                let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
                let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
                let source = try XCTUnwrap(lazy.cells.element?.lazyRows)
                let identity = source.sequence[3]
                let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
                XCTAssertLessThan(builds.numbers.count, 80)
                withAnimation(.eased(200, .linear)) {
                    rows.wrappedValue.insert(contentsOf: count..<(count + 100), at: 5)
                }
                for _ in 0..<12 { host.step(); host.frame() }
                let expanded = try XCTUnwrap(lazy.cells.element?.lazyRows)
                XCTAssertEqual(expanded.predecessor, ObjectIdentifier(source))
                XCTAssertEqual(expanded.inserted.count, 100)
                XCTAssertEqual(lazy.cells.orderedIdentities.count, count + 100)
                XCTAssertEqual(lazy.cells.position(of: identity), 3)
                XCTAssertNil(lazy.cells.element?.value(.items))
                XCTAssertTrue(lazy.mounted[identity]?.view === retained)
                XCTAssertLessThan(lazy.mounted.count, 80)
                XCTAssertLessThan(builds.numbers.count, 120, "offscreen inserted views must stay unbuilt")

                // A distant jump followed by a reversal must not let an old
                // optional request restore the previous window or retain its seats.
                scroll.scroller.move(to: Point(0, 4_000))
                for _ in 0..<12 { host.step(); host.frame() }
                scroll.scroller.move(to: Point(0, 800))
                for _ in 0..<12 { host.step(); host.frame() }
                let span = try XCTUnwrap(lazy.span)
                let visible = lazy.cells.places(in: span, overscan: 0)
                XCTAssertFalse(visible.isEmpty)
                for place in visible {
                    let item = try XCTUnwrap(lazy.mounted[lazy.cells.orderedIdentities[place]])
                    XCTAssertGreaterThan(item.view.frame.height, 0)
                    XCTAssertGreaterThan(item.view.frame.width, 0)
                }
                XCTAssertNil(lazy.mounted[identity])
                XCTAssertLessThan(lazy.mounted.count, 80)
            }
        }
    }

    func testWithAnimationMovesLazyInsertionsAndDoesNotAnimateLaterScrolling() throws {
        try onUIThread {
            let rows = State(wrappedValue: Array(0..<1_000))
            let clock = TestClock()
            let host = GTKRenderer.running(clock: clock) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.wrappedValue) { number in
                            Text("File \(number)")
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 320, height: 240)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            host.runtime.layoutMotion.applicationMotion = .none
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            let identity = lazy.cells.orderedIdentities[4]
            let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
            let before = retained.placedFrame.y
            withAnimation(.eased(200, .linear)) { rows.wrappedValue.insert(-1, at: 0) }
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertTrue(lazy.mounted[identity]?.view === retained)
            clock.now = 100
            for _ in 0..<4 { host.frame(); host.step() }
            XCTAssertEqual(retained.placedFrame.y, before + 14, accuracy: 1)
            clock.now = 200
            for _ in 0..<4 { host.frame(); host.step() }
            XCTAssertEqual(retained.placedFrame.y, before + 28, accuracy: 1)
            let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
            scroll.scroller.move(to: Point(0, 4_000))
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertFalse(host.runtime.animator.isMoving, "scroll recycling must not inherit a data insertion transaction")
            XCTAssertLessThan(lazy.mounted.count, 80)
            for item in lazy.mounted.values { XCTAssertEqual(item.view.drawnOpacity, 1, accuracy: 0.01) }
        }
    }

    func testGraphRowsReleaseOffscreenViewsAndNeverBuildClosedDetails() throws {
        try onUIThread {
            let builds = ModifiedLazyBuilds()
            let host = GTKRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<10_000) { number in
                            HStack(spacing: 0) {
                                Canvas { context, size in
                                    context.fill(Path(Rect(0, 0, size.width, size.height)), with: .color(Color("#FF0000")))
                                    var path = Path()
                                    path.move(to: Point(16, 0))
                                    path.addCurve(to: Point(48, size.height),
                                                  control1: Point(16, 16), control2: Point(48, 16))
                                    context.stroke(path, with: .color(.white), lineWidth: 2)
                                }
                                .frame(width: 100, height: 32)
                                Text("Commit \(number)")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .popover(isPresented: Binding(get: { false }, set: { _ in })) {
                                builds.calls += 1
                                return Text("Hidden detail")
                                    .onAppear { builds.numbers.insert(number) }
                            }
                        }
                    }
                }
                .frame(width: 320, height: 240)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
            let baseline = GTKView.liveCount
            weak var departed: GTKView? = lazy.mounted.values.first?.view
            XCTAssertNotNil(departed)
            for offset in stride(from: 4_000.0, through: 24_000.0, by: 4_000) {
                scroll.scroller.move(to: Point(0, offset))
                for _ in 0..<12 { host.step(); host.frame() }
                XCTAssertNil(departed, "offscreen native rows must be released rather than retained by scroll history")
                XCTAssertLessThan(lazy.mounted.count, 80)
                XCTAssertLessThan(GTKView.liveCount, baseline + 300, "the live tree stays bounded by the viewport")
                XCTAssertEqual(builds.calls, 0, "closed details must not build during initialization or recycling")
                XCTAssertTrue(builds.numbers.isEmpty, "closed details must not start their onAppear work")
                XCTAssertEqual(host.views(GTKCanvasView.self).count, lazy.mounted.count)
                let canvas = try XCTUnwrap(host.views(GTKCanvasView.self).first)
                let pixels = GTKTestHost.pixels(of: canvas.widget, at: [(8, 16)])
                XCTAssertEqual(pixels, [0xFFFF0000], "newly realized graph rows have painted their native surface")
            }
        }
    }

    func testFolderExpansionRetainsSurvivingRowMeasurements() throws {
        try onUIThread {
            let original = Array(0..<1_000)
            let rows = State(wrappedValue: original)
            let host = GTKRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.wrappedValue) { number in
                            HStack {
                                Text("File \(number)")
                                Text("Kind").font(.caption)
                            }
                            .frame(height: 40)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 320, height: 240)
            }
            for _ in 0..<12 { host.step() }
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            for list in [Array(0..<3) + [1_000, 1_001] + Array(3..<1_000), original] {
                let before = lazy.cells.measurements
                let held = lazy.mounted.mapValues(\.view)
                rows.wrappedValue = list
                for _ in 0..<12 { host.step() }
                let incoming = lazy.mounted.filter { held[$0.key] !== $0.value.view }
                XCTAssertEqual(lazy.cells.measurements - before, incoming.count,
                               "a new content closure must not discard unchanged rows' sizes")
                for (identity, view) in held where lazy.mounted[identity] != nil {
                    XCTAssertTrue(lazy.mounted[identity]?.view === view)
                }
            }
        }
    }

    func testFolderAnimationFramesReuseRowsAndMeasurements() throws {
        try onUIThread {
            let original = Array(0..<1_000)
            let rows = State(wrappedValue: original)
            let builds = ModifiedLazyBuilds()
            let clock = TestClock()
            let host = GTKRenderer.running(clock: clock) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.wrappedValue) { number in
                            builds.calls += 1
                            builds.numbers.insert(number)
                            return Button {} label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text("File \(number)")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(height: 28)
                        }
                        .transition(.opacity.combined(with: .offset(y: -48)))
                    }
                    .animation(.eased(200, .linear))
                }
                .frame(width: 320, height: 240)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            clock.now += 200
            for _ in 0..<12 { host.step(); host.frame() }
            let identity = lazy.cells.orderedIdentities[6]
            let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
            let initialY = retained.placedFrame.y
            for expanded in [true, false] {
                let began = clock.now
                let before = retained.placedFrame.y
                rows.wrappedValue = expanded
                    ? Array(0..<3) + [1_000, 1_001] + Array(3..<1_000) : original
                for _ in 0..<12 { host.step(); host.frame() }
                let measurements = lazy.cells.measurements
                let descriptions = builds.calls
                let target = initialY + (expanded ? 56 : 0)
                for tick in stride(from: 20.0, through: 180.0, by: 20) {
                    clock.now = began + tick
                    host.frame()
                    host.step()
                    XCTAssertTrue(lazy.mounted[identity]?.view === retained)
                    XCTAssertEqual(retained.placedFrame.y, before + (target - before) * tick / 200, accuracy: 1)
                    XCTAssertEqual(lazy.cells.measurements, measurements, "moving rows reuse their measured sizes")
                    XCTAssertEqual(builds.calls, descriptions, "animation ticks must not describe the row source")
                }
                clock.now = began + 200
                for _ in 0..<12 { host.step(); host.frame() }
                XCTAssertEqual(retained.placedFrame.y, target, accuracy: 1)
                XCTAssertLessThan(builds.numbers.count, 80, "only the viewport and its overscan are built")
            }
        }
    }

    func testNativeIntrinsicSizeChangesStillRefreshACachedLazyRow() throws {
        try onUIThread {
            let host = GTKRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<1_000) { number in
                            Text("File \(number)").frame(width: 120)
                        }
                    }
                }
                .frame(width: 160, height: 240)
            }
            for _ in 0..<12 { host.step() }
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            let identity = lazy.cells.orderedIdentities[0]
            let row = try XCTUnwrap(lazy.mounted[identity]?.view)
            let label = try XCTUnwrap(host.views(GTKTextView.self).first { $0.text == "File 0" })
            let before = lazy.cells.extents.extent(of: identity)
            // Exercise a native requisition change with no patch or lazy content revision.
            label.setText(String(repeating: "Words that wrap onto another line. ", count: 12))
            for _ in 0..<12 { host.step() }
            XCTAssertTrue(lazy.mounted[identity]?.view === row)
            XCTAssertGreaterThan(lazy.cells.extents.extent(of: identity), before)
            XCTAssertLessThan(lazy.mounted.count, 80)
        }
    }

    func testModifiedSourcesStayWindowedAcrossRepeatedPageSwitches() throws {
        try onUIThread {
            let showing = State(wrappedValue: true)
            let builds = ModifiedLazyBuilds()
            let host = GTKRenderer.running(reducesMotion: true) {
                if showing.wrappedValue {
                    ModifiedLazyPage(items: Array(0..<10_000), builds: builds)
                } else {
                    Text("Other page")
                }
            }
            for _ in 0..<8 { host.step() }
            for visit in 0..<3 {
                if visit > 0 {
                    showing.wrappedValue = false
                    for _ in 0..<8 { host.step() }
                    XCTAssertTrue(host.views(GTKTextFieldView.self).isEmpty)
                    builds.numbers.removeAll()
                    showing.wrappedValue = true
                    for _ in 0..<8 { host.step() }
                }
                XCTAssertFalse(builds.numbers.isEmpty)
                XCTAssertLessThan(builds.numbers.count, 80, "each visit builds a viewport, not ten thousand rows")
                XCTAssertEqual(host.views(GTKPickerView.self).count, 2, "ordinary grouped controls still expand")
                let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
                XCTAssertEqual(lazy.cells.orderedIdentities.count, 10_002)
                XCTAssertLessThan(lazy.mounted.count, 80)
                let work = [lazy.cells.requests, lazy.cells.measurements]
                for _ in 0..<4 { host.step() }
                XCTAssertEqual([lazy.cells.requests, lazy.cells.measurements], work, "idle layout reuses the window")
            }
        }
    }

    func testModifiedSourceUpdatesKeepNativeInputStateAndFocus() throws {
        try onUIThread {
            let original = Array(0..<10_000)
            let items = State(wrappedValue: original)
            let builds = ModifiedLazyBuilds()
            let host = GTKRenderer.running(reducesMotion: true) {
                ModifiedLazyPage(items: items.wrappedValue, builds: builds)
            }
            for _ in 0..<8 { host.step() }
            let field = try XCTUnwrap(host.views(GTKTextFieldView.self).first { $0.text == "Row 1" })
            XCTAssertNotEqual(gtk_widget_grab_focus(field.widget), 0)
            host.settle { builds.rows[1]?.focused == true }
            field.type("Edited")
            for _ in 0..<8 { host.step() }
            XCTAssertEqual(builds.rows[1]?.words, "Edited")

            for changed in [[0, 1, 10_000, 10_001] + Array(2..<10_000), original, [0, 2, 1] + Array(3..<10_000)] {
                builds.numbers.removeAll()
                items.wrappedValue = changed
                for _ in 0..<8 { host.step() }
                XCTAssertLessThan(builds.numbers.count, 80, "updates do not build the offscreen source")
                XCTAssertTrue(host.views(GTKTextFieldView.self).contains { $0 === field })
                XCTAssertEqual(field.text, "Edited")
                XCTAssertEqual(builds.rows[1]?.words, "Edited")
                XCTAssertEqual(builds.rows[1]?.focused, true)
                let root = try XCTUnwrap(gtk_widget_get_root(field.widget))
                let focused = try XCTUnwrap(gtk_root_get_focus(root))
                XCTAssertTrue(focused == field.widget || gtk_widget_is_ancestor(focused, field.widget) != 0)
            }
        }
    }

    func testAddingToAnEmptyLazyStackRunsTheInsertionTransition() throws {
        try onUIThread {
            let clock = TestClock()
            let rows = State(wrappedValue: [Int]())
            let host = GTKRenderer.running(clock: clock) {
                LazyVStack(spacing: 0) {
                    ForEach(rows.wrappedValue) { number in
                        Text("Row \(number)").frame(height: 40)
                    }
                }
                .animation(.eased(200, .linear))
                .frame(width: 240, height: 240)
            }

            for _ in 0..<8 { host.step() }
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            for number in 0..<2 {
                rows.wrappedValue = [number]
                for _ in 0..<8 { host.step() }
                let row = try XCTUnwrap(lazy.mounted.values.first?.view)
                XCTAssertEqual(row.drawnOpacity, 0, accuracy: 0.01)
                clock.now += 100
                for _ in 0..<8 { host.step() }
                XCTAssertEqual(row.drawnOpacity, 0.5, accuracy: 0.01)
                clock.now += 100
                for _ in 0..<8 { host.step() }
                XCTAssertEqual(row.drawnOpacity, 1, accuracy: 0.01)
                rows.wrappedValue = []
                for _ in 0..<8 { host.step() }
            }

        }
    }

    func testDeletingBeforeTheViewportKeepsThePresentedAnchor() throws {
        try onUIThread {
            for kind in 0..<4 {
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 2
                let clock = TestClock()
                let rows = State(wrappedValue: Array(0..<100))
                let host = GTKRenderer.running(clock: clock) {
                    let content = ForEach(rows.wrappedValue) { number in
                        Text("Row \(number)").frame(width: 40, height: 40)
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        Group {
                            if kind == 0 { LazyVStack(spacing: 0) { content } }
                            else if kind == 1 { LazyHStack(spacing: 0) { content } }
                            else if kind == 2 {
                                LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            } else {
                                LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            }
                        }
                        .animation(.eased(200, .linear))
                    }
                    .frame(width: 240, height: 240)
                }

                for _ in 0..<8 { host.step() }
                let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
                let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
                scroll.scroller.move(to: Point(horizontal ? 400 : 0, horizontal ? 0 : 400))
                for _ in 0..<8 { host.step() }
                let identity = lazy.cells.orderedIdentities[10 * perRun]
                let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
                for removed in [11, 9, 0] {
                    let relative = (horizontal ? retained.placedFrame.x : retained.placedFrame.y)
                        - (horizontal ? scroll.scroller.standing.offset.x : scroll.scroller.standing.offset.y)
                    let began = clock.now
                    rows.wrappedValue.removeAll { (removed * perRun..<((removed + 1) * perRun)).contains($0) }
                    for tick in stride(from: 0.0, through: 240.0, by: 40) {
                        clock.now = began + tick
                        for _ in 0..<8 {
                            host.step()
                            XCTAssertEqual((horizontal ? retained.placedFrame.x : retained.placedFrame.y)
                                           - (horizontal ? scroll.scroller.standing.offset.x : scroll.scroller.standing.offset.y),
                                           relative, accuracy: 1,
                                           "removing \(removed), at \(tick) ms must keep the visible anchor in place")
                        }
                    }
                }
            }
        }
    }

    func testDataChangesAnimateInEveryLazyDirection() throws {
        try onUIThread {
            for kind in 0..<4 {
                let clock = TestClock()
                let rows = State(wrappedValue: Array(0..<40))
                let extent = State(wrappedValue: 40.0)
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 2
                let host = GTKRenderer.running(clock: clock) {
                    let content = ForEach(rows.wrappedValue) { number in
                        ResizingLazyRow(number: number, varies: number < perRun,
                                        horizontal: horizontal, extent: extent.projectedValue)
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        Group {
                            if kind == 0 { LazyVStack(spacing: 0) { content } }
                            else if kind == 1 { LazyHStack(spacing: 0) { content } }
                            else if kind == 2 {
                                LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            } else {
                                LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            }
                        }
                        .animation(.eased(200, .linear))
                    }
                    .frame(width: 240, height: 240)
                }
                for _ in 0..<8 { host.step() }
                let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
                let identity = lazy.cells.orderedIdentities[perRun * 2]
                let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
                for operation in 0..<5 {
                    let before = horizontal ? retained.placedFrame.x : retained.placedFrame.y
                    let began = clock.now
                    let leaving = lazy.mounted[lazy.cells.orderedIdentities[perRun]]?.view
                    if operation == 0 { rows.wrappedValue.removeSubrange(perRun..<perRun * 2) }
                    else if operation == 1 { rows.wrappedValue.insert(contentsOf: 100..<100 + perRun, at: perRun) }
                    else if operation == 2 { rows.wrappedValue.swapAt(perRun * 2, perRun * 3) }
                    else if operation == 3 { extent.wrappedValue = 80 }
                    else { extent.wrappedValue = 40 }
                    for _ in 0..<8 { host.step() }
                    let joining = operation == 1 ? lazy.mounted[lazy.cells.orderedIdentities[perRun]]?.view : nil
                    if operation == 0 { XCTAssertEqual(try XCTUnwrap(leaving).drawnOpacity, 1, accuracy: 0.01) }
                    if let joining { XCTAssertEqual(joining.drawnOpacity, 0, accuracy: 0.01) }
                    let target = before + (operation == 0 || operation == 4 ? -40 : 40)
                    XCTAssertEqual(horizontal ? retained.placedFrame.x : retained.placedFrame.y, before, accuracy: 1,
                                   "kind \(kind), operation \(operation) must start at the old position")
                    clock.now = began + 100
                    for _ in 0..<8 { host.step() }
                    XCTAssertEqual(horizontal ? retained.placedFrame.x : retained.placedFrame.y, (before + target) / 2, accuracy: 1,
                                   "kind \(kind), operation \(operation) must pass through the midpoint")
                    if operation == 0 { XCTAssertEqual(try XCTUnwrap(leaving).drawnOpacity, 0.5, accuracy: 0.01) }
                    if let joining { XCTAssertEqual(joining.drawnOpacity, 0.5, accuracy: 0.01) }
                    clock.now = began + 200
                    for _ in 0..<8 { host.step() }
                    XCTAssertEqual(horizontal ? retained.placedFrame.x : retained.placedFrame.y, target, accuracy: 1)
                    XCTAssertTrue(lazy.mounted[identity]?.view === retained)
                    if let joining { XCTAssertEqual(joining.drawnOpacity, 1, accuracy: 0.01) }
                }
                let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
                scroll.scroller.move(to: Point(horizontal ? 480 : 0, horizontal ? 0 : 480))
                for _ in 0..<8 { host.step() }
                XCTAssertFalse(host.runtime.animator.isMoving, "scrolling must not start data transitions")
                for item in lazy.mounted.values { XCTAssertEqual(item.view.drawnOpacity, 1, accuracy: 0.01) }

            }
        }
    }

    func testGalleryShelvesKeepTheOfferedWidthThroughComposedRows() throws {
        try onUIThread {
            let standing = State(wrappedValue: 0)
            let host = GTKRenderer.running {
                VStack {
                    Text("\(standing.wrappedValue) tiles standing")
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(0..<24) { shelf in
                                GalleryShelf(number: shelf, standing: standing.projectedValue)
                            }
                        }
                    }
                }
                .spacing(10)
                .contentPadding(16)
            }
            for _ in 0..<30 { host.step() }
            let outer = try XCTUnwrap(host.views(GTKScrollView.self).first)
            for width in [560.0, 1_000, 700] {
                host.window?.setSize(width: width, height: 600)
                for _ in 0..<30 { host.step() }
                let scrolls = host.views(GTKScrollView.self)
                XCTAssertGreaterThan(scrolls.count, 2)
                for scroll in scrolls.dropFirst() {
                    XCTAssertEqual(scroll.frame.width, outer.frame.width, accuracy: 1,
                                   "a composed shelf must receive the vertical viewport's width")
                    let row = try XCTUnwrap(host.views(GTKLazyStackView.self).first {
                        $0.placingLayout === scroll.scroller.content
                    })
                    let measured = row.cells.orderedIdentities.filter { row.cells.extents.hasMeasurement(for: $0) }.count
                    XCTAssertEqual(scroll.scroller.standing.reach.x + scroll.frame.width,
                                   Double(measured) * 96 + Double(40 - measured) * 44 + 39 * 8, accuracy: 1)
                }
                outer.scroller.move(to: outer.scroller.standing.reach)
                for _ in 0..<30 { host.step() }
                XCTAssertTrue(host.views(GTKLabelView.self).contains { $0.text == "Shelf 23" })
                outer.scroller.move(to: .zero)
                for _ in 0..<20 { host.step() }
            }
        }
    }

    func testGalleryAdaptiveGridDocumentEndsAtTheLastRowAfterResizeAndDeletion() throws {
        try onUIThread {
            let standing = State(wrappedValue: 0)
            let rows = State(wrappedValue: Array(0..<500))
            let height = State(wrappedValue: 64.0)
            let host = GTKRenderer.running {
                VStack {
                    Text("\(standing.wrappedValue) standing")
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(rows.wrappedValue) { cell in
                                Text("Cell \(cell)")
                                    .frame(height: height.wrappedValue)
                                    .frame(maxWidth: .infinity)
                                    .background(Color("#FF0000"))
                                    .onAppear { standing.wrappedValue += 1 }
                                    .onDisappear { standing.wrappedValue -= 1 }
                            }
                        }
                    }
                }
                .spacing(10)
                .contentPadding(16)
            }
            for _ in 0..<30 { host.step() }
            let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
            let grid = try XCTUnwrap(host.views(GTKLazyGridView.self).first)
            for (width, cellHeight, remove) in [(560.0, 64.0, 0), (1_000, 64, 0), (700, 88, 7), (560, 32, 11)] {
                host.window?.setSize(width: width, height: 600)
                height.wrappedValue = cellHeight
                rows.wrappedValue.removeFirst(remove)
                for _ in 0..<30 { host.step() }
                let tracks = Int((scroll.frame.width + 10) / 106)
                let runs = (rows.wrappedValue.count + tracks - 1) / tracks
                XCTAssertEqual(grid.cells.window?.perRun, tracks)
                XCTAssertEqual(scroll.scroller.standing.reach.y + scroll.frame.height,
                               grid.cells.runs.total(count: runs), accuracy: 1)
                scroll.scroller.move(to: scroll.scroller.standing.reach)
                for _ in 0..<30 { host.step() }
                XCTAssertTrue(host.views(GTKLabelView.self).contains { $0.text == "Cell 499" })
                let identity = try XCTUnwrap(grid.cells.orderedIdentities.last)
                let last = try XCTUnwrap(grid.mounted[identity]?.view)
                var bottom = graphene_point_t(x: Float(last.frame.width / 2), y: Float(last.frame.height))
                var inGrid = graphene_point_t()
                XCTAssertNotEqual(gtk_widget_compute_point(last.widget, grid.widget, &bottom, &inGrid), 0)
                XCTAssertEqual(Double(inGrid.y), grid.cells.runs.total(count: runs), accuracy: 1)
                var inScroll = graphene_point_t()
                XCTAssertNotEqual(gtk_widget_compute_point(last.widget, scroll.widget, &bottom, &inScroll), 0)
                XCTAssertEqual(Double(inScroll.y),
                               scroll.frame.height, accuracy: 1,
                               "the last rendered row must meet the viewport's bottom without an empty tail")
                let colors = GTKTestHost.pixels(of: scroll.widget, at: [
                    (Double(inScroll.x), scroll.frame.height - 4),
                ])
                XCTAssertEqual(colors, [0xFFFF0000], "GTK must paint the last cell at the actual viewport bottom")
            }
        }
    }

    func testExactWindowsReachIdentityAndIdleInEveryDirection() throws {
        try onUIThread {
            for kind in 0..<4 {
                let host = GTKRenderer.running { ExactLazyPage(kind: kind) }
                for _ in 0..<30 { host.step() }
                let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
                let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 4
                let extent = horizontal ? 80.0 : 40.0
                let viewport = horizontal ? scroll.frame.width : scroll.frame.height
                // Supply exact fixture geometry without building offscreen
                // controls; this test exercises window identity and idle reuse.
                if kind < 2 {
                    for identity in lazy.cells.orderedIdentities { lazy.cells.extents.measure(identity, extent: extent) }
                } else {
                    for run in 0..<(1_000 / perRun) { lazy.cells.runs.measure(run, extent: extent) }
                }
                lazy.invalidateMeasurements()
                for _ in 0..<8 { host.step() }
                let reach = scroll.scroller.standing.reach
                XCTAssertEqual(viewport, horizontal ? 480 : 240, accuracy: 1)
                XCTAssertEqual(horizontal ? reach.x : reach.y,
                               1_000 / Double(perRun) * extent - viewport, accuracy: 1)
                var previous: [String: GTKView] = [:]
                for offset in [0.0, extent * 20, extent * 21, extent * 21 + 1,
                               extent * 20, extent * 150, extent * 5, 0] {
                    scroll.scroller.move(to: Point(horizontal ? offset : 0, horizontal ? 0 : offset))
                    for _ in 0..<6 { host.step() }
                    let span = try XCTUnwrap(lazy.span)
                    let first = Int((span.lowerBound / extent).rounded(.down))
                    let last = Int((span.upperBound / extent).rounded(.up))
                    let visible = max(0, first - 1) * perRun..<min(1_000, (last + 1) * perRun)
                    let margin = Int(viewport / extent)
                    let target = max(0, first - 1 - margin) * perRun..<min(1_000, (last + 1 + margin) * perRun)
                    XCTAssertLessThanOrEqual(lazy.cells.built.lowerBound, visible.lowerBound)
                    XCTAssertGreaterThanOrEqual(lazy.cells.built.upperBound, visible.upperBound)
                    XCTAssertGreaterThanOrEqual(lazy.cells.built.lowerBound, target.lowerBound)
                    XCTAssertLessThanOrEqual(lazy.cells.built.upperBound, target.upperBound)
                    XCTAssertEqual(lazy.mounted.count, lazy.cells.built.count)
                    for (identity, item) in lazy.mounted {
                        if let kept = previous[identity] { XCTAssertTrue(kept === item.view) }
                        XCTAssertGreaterThan(item.view.frame.width, 0)
                        XCTAssertGreaterThan(item.view.frame.height, 0)
                    }
                    previous = lazy.mounted.mapValues(\.view)
                    if kind == 1 && offset == 1_600 { XCTAssertGreaterThanOrEqual(lazy.mounted.count, 8) }
                }
                for _ in 0..<48 where host.runtime.lazyPrefetch.isPending {
                    host.runtime.lazyPrefetch.drain(until: ContinuousClock.now.advanced(by: .seconds(1)))
                    host.step()
                }
                let work = [lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements]
                for _ in 0..<200 { host.step() }
                XCTAssertEqual([lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements], work,
                               "stationary kind \(kind) must not recalculate")
            }
        }
    }

    func testNaturalRowsRetainSubtreesAndRenderThroughContinuousScroll() throws {
        try onUIThread {
            let host = GTKRenderer.running { NaturalLazyPage() }
            for _ in 0..<40 { host.step() }
            let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(GTKLazyStackView.self).first)
            XCTAssertGreaterThan(scroll.frame.height, 200)
            XCTAssertLessThan(scroll.frame.height, 400)
            XCTAssertGreaterThan(scroll.scroller.standing.reach.y, 20_000)
            let row = try XCTUnwrap(host.views(GTKLabelView.self).first { $0.text == "Row 2" })
            let button = try XCTUnwrap(host.views(GTKButtonView.self).first { $0.text == "Delete 1" })
            button.click()
            for _ in 0..<40 {
                host.step()
                XCTAssertTrue(host.views(GTKLabelView.self).first { $0.text == "Row 2" } === row)
                XCTAssertEqual(row.opacity, 1)
            }
            for offset in stride(from: 0.0, through: 2_000.0, by: 80) {
                scroll.scroller.move(to: Point(0, offset))
                for _ in 0..<3 { host.step() }
                let span = try XCTUnwrap(lazy.span)
                let visible = lazy.cells.places(in: span, overscan: 0)
                XCTAssertFalse(visible.isEmpty)
                for place in visible {
                    let item = try XCTUnwrap(lazy.mounted[lazy.cells.orderedIdentities[place]])
                    XCTAssertEqual(item.view.opacity, 1)
                    XCTAssertGreaterThan(item.view.frame.height, 0)
                }
                // Sample the actual GTK renderer, not merely the backing layout geometry.
                let middle = visible.lowerBound + visible.count / 2
                let painted = try XCTUnwrap(lazy.mounted[lazy.cells.orderedIdentities[middle]])
                let point = (painted.view.frame.x + 3,
                             painted.view.frame.y - span.lowerBound + painted.view.frame.height / 2)
                let colors = GTKTestHost.pixels(of: scroll.widget, at: [point])
                XCTAssertTrue(colors.contains {
                    ($0 >> 24) == 255 && (($0 >> 16) & 255) >= 220 && ($0 & 0xFFFF) == 0
                },
                              "offset \(offset), point \(point), pixels \(colors)")
            }
            scroll.scroller.move(to: scroll.scroller.standing.reach)
            for _ in 0..<40 { host.step() }
            for _ in 0..<6 {
                try XCTUnwrap(host.views(GTKButtonView.self).last).click()
                for _ in 0..<40 { host.step() }
                let standing = scroll.scroller.standing
                XCTAssertEqual(standing.offset.y, standing.reach.y, accuracy: 1)
                XCTAssertEqual(standing.reach.y + scroll.frame.height, lazy.cells.total, accuracy: 1)
                let last = try XCTUnwrap(lazy.mounted[lazy.cells.orderedIdentities.last!]?.view)
                XCTAssertEqual(last.frame.y + last.frame.height, lazy.cells.total, accuracy: 1)
            }
            for _ in 0..<10 { host.step() }
            let work = [lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements]
            for _ in 0..<200 { host.step() }
            XCTAssertEqual([lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements], work)
        }
    }

    func testMixedSizesAndLeadingDeletionCanStillReachTheEnd() throws {
        try onUIThread {
            for kind in 0..<4 {
                let host = GTKRenderer.running { UnevenLazyPage(kind: kind, mixed: true) }
                for _ in 0..<40 { host.step() }
                let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
                let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
                let horizontal = kind % 2 == 1
                let drop = try XCTUnwrap(host.views(GTKButtonView.self).first { $0.text == "Drop ten" })
                drop.click()
                for _ in 0..<40 { host.step() }
                for action in ["Original", "Grow", "Shrink"] {
                    if action != "Original" {
                        let button = try XCTUnwrap(host.views(GTKButtonView.self).first { $0.text == action })
                        button.click()
                        for _ in 0..<40 { host.step() }
                    }
                    for offset in stride(from: 0.0, through: 1_000.0, by: 160) {
                        scroll.scroller.move(to: Point(horizontal ? offset : 0, horizontal ? 0 : offset))
                        for _ in 0..<4 { host.step() }
                    }
                    scroll.scroller.move(to: scroll.scroller.standing.reach)
                    for _ in 0..<40 { host.step() }
                    let span = try XCTUnwrap(lazy.span)
                    let last = try XCTUnwrap(lazy.mounted[lazy.cells.orderedIdentities.last!]?.view,
                                            "kind \(kind), \(action)")
                    let start = horizontal ? last.frame.x : last.frame.y
                    let extent = horizontal ? last.frame.width : last.frame.height
                    XCTAssertLessThan(start, span.upperBound)
                    XCTAssertGreaterThan(start + extent, span.lowerBound)
                    let standing = scroll.scroller.standing
                    let total = kind < 2 ? lazy.cells.total
                        : lazy.cells.runs.total(count: (lazy.cells.orderedIdentities.count + 3) / 4)
                    XCTAssertEqual((horizontal ? standing.reach.x : standing.reach.y)
                                   + (horizontal ? scroll.frame.width : scroll.frame.height), total, accuracy: 1,
                                   "kind \(kind), \(action): the native document must shrink with the content")
                    XCTAssertEqual(horizontal ? standing.offset.x : standing.offset.y,
                                   horizontal ? standing.reach.x : standing.reach.y, accuracy: 1)
                    for _ in 0..<40 { host.step() }
                    XCTAssertEqual(scroll.scroller.standing.offset, standing.offset)
                }
            }
        }
    }

    /// Of a thousand rows a window's worth are built, and no more.
    func testOnlyTheWindowedRowsAreBuilt() throws {
        try onUIThread {
            let host = GTKRenderer.running { LazyRowsPage() }
            host.settle { host.views(GTKLabelView.self).count > 4 }

            XCTAssertLessThan(host.views(GTKLabelView.self).count, 60, "a window's reach of a thousand rows")
        }
    }

    /// Scrolling asks the rows the window moved to be built, and lets the
    /// ones it left go.
    func testScrollingBuildsAheadAndLetsGoBehind() throws {
        try onUIThread {
            let host = GTKRenderer.running { LazyRowsPage() }
            let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
            host.settle { host.views(GTKLabelView.self).contains { $0.text == "Row 0" } }

            let lazy = try XCTUnwrap(host.views(GTKLazyStackView.self).first)
            scroll.scroller.move(to: Point(0, lazy.cells.offset(of: 500)))
            host.settle { host.views(GTKLabelView.self).contains { $0.text == "Row 500" } }

            let standing = host.views(GTKLabelView.self).map(\.text)
            XCTAssertFalse(standing.contains("Row 0"), "the first row was let go")
            XCTAssertLessThan(standing.count, 150, "still a window's reach")
        }
    }

    /// The room is the run's whole length before most of its rows exist.
    func testTheScrollRoomIsTheWholeRunAtOnce() throws {
        try onUIThread {
            let host = GTKRenderer.running { LazyRowsPage() }
            host.settle { host.views(GTKLabelView.self).count > 4 }

            // Known rows replace only their own forty-four-point estimates.
            let lazy = try XCTUnwrap(host.views(GTKLazyStackView.self).first)
            let measured = lazy.cells.orderedIdentities.filter { lazy.cells.extents.hasMeasurement(for: $0) }.count
            XCTAssertLessThan(measured, lazy.cells.orderedIdentities.count)
            XCTAssertEqual(lazy.frame.height, Double(measured) * 40 + Double(1_000 - measured) * 44, accuracy: 1)
        }
    }

    /// Outside a scroller there is no window to narrow by: every child is
    /// built, as a plain stack's would be.
    func testALazyStackWithNoScrollerBuildsAll() throws {
        try onUIThread {
            let host = GTKRenderer.running { LazyRowsPage(count: 30, scrolls: false) }
            host.settle { host.views(GTKLabelView.self).count == 30 }

            XCTAssertEqual(host.views(GTKLabelView.self).count, 30)
        }
    }
}

/// A thousand forty-point rows in a scroller - or thirty, where it does not
/// scroll.
private struct LazyRowsPage: View {
    var count = 1_000
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count) { row in
                        Text("Row \(row)").frame(height: 40)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(0..<count) { row in
                    Text("Row \(row)").frame(height: 40)
                }
            }
        }
    }
}

private struct ExactLazyPage: View {
    let kind: Int
    var count = 1_000

    var body: some View {
        ScrollView(kind % 2 == 1 ? .horizontal : .vertical) {
            if kind == 0 {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count) { Text("Row \($0)").frame(width: 80, height: 40) }
                }
            } else if kind == 1 {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count) { Text("Row \($0)").frame(width: 80, height: 40) }
                }
            } else if kind == 2 {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(80)), count: 4), spacing: 0) {
                    ForEach(0..<count) { Text("Row \($0)").frame(width: 80, height: 40) }
                }
            } else {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(40)), count: 4), spacing: 0) {
                    ForEach(0..<count) { Text("Row \($0)").frame(width: 80, height: 40) }
                }
            }
        }
        .frame(width: 480, height: 240)
    }
}


private struct NaturalLazyPage: View {
    @State private var standing: Set<Int> = []
    @State private var gone: Set<Int> = []

    var body: some View {
        Grid {
            VStack {
                Text("\(standing.count) standing")
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text("Header")
                        ForEach((0..<1_000).filter { !gone.contains($0) }) { row in
                            Grid {
                                Text("Row \(row)")
                                Button("Delete \(row)") { gone.insert(row) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color("#FF0000"))
                            .animation(.inherited)
                            .onAppear { standing.insert(row) }
                            .onDisappear { standing.remove(row) }
                        }
                        Text("Footer")
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

private struct UnevenLazyPage: View {
    let kind: Int
    let mixed: Bool
    @State private var rows: [Int]
    @State private var extra = 0.0
    @State private var standing: Set<Int> = []

    init(kind: Int, mixed: Bool, count: Int = 200) {
        self.kind = kind
        self.mixed = mixed
        _rows = State(wrappedValue: Array(0..<count))
    }

    var body: some View {
        VStack {
            HStack {
                Text("\(standing.count) standing")
                Button("Drop ten") { rows.removeFirst(10) }
                Button("Grow") { extra = 70 }
                Button("Shrink") { extra = -20 }
            }
            ScrollView(kind % 2 == 1 ? .horizontal : .vertical) {
                if kind == 0 {
                    LazyVStack(spacing: 3) {
                        ForEach(rows) { row in
                            Text("Row \(row)")
                                .frame(width: 80, height: 40 + (mixed ? Double(row % 7) * 9 : 0) + (row % 3 == 0 ? extra : 0))
                                .onAppear { standing.insert(row) }
                                .onDisappear { standing.remove(row) }
                        }
                    }
                } else if kind == 1 {
                    LazyHStack(spacing: 3) {
                        ForEach(rows) { row in
                            Text("Row \(row)")
                                .frame(width: 40 + (mixed ? Double(row % 7) * 9 : 0) + (row % 3 == 0 ? extra : 0), height: 40)
                                .onAppear { standing.insert(row) }
                                .onDisappear { standing.remove(row) }
                        }
                    }
                } else if kind == 2 {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(80)), count: 4), spacing: 3) {
                        ForEach(rows) { row in
                            Text("Row \(row)")
                                .frame(height: 40 + (mixed ? Double(row % 7) * 9 : 0) + (row % 3 == 0 ? extra : 0))
                                .onAppear { standing.insert(row) }
                                .onDisappear { standing.remove(row) }
                        }
                    }
                } else {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(40)), count: 4), spacing: 3) {
                        ForEach(rows) { row in
                            Text("Row \(row)")
                                .frame(width: 40 + (mixed ? Double(row % 7) * 9 : 0) + (row % 3 == 0 ? extra : 0))
                                .onAppear { standing.insert(row) }
                                .onDisappear { standing.remove(row) }
                        }
                    }
                }
            }
            .frame(width: 480, height: 240)
        }
    }
}

private struct GalleryShelf: View {
    let number: Int
    @Binding var standing: Int

    var body: some View {
        VStack {
            Text("Shelf \(number)").font(.system(size: 12)).horizontalAlignment(.start)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<40) { tile in
                        Text("\(number).\(tile)")
                            .frame(width: 96, height: 72)
                            .onAppear { standing += 1 }
                            .onDisappear { standing -= 1 }
                    }
                }
            }
            .frame(height: 88)
        }
    }
}

/// Its own state read changes the child without rebuilding the lazy source.
private struct ResizingLazyRow: View {
    let number: Int
    let varies: Bool
    let horizontal: Bool
    @Binding var extent: Double

    var body: some View {
        Text("Row \(number)")
            .frame(width: horizontal && varies ? extent : 40,
                   height: !horizontal && varies ? extent : 40)
            .transition(.opacity)
            .animation(.eased(200, .linear))
    }
}

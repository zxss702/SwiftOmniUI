// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

fileprivate struct BlockAnchorPayload: Equatable, Sendable {
    let id: String
    let bounds: Anchor<Rect>
    let textLayouts: Text.LayoutKey.Value
}

fileprivate struct SelectionBlocksKey: PreferenceKey {
    static let defaultValue: [BlockAnchorPayload] = []
    static func reduce(value: inout [BlockAnchorPayload], nextValue: () -> [BlockAnchorPayload]) {
        value.append(contentsOf: nextValue())
    }
}

fileprivate struct SelectionLayoutInput: Equatable, Sendable {
    let anchors: [BlockAnchorPayload]
    let size: Size
}

@Observable
@MainActor
fileprivate final class SelectionModel {
    var selectionRects: [Rect] = []
    var anchorRects: [Rect] = []
    var dragEvents: [String] = []
    var tapEvents: [String] = []
    var layoutUpdates = 0
    var lastAnchors: [BlockAnchorPayload] = []
    var lastContainerSize: Size = .zero
    var lastProxy: GeometryProxy?
}

final class GTKMarkdownSelectionTests: XCTestCase {

    private struct DelayedSelectableView: View {
        let model: SelectionModel
        @State private var showExtraBlock = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Button("Show Extra") {
                    showExtraBlock = true
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("First nested selectable line")
                                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                                    Color.clear
                                        .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                                            let nestedTexts = nested.flatMap { $0.textLayouts }
                                            Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                                                [BlockAnchorPayload(id: "inner-1", bounds: bounds, textLayouts: layouts.filter { !nestedTexts.contains($0) })]
                                            }
                                        }
                                }
                        }
                        .padding(.leading, 12)
                        .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                            Color.clear
                                .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                                    let nestedTexts = nested.flatMap { $0.textLayouts }
                                    Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                                        [BlockAnchorPayload(id: "outer-quote", bounds: bounds, textLayouts: layouts.filter { !nestedTexts.contains($0) })]
                                    }
                                }
                        }

                        if showExtraBlock {
                            Text("Delayed appended selectable line")
                                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                                    Color.clear
                                        .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                                            let nestedTexts = nested.flatMap { $0.textLayouts }
                                            Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                                                [BlockAnchorPayload(id: "delayed-2", bounds: bounds, textLayouts: layouts.filter { !nestedTexts.contains($0) })]
                                            }
                                        }
                                }
                        }
                    }
                    .frame(width: 400, height: 300, alignment: .topLeading)
                    .coordinateSpace(name: "SelectionDocumentSpace")
                    .overlay {
                        Canvas { context, _ in
                            for rect in model.selectionRects {
                                var path = Path()
                                path.addRect(rect)
                                context.fill(path, with: .color(Color("#B3D7FF")))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .backgroundPreferenceValue(SelectionBlocksKey.self) { anchors in
                        GeometryReader { geometry in
                            Color.clear
                                .onChange(of: SelectionLayoutInput(anchors: anchors, size: geometry.size), initial: true) { _, _ in
                                    model.layoutUpdates += 1
                                    model.lastAnchors = anchors
                                    model.lastContainerSize = geometry.size
                                    model.lastProxy = geometry
                                    model.anchorRects = anchors.map { geometry[$0.bounds] }
                                }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                model.dragEvents.append("drag:\(Int(value.startLocation.x)),\(Int(value.startLocation.y))->\(Int(value.location.x)),\(Int(value.location.y))")
                                model.selectionRects = [Rect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y), width: max(1, abs(value.location.x - value.startLocation.x)), height: 18)]
                            }
                            .onEnded { value in
                                model.dragEvents.append("ended:\(Int(value.location.x)),\(Int(value.location.y))")
                            }
                    )
                    .onTapGesture(count: 3) {
                        model.tapEvents.append("tap3")
                    }
                    .onTapGesture(count: 2) {
                        model.tapEvents.append("tap2")
                    }
                    .onTapGesture {
                        model.tapEvents.append("tap1")
                    }
                }
                .frame(width: 400, height: 300)
            }
            .frame(width: 500, height: 400)
        }
    }

    func testNestedDelayedMakeTextSelectableCanvasAndMultiTap() throws {
        onUIThread {
            let model = SelectionModel()
            let host = GTKRenderer.running {
                DelayedSelectableView(model: model)
            }

            host.settle {
                model.lastAnchors.count == 2
                    && model.anchorRects.allSatisfy { $0.width > 0 && $0.height > 0 }
                    && model.lastAnchors.flatMap(\.textLayouts).allSatisfy { !$0.isEmpty }
            }
            XCTAssertEqual(model.lastAnchors.count, 2)
            XCTAssertEqual(model.anchorRects.filter { $0.width <= 0 || $0.height <= 0 }.count, 0)

            // Trigger delayed block while container size remains 400x300.
            let button = host.views(GTKButtonView.self).first
            XCTAssertNotNil(button)
            button?.click()
            host.settle {
                model.lastAnchors.count == 3
                    && model.anchorRects.allSatisfy { $0.width > 0 && $0.height > 0 }
            }
            XCTAssertEqual(model.lastAnchors.count, 3)
            XCTAssertEqual(model.anchorRects.filter { $0.width <= 0 || $0.height <= 0 }.count, 0)

            // Verify stacked tap counts 1, 2, 3 dispatch individually.
            let tapTarget = host.views(GTKView.self).first { $0.hearing.contains(.taps) }
            XCTAssertNotNil(tapTarget)
            tapTarget?.heard(.tap(run: 1))
            tapTarget?.heard(.tap(run: 2))
            tapTarget?.heard(.tap(run: 3))
            host.settle { model.tapEvents.count == 3 }
            XCTAssertEqual(model.tapEvents, ["tap1", "tap2", "tap3"])

            // Verify DragGesture redraws Observable Canvas.
            let dragTarget = host.views(GTKView.self).first { $0.hearing.contains(.drags) }
            XCTAssertNotNil(dragTarget)
            dragTarget?.heard(.drag(.started, x: 0, y: 0, at: Point(x: 10, y: 10), from: Point(x: 10, y: 10)))
            dragTarget?.heard(.drag(.running, x: 90, y: 4, at: Point(x: 100, y: 14), from: Point(x: 10, y: 10)))
            host.settle { !model.dragEvents.isEmpty && host.views(GTKCanvasView.self).contains { $0.sourceElement?.value(.drawable) != nil } }
            XCTAssertTrue(host.views(GTKCanvasView.self).contains {
                if case .values(let items)? = $0.sourceElement?.value(.drawable) { return !items.isEmpty }
                return false
            })
        }
    }
}

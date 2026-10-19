// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

private struct OffsetParameterLayout: Layout {
    typealias Cache = Void
    let offset: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> Size {
        proposal.replacingUnspecifiedDimensions(by: Size(width: 240, height: 160))
    }

    func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for subview in subviews {
            subview.place(at: Point(bounds.x + offset, bounds.y),
                          proposal: ProposedViewSize(width: 40, height: 32))
        }
    }
}

private enum OffsetTag: LayoutValueKey {
    static let defaultValue = 0.0
}

private struct OffsetTaggedChild: View {
    let offset: State<Double?>

    var body: some View {
        var content = Rectangle().frame(width: 40, height: 32).id("tagged-child")
        if let offset = offset.wrappedValue {
            content = content.layoutValue(key: OffsetTag.self, value: offset)
        }
        return content
    }
}

private struct OffsetTagLayout: Layout {
    typealias Cache = Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> Size {
        proposal.replacingUnspecifiedDimensions(by: Size(width: 240, height: 80))
    }

    func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for subview in subviews {
            subview.place(at: Point(bounds.x + subview[OffsetTag.self], bounds.y),
                          proposal: ProposedViewSize(width: 40, height: 32))
        }
    }
}

final class WinUICustomLayoutUpdatesTests: XCTestCase {
    func testChildLayoutValueChangesMoveTheRetainedViewWithoutRefreshingItsSibling() throws {
        try onUIThread {
            let offset = State<Double?>(wrappedValue: nil)
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack {
                    OffsetTagLayout {
                        OffsetTaggedChild(offset: offset).id("tagged-child")
                    }.id("tag-owner")
                    OffsetTagLayout {
                        Rectangle().frame(width: 40, height: 32).id("other-child")
                    }.id("other-owner")
                }
            }
            let owner = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("tag-owner")))
            let sibling = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("other-owner")))
            let custom = try XCTUnwrap(host.views(WinUICustomLayoutView.self).first { $0.sourceElement === owner })
            let child = try XCTUnwrap(host.view(id: .manual("tagged-child")))
            let siblingRevision = sibling.customLayoutRevision
            let originalBox = try XCTUnwrap(CoreLink().customLayout(for: owner.id))
            var ownerRevision = owner.customLayoutRevision

            let values: [Double?] = [24, 96, nil]
            for next in values {
                offset.wrappedValue = next
                host.runtime.pump.turn()
                host.layOut()
                XCTAssertTrue(host.views(WinUICustomLayoutView.self).contains { $0 === custom })
                XCTAssertTrue(host.view(id: .manual("tagged-child")) === child)
                XCTAssertTrue(CoreLink().customLayout(for: owner.id) === originalBox)
                XCTAssertGreaterThan(owner.customLayoutRevision, ownerRevision)
                XCTAssertEqual(sibling.customLayoutRevision, siblingRevision)
                XCTAssertEqual(child.placedFrame.x, next ?? OffsetTag.defaultValue, accuracy: 1)
                XCTAssertEqual(child.laidOutFrame.width, 40, accuracy: 1)
                XCTAssertEqual(child.laidOutFrame.height, 32, accuracy: 1)
                ownerRevision = owner.customLayoutRevision
            }
        }
    }

    func testLayoutParameterChangesMoveAnUnchangedNativeChild() throws {
        try onUIThread {
            let offset = State(wrappedValue: 10.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                OffsetParameterLayout(offset: offset.wrappedValue) {
                    Rectangle().frame(width: 40, height: 32).id("child")
                }.frame(width: 240, height: 160).id("layout")
            }
            let layout = try XCTUnwrap(host.views(WinUICustomLayoutView.self).first)
            let child = try XCTUnwrap(host.view(id: .manual("child")))
            XCTAssertEqual(child.placedFrame.x, 10, accuracy: 1)

            for next in [80.0, 20, 120] {
                offset.wrappedValue = next
                host.runtime.pump.turn()
                host.layOut()
                XCTAssertTrue(host.views(WinUICustomLayoutView.self).first === layout)
                XCTAssertTrue(host.view(id: .manual("child")) === child)
                XCTAssertEqual(child.placedFrame.x, next, accuracy: 1)
                XCTAssertEqual(child.laidOutFrame.width, 40, accuracy: 1)
                XCTAssertEqual(child.laidOutFrame.height, 32, accuracy: 1)
            }
        }
    }
}

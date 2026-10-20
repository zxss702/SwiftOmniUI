// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost

/// The layout arithmetic every Swift host places its children with.
final class LayoutArithmeticTests: XCTestCase {
    @MainActor
    func testHorizontalScrollerFillsItsViewportInsideMargins() {
        var scroll = Child(width: 0, height: 56)
        scroll.values.scrollAxes = .horizontal
        scroll.values.margin = EdgeInsets(10)
        XCTAssertEqual(StackArithmetic.size(of: [scroll], axis: .vertical, spacing: 0,
                                             padding: EdgeInsets(6), width: 100).width, 100)
        scroll.values.maximumWidth = 50
        XCTAssertEqual(StackArithmetic.size(of: [scroll], axis: .vertical, spacing: 0,
                                             padding: EdgeInsets(6), width: 100).width, 82)
        scroll.values.width = 30
        XCTAssertEqual(StackArithmetic.size(of: [scroll], axis: .vertical, spacing: 0,
                                             padding: EdgeInsets(6), width: 100).width, 62)
    }

    /// A row of an arrangement's own stands across the top or the bottom of its room, the page taking the rest -
    /// never less than none where the row is taller than the room.
    func testARowBesideAPageLeavesItTheRest() {
        let room = Rect(x: 0, y: 10, width: 300, height: 200)
        let top = RowEdge.top.split(room, row: 40)
        XCTAssertEqual(top.row, Rect(x: 0, y: 10, width: 300, height: 40))
        XCTAssertEqual(top.page, Rect(x: 0, y: 50, width: 300, height: 160))
        let bottom = RowEdge.bottom.split(room, row: 40)
        XCTAssertEqual(bottom.row, Rect(x: 0, y: 170, width: 300, height: 40))
        XCTAssertEqual(bottom.page, Rect(x: 0, y: 10, width: 300, height: 160))
        XCTAssertEqual(RowEdge.top.split(room, row: 500).page.height, 0)
        XCTAssertEqual(RowEdge.size(page: LayoutSize(width: 100, height: 60), row: 40), LayoutSize(width: 100, height: 100))
    }

    /// A contradiction between a least and a most size is settled by the least; the room caps both.
    func testTheLeastSizeWinsAndTheRoomCaps() {
        XCTAssertEqual(Extent.bounded(10, minimum: 40, maximum: 20), 40)
        XCTAssertEqual(Extent.bounded(90, minimum: nil, maximum: 50), 50)
        XCTAssertEqual(Extent.bounded(90, minimum: nil, maximum: nil, available: 30), 30)
        XCTAssertEqual(Extent.bounded(.nan, minimum: 5, maximum: nil), 5)
    }

    /// A vertical stack sets shown children one under another; a hidden one takes no room and no spacing.
    @MainActor
    func testAVerticalStackPlacesItsShownChildrenInOrder() {
        var centred = Child(width: 20, height: 10)
        centred.values.horizontal = 1
        let items = [Child(width: 20, height: 10), Child(width: 20, height: 10, shown: false), centred]

        let size = StackArithmetic.size(of: items, axis: .vertical, spacing: 5, padding: EdgeInsets(2), width: nil)
        let places = StackArithmetic.places(
            of: items, axis: .vertical, spacing: 5, padding: EdgeInsets(2), in: Rect(0, 0, 100, 50),
            direction: .leftToRight)

        XCTAssertEqual(size, LayoutSize(width: 24, height: 29))
        XCTAssertEqual(places[0], Rect(2, 12.5, 96, 10), "a filling child takes the slot's width")
        XCTAssertNil(places[1])
        XCTAssertEqual(places[2], Rect(40, 27.5, 20, 10), "a centred child stands in the middle")
    }

    /// A flexible child - a `Spacer` - takes the room a stack has left over along its axis, two of them
    /// sharing it evenly; where the room runs short it keeps at least the length it named.
    @MainActor
    func testAFlexibleChildTakesTheRoomLeftOver() {
        var spring = Child(width: 0, height: 0)
        spring.values.flex = 0
        var second = Child(width: 0, height: 0)
        second.values.flex = 0

        let pushed = StackArithmetic.places(
            of: [Child(width: 20, height: 10), spring, Child(width: 30, height: 10)],
            axis: .horizontal, spacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 100, 10),
            direction: .leftToRight)
        let shared = StackArithmetic.places(
            of: [spring, Child(width: 20, height: 10), second],
            axis: .horizontal, spacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 100, 10),
            direction: .leftToRight)
        let cramped = StackArithmetic.places(
            of: [Child(width: 95, height: 10), { var s = Child(width: 0, height: 0); s.values.flex = 40; return s }()],
            axis: .horizontal, spacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 100, 10),
            direction: .leftToRight)

        XCTAssertEqual(pushed[1], Rect(20, 0, 50, 10), "the spacer takes the room between its neighbours")
        XCTAssertEqual(pushed[2], Rect(70, 0, 30, 10), "and pushes what follows it to the end")
        XCTAssertEqual(shared[0]?.width, 40, "two spacers share the room evenly")
        XCTAssertEqual(shared[2]?.width, 40)
        XCTAssertEqual(cramped[1]?.width, 40, "a spacer keeps the length it named where the room runs short")
    }

    /// A column's natural height counts a spacer's minimum, so nothing asks for less than it needs.
    @MainActor
    func testAStackSizesAFlexibleChildAtItsMinimum() {
        var spring = Child(width: 0, height: 0)
        spring.values.flex = 30

        let size = StackArithmetic.size(
            of: [Child(width: 20, height: 10), spring], axis: .vertical, spacing: 5,
            padding: EdgeInsets(0), width: nil)

        XCTAssertEqual(size.height, 45)
    }

    // MARK: - Right to left

    /// A row laid out right to left fills from the right, its padding and margins on the other sides;
    /// spacing and sizes are the same.
    @MainActor
    func testARowRightToLeftFillsFromTheRight() {
        var first = Child(width: 20, height: 10)
        first.values.margin = EdgeInsets(3, 0, 0, 0)
        let items = [first, Child(width: 30, height: 10)]

        let places = StackArithmetic.places(
            of: items, axis: .horizontal, spacing: 5, padding: EdgeInsets(2, 0, 0, 0), in: Rect(0, 0, 100, 10),
            direction: .rightToLeft)

        XCTAssertEqual(places[0], Rect(55, 0, 20, 10), "the row centred in its room, the first child on its right")
        XCTAssertEqual(places[1], Rect(20, 0, 30, 10), "the next one to its left, the spacing between")
    }

    /// A column keeps its order down; a child aligned to its start stands at the right.
    @MainActor
    func testAColumnRightToLeftStandsItsStartAtTheRight() {
        var start = Child(width: 20, height: 10)
        start.values.horizontal = 0
        var end = Child(width: 20, height: 10)
        end.values.horizontal = 2

        let places = StackArithmetic.places(
            of: [start, end], axis: .vertical, spacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 100, 20),
            direction: .rightToLeft)

        XCTAssertEqual(places[0], Rect(80, 0, 20, 10))
        XCTAssertEqual(places[1], Rect(0, 10, 20, 10))
    }

    /// Right to left, a grid's column 0 is the rightmost, and its rows are where they were.
    @MainActor
    func testAGridRightToLeftStartsItsColumnsAtTheRight() {
        var first = Child(width: 10, height: 10)
        first.values.column = 0
        var second = Child(width: 10, height: 10)
        second.values.column = 1

        let places = GridArithmetic.places(
            of: [first, second], rows: [], columns: [.fixed(20), .fixed(30)],
            rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 100, 10),
            direction: .rightToLeft)

        XCTAssertEqual(places.map { $0?.x }, [80, 50])
    }

    /// Right to left, a ZStack's areas count from the right edge, and a child at its area's start stands at
    /// the area's right.
    @MainActor
    func testAZStackRightToLeftCountsItsAreasFromTheRight() {
        var badge = Child(width: 20, height: 10)
        badge.values.area = .absolute(10, 5, 40, 30)
        badge.values.horizontal = 0
        badge.values.vertical = 0
        var half = Child(width: 20, height: 10)
        half.values.area = .proportional(0, 0, 0.5, 1)

        let places = ZStackArithmetic.places(
            of: [badge, half], in: Rect(0, 0, 100, 50), padding: EdgeInsets(0), direction: .rightToLeft)

        XCTAssertEqual(places[0], Rect(70, 5, 20, 10))
        XCTAssertEqual(places[1], Rect(50, 0, 50, 50), "a proportion from 0 is the right half")
    }

    /// One child and its padding turn with the room; left to right is the default, and changes nothing.
    @MainActor
    func testOneChildRightToLeftTurnsWithItsRoom() {
        var child = Child(width: 20, height: 10)
        child.values.horizontal = 0

        let room = Rect(0, 0, 100, 10)
        XCTAssertEqual(
            SingleChildArithmetic.place(of: child, in: room, padding: EdgeInsets(4, 0, 0, 0), direction: .rightToLeft),
            Rect(76, 0, 20, 10))
        XCTAssertEqual(
            SingleChildArithmetic.place(of: child, in: room, padding: EdgeInsets(4, 0, 0, 0), direction: .leftToRight),
            Rect(4, 0, 20, 10))
    }

    /// Fixed tracks take their length, automatic tracks their child, proportional tracks share the rest.
    @MainActor
    func testGridTracksShareTheRoomByKind() {
        var fixed = Child(width: 10, height: 10)
        fixed.values.column = 0
        var automatic = Child(width: 30, height: 10)
        automatic.values.column = 1
        var shared = Child(width: 5, height: 10)
        shared.values.column = 2
        let columns: [GridLength] = [.fixed(20), .auto, .proportional(1)]

        let places = GridArithmetic.places(
            of: [fixed, automatic, shared], rows: [], columns: columns,
            rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 100, 10), direction: .leftToRight)

        XCTAssertEqual(places.map { $0?.x }, [0, 20, 50])
        XCTAssertEqual(places.map { $0?.width }, [20, 30, 50])
    }

    /// Words in a proportional column wrap to it: their row is as tall as they are at the column's width, where
    /// the grid places them and where it is measured for a width narrower than its words.
    @MainActor
    func testARowIsAsTallAsItsWordsAtTheirColumnsWidth() {
        let icon = Child(width: 20, height: 20)
        var words = Child(width: 300, height: 10)
        words.wraps = true
        words.values.column = 1
        let columns: [GridLength] = [.auto, .fill]

        let places = GridArithmetic.places(
            of: [icon, words], rows: [.auto], columns: columns,
            rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0), in: Rect(0, 0, 120, 200), direction: .leftToRight)
        let size = GridArithmetic.size(
            of: [icon, words], rows: [.auto], columns: columns,
            rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0), width: 120)

        XCTAssertEqual(places[1], Rect(20, 0, 100, 30), "three lines of words at the column's 100")
        XCTAssertEqual(size.height, 30)
        XCTAssertEqual(size.width, 120, "both measured axes must belong to the resolved column proposal")
        XCTAssertEqual(GridArithmetic.size(of: [icon, words], rows: [.auto], columns: columns,
                                           rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0)).width, 320,
                       "an unspecified proposal still reports the ideal width")
    }

    @MainActor
    func testAnExpandingGridMeasuresRowsAtItsOfferedColumns() {
        let cases: [(Axis, Double?, Double)] = [
            (.neither, nil, 64.9), (.horizontal, nil, 920),
            (.both, nil, 920), (.neither, 0, 920)]
        for (axis, flex, proposal) in cases {
            let offers = Offers()
            var child = Child(width: 64.9, height: 32.45)
            child.values.expandingAxes = axis
            child.values.flex = flex
            child.scalesToWidth = true
            child.offers = offers
            let size = GridArithmetic.size(
                of: [child], rows: [.auto], columns: [.fill], rowSpacing: 0,
                columnSpacing: 0, padding: EdgeInsets(0), width: 920)
            XCTAssertEqual(offers.widths.last!, proposal)
            XCTAssertEqual(size.width, proposal, accuracy: 0.01, "returned width follows the same tracks as row height")
            XCTAssertEqual(size.height, proposal / 2, accuracy: 0.01, "row height follows the column's actual proposal")
        }
    }

    /// A ZStack stands each child in its area - the room within the padding, a rectangle in points, or one
    /// in fractions of the room - by the child's own alignments; a hidden one has no place.
    @MainActor
    func testAZStackStandsEachChildInItsArea() {
        var corner = Child(width: 20, height: 10)
        corner.values.horizontal = 2
        corner.values.vertical = 2
        var badge = Child(width: 20, height: 10)
        badge.values.area = .absolute(10, 5, 40, 30)
        badge.values.horizontal = 0
        badge.values.vertical = 0
        var half = Child(width: 20, height: 10)
        half.values.area = .proportional(0.5, 0, 0.5, 1)
        let items = [Child(width: 20, height: 10), corner, badge, half, Child(width: 20, height: 10, shown: false)]

        let places = ZStackArithmetic.places(
            of: items, in: Rect(0, 0, 100, 50), padding: EdgeInsets(4), direction: .leftToRight)

        XCTAssertEqual(places[0], Rect(4, 4, 92, 42), "the whole room within the padding")
        XCTAssertEqual(places[1], Rect(76, 36, 20, 10), "its natural size, at the room's far corner")
        XCTAssertEqual(places[2], Rect(14, 9, 20, 10), "points from the room's top left, the child at its start")
        XCTAssertEqual(places[3], Rect(50, 4, 46, 42), "the right half of the room")
        XCTAssertNil(places[4])
    }

    /// A ZStack needs the room its neediest child does: a rectangle in points to its far corner, a share
    /// big enough to hold the child, and anything else its natural size and margins.
    @MainActor
    func testAZStackMeasuresAsItsNeediestChild() {
        var margined = Child(width: 30, height: 10)
        margined.values.margin = EdgeInsets(5, 0, 5, 0)
        var badge = Child(width: 20, height: 10)
        badge.values.area = .absolute(10, 5, 40, 30)
        var half = Child(width: 30, height: 20)
        half.values.area = .proportional(0.5, 0, 0.5, 0.5)

        XCTAssertEqual(ZStackArithmetic.size(of: [margined], padding: EdgeInsets(2), width: nil), LayoutSize(width: 44, height: 14))
        XCTAssertEqual(ZStackArithmetic.size(of: [badge], padding: EdgeInsets(0), width: nil), LayoutSize(width: 50, height: 35))
        XCTAssertEqual(
            ZStackArithmetic.size(of: [margined, badge, half], padding: EdgeInsets(0), width: nil),
            LayoutSize(width: 60, height: 40), "half of the room holds the child only in twice its size")
    }

    /// A child that fills both ways takes the room within the padding, whatever it would measure.
    @MainActor
    func testASingleFillingChildTakesTheRoom() {
        let place = SingleChildArithmetic.place(
            of: Child(width: 5, height: 5), in: Rect(0, 0, 100, 40), padding: EdgeInsets(10), direction: .leftToRight)

        XCTAssertEqual(place, Rect(10, 10, 80, 20))
    }

    /// Every layout offers a child the room it stands in less the child's margin, once: the child answers for
    /// itself, and the layout adds the margin back.
    @MainActor
    func testEveryLayoutOffersAChildItsRoomLessItsMarginOnce() {
        let offers = Offers()
        var child = Child(width: 10, height: 10)
        child.values.margin = EdgeInsets(8, 4)
        child.values.horizontal = 0
        child.offers = offers
        var half = child
        half.values.area = .proportional(0, 0, 0.5, 1)
        let room = Rect(0, 0, 100, 100)

        func offered(_ layout: () -> Void) -> [Double?] {
            offers.widths = []
            layout()
            return offers.widths
        }

        XCTAssertEqual(offered {
            _ = StackArithmetic.size(of: [child], axis: .vertical, spacing: 0, padding: EdgeInsets(0), width: 100)
        }, [84], "a stack measured")
        XCTAssertEqual(offered {
            _ = StackArithmetic.places(
                of: [child], axis: .vertical, spacing: 0, padding: EdgeInsets(0), in: room, direction: .leftToRight)
        }, [84], "a stack placing")
        XCTAssertEqual(offered { _ = ZStackArithmetic.size(of: [child], padding: EdgeInsets(0), width: 100) }, [84], "a ZStack")
        XCTAssertEqual(offered { _ = ZStackArithmetic.size(of: [half], padding: EdgeInsets(0), width: 100) }, [34], "its area")
        XCTAssertEqual(offered { _ = SingleChildArithmetic.size(of: child, padding: EdgeInsets(0), width: 100) }, [84], "one child")
        XCTAssertEqual(offered {
            _ = SingleChildArithmetic.place(of: child, in: room, padding: EdgeInsets(0), direction: .leftToRight)
        }, [84], "one child placed")
        XCTAssertEqual(offered {
            _ = GridArithmetic.places(
                of: [child], rows: [.auto], columns: [], rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0),
                in: room, direction: .leftToRight)
        }, [84, 84], "a grid's row and its place")
        XCTAssertEqual(offered {
            _ = ScrollArithmetic.contentSize(of: child, padding: EdgeInsets(0), orientation: .vertical, width: 100)
        }, [84], "a scroller's document")
    }

    /// A flow fills its columns row first, each row as tall as its cells - the rows counted,
    /// not stated.
    @MainActor
    func testAFlowFillsItsColumnsRowFirst() {
        let items = [Child(width: 10, height: 10), Child(width: 10, height: 20), Child(width: 10, height: 10)]
        let flow = [GridItem(.fixed(40)), GridItem(.fixed(40))]

        let places = GridArithmetic.places(
            of: items, rows: [], columns: [], rowSpacing: 4, columnSpacing: 0, padding: EdgeInsets(0),
            in: Rect(0, 0, 100, 60), direction: .leftToRight, flow: flow)
        let size = GridArithmetic.size(
            of: items, rows: [], columns: [], rowSpacing: 4, columnSpacing: 0, padding: EdgeInsets(0),
            width: 100, flow: flow)

        XCTAssertEqual(places[0], Rect(0, 0, 40, 20), "the first cell's row is as tall as its tallest")
        XCTAssertEqual(places[1], Rect(40, 0, 40, 20))
        XCTAssertEqual(places[2], Rect(0, 24, 40, 10), "the third cell opens the second row")
        XCTAssertEqual(size.height, 34)
        XCTAssertEqual(size.width, 80)
    }

    /// An adaptive item stands for as many columns of its minimum as the room fits, each a
    /// bounded share of what is left.
    @MainActor
    func testAnAdaptiveItemFitsAsManyColumnsAsTheRoomAllows() {
        let items = [Child(width: 10, height: 10), Child(width: 10, height: 10), Child(width: 10, height: 10)]
        let flow = [GridItem(.adaptive(minimum: 40))]

        let wide = GridArithmetic.places(
            of: items, rows: [], columns: [], rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0),
            in: Rect(0, 0, 110, 40), direction: .leftToRight, flow: flow)

        XCTAssertEqual(wide.map { $0?.x }, [0, 55, 0], "110 points fits two columns of 40")
        XCTAssertEqual(wide.map { $0?.width }, [55, 55, 55])
        XCTAssertEqual(wide.map { $0?.y }, [0, 0, 10])

        let narrow = GridArithmetic.places(
            of: items, rows: [], columns: [], rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0),
            in: Rect(0, 0, 50, 60), direction: .leftToRight, flow: flow)

        XCTAssertEqual(narrow.map { $0?.x }, [0, 0, 0], "50 points fits one column of 40")
        XCTAssertEqual(narrow.map { $0?.width }, [50, 50, 50])
    }

    /// A flexible column keeps the bounds it named: the room's share, never under its minimum
    /// nor over its maximum.
    @MainActor
    func testAFlexibleColumnKeepsItsBounds() {
        let items = [Child(width: 10, height: 10), Child(width: 10, height: 10)]
        let flow = [GridItem(.flexible(minimum: 20, maximum: 60)), GridItem(.fixed(20))]

        let wide = GridArithmetic.places(
            of: items, rows: [], columns: [], rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0),
            in: Rect(0, 0, 100, 20), direction: .leftToRight, flow: flow)
        let narrow = GridArithmetic.places(
            of: items, rows: [], columns: [], rowSpacing: 0, columnSpacing: 0, padding: EdgeInsets(0),
            in: Rect(0, 0, 30, 20), direction: .leftToRight, flow: flow)

        XCTAssertEqual(wide[0]?.width, 60, "the share is capped at the maximum")
        XCTAssertEqual(wide[1]?.x, 60)
        XCTAssertEqual(narrow[0]?.width, 20, "and floored at the minimum")
        XCTAssertEqual(narrow[1]?.x, 20)
    }

    /// A kept size answers for its width until it is forgotten; a pass needs at most a few.
    @MainActor
    func testAMeasurementIsKeptPerOfferedWidth() {
        let cache = MeasurementCache()
        var measured = 0
        func size(_ width: Double?) -> LayoutSize {
            cache.size(offering: width) { measured += 1; return LayoutSize(width: width ?? 1, height: 1) }
        }

        _ = size(10); _ = size(10); _ = size(nil)
        XCTAssertEqual(measured, 2)
        cache.invalidate()
        _ = size(10)
        XCTAssertEqual(measured, 3)
    }
}

/// A child of a stated natural size; one that wraps is as wide as that on one line, and a line taller for each
/// time it has to break to fit a narrower width.
private struct Child: LayoutChild {
    var values = LayoutValues()
    let natural: LayoutSize
    let isShown: Bool
    var wraps = false
    var scalesToWidth = false

    /// Where the widths it is offered are written; nil keeps none.
    var offers: Offers?

    init(width: Double, height: Double, shown: Bool = true) {
        natural = LayoutSize(width: width, height: height)
        isShown = shown
    }

    func size(offered width: Double?) -> LayoutSize {
        offers?.widths.append(width)
        if scalesToWidth, let width, width.isFinite {
            return LayoutSize(width: width, height: width * natural.height / natural.width)
        }
        if wraps, let width, width > 0, width < natural.width {
            return LayoutSize(width: width, height: natural.height * (natural.width / width).rounded(.up))
        }
        return LayoutSize(
            width: values.boundedWidth(values.width ?? natural.width),
            height: values.boundedHeight(values.height ?? natural.height))
    }
}

/// The widths a child was offered, in order.
@MainActor
private final class Offers {
    var widths: [Double?] = []
}

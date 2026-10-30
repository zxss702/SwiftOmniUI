// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private struct ForegroundCapsule: View {
    var body: some View { Capsule(style: .continuous) }
}

@MainActor final class ShapeForegroundTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    func testACapsuleUsesItsForegroundWithoutChangingItsOpacity() throws {
        let patch = Renders().render(Capsule(style: .continuous).foregroundStyle(.black.opacity(0.03)).node)
        XCTAssertEqual(patch.props[.fill], Brush.solidColor(.black.opacity(0.03)).propValue)
        XCTAssertNil(patch.props[.foregroundStyle], "a shape receives its brush through the shape contract")
        XCTAssertNil(patch.props[.opacity], "the style's alpha does not change the view's opacity")
    }

    func testAFrameBeforeOrAfterTheForegroundKeepsTheBrushOnItsShape() throws {
        let views: [any View] = [
            Capsule().foregroundStyle(.black.opacity(0.03)).frame(width: 100, height: 20),
            Capsule().frame(width: 100, height: 20).foregroundStyle(.black.opacity(0.03)),
        ]
        for view in views {
            let patch = Renders().render(view.node)
            let shape = try XCTUnwrap(patch.subtree.first { $0.type == .rectangle })
            XCTAssertEqual(shape.props[.fill], Brush.solidColor(.black.opacity(0.03)).propValue)
            XCTAssertNil(shape.props[.foregroundStyle])
        }
    }

    func testForegroundColorAndTypeErasureUseTheSameShapeFillPath() {
        let views: [any View] = [
            Capsule().foregroundColor(.black.opacity(0.03)),
            AnyView(Capsule()).foregroundStyle(.black.opacity(0.03)),
        ]
        for view in views {
            XCTAssertEqual(Renders().render(view.node).props[.fill], Brush.solidColor(.black.opacity(0.03)).propValue)
        }
    }

    func testASpacerStaysClearWithoutForegroundAndWithItsOwnForeground() throws {
        try testAFixedSpacerKeepsItsExtentWithoutAnExtraLayoutContainer()
        let views: [any View] = [
            Spacer(),
            Spacer().foregroundStyle(.red),
            Spacer(minLength: 12).frame(width: 100, height: 20).foregroundStyle(.blue),
        ]
        for (index, view) in views.enumerated() {
            let patch = Renders().render(view.node)
            let spacer = try XCTUnwrap(patch.subtree.first { $0.type == .rectangle })
            XCTAssertEqual(spacer.props[.fill], Brush.solidColor(.clear).propValue)
            let layout = try XCTUnwrap(patch.subtree.first { $0.props[.flex] != nil })
            XCTAssertEqual(layout.props[.flex], (index == 2 ? 12.0 : 0.0).propValue)
        }
    }

    func testAContainerForegroundFillsShapesButLeavesItsSpacerClear() throws {
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let patch = Renders().render(HStack {
            Capsule().id("shape")
            Spacer(minLength: 12).id("spacer")
        }.foregroundStyle(gradient).node)
        let spacer = try XCTUnwrap(patch.child(.manual("spacer")))
        XCTAssertEqual(spacer.props[.fill], Brush.solidColor(.clear).propValue)
        XCTAssertEqual(spacer.props[.flex], 12.0.propValue)
        XCTAssertEqual(patch.child(.manual("shape"))?.props[.fill], gradient.brush.propValue.resolvingColorScheme())
    }

    func testAFixedSpacerKeepsItsExtentWithoutAnExtraLayoutContainer() throws {
        let patch = Renders().render(Spacer(minLength: 12)
            .frame(width: 100, height: 20, alignment: .trailing).node)
        let spacer = try XCTUnwrap(patch.subtree.first { $0.type == .rectangle })
        XCTAssertEqual(spacer.props[.width], 100.0.propValue)
        XCTAssertEqual(spacer.props[.height], 20.0.propValue)
        XCTAssertEqual(spacer.props[.flex], 12.0.propValue)
        XCTAssertFalse(patch.subtree.contains { $0.type == .grid })
    }

    func testASpacerKeepsAnExplicitBackgroundVisibleThroughItsClearFill() throws {
        let patch = Renders().render(Spacer().id("spacer").background {
            Rectangle().fill(.blue).id("background")
        }.foregroundStyle(.red).node)
        XCTAssertEqual(patch.subtree.first { $0.id == .manual("spacer") }?.props[.fill],
                       Brush.solidColor(.clear).propValue)
        XCTAssertEqual(patch.subtree.first { $0.id == .manual("background") }?.props[.fill],
                       Brush.solidColor(.blue).propValue.resolvingColorScheme())
    }

    func testAContainerPassesItsForegroundToShapesAndText() throws {
        let patch = Renders().render(VStack {
            ForegroundCapsule().id("composed")
            Circle().foregroundStyle(.red).id("nearer")
            Text("inherited").id("text")
            Text("own").foregroundStyle(.blue).id("own-text")
        }.foregroundStyle(.black.opacity(0.03)).node)
        XCTAssertEqual(patch.child(.manual("composed"))?.props[.fill], Brush.solidColor(.black.opacity(0.03)).propValue)
        XCTAssertEqual(patch.child(.manual("nearer"))?.props[.fill], Brush.solidColor(.red).propValue.resolvingColorScheme())
        XCTAssertEqual(patch.child(.manual("text"))?.props[.foregroundStyle], Color.black.opacity(0.03).propValue)
        XCTAssertEqual(patch.child(.manual("own-text"))?.props[.foregroundStyle], Color.blue.propValue.resolvingColorScheme())
    }

    func testAModifiedContainerAndAFragmentKeepForegroundInheritance() throws {
        let patch = Renders().render(VStack {
            Group {
                Capsule().id("capsule")
                Circle().id("circle")
            }.foregroundStyle(.blue)
            Rectangle().id("rectangle")
        }.padding(4).foregroundStyle(.red).node)
        XCTAssertEqual(patch.subtree.first { $0.id == .manual("capsule") }?.props[.fill], Brush.solidColor(.blue).propValue.resolvingColorScheme())
        XCTAssertEqual(patch.subtree.first { $0.id == .manual("circle") }?.props[.fill], Brush.solidColor(.blue).propValue.resolvingColorScheme())
        XCTAssertEqual(patch.subtree.first { $0.id == .manual("rectangle") }?.props[.fill], Brush.solidColor(.red).propValue.resolvingColorScheme())
    }

    func testACompleteGradientSurvivesAFrameAndAComposedView() throws {
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let patch = Renders().render(ForegroundCapsule().frame(width: 100, height: 20).foregroundStyle(gradient).node)
        let shape = try XCTUnwrap(patch.subtree.first { $0.type == .rectangle })
        XCTAssertEqual(shape.props[.fill], gradient.brush.propValue.resolvingColorScheme())
    }

    func testAMaterialForegroundIsNotDroppedForHavingNoFirstColour() throws {
        let patch = Renders().render(Capsule().frame(width: 100, height: 20).foregroundStyle(.regularMaterial).node)
        let shape = try XCTUnwrap(patch.subtree.first { $0.type == .rectangle })
        XCTAssertEqual(shape.props[.fill], Material.regularMaterial.brush.propValue)
    }

    func testExplicitFillWinsOnTheShapeAndThroughContainersAndStyles() {
        XCTAssertEqual(Renders().render(Capsule().fill(.blue).foregroundStyle(.red).node).props[.fill],
                       Brush.solidColor(.blue).propValue.resolvingColorScheme())
        let container = Renders().render(VStack {
            Capsule().fill(.blue).id("filled")
        }.foregroundStyle(.red).node)
        XCTAssertEqual(container.child(.manual("filled"))?.props[.fill], Brush.solidColor(.blue).propValue.resolvingColorScheme())
        let sheet = StyleSheet { Style<Rectangle>().fill(.blue) }
        XCTAssertEqual(Renders().render(Rectangle().foregroundStyle(.red).node, styles: sheet).props[.fill],
                       Brush.solidColor(.blue).propValue.resolvingColorScheme())
    }

    func testForegroundDoesNotFillAStrokeOnlyShape() {
        let views: [any View] = [
            Capsule().stroke(.blue, lineWidth: 2).foregroundStyle(.red),
            Capsule().strokeBorder(.blue, lineWidth: 2).foregroundStyle(.red),
        ]
        for view in views {
            XCTAssertNil(Renders().render(view.node).props[.fill])
        }
        let container = Renders().render(VStack {
            Capsule().stroke(.blue, lineWidth: 2).id("outlined")
        }.foregroundStyle(.red).node)
        XCTAssertNil(container.child(.manual("outlined"))?.props[.fill])
    }

    func testChangingAndRemovingForegroundUpdatesFillWithoutReplacingTheShape() {
        let renders = Renders()
        let first = renders.render(Capsule().foregroundStyle(.red).id("capsule").node)
        let changed = renders.render(Capsule().foregroundStyle(.blue).id("capsule").node)
        XCTAssertEqual(changed.id, first.id)
        XCTAssertFalse(changed.replace)
        XCTAssertEqual(changed.props[.fill], Brush.solidColor(.blue).propValue.resolvingColorScheme())

        let removed = renders.render(Capsule().id("capsule").node)
        XCTAssertFalse(removed.replace)
        XCTAssertEqual(removed.props[.fill], Brush.solidColor(.primary).propValue.resolvingColorScheme())
    }

    func testThemedForegroundAndTheDefaultFillFollowAColorSchemeChange() throws {
        let info = StandardEnvironment.appInfo
        let previous = info.colorScheme
        defer { info.colorScheme = previous }
        info.colorScheme = .light
        let renders = Renders()
        let first = renders.render(VStack {
            Capsule().foregroundStyle(Color(light: .red, dark: .blue)).id("themed")
            Circle().id("default")
        }.node)
        XCTAssertEqual(first.child(.manual("themed"))?.props[.fill], Brush.solidColor(.red).propValue.resolvingColorScheme())
        XCTAssertEqual(first.child(.manual("default"))?.props[.fill], Brush.solidColor(.primary).propValue.resolvingColorScheme())

        Renderer.shared.clearInvalidation()
        info.colorScheme = .dark
        let changed = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(changed.child(.manual("themed"))?.props[.fill], Brush.solidColor(.blue).propValue.resolvingColorScheme())
        XCTAssertEqual(changed.child(.manual("default"))?.props[.fill], Brush.solidColor(.primary).propValue.resolvingColorScheme())
        XCTAssertFalse(changed.subtree.contains(where: \.replace))
    }
}

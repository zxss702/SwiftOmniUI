// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class SystemColorTests: XCTestCase {
    /// Reference sRGB palette, independent of host channel order, font coverage or screenshot color profiles.
    func testStandardUIColorsCarryBothAppearances() {
        let palette: [(Color, String, String)] = [
            (.red, "#FF383C", "#FF4245"), (.orange, "#FF8D28", "#FF9230"),
            (.yellow, "#FFCC00", "#FFD600"), (.green, "#34C759", "#30D158"),
            (.mint, "#00C8B3", "#00DAC3"), (.teal, "#00C3D0", "#00D2E0"),
            (.cyan, "#00C0E8", "#3CD3FE"), (.blue, "#0088FF", "#0091FF"),
            (.indigo, "#6155F5", "#6D7CFF"), (.purple, "#CB30E0", "#DB34F2"),
            (.pink, "#FF2D55", "#FF375F"), (.brown, "#AC7F5E", "#B78A66"),
            (.gray, "#8E8E93", "#98989D"),
        ]
        for (color, light, dark) in palette {
            XCTAssertEqual(color.propValue, .themed(light: Color(light).propValue, dark: Color(dark).propValue))
            withTheme(.light) { XCTAssertEqual(color.propValue.resolvingColorScheme(), Color(light).propValue) }
            withTheme(.dark) { XCTAssertEqual(color.propValue.resolvingColorScheme(), Color(dark).propValue) }
        }
        XCTAssertEqual(Color.magenta, Color("#FF00FF"), "CSS-only names remain constant")
        XCTAssertEqual(Color.cornflowerBlue, Color("#6495ED"))
        XCTAssertNotEqual(Color.cyan, Color(red: 0, green: 1, blue: 1))
    }

    func testOpacityMixAndNestedPairsKeepTheDarkPalette() {
        let alpha = Color.cyan.opacity(0.25)
        XCTAssertEqual(alpha.propValue, .themed(
            light: Color("#4000C0E8").propValue, dark: Color("#403CD3FE").propValue))
        let paired = Color(light: .red, dark: .blue)
        withTheme(.light) { XCTAssertEqual(paired.propValue.resolvingColorScheme(), Color("#FF383C").propValue) }
        withTheme(.dark) { XCTAssertEqual(paired.propValue.resolvingColorScheme(), Color("#0091FF").propValue) }
        XCTAssertEqual(Color.cyan.mix(with: .black, by: 0.5).propValue, .themed(
            light: Color("#006074").propValue, dark: Color("#1E6A7F").propValue))
    }

    /// A theme change revisits both a label and a gradient-bearing shape, retaining their identities.
    func testNamedColorsInvalidateTheirRenderedUses() throws {
        let info = StandardEnvironment.appInfo
        let previous = info.colorScheme
        defer { info.colorScheme = previous }
        info.colorScheme = .light
        let renders = Renders()
        let gradient = LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
        let first = renders.render(VStack {
            Text("神衍·智能").foregroundStyle(.cyan).id("title")
            Capsule().foregroundStyle(gradient).id("shape")
        }.node)
        XCTAssertEqual(first.child(.manual("title"))?.props[.foregroundStyle], Color("#00C0E8").propValue)
        XCTAssertEqual(first.child(.manual("shape"))?.props[.fill], gradient.brush.propValue.resolvingColorScheme())

        Renderer.shared.clearInvalidation()
        info.colorScheme = .dark
        let changed = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(changed.child(.manual("title"))?.props[.foregroundStyle], Color("#3CD3FE").propValue)
        XCTAssertEqual(changed.child(.manual("shape"))?.props[.fill], gradient.brush.propValue.resolvingColorScheme())
        XCTAssertFalse(changed.subtree.contains(where: \.replace))
    }
}

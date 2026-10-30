// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The key the SwiftUI spelling writes: a literal carries its pattern and
// arguments across to the host, a `String` stays the words they are.
//
// Design: the literal is looked up, the variable is not - the same split
// SwiftUI makes.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class LocalizedStringKeyTests: XCTestCase {
    /// A plain literal is a key of itself and nothing else.
    func testALiteralIsItsOwnPattern() {
        let key: LocalizedStringKey = "Save"

        XCTAssertEqual(key.pattern, "Save")
        XCTAssertEqual(key.arguments, [])
        XCTAssertEqual(key.displayString, "Save")
    }

    /// An interpolation stands as the specifier the table carries: `%lld`
    /// for a whole number, `%@` for anything else.
    func testInterpolationsStandAsTheirSpecifiers() {
        let count = 3
        let name = "Ada"
        let key: LocalizedStringKey = "\(count) files for \(name)"

        XCTAssertEqual(key.pattern, "%lld files for %@")
        XCTAssertEqual(key.arguments.map(\.kind), [.whole, .string])
        XCTAssertEqual(key.displayString, "3 files for Ada")
    }

    /// `\(x, specifier:)` puts the specifier it names in the key, as the
    /// `.xcstrings` catalogs SCE carries do.
    func testANamedSpecifierStandsInTheKey() {
        let elapsed = 1.005
        let key: LocalizedStringKey = "Elapsed: \(elapsed, specifier: "%.2f") s"

        XCTAssertEqual(key.pattern, "Elapsed: %.2f s")
        XCTAssertEqual(key.displayString, "Elapsed: 1.005 s")
    }

    /// `%%` is a percent sign, not a specifier.
    func testADoubledPercentIsAPercent() {
        let key = LocalizedStringKey(pattern: "100%% sure")
        XCTAssertEqual(key.displayString, "100% sure")
    }

    /// A key survives the crossing: the pattern and each argument's kind and
    /// value come back as themselves.
    func testAKeyComesBackAsItself() {
        let key: LocalizedStringKey = "\(7) of \(12.5, specifier: "%.1f") for \("all")"

        XCTAssertEqual(LocalizedStringKey(propValue: key.propValue), key)
    }

    /// THE SPLIT THE SPELLING MAKES: `Text("…")` is a key looked up, its
    /// words beside it as the fallback; `Text(someString)` is verbatim - a
    /// variable is never looked up.
    func testALiteralTextCarriesItsKeyAndAVariableDoesNot() {
        let verbatim = "Runtime"

        XCTAssertNotNil(Text("Literal").node.props[.textKey])
        XCTAssertEqual(Text("Literal").node.props[.text], .string("Literal"))
        XCTAssertNil(Text(verbatim).node.props[.textKey])
        XCTAssertEqual(Text(verbatim).node.props[.text], .string("Runtime"))
    }

    /// The same split at every other literal-taking front: a button, a menu
    /// item, a placeholder, a tip.
    func testEveryFrontCarriesItsKey() {
        let verbatim = "Runtime"

        XCTAssertNotNil(Button("Save") {}.node.props[.textKey])
        XCTAssertNil(Button(verbatim) {}.node.props[.textKey])
        XCTAssertNotNil(MenuItem("New").node.props[.textKey])
        XCTAssertNil(MenuItem(verbatim).node.props[.textKey])
        XCTAssertNotNil(TextField("Search", text: State("").projectedValue).node.props[.placeholderKey])
        XCTAssertNil(TextField(verbatim, text: State("").projectedValue).node.props[.placeholderKey])
        XCTAssertNotNil(Text("x").help("The tip").node.props[.hintKey])
        XCTAssertNil(Text("x").help(verbatim).node.props[.hintKey])
    }

    /// A key's words still read as the plain member: `text`, `placeholder`,
    /// `hint` hold the fallback the host shows where its tables name no key.
    func testTheFallbackStandsBesideTheKey() {
        XCTAssertEqual(Button("Save") {}.node.props[.text], .string("Save"))
        XCTAssertEqual(
            TextField("Search", text: State("").projectedValue).node.props[.placeholder],
            .string("Search"))
        XCTAssertEqual(Text("x").help("The tip").node.props[.hint], .string("The tip"))
    }
}

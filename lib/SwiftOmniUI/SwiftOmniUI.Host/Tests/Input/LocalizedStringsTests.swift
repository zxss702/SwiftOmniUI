// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

final class LocalizedStringsTests: XCTestCase {
    /// The specifiers SCE's `.xcstrings` carries: `%lld` a whole number,
    /// `%@` anything's text, `%.2f` a precision.
    func testTheSpecifiersTheCatalogCarries() {
        XCTAssertEqual(
            HostLocalizedStrings.format("%lld files", arguments: [.whole(3)]),
            "3 files")
        XCTAssertEqual(
            HostLocalizedStrings.format("Hello, %@!", arguments: [.string("Ada")]),
            "Hello, Ada!")
        XCTAssertEqual(
            HostLocalizedStrings.format("%.2f s", arguments: [.number(1.006)]),
            "1.01 s")
    }

    /// The rest of the family: integers signed and not, hex, floats as they
    /// fall, a percent sign doubled.
    func testTheFamilyAroundThem() {
        XCTAssertEqual(HostLocalizedStrings.format("%d", arguments: [.whole(-2)]), "-2")
        XCTAssertEqual(HostLocalizedStrings.format("%u", arguments: [.whole(2)]), "2")
        XCTAssertEqual(HostLocalizedStrings.format("%x", arguments: [.whole(255)]), "ff")
        XCTAssertEqual(HostLocalizedStrings.format("%X", arguments: [.whole(255)]), "FF")
        XCTAssertEqual(HostLocalizedStrings.format("%f", arguments: [.number(1.5)]), "1.500000")
        XCTAssertEqual(HostLocalizedStrings.format("100%% sure", arguments: []), "100% sure")
    }

    /// An argument short of its specifier leaves the specifier written; a
    /// shape it cannot answer gives the argument's plain text.
    func testWhatAnArgumentCannotAnswerStaysWritten() {
        XCTAssertEqual(
            HostLocalizedStrings.format("%lld and %lld", arguments: [.whole(1)]),
            "1 and %lld")
        XCTAssertEqual(
            HostLocalizedStrings.format("%lld", arguments: [.string("many")]),
            "many")
    }

    /// `resolve`: the table's answer formatted, its silence the key's own
    /// pattern formatted - the fallback a missing translation draws.
    func testResolveAnswersTheTableOrTheKey() {
        let key = LocalizedStringKey(pattern: "%lld files", arguments: [.whole(4)])
        XCTAssertEqual(
            HostLocalizedStrings.resolve(key) { _ in "%lld Dateien" },
            "4 Dateien")
        XCTAssertEqual(
            HostLocalizedStrings.resolve(key) { _ in nil },
            "4 files")
    }
}

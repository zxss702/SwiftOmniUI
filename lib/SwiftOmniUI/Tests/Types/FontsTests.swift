// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `Fonts.register`: before a host binds `add` the path waits in `pending`;
// once bound the path is handed over - and a file registers once, however
// often it is named.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

final class FontsTests: XCTestCase {
    override func tearDown() {
        Fonts.add = nil
        Fonts.pending = []
        Fonts.handled = []
        super.tearDown()
    }

    func testRegisterWaitsForTheHost() {
        XCTAssertTrue(Fonts.register(path: "/x/Songti.ttf"))
        XCTAssertEqual(Fonts.pending, ["/x/Songti.ttf"])
    }

    func testTheHostDrainsWhatWaited() {
        XCTAssertTrue(Fonts.register(path: "/x/Songti.ttf"))
        var added: [String] = []
        Fonts.add = { added.append($0); return true }
        for path in Fonts.pending { _ = Fonts.add?(path) }
        Fonts.pending.removeAll()
        XCTAssertEqual(added, ["/x/Songti.ttf"])
        XCTAssertTrue(Fonts.pending.isEmpty)
    }

    func testAStartedHostTakesItAtOnce() {
        var added: [String] = []
        Fonts.add = { added.append($0); return true }
        XCTAssertTrue(Fonts.register(path: "/x/SF-Mono-Light.otf"))
        XCTAssertEqual(added, ["/x/SF-Mono-Light.otf"])
        XCTAssertTrue(Fonts.pending.isEmpty)
    }

    func testARefusedFileAnswersFalse() {
        Fonts.add = { _ in false }
        XCTAssertFalse(Fonts.register(path: "/x/missing.ttf"))
    }

    func testAFileRegistersOnce() {
        XCTAssertTrue(Fonts.register(path: "/x/Songti.ttf"))
        XCTAssertTrue(Fonts.register(path: "/x/Songti.ttf"))
        XCTAssertEqual(Fonts.pending, ["/x/Songti.ttf"])
    }
}

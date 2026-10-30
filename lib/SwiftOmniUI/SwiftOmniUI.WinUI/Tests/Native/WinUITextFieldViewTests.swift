// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

/// A text field: the words, checking and keyboard it takes.
final class WinUITextFieldViewTests: XCTestCase {
    /// A field takes the traits its purpose gives on every host (`InputTraits`): plain words are neither spell
    /// checked nor predicted, though the tree leaves both on; prose starts its sentences in capitals and a chat
    /// offers emoji, each by its input scope.
    func testAFieldTakesTheTraitsItsPurposeGives() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let purpose = State(wrappedValue: InputPurpose.plain)
            let host = WinUIRenderer.running {
                VStack {
                    TextField(words.projectedValue)
                        .textContentType(purpose.wrappedValue)
                        .frame(width: 200)
                }
            }
            host.layOut()
            let field = try XCTUnwrap(host.views(WinUITextFieldView.self).first)
            XCTAssertEqual(Self.checkedAndPredicted(field), [0, 0], "plain words")

            let scopes: [(InputPurpose, WinUIInputScope)] = [
                (.text, .text), (.chat, .chat), (.email, .email), (.numeric, .number), (.default, .default),
            ]
            for (written, scope) in scopes {
                purpose.wrappedValue = written
                host.settle { Self.read(field, "scope") == "\(scope.rawValue)" }
                XCTAssertEqual(Self.read(field, "scope"), "\(scope.rawValue)", "\(written)")
            }
            XCTAssertEqual(Self.checkedAndPredicted(field), [1, 1], "the default's words")
        }
    }

    /// Whether `field`'s words are spell checked and predicted, 1 or 0 each.
    @MainActor private static func checkedAndPredicted(_ field: WinUIView) -> [Int32] {
        var facts = [Int32](repeating: 0, count: 9)
        swiftomniui_winui_field_facts(field.handle, &facts)
        return Array(facts[1...2])
    }

    @MainActor private static func read(_ view: WinUIView, _ what: String) -> String {
        WinUIStrings.read { swiftomniui_winui_read(view.handle, what, $0, $1) }
    }
}

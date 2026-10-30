// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `DividerContract` on a host: a separator stands between the entries it parts, and goes where the tree takes
/// it away.
@_spi(Host) public enum MenuSeparatorTests: ConformanceFamily {
    public static let name = "Divider"

    public static var cases: [ConformanceCase] {
        [
            ConformanceCase("aSeparatorPartsItsEntries", proves: [
                Covered(DividerContract.self),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let parted = State(wrappedValue: true)
                s.start {
                    VStack {
                        Text("Row").contextMenu {
                            MenuItem("Cut")
                            if parted.wrappedValue { Divider() }
                            MenuItem("Delete")
                        }.id("row")
                        Button("Join").onClicked { parted.wrappedValue = false }.id("join")
                    }
                }
                let row = try s.element("row")
                s.expect(try s.menu(of: row), "Cut;-;Delete")

                try s.perform(.activate, on: s.element("join"))
                try s.settle { try s.menu(of: row) == "Cut;Delete" }
                s.expect(try s.menu(of: row), "Cut;Delete")
            },
        ]
    }
}

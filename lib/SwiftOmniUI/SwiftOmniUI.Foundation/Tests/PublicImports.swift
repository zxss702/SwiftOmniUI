// SPDX-FileCopyrightText: 2026 Pawe? Krzywdzi?ski and Contributors
// SPDX-License-Identifier: Apache-2.0

// Do not import Foundation, XCTest, or the Host SPI here: the application facade
// must supply these names on its own, on both Windows and Linux.
import SwiftOmniUI

private let publicURL = URL(fileURLWithPath: ".")
private let publicFileManager = FileManager.default

// Ordinary import: these SwiftUI APIs must not require the Host SPI.
private struct PositionSurface: View {
    @State var position = ScrollPosition(edge: .bottom)
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) { Text("row").id("row") }
                .lineSpacing(16)
        }
        .scrollPosition($position, anchor: .bottom)
    }
}

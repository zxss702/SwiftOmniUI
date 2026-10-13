// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import WinSDK
import XCTest

final class WinUIDividerTests: XCTestCase {
    func testHorizontalAndVerticalDividersPaintAndKeepTheirIdentityWhenResized() throws {
        try onUIThread {
            let width = State(wrappedValue: 120.0), height = State(wrappedValue: 80.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer()
                        Divider().id("horizontal")
                        Spacer()
                    }.frame(width: width.wrappedValue, height: 60)
                    HStack(spacing: 0) {
                        Spacer()
                        Divider().id("vertical")
                        Spacer()
                    }.frame(width: 120, height: height.wrappedValue)
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let horizontal = try XCTUnwrap(host.view(id: .manual("horizontal")) as? WinUIDividerView)
            let vertical = try XCTUnwrap(host.view(id: .manual("vertical")) as? WinUIDividerView)
            XCTAssertEqual(horizontal.frame.width, 120)
            XCTAssertEqual(horizontal.frame.height, 1)
            XCTAssertEqual(vertical.frame.width, 1)
            XCTAssertEqual(vertical.frame.height, 80)
            try assertPainted(horizontal, at: [(1, 0.5), (60, 0.5), (119, 0.5)])
            try assertPainted(vertical, at: [(0.5, 1), (0.5, 40), (0.5, 79)])

            width.wrappedValue = 200
            height.wrappedValue = 100
            host.settle { horizontal.frame.width == 200 && vertical.frame.height == 100 }
            XCTAssertTrue(host.view(id: .manual("horizontal")) === horizontal)
            XCTAssertTrue(host.view(id: .manual("vertical")) === vertical)
            XCTAssertEqual(horizontal.frame.width, 200)
            XCTAssertEqual(horizontal.frame.height, 1)
            XCTAssertEqual(vertical.frame.width, 1)
            XCTAssertEqual(vertical.frame.height, 100)
            try assertPainted(horizontal, at: [(1, 0.5), (100, 0.5), (199, 0.5)])
            try assertPainted(vertical, at: [(0.5, 1), (0.5, 50), (0.5, 99)])
        }
    }

    func testTheNativeThemeResourceChangesWithoutRebuildingTheDivider() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) { Divider().id("line") }.frame(width: 120, height: 1)
            }
            let content = try XCTUnwrap(host.window?.content)
            let line = try XCTUnwrap(host.view(id: .manual("line")) as? WinUIDividerView)
            defer { swiftomniui_winui_set_theme_for_testing(content.handle, 0) }
            var light: UInt32?
            var dark: UInt32?
            for theme in [Int32(1), 2, 1] {
                swiftomniui_winui_set_theme_for_testing(content.handle, theme)
                WinUITestHost.pump()
                host.layOut()
                let fill = try fill(of: line)
                if theme == 1 {
                    if let light { XCTAssertEqual(fill, light, "returning to light restores the native separator brush") }
                    else { light = fill }
                } else { dark = fill }
                try assertPainted(line, at: [(1, 0.5), (60, 0.5), (119, 0.5)])
                XCTAssertTrue(host.view(id: .manual("line")) === line)
            }
            var contrast = HIGHCONTRASTW()
            contrast.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
            XCTAssertNotEqual(SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), contrast.cbSize, &contrast, 0), 0)
            if contrast.dwFlags & DWORD(HCF_HIGHCONTRASTON) == 0 {
                XCTAssertNotEqual(light, dark, "light/dark resource changes must reach the same native rectangle")
            }
        }
    }

    @MainActor private func fill(of view: WinUIDividerView) throws -> UInt32 {
        var bytes = [CChar](repeating: 0, count: 32)
        let length = swiftomniui_winui_read(view.handle, "fill", &bytes, Int32(bytes.count))
        XCTAssertGreaterThan(length, 0)
        let text = String(decoding: bytes.prefix(Int(max(0, length))).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("#"))
        return try XCTUnwrap(UInt32(text.dropFirst(), radix: 16))
    }

    @MainActor private func assertPainted(_ view: WinUIDividerView, at points: [(Double, Double)]) throws {
        let fill = try fill(of: view), alpha = Double(fill >> 24)
        XCTAssertGreaterThan(alpha, 0, "the default native divider must not become a transparent brush")
        for pixel in view.pixels(at: points) {
            XCTAssertEqual(Double(pixel >> 24), alpha, accuracy: 1)
            for shift in [0, 8, 16] {
                XCTAssertEqual(Double(pixel >> shift & 0xFF), Double(fill >> shift & 0xFF) * alpha / 255, accuracy: 1)
            }
        }
    }
}

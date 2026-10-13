// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISystemColorTests: XCTestCase {
    func testCyanReachesTextAndNativePaintWithTheSameSRGBComponents() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    Text("神衍·智能").foregroundStyle(.cyan)
                    Rectangle().fill(.cyan).frame(width: 100, height: 40)
                    Rectangle().fill(LinearGradient(colors: [.cyan, .cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 100, height: 40)
                    Rectangle().fill(Color(red: 0, green: 1, blue: 1)).frame(width: 100, height: 40)
                    Rectangle().fill(Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75)).frame(width: 100, height: 40)
                    Rectangle().fill(.cyan.opacity(0.25)).frame(width: 100, height: 40)
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let previous = StandardEnvironment.appInfo.colorScheme
            defer { host.runtime.core.setColorScheme(previous) }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let shapes = host.views(WinUIPathView.self)
            XCTAssertEqual(shapes.count, 5)
            guard shapes.count == 5 else { return }

            for (scheme, rgb) in [(ColorScheme.light, UInt32(0x00C0E8)), (.dark, UInt32(0x3CD3FE)), (.light, UInt32(0x00C0E8))] {
                host.runtime.core.setColorScheme(scheme)
                host.step()
                let expected = UInt32(0xFF000000) | rgb
                host.settle { shapes[0].pixels(at: [(50, 20)]) == [expected] }
                XCTAssertEqual(label.wordsStyle.color, expected)
                XCTAssertEqual(shapes[0].pixels(at: [(50, 20)]), [expected])
                XCTAssertEqual(shapes[1].pixels(at: [(10, 20), (90, 20)]), [expected, expected])
                XCTAssertEqual(shapes[2].pixels(at: [(50, 20)]), [0xFF00FFFF], "constant RGB stays pure cyan in either theme")
                XCTAssertEqual(shapes[3].pixels(at: [(50, 20)]), [0xFF4080BF], "numeric sRGB channels are not gamma-encoded again")
                let translucent = try XCTUnwrap(shapes[4].pixels(at: [(50, 20)]).first)
                XCTAssertEqual(Double(translucent >> 24), 64, accuracy: 1)
                // RenderTargetBitmap returns premultiplied BGRA; the helper packs it as ARGB.
                for shift in [0, 8, 16] {
                    XCTAssertEqual(Double(translucent >> shift & 0xFF), Double(rgb >> shift & 0xFF) * 64 / 255, accuracy: 1)
                }
                XCTAssertTrue(host.views(WinUILabelView.self).first === label)
                XCTAssertTrue(host.views(WinUIPathView.self).first === shapes[0])
            }
        }
    }
}

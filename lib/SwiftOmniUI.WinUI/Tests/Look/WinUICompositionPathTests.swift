// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// Composition drawing must be sampled on screen, over a known backdrop.
/// RenderTargetBitmap excludes child visuals and cannot verify these vectors.
final class WinUICompositionPathTests: XCTestCase {
    func testRoundedVectorKeepsItsAlphaAndGeometryWhileChangingWidth() throws {
        try onUIThread {
            let width = State(wrappedValue: 100.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                ZStack {
                    Color.white
                    RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.2)).id("vector")
                }.frame(width: width.wrappedValue, height: 60)
            }
            let shape = try XCTUnwrap(host.views(WinUIPathView.self).first)
            let window = try XCTUnwrap(host.window)
            for value in [100.0, 148, 100] {
                width.wrappedValue = value
                host.step()
                let points = [(value / 2, 30.0), (1.0, 1.0), (value - 2, 30.0)]
                host.settle {
                    let pixels = shape.presentedPixels(at: points, in: window)
                    return pixels.count == 3 && abs(Int(pixels[0] & 255) - 204) <= 1
                        && pixels[1] == 0xFFFF_FFFF && abs(Int(pixels[2] & 255) - 204) <= 1
                }
                let pixels = shape.presentedPixels(at: points, in: window)
                XCTAssertEqual(pixels.count, 3)
                guard pixels.count == 3 else { return }
                for index in [0, 2] {
                    for shift in [0, 8, 16] {
                        XCTAssertEqual(Double((pixels[index] >> shift) & 255), 204, accuracy: 1)
                    }
                }
                XCTAssertEqual(pixels[1], 0xFFFF_FFFF)
                XCTAssertTrue(host.views(WinUIPathView.self).first === shape)
                XCTAssertEqual(shape.laidOutFrame.width, value, accuracy: 0.001)
            }
        }
    }

    func testVectorGradientAndEvenOddHoleUseTheLiveCompositionDrawing() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                ZStack {
                    Color.white
                    Path("M 0 0 L 100 0 L 100 60 L 0 60 Z M 40 20 L 60 20 L 60 40 L 40 40 Z")
                        .fill(LinearGradient(colors: [Color("#FF0000"), Color("#0000FF")],
                                             startPoint: .leading, endPoint: .trailing),
                              style: FillStyle(eoFill: true, antialiased: true))
                }.frame(width: 100, height: 60)
            }
            let shape = try XCTUnwrap(host.views(WinUIPathView.self).first)
            let window = try XCTUnwrap(host.window)
            let points = [(2.0, 30.0), (50.0, 30.0), (98.0, 30.0)]
            host.settle {
                let pixels = shape.presentedPixels(at: points, in: window)
                return pixels.count == 3 && pixels[0] & 255 < 32 && pixels[2] >> 16 & 255 < 32
            }
            let pixels = shape.presentedPixels(at: points, in: window)
            XCTAssertEqual(pixels.count, 3)
            guard pixels.count == 3 else { return }
            XCTAssertGreaterThan(pixels[0] >> 16 & 255, 224)
            XCTAssertEqual(pixels[1], 0xFFFF_FFFF)
            XCTAssertGreaterThan(pixels[2] & 255, 224)
        }
    }
}

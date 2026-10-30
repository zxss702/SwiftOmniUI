// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI
@testable import SwiftOmniUIWinUI
import XCTest

/// Composition drawing must be sampled on screen, over a known backdrop.
/// RenderTargetBitmap excludes child visuals and cannot verify these vectors.
final class WinUICompositionPathTests: XCTestCase {
    func testCapsuleKeepsAntialiasedEdgesInsideRedirectedSafeBar() throws {
        try onUIThread {
            let width = State(wrappedValue: 96.0)
            let offset = State(wrappedValue: 0.0)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView {
                    Text("Sidebar").navigationSplitViewColumnWidth(220)
                } content: {
                    ZStack {
                        Color.white
                        Capsule().fill(.black).id("ordinary-pill")
                            .frame(width: width.wrappedValue, height: 32)
                            .offset(x: offset.wrappedValue, y: offset.wrappedValue)
                    }
                } detail: {
                    ScrollView { Text("Expert actions").frame(height: 1200) }
                        .safeAreaInset(edge: .top, spacing: 0) {
                            ScrollView(.horizontal) {
                                HStack {
                                    Button {} label: {
                                        Text("Expert").foregroundStyle(.white)
                                            .frame(width: width.wrappedValue, height: 32)
                                            .background {
                                                Capsule().fill(.black).id("redirected-pill")
                                            }
                                    }.buttonStyle(.plain)
                                        .offset(x: offset.wrappedValue, y: offset.wrappedValue)
                                }.padding(8)
                            }
                            .frame(height: 48)
                            .background(Color.white)
                            .id("expert-pill-bar")
                        }
                        .navigationSplitViewColumnWidth(280)
                }
            }
            let window = try XCTUnwrap(host.window)
            let ordinary = try XCTUnwrap(host.view(id: .manual("ordinary-pill")))
            let redirected = try XCTUnwrap(host.view(id: .manual("redirected-pill")))
            let bar = try XCTUnwrap(host.view(id: .manual("expert-pill-bar")))
            for (nextWidth, nextOffset) in [(96.0, 0.0), (138, 0.35), (96, 0)] {
                width.wrappedValue = nextWidth
                offset.wrappedValue = nextOffset
                for _ in 0..<8 { host.step(); host.frame() }
                XCTAssertTrue(swiftomniui_winui_window_material_redirects(window.handle, bar.presentationHandle),
                              "this must exercise the captured fixed-control path, not just the ordinary shape")
                // Sample along both curved edges. Pure black/white alone is an
                // aliased silhouette; fractional coverage must survive capture.
                // Presented pixels are required: RenderTargetBitmap omits the
                // Composition ShapeVisual and SafeBar redirection entirely.
                var edge: [(Double, Double)] = []
                for row in 0..<32 {
                    let y = (Double(row) + 0.5) / 2
                    let x = 16 - (256 - (y - 16) * (y - 16)).squareRoot()
                    for delta in [-0.75, -0.25, 0.25, 0.75] {
                        edge.append((max(0.125, x + delta), y))
                        edge.append((min(nextWidth - 0.125, nextWidth - x - delta), y))
                    }
                }
                for pill in [ordinary, redirected] {
                    host.settle {
                        pill.presentedPixels(at: [(nextWidth / 2, 28)], in: window) == [0xFF00_0000]
                    }
                    XCTAssertEqual(pill.presentedPixels(at: [(nextWidth / 2, 28)], in: window), [0xFF00_0000],
                                   "antialiasing must not blur or lighten the solid interior")
                    let pixels = pill.presentedPixels(at: edge, in: window)
                    XCTAssertEqual(pixels.count, edge.count)
                    let coverage = pixels.filter { pixel in
                        let value = pixel & 255
                        return value > 8 && value < 247
                            && abs(Int(pixel >> 8 & 255) - Int(value)) <= 2
                            && abs(Int(pixel >> 16 & 255) - Int(value)) <= 2
                    }
                    XCTAssertGreaterThan(coverage.count, 4, "curved edges must retain antialiased coverage")
                    XCTAssertEqual(pill.presentedPixels(at: [(1, 1), (nextWidth - 2, 1)], in: window),
                                   [0xFFFF_FFFF, 0xFFFF_FFFF], "the capsule must retain clear corners")
                }
            }
        }
    }

    func testRoundedVectorKeepsItsAlphaAndGeometryWhileChangingWidth() throws {
        try onUIThread {
            let width = State(wrappedValue: 100.0)
            let alpha = State(wrappedValue: 0.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                ZStack {
                    Color.white
                    RoundedRectangle(cornerRadius: 20).fill(.black.opacity(alpha.wrappedValue)).id("vector")
                }.frame(width: width.wrappedValue, height: 60)
                    .frame(width: 200, height: 100)
            }
            // Color.white also owns a Rectangle. Inspect the foreground vector.
            let shape = try XCTUnwrap(host.views(WinUIPathView.self).last)
            let window = try XCTUnwrap(host.window)
            for (value, opacity) in [(100.0, 0.0), (100, 0.2), (148, 0.2), (148, 0), (100, 0), (100, 0.2)] {
                width.wrappedValue = value
                alpha.wrappedValue = opacity
                host.step()
                XCTAssertEqual(shape.drawsInk, opacity > 0)
                let expected = Int((255 * (1 - opacity)).rounded())
                let points = [(value / 2, 30.0), (1.0, 1.0), (value - 2, 30.0)]
                host.settle {
                    guard abs(shape.laidOutFrame.width - value) < 0.001 else { return false }
                    let pixels = shape.presentedPixels(at: points, in: window)
                    return pixels.count == 3 && abs(Int(pixels[0] & 255) - expected) <= 1
                        && pixels[1] == 0xFFFF_FFFF && abs(Int(pixels[2] & 255) - expected) <= 1
                }
                let pixels = shape.presentedPixels(at: points, in: window)
                XCTAssertEqual(pixels.count, 3)
                guard pixels.count == 3 else { return }
                for index in [0, 2] {
                    for shift in [0, 8, 16] {
                        XCTAssertEqual(Double((pixels[index] >> shift) & 255), Double(expected), accuracy: 1)
                    }
                }
                XCTAssertEqual(pixels[1], 0xFFFF_FFFF)
                XCTAssertTrue(host.views(WinUIPathView.self).last === shape)
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

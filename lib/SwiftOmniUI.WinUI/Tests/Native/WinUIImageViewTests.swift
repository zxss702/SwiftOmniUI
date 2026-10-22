// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
import Foundation
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIImageViewTests: XCTestCase {
    func testSupersampledMemoryImagePreservesThinStrokeCoverageWhenDisplayed() throws {
        try onUIThread {
            var rgba = [UInt8](repeating: 0, count: 64 * 64 * 4)
            for y in 0..<64 {
                for x in stride(from: 0, to: 64, by: 4) {
                    let at = (y * 64 + x) * 4
                    rgba[at] = 255; rgba[at + 3] = 255
                }
            }
            let bitmap = try XCTUnwrap(BitmapImage(pixels: PicturePixels(width: 64, height: 64, rgba: rgba),
                                                  scale: 16, size: Size(4, 4)))
            let host = WinUIRenderer.running(reducesMotion: true) {
                Image(ImageSource(bitmap: bitmap)).frame(width: 4, height: 4)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            host.settle { ((try? Self.decoded(image))?.width ?? 64) < 64 }
            let result = try Self.decoded(image)
            XCTAssertLessThan(result.width, 64)
            let alpha = stride(from: 3, to: result.rgba.count, by: 4).map { Int(result.rgba[$0]) }
            XCTAssertEqual(Double(alpha.reduce(0, +)) / Double(alpha.count), 255.0 / 4, accuracy: 1,
                           "Area filtering must preserve the coverage of subpixel strokes")
            for at in stride(from: 0, to: result.rgba.count, by: 4) {
                XCTAssertEqual(result.rgba[at], result.rgba[at + 3])
                XCTAssertEqual(result.rgba[at + 1], 0)
                XCTAssertEqual(result.rgba[at + 2], 0)
            }
            XCTAssertEqual(image.measure(width: nil, height: nil), LayoutSize(width: 4, height: 4))
        }
    }

    /// Inspect decoded bytes directly, before the UI queue has any chance to
    /// finish a load. Metadata or a later rendered screenshot alone cannot prove this.
    @MainActor
    private static func decoded(_ image: WinUIImageView) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        var size: [Int32] = [0, 0]
        XCTAssertTrue(swiftomniui_winui_image_decoded_pixels(image.handle, &size, nil, 0))
        let width = Int(size[0]), height = Int(size[1])
        guard width > 0, height > 0 else {
            throw NSError(domain: "WinUIImageViewTests.MissingDecodedPixels", code: 1)
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        XCTAssertTrue(swiftomniui_winui_image_decoded_pixels(image.handle, &size, &rgba, Int64(rgba.count)))
        return (width, height, rgba)
    }

    private static func pixel(_ decoded: (width: Int, height: Int, rgba: [UInt8]), x: Int, y: Int) -> [UInt8] {
        let start = (y * decoded.width + x) * 4
        return Array(decoded.rgba[start..<(start + 4)])
    }

    func testAnSVGHasActualPixelsBeforeApplyReturns() throws {
        try onUIThread {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: WinUITestHost.pictures + "/test_halves.svg",
                                             toPath: folder.path + "/cold.svg")
            swiftomniui_winui_set_pictures(folder.path)
            defer {
                swiftomniui_winui_set_pictures(WinUITestHost.pictures)
                try? FileManager.default.removeItem(at: folder)
            }
            let image = WinUIImageView()
            image.apply(source: ImageSource("cold.svg"), aspect: .fit, resizable: true)
            let data = try Self.decoded(image)
            XCTAssertEqual(data.width, 40)
            XCTAssertEqual(data.height, 20)
            XCTAssertEqual(Self.pixel(data, x: 5, y: 10), [255, 0, 0, 255])
            XCTAssertEqual(Self.pixel(data, x: 35, y: 10), [0, 0, 255, 255])
            XCTAssertEqual(image.measure(width: nil, height: nil), LayoutSize(width: 40, height: 20))
        }
    }

    func testRecycledRowsShareReadySVGPixelsAndIgnoreFileFontChanges() throws {
        try onUIThread {
            let first = WinUIImageView()
            let second = WinUIImageView()
            for image in [first, second] {
                image.apply(source: ImageSource("test_halves.svg"), aspect: .fit, resizable: true)
                image.prepareMeasure(width: 80, height: 40)
                swiftomniui_winui_arrange(image.handle, 0, 0, 80, 40)
                XCTAssertEqual(image.committedFrame, Rect(0, 0, 80, 40))
            }
            XCTAssertTrue(swiftomniui_winui_images_share_source(first.handle, second.handle))
            var font = TextLook()
            font.size = 48
            first.apply(source: ImageSource("test_halves.svg"), aspect: .fit, resizable: true, font: font)
            XCTAssertTrue(swiftomniui_winui_images_share_source(first.handle, second.handle),
                          "inherited font changes must not replace a file image's prepared raster")
            let data = try Self.decoded(first)
            XCTAssertEqual(data.width, 80)
            XCTAssertEqual(data.height, 40)
            XCTAssertEqual(Self.pixel(data, x: 10, y: 20), [255, 0, 0, 255])
            XCTAssertEqual(Self.pixel(data, x: 70, y: 20), [0, 0, 255, 255])
        }
    }

    func testStretchPreparesPixelsSynchronouslyAndKeepsTheDeclaredSize() throws {
        try onUIThread {
            let image = WinUIImageView()
            image.apply(source: ImageSource("test_halves.svg"), aspect: .stretch, resizable: true)
            image.prepareMeasure(width: 80, height: 80)
            swiftomniui_winui_arrange(image.handle, 0, 0, 80, 80)
            XCTAssertEqual(image.committedFrame, Rect(0, 0, 80, 80))
            let data = try Self.decoded(image)
            XCTAssertEqual(data.width, 80)
            XCTAssertEqual(data.height, 80)
            XCTAssertEqual(Self.pixel(data, x: 10, y: 5), [255, 0, 0, 255])
            XCTAssertEqual(Self.pixel(data, x: 70, y: 75), [0, 0, 255, 255])
            XCTAssertEqual(image.measure(width: nil, height: nil), LayoutSize(width: 40, height: 20))
        }
    }

    func testChangingFoldersAndSourcesBeforeTheFirstFrameShowsOnlyTheNewPixels() throws {
        try onUIThread {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let red = folder.appendingPathComponent("red"), blue = folder.appendingPathComponent("blue")
            for (path, color) in [(red, "red"), (blue, "blue")] {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                try "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 8 8\"><rect width=\"8\" height=\"8\" fill=\"\(color)\"/></svg>"
                    .write(to: path.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)
            }
            defer {
                swiftomniui_winui_set_pictures(WinUITestHost.pictures)
                try? FileManager.default.removeItem(at: folder)
            }
            let image = WinUIImageView()
            swiftomniui_winui_set_pictures(red.path)
            image.apply(source: ImageSource("icon.svg"), aspect: .fit, resizable: true)
            XCTAssertEqual(Self.pixel(try Self.decoded(image), x: 4, y: 4), [255, 0, 0, 255])
            swiftomniui_winui_set_pictures(blue.path)
            image.apply(source: ImageSource("icon.svg"), aspect: .fit, resizable: true)
            XCTAssertEqual(Self.pixel(try Self.decoded(image), x: 4, y: 4), [0, 0, 255, 255])
            image.apply(source: nil, aspect: .fit)
            XCTAssertEqual(image.measure(width: nil, height: nil), .zero, "clearing a source clears its intrinsic size")
        }
    }

    func testExpandedLazyFileRowsHaveReadyIconsWhenMounted() throws {
        try onUIThread {
            let rows = State(wrappedValue: Array(0..<4))
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.wrappedValue) { number in
                            HStack {
                                Image("test_halves.svg").resizable().scaledToFit().frame(width: 20, height: 20)
                                Text("File \(number)")
                            }
                            .frame(height: 28)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 320, height: 320)
            }
            for _ in 0..<8 { host.step() }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let original = try XCTUnwrap(host.views(WinUIImageView.self).first)
            for count in [12, 4, 12] {
                rows.wrappedValue = Array(0..<count)
                host.runtime.pump.turn()
                // Realize the fresh identities directly. Check bytes before running
                // another UI-loop step, where an asynchronous image load could finish.
                lazy.cells.tellAll()
                host.runtime.pump.turn()
                let images = host.views(WinUIImageView.self)
                XCTAssertEqual(images.count, count)
                XCTAssertTrue(images.contains { $0 === original }, "surviving rows keep their native image")
                for image in images {
                    let data = try Self.decoded(image)
                    XCTAssertGreaterThan(data.rgba[3], 0)
                }
            }
        }
    }

    func testSystemGlyphsPaintAtDisclosureAndButtonSizesAfterPageReplacement() throws {
        try onUIThread {
            let alternate = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true) {
                HStack(spacing: 12) {
                    if alternate.wrappedValue {
                        Text("Replacement")
                    } else {
                        Image(systemName: "\u{E70D}")
                            .foregroundStyle(.black)
                            .id("disclosure")
                            .frame(width: 8, height: 8)
                        Image(systemName: "\u{E723}")
                            .foregroundStyle(.black)
                            .id("attachment")
                            .frame(width: 40, height: 40)
                    }
                }
                .frame(width: 180, height: 64)
            }
            @MainActor func visible(_ id: String, width: Int, height: Int) throws {
                let image = try XCTUnwrap(host.view(id: .manual(id)) as? WinUIImageView)
                let points = (0..<height).flatMap { y in
                    (0..<width).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
                }
                XCTAssertTrue(image.pixels(at: points).contains { ($0 >> 24) != 0 },
                              "the native glyph must paint pixels in the allocated image")
            }
            host.settle { (host.view(id: .manual("attachment"))?.laidOutFrame.width ?? 0) > 0 }
            host.layOut()
            try visible("disclosure", width: 8, height: 8)
            try visible("attachment", width: 40, height: 40)
            alternate.wrappedValue = true
            host.settle { host.view(id: .manual("attachment")) == nil }
            alternate.wrappedValue = false
            host.settle { (host.view(id: .manual("attachment"))?.laidOutFrame.width ?? 0) > 0 }
            host.layOut()
            try visible("disclosure", width: 8, height: 8)
            try visible("attachment", width: 40, height: 40)
        }
    }

    func testSystemGlyphUsesFluentFontAndPaintsWithoutAnExplicitForeground() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                HStack {
                    Image(systemName: "\u{E8D5}").id("folder").frame(width: 16, height: 16)
                    Image(systemName: "\u{E721}").foregroundStyle(.black)
                        .id("search").frame(width: 20, height: 20)
                }
                .frame(width: 100, height: 40)
            }
            host.settle { host.view(id: .manual("search"))?.laidOutFrame.width == 20 }
            host.layOut()
            for (id, size) in [("folder", 16), ("search", 20)] {
                let image = try XCTUnwrap(host.view(id: .manual(id)) as? WinUIImageView)
                let points = (0..<size).flatMap { y in
                    (0..<size).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
                }
                XCTAssertTrue(image.pixels(at: points).contains { ($0 >> 24) != 0 },
                              "the system FontIcon must paint both theme and explicit tint")
            }
        }
    }

    func testFootnoteDisclosureGlyphPaintsAfterNativeStyleResolution() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                Image(systemName: "\u{E70D}")
                    .font(.footnote)
                    .foregroundStyle(.black)
                    .id("styledDisclosure")
                    .frame(width: 24, height: 24)
            }
            host.settle { host.view(id: .manual("styledDisclosure"))?.laidOutFrame.width == 24 }
            host.layOut()
            let image = try XCTUnwrap(host.view(id: .manual("styledDisclosure")) as? WinUIImageView)
            XCTAssertTrue(image.found)
            XCTAssertGreaterThan(image.measure(width: nil, height: nil).width, 0)
            let points = (0..<24).flatMap { y in
                (0..<24).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
            }
            XCTAssertTrue(image.pixels(at: points).contains { ($0 >> 24) != 0 },
                          "a .footnote style must keep the native FontIcon visible")
        }
    }

    func testRawFluentGlyphsSurviveRepeatedNativeUpdates() throws {
        try onUIThread {
            let image = WinUIImageView()
            var size = [0.0, 0.0]
            for glyph in ["\u{E701}", "\u{E70D}", "\u{E723}", "\u{E721}", "\u{E8D5}"] {
                XCTAssertTrue(swiftomniui_winui_image_set_symbol(
                    image.handle, glyph, ContentMode.center.rawValue, 16, 700, -1, &size),
                    "a FontIcon glyph must not fail an interface query")
                XCTAssertEqual(size, [16, 16])
                swiftomniui_winui_image_set_tint(image.handle, true, 0xff000000)
            }
        }
    }

    /// A new file is decoded before apply returns, without pumping the UI queue or relying on its metadata.
    func testABitmapIsDecodedBeforeApplyReturns() throws {
        try onUIThread {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: WinUITestHost.pictures + "/test_dot.png", toPath: folder.path + "/dot.png")
            swiftomniui_winui_set_pictures(folder.path)
            defer {
                swiftomniui_winui_set_pictures(WinUITestHost.pictures)
                try? FileManager.default.removeItem(at: folder)
            }
            let image = WinUIImageView()
            image.apply(source: ImageSource("dot.png"), aspect: .fit)
            let pixels = try Self.decoded(image)
            XCTAssertEqual(pixels.width, 6)
            XCTAssertEqual(pixels.height, 4)
            XCTAssertTrue(stride(from: 3, to: pixels.rgba.count, by: 4).contains { pixels.rgba[$0] > 0 },
                          "a cold bitmap must have actual visible pixels before apply returns")
            var size = [0.0, 0.0]
            swiftomniui_winui_image_size(image.handle, &size)
            XCTAssertEqual(size, [6, 4])
            XCTAssertEqual(image.measure(width: nil, height: nil), LayoutSize(width: 6, height: 4))
        }
    }

    /// A decoded bitmap gives its ancestors their final size at the first layout.
    func testABitmapSizesItsAncestorsAtTheFirstLayout() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack { HStack { Image("test_dot.png") } }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
            }
            let row = try XCTUnwrap(host.views(WinUIStackView.self).last)
            XCTAssertTrue(row.frame == (0, 0, 6, 4), "\(row.frame)")
            host.step()
            XCTAssertTrue(row.frame == (0, 0, 6, 4), "\(row.frame)")
        }
    }

    /// An SVG stands at the size it declares: its width and height, the one it leaves out taken from its viewBox's
    /// proportions, or its viewBox alone.
    func testAnSVGStandsAtTheSizeItDeclares() throws {
        try onUIThread {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftomniui-winui-svg")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let figure = "<rect width=\"10\" height=\"10\" fill=\"red\"/></svg>"
            let pictures: [(name: String, tag: String, width: Double, height: Double)] = [
                ("sized.svg", "width=\"30\" height=\"20\" viewBox=\"0 0 3 2\"", 30, 20),
                ("boxed.svg", "viewBox=\"0 0 40 10\"", 40, 10),
                ("wide.svg", "width=\"60\" viewBox=\"0,0,40,10\"", 60, 15),
                ("tall.svg", "height=\"30pt\" viewBox=\"0 0 10 20\"", 20, 40),
            ]
            for picture in pictures {
                try "<svg xmlns=\"http://www.w3.org/2000/svg\" \(picture.tag)>\(figure)".write(
                    to: folder.appendingPathComponent(picture.name), atomically: true, encoding: .utf8)
            }
            swiftomniui_winui_set_pictures(folder.path)
            defer { swiftomniui_winui_set_pictures("") }

            for picture in pictures {
                let host = WinUIRenderer.running {
                    VStack { HStack { Image(ImageSource(picture.name)) } }
                        .horizontalAlignment(.start)
                        .verticalAlignment(.start)
                }
                let row = try XCTUnwrap(host.views(WinUIStackView.self).last)
                host.settle { row.frame.width == picture.width }

                XCTAssertTrue(row.frame == (0, 0, picture.width, picture.height), "\(picture.name): \(row.frame)")
            }
        }
    }
}

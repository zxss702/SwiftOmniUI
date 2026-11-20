// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
import Foundation
import SwiftOmniUIConformance
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIImageViewTests: XCTestCase {
    func testFittedImageStaysCenteredWhileItsInnerFrameResizes() throws {
        try onUIThread {
            let clock = TestClock()
            let selected = State(wrappedValue: true)
            let host = WinUIRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    let size = selected.wrappedValue ? 24.0 : 32.0
                    Image("test_large_halves.png").resizable().scaledToFit()
                        .frame(width: size, height: size)
                        .frame(width: 32, height: 32)
                        .id("icon-slot")
                    if selected.wrappedValue {
                        Text("Caption").lineLimit(1).transition(.blur)
                    }
                }
                .animation(.eased(240, .linear), value: selected.wrappedValue)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            let inner = try XCTUnwrap(image.placingLayout)
            let slot = try XCTUnwrap(host.view(id: .manual("icon-slot")))
            host.settle { image.laidOutFrame.width > 0 }
            XCTAssertTrue(inner.placingLayout === slot)
            XCTAssertEqual(image.laidOutFrame.width, 24, accuracy: 0.5)

            for selection in [false, true] {
                let start = clock.now
                selected.wrappedValue = selection
                host.step()
                host.frame()
                for elapsed in [0.0, 60, 120, 180, 240] {
                    clock.now = start + elapsed
                    host.frame()
                    let frame = image.laidOutFrame
                    let offset = try XCTUnwrap(image.layoutOffset(relativeTo: slot))
                    XCTAssertEqual(frame.width, inner.laidOutFrame.width, accuracy: 0.5)
                    XCTAssertEqual(frame.height, frame.width / 2, accuracy: 0.5)
                    XCTAssertEqual(offset.x + frame.width / 2, 16, accuracy: 0.5)
                    XCTAssertEqual(offset.y + frame.height / 2, 16, accuracy: 0.5)
                    if elapsed == 120 {
                        XCTAssertEqual(frame.width, 28, accuracy: 0.5)
                        // Give XAML a paint turn at the same test-clock time
                        // before reading the pixels of this layout sample.
                        WinUITestHost.pump(0.04)
                        let coordinates = stride(from: 0.25, to: 32, by: 0.5).map { $0 }
                        let pixels = slot.pixels(at: coordinates.map { ($0, 16) } + coordinates.map { (8, $0) })
                        let axes = [pixels.prefix(coordinates.count), pixels.suffix(coordinates.count)]
                        let extents = zip(axes, [28.0, 14.0])
                        for (axis, extent) in extents {
                            let colored = zip(coordinates, axis).compactMap { point, pixel in pixel >> 24 > 127 ? point : nil }
                            let first = try XCTUnwrap(colored.first)
                            let last = try XCTUnwrap(colored.last)
                            let note = "selection \(selection), expected \(extent) DIP, bitmap sampled from \(first) to \(last)"
                            XCTAssertEqual((first + last) / 2, 16, accuracy: 0.75, note)
                            XCTAssertEqual(last - first + 0.5, extent, accuracy: 1, note)
                        }
                    }
                }
                XCTAssertEqual(image.laidOutFrame.width, selection ? 24 : 32, accuracy: 0.5)
            }
        }
    }

    func testTabIconsStayCenteredThroughRepeatedSelectionChanges() throws {
        try onUIThread {
            let tracePath = ProcessInfo.processInfo.environment["SOUI_TAB_GEOMETRY_TRACE"]
            var trace: [TabGeometrySample] = []
            for (usesButtons, usesSafeBar) in [(false, false), (true, false), (true, true)] {
                let clock = TestClock()
                let selection = State(wrappedValue: 0)
                let host = WinUIRenderer.running(clock: clock) {
                    AnimatedIconTabs(selection: selection, usesButtons: usesButtons, usesSafeBar: usesSafeBar)
                }
                let icons = host.views(WinUIImageView.self)
                guard icons.count == (usesSafeBar ? 3 : 2) else {
                    XCTFail("unexpected tab icon count: \(icons.count)")
                    return
                }
                let slots = try icons.map { try XCTUnwrap($0.placingLayout?.placingLayout) }
                let buttons = host.views(WinUIButtonView.self)
                guard !usesButtons || buttons.count == icons.count else {
                    XCTFail("each icon must have one native button")
                    return
                }
                host.frame()
                let rowCenters = slots.map { $0.origin.y + $0.laidOutFrame.height / 2 }
                let scenario = usesSafeBar ? "safe-bar" : usesButtons ? "scroll-buttons" : "plain-stack"

                @MainActor func capture(_ phase: String, from previous: Int, to next: Int, elapsed: Double) {
                    guard tracePath != nil else { return }
                    for (index, (icon, slot)) in zip(icons, slots).enumerated() {
                        let button = usesButtons ? buttons[index] : nil
                        trace.append(TabGeometrySample(
                            scenario: scenario, phase: phase, from: previous, to: next, icon: index,
                            elapsedMS: elapsed, image: .init(icon), innerFrame: icon.placingLayout.map { TabGeometry($0) },
                            slot: .init(slot), button: button.map { TabGeometry($0) },
                            imageOffsetInSlot: icon.layoutOffset(relativeTo: slot).map { [$0.x, $0.y] },
                            imageOffsetInButton: button.flatMap { icon.layoutOffset(relativeTo: $0) }.map { [$0.x, $0.y] },
                            nativePictureFrame: Self.nativePictureFrame(icon)))
                    }
                }

                var previous = 0
                for next in usesSafeBar ? [1, 2, 0, 2, 1] : [1, 0, 1] {
                    let start = clock.now
                    capture("before-click", from: previous, to: next, elapsed: 0)
                    if usesButtons {
                        let button = try XCTUnwrap(buttons.indices.contains(next) ? buttons[next] : nil)
                        swiftomniui_winui_button_invoke(button.handle)
                    } else {
                        selection.wrappedValue = next
                    }
                    host.runtime.pump.turn()
                    host.layOut()
                    capture("after-layout", from: previous, to: next, elapsed: 0)
                    XCTAssertEqual(icons[next].laidOutFrame.width, 32, accuracy: 0.5,
                                   "laying out the state change before the first tick must preserve the incoming size")
                    XCTAssertEqual(icons[previous].laidOutFrame.width, 24, accuracy: 0.5,
                                   "laying out the state change before the first tick must preserve the outgoing size")
                    var sawIntermediateSize = false
                    for elapsed in stride(from: 0.0, through: 720, by: 16) {
                        clock.now = start + elapsed
                        host.frame()
                        capture("frame", from: previous, to: next, elapsed: elapsed)
                        for (index, (icon, slot)) in zip(icons, slots).enumerated() {
                            let frame = icon.laidOutFrame
                            let offset = try XCTUnwrap(icon.layoutOffset(relativeTo: slot))
                            let note = "buttons \(usesButtons), safe bar \(usesSafeBar), icon \(index), tab \(next), frame at \(elapsed)ms"
                            XCTAssertEqual(slot.laidOutFrame.width, 32, accuracy: 0.5, note)
                            XCTAssertEqual(slot.laidOutFrame.height, 32, accuracy: 0.5, note)
                            XCTAssertEqual(offset.x + frame.width / 2, 16, accuracy: 0.5, note)
                            XCTAssertEqual(offset.y + frame.height / 2, 16, accuracy: 0.5, note)
                            let native = try XCTUnwrap(Self.nativePictureFrame(icon))
                            XCTAssertEqual(native[0] + native[2] / 2, frame.width / 2, accuracy: 0.5, note)
                            XCTAssertEqual(native[1] + native[3] / 2, frame.height / 2, accuracy: 0.5, note)
                            XCTAssertEqual(native[2], frame.width, accuracy: 0.5, note)
                            XCTAssertEqual(native[3], frame.height, accuracy: 0.5, note)
                            XCTAssertEqual(slot.origin.y + offset.y + frame.height / 2,
                                           rowCenters[index], accuracy: 0.5, note)
                            if usesButtons {
                                let offsetInButton = try XCTUnwrap(icon.layoutOffset(relativeTo: buttons[index]))
                                let horizontalCenter = offsetInButton.x + frame.width / 2
                                XCTAssertGreaterThanOrEqual(horizontalCenter, 15.5, note)
                                XCTAssertLessThanOrEqual(horizontalCenter, 21.0, note)
                            }
                            sawIntermediateSize = sawIntermediateSize || (frame.width > 25 && frame.width < 31)
                        }
                    }
                    XCTAssertTrue(sawIntermediateSize, "the icon size must animate on tab \(next)")
                    XCTAssertEqual(icons[next].laidOutFrame.width, 24, accuracy: 0.5)
                    XCTAssertEqual(icons[previous].laidOutFrame.width, 32, accuracy: 0.5)
                    previous = next
                }
            }
            if let tracePath {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(trace).write(to: URL(fileURLWithPath: tracePath), options: .atomic)
            }
        }
    }

    @MainActor private static func nativePictureFrame(_ image: WinUIImageView) -> [Double]? {
        var frame = [Double](repeating: 0, count: 4)
        return swiftomniui_winui_image_content_frame(image.handle, &frame) ? frame : nil
    }

    func testHeightOnlyFittedIconKeepsTheButtonLabelCompact() throws {
        try onUIThread {
            struct ToolFileIcon: View {
                var body: some View {
                    Image("test_halves.svg").resizable().scaledToFit()
                }
            }
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                VStack(alignment: .leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "\u{E7B3}").resizable().scaledToFit()
                            .frame(width: 12, height: 12)
                        Text("Read").id("tool-name")
                        Button {} label: {
                            HStack(spacing: 8) {
                                ToolFileIcon()
                                    .frame(height: 12)
                                    .id("icon-frame")
                                Text("Package").lineLimit(1).id("file-name")
                            }
                        }
                        .buttonStyle(.plain)
                        Text("1 - 201").font(.footnote).bold().id("line-range")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            host.settle { (host.view(id: .manual("file-name"))?.placedFrame.width ?? 0) > 0 }
            let tool = try XCTUnwrap(host.view(id: .manual("tool-name"))).placedFrame
            let icon = try XCTUnwrap(host.view(id: .manual("icon-frame"))).placedFrame
            let name = try XCTUnwrap(host.view(id: .manual("file-name"))).placedFrame
            let range = try XCTUnwrap(host.view(id: .manual("line-range"))).placedFrame

            XCTAssertEqual(icon.height, 12, accuracy: 0.5)
            XCTAssertEqual(icon.width, 24, accuracy: 0.5)
            XCTAssertEqual(name.x - (icon.x + icon.width), 8, accuracy: 0.5)
            XCTAssertLessThan(range.x - (tool.x + tool.width), 200,
                              "a height-fixed scaledToFit icon must not expand across an infinity-maxWidth leading row")
        }
    }

    private func checkSymbolCanStartUnscaledThenScaleAndSwitchToPixels() throws {
        try onUIThread {
            let mode = State(wrappedValue: 0)
            let pixels = PicturePixels(width: 2, height: 2,
                                       rgba: Array(repeating: [UInt8(255), 0, 0, 255], count: 4).flatMap { $0 })
            let bitmap = try XCTUnwrap(BitmapImage(pixels: pixels, size: Size(2, 2)))
            let host = WinUIRenderer.running(reducesMotion: true) {
                Image(mode.wrappedValue == 2 ? ImageSource(bitmap: bitmap) : .symbol("\u{E8B7}"))
                    .setValue(ImageContract.isResizable, mode.wrappedValue != 0)
                    .scaledToFit().font(.system(size: 16)).foregroundStyle(.black)
                    .horizontalAlignment(.fill).verticalAlignment(.fill)
                    .frame(width: 64, height: 64)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            let points = (0..<64).flatMap { y in
                (0..<64).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
            }
            @MainActor func inkWidth() -> Int {
                let ink = image.pixels(at: points).enumerated().compactMap { index, pixel in
                    pixel >> 24 > 32 ? index % 64 : nil
                }
                return ink.isEmpty ? 0 : ink.max()! - ink.min()! + 1
            }
            for value in [0, 1, 0, 1, 2, 0] {
                mode.wrappedValue = value
                host.step()
                host.layOut()
                XCTAssertTrue(host.views(WinUIImageView.self).first === image)
                XCTAssertEqual(image.laidOutFrame.width, 64, accuracy: 0.001)
                XCTAssertEqual(image.laidOutFrame.height, 64, accuracy: 0.001)
                let width = inkWidth()
                XCTAssertGreaterThan(width, value != 0 ? 32 : 4)
                if value == 0 { XCTAssertLessThanOrEqual(width, 18) }
                if value == 2 {
                    XCTAssertTrue(image.pixels(at: points).allSatisfy { $0 == 0xffff0000 },
                                  "switching a symbol to pixels must hide the previous glyph")
                }
            }
        }
    }

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

    func testLargeCustomImagePaintsBothSidesWhenScaledIntoSmallFrame() throws {
        try onUIThread {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try """
                <svg xmlns="http://www.w3.org/2000/svg" width="400" height="200" viewBox="0 0 400 200">
                  <rect width="200" height="200" fill="red"/>
                  <rect x="200" width="200" height="200" fill="blue"/>
                </svg>
                """.write(to: folder.appendingPathComponent("large.svg"), atomically: true, encoding: .utf8)
            swiftomniui_winui_set_pictures(folder.path)
            defer {
                swiftomniui_winui_set_pictures(WinUITestHost.pictures)
                try? FileManager.default.removeItem(at: folder)
            }
            let host = WinUIRenderer.running {
                Image("large.svg").resizable().scaledToFit().frame(width: 40, height: 40)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            host.settle { image.laidOutFrame.width > 0 }
            host.layOut()
            let colors = image.pixels(at: [(10, 20), (30, 20)])
            XCTAssertEqual(colors.map { $0 & 0x00FF_FFFF }, [0x00FF_0000, 0x0000_00FF])
        }
    }

    func testLargePNGPaintsBothSidesWhenScaledIntoSmallFrame() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                Image("test_large_halves.png").resizable().scaledToFit().frame(width: 40, height: 40)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            host.settle { image.laidOutFrame.width > 0 }
            host.layOut()
            let frame = image.laidOutFrame
            XCTAssertEqual(frame.width, 40, accuracy: 0.5)
            XCTAssertEqual(frame.height, 20, accuracy: 0.5)
            let colors = image.pixels(at: [(10, frame.height / 2), (30, frame.height / 2)])
            XCTAssertEqual(colors.map { $0 & 0x00FF_FFFF }, [0x00FF_0000, 0x0000_00FF])
        }
    }

    func testMemoryBitmapUsesLogicalSizeAndScalesWithinFrame() throws {
        try onUIThread {
            let rgba = (0..<(40 * 20)).flatMap { index -> [UInt8] in
                index % 40 < 20 ? [255, 0, 0, 255] : [0, 0, 255, 255]
            }
            let pixels = PicturePixels(width: 40, height: 20, rgba: rgba)
            let bitmap = try XCTUnwrap(BitmapImage(pixels: pixels,
                                                   size: Size(width: 400, height: 200)))
            let host = WinUIRenderer.running {
                Image(ImageSource(bitmap: bitmap)).resizable().scaledToFit()
                    .frame(width: 40, height: 40)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            host.settle { image.laidOutFrame.width > 0 }
            host.layOut()
            let colors = image.pixels(at: [(10, 20), (30, 20)])
            XCTAssertEqual(colors.map { $0 & 0x00FF_FFFF }, [0x00FF_0000, 0x0000_00FF])
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
            @MainActor func glyph(_ symbol: String) -> WinUIImageView? {
                host.views(WinUIImageView.self).first {
                    $0.sourceElement?.value(ImageContract.source.token) == .name(symbol)
                }
            }
            @MainActor func visible(_ symbol: String, width: Int, height: Int) throws {
                let image = try XCTUnwrap(glyph(symbol))
                let points = (0..<height).flatMap { y in
                    (0..<width).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
                }
                XCTAssertTrue(image.pixels(at: points).contains { ($0 >> 24) != 0 },
                              "the native glyph must paint pixels in the allocated image")
            }
            host.settle { (glyph("\u{E723}")?.laidOutFrame.width ?? 0) > 0 }
            host.layOut()
            try visible("\u{E70D}", width: 8, height: 8)
            try visible("\u{E723}", width: 40, height: 40)
            alternate.wrappedValue = true
            host.settle { glyph("\u{E723}") == nil }
            alternate.wrappedValue = false
            host.settle { (glyph("\u{E723}")?.laidOutFrame.width ?? 0) > 0 }
            host.layOut()
            try visible("\u{E70D}", width: 8, height: 8)
            try visible("\u{E723}", width: 40, height: 40)
        }
    }

    func testSymbolInFixedButtonLabelRepaintsWhenItsSourceChanges() throws {
        try onUIThread {
            let paused = State(wrappedValue: false)
            let pause = "\u{E769}"
            let play = "\u{E768}"
            let host = WinUIRenderer.running {
                Button {} label: {
                    Image(systemName: paused.wrappedValue ? play : pause)
                        .contentTransition(.symbolEffect)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
            }
            let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
            host.settle { image.laidOutFrame.width > 0 }
            host.layOut()
            let width = Int(ceil(image.laidOutFrame.width))
            let height = Int(ceil(image.laidOutFrame.height))
            XCTAssertGreaterThan(width, 0)
            XCTAssertGreaterThan(height, 0)
            let points = (0..<height).flatMap { y in
                (0..<width).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
            }
            var last = image.pixels(at: points)
            XCTAssertTrue(last.contains { ($0 >> 24) != 0 })

            for isPaused in [true, false, true, false] {
                withAnimation(.snappy) { paused.wrappedValue = isPaused }
                host.step()
                host.frame()
                XCTAssertTrue(host.views(WinUIImageView.self).first === image)
                XCTAssertEqual(image.sourceElement?.value(ImageContract.source.token), .name(isPaused ? play : pause))
                let pixels = image.pixels(at: points)
                XCTAssertTrue(pixels.contains { ($0 >> 24) != 0 })
                XCTAssertNotEqual(pixels, last)
                last = pixels
            }
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
                let frame = try XCTUnwrap(host.view(id: .manual(id)))
                let image = try XCTUnwrap(frame.sourceElement?.first(type: .image)?.winUI.view as? WinUIImageView)
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
            let frame = try XCTUnwrap(host.view(id: .manual("styledDisclosure")))
            let image = try XCTUnwrap(frame.sourceElement?.first(type: .image)?.winUI.view as? WinUIImageView)
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
        try checkSymbolCanStartUnscaledThenScaleAndSwitchToPixels()
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

private struct TabGeometrySample: Encodable {
    var scenario: String
    var phase: String
    var from: Int
    var to: Int
    var icon: Int
    var elapsedMS: Double
    var image: TabGeometry
    var innerFrame: TabGeometry?
    var slot: TabGeometry
    var button: TabGeometry?
    var imageOffsetInSlot: [Double]?
    var imageOffsetInButton: [Double]?
    var nativePictureFrame: [Double]?
}

private struct TabGeometry: Encodable {
    var actualOffset: [Double]
    var actualSize: [Double]
    var desiredSize: [Double]
    var rootCenter: [Double]?
    var soUIPlacement: [Double]

    @MainActor init(_ view: WinUIView) {
        let actual = view.laidOutFrame
        let desired = view.desiredSize
        let placement = view.placedFrame
        actualOffset = [actual.x, actual.y]
        actualSize = [actual.width, actual.height]
        desiredSize = [desired.width, desired.height]
        soUIPlacement = [placement.x, placement.y, placement.width, placement.height]
        var matrix = [Double](repeating: 0, count: 6)
        if swiftomniui_winui_matrix_to_root(view.handle, &matrix) {
            let centerX = actual.width / 2
            let centerY = actual.height / 2
            rootCenter = [
                matrix[4] + centerX * matrix[0] + centerY * matrix[2],
                matrix[5] + centerX * matrix[1] + centerY * matrix[3],
            ]
        }
    }
}

private struct AnimatedIconTabs: View {
    let selection: State<Int>
    let usesButtons: Bool
    let usesSafeBar: Bool
    @Namespace private var namespace

    var body: some View {
        if usesSafeBar {
            VStack {
                ScrollView { Text("Conversation \(selection.wrappedValue)") }
                    .id(selection.wrappedValue)
                    .transition(.identity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(.horizontal) { tabs.buttonStyle(.plain) }
                    .scrollIndicators(.hidden)
            }
            .frame(width: 320)
        } else if usesButtons {
            ScrollView(.horizontal) { tabs.buttonStyle(.plain) }
                .frame(width: 320, height: 64)
        } else {
            tabs.animation(.snappy, value: selection.wrappedValue)
        }
    }

    private var tabs: some View {
        HStack {
            ForEach(0..<(usesSafeBar ? 3 : 2)) { index in
                let selected = selection.wrappedValue == index
                tab(index, selected: selected)
                    .background {
                        if selected {
                            Capsule().fill(Color.black).matchedGeometryEffect(id: "selected-tab", in: namespace)
                        }
                    }
            }
        }
        .padding(8)
    }

    @ViewBuilder private func tab(_ index: Int, selected: Bool) -> some View {
        if usesButtons {
            Button {
                withAnimation(.snappy) { selection.wrappedValue = index }
            } label: {
                if usesSafeBar, index == 0 {
                    icon(selected: selected)
                        .contentShape(Rectangle())
                } else {
                    face(index, selected: selected)
                }
            }
        } else {
            face(index, selected: selected)
        }
    }

    private func face(_ index: Int, selected: Bool) -> some View {
        HStack(spacing: 0) {
            icon(selected: selected)
                .padding(.leading, selected ? 4 : 0)
            if selected {
                Text(index == 0 ? "负责人" : "操控")
                    .lineLimit(1)
                    .padding(.trailing, 12)
                    .transition(.blur.combined(with: .scale(anchor: .leading)).combined(with: .offset(x: -32)))
            }
        }
        .frame(height: 32)
    }

    private func icon(selected: Bool) -> some View {
        Image("test_large_halves.png").resizable().scaledToFit()
            .frame(width: selected ? 24 : 32, height: selected ? 24 : 32)
            .frame(width: 32, height: 32)
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A Canvas: the relay's panel, which replays the drawing with Direct2D; the whole drawing crosses in one call.
/// Design: docs/design/platforms/winui/drawing.md#a-canvas
@MainActor
final class WinUICanvasView: WinUIView {
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let size = ProposedViewSize(width: width, height: height).replacingUnspecifiedDimensions()
        return LayoutSize(width: max(0, size.width), height: max(0, size.height))
    }

    static func bitmap(size: Size, scale: Double, drawing: [DrawCommand]) -> PicturePixels? {
        let pixelWidth = (size.width * scale).rounded(.up), pixelHeight = (size.height * scale).rounded(.up)
        // Check the floating-point values before converting to Int: malformed
        // or overflowing dimensions must fail rather than trap in Swift.
        guard scale.isFinite, scale > 0, pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth > 0, pixelHeight > 0, pixelWidth <= 32768, pixelHeight <= 32768 else { return nil }
        let width = Int(pixelWidth), height = Int(pixelHeight)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let flat = HostDrawing(drawing)
        let words = flat.strings.flatMap { $0.utf8.map { CChar(bitPattern: $0) } }
        let lengths = flat.strings.map { Int32($0.utf8.count) }
        let result = swiftomniui_winui_bitmap_render(Int32(width), Int32(height), scale, &rgba,
            flat.ints, Int32(flat.ints.count), flat.numbers, Int32(flat.numbers.count),
            words, lengths, Int32(lengths.count))
        return result ? PicturePixels(width: width, height: height, rgba: rgba) : nil
    }

    /// What the canvas does as a press goes down on it, moves, and is lifted, at a point in DIPs of it.
    var onPressed: ((Point) -> Void)?
    var onDragged: ((Point) -> Void)?
    var onReleased: ((Point) -> Void)?
    private var drawnCommands: [DrawCommand]?
    private var requestedSize: (element: ElementId, size: Size)?

    init() {
        super.init { number in swiftomniui_winui_canvas_make(number) }
    }

    override func commitGeometry(in place: Rect) {
        if let element = sourceElement,
           place.width.isFinite, place.height.isFinite,
           place.width > 0, place.height > 0 {
            let size = Size(place.width, place.height)
            if requestedSize?.element != element.id || requestedSize?.size != size {
                requestedSize = (element.id, size)
                if let commands = CoreLink().canvasDrawing(for: element.id, size: size) {
                    draw(commands)
                }
            }
        }
    }

    /// The drawing, its instructions in the order they were written; nil draws nothing.
    func draw(_ drawing: [DrawCommand]?) {
        let commands = drawing ?? []
        guard drawnCommands != commands else { return }
        drawnCommands = commands
        let flat = HostDrawing(commands)
        let words = flat.strings.flatMap { $0.utf8.map { CChar(bitPattern: $0) } }
        let lengths = flat.strings.map { Int32($0.utf8.count) }
        flat.ints.withUnsafeBufferPointer { ints in
            flat.numbers.withUnsafeBufferPointer { numbers in
                words.withUnsafeBufferPointer { words in
                    lengths.withUnsafeBufferPointer { lengths in
                        swiftomniui_winui_canvas_draw(
                            handle, ints.baseAddress, Int32(ints.count), numbers.baseAddress, Int32(numbers.count),
                            words.baseAddress, lengths.baseAddress, Int32(lengths.count))
                    }
                }
            }
        }
    }

    /// The room `text` takes drawn in the font `look` names, measured by DirectWrite: wrapped at `maximumWidth`
    /// where one is given, each paragraph one line else - the `measureText` act's answer.
    func measureText(_ text: String, font look: TextLook, maximumWidth: Double?) -> Size {
        var measured = (0.0, 0.0)
        let made = withUnsafeMutablePointer(to: &measured) {
            $0.withMemoryRebound(to: Double.self, capacity: 2) {
                swiftomniui_winui_measure_text(
                    text, look.family ?? "", look.size ?? 0, Int32(look.weight ?? 0),
                    look.attributes.contains(.italic) ? 1 : 0, maximumWidth ?? 0, $0)
            }
        }
        return made == 1 ? Size(width: measured.0, height: measured.1) : .zero
    }

    /// A press on the canvas at `point`, in its phase: 0 pressed, 1 dragged, 2 released.
    func pressed(phase: Int32, at point: Point) {
        switch phase {
        case 0: onPressed?(point)
        case 1: onDragged?(point)
        default: onReleased?(point)
        }
    }

    override func detach() {
        super.detach()
        requestedSize = nil
        drawnCommands = nil
        onPressed = nil
        onDragged = nil
        onReleased = nil
    }
}

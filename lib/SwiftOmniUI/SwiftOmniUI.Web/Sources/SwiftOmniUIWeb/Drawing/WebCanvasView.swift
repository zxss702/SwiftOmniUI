// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A Canvas: its drawing replayed in order on a `<canvas>` filling the room its layout gives it - the instructions
/// and the pen the host layer reads (`CanvasInstruction`, `CanvasPen`), its arcs the host layer's curves - drawn
/// again as the room changes; a press, its drag and its release told where they are.
/// Design: docs/design/platforms/web/drawing.md#a-canvas
@MainActor
final class WebCanvasView: WebDOMView {
    var onPressed: ((Point) -> Void)?
    var onDragged: ((Point) -> Void)?
    var onReleased: ((Point) -> Void)?

    private let surface = WebDOMView(tag: "canvas")
    private var instructions: [CanvasInstruction] = []
    private var pressing = false

    init() {
        super.init(tag: "div")
        attribute("class", "swiftomniui-canvas")
        WebRelay.insert(surface.node, into: node, at: 0)
        WebRelay.observeSize(node, WebRelay.listener { [weak self] in self?.redraw() })
        listen("pointerdown") { [weak self] in
            guard let self else { return }
            pressing = true
            WebRelay.capturePointer(node)
            onPressed?(WebRelay.eventPoint)
        }
        listen("pointermove") { [weak self] in
            guard let self, pressing else { return }
            onDragged?(WebRelay.eventPoint)
        }
        for event in ["pointerup", "pointercancel"] {
            listen(event) { [weak self] in
                guard let self, pressing else { return }
                pressing = false
                onReleased?(WebRelay.eventPoint)
            }
        }
    }

    /// The drawing, as its contract declares it; none draws nothing.
    func apply(_ drawing: [DrawCommand]?) {
        instructions = CanvasInstruction.instructions(drawing)
        redraw()
    }

    /// The room `words` take drawn in the font `look` names, asked of the `<canvas>`'s own `measureText` -
    /// wrapped at `width` where one is given: the `measureText` act's answer.
    func measureText(_ words: String, font look: TextLook, maximumWidth width: Double?) -> Size {
        WebRelay.measureText(on: surface.node, words, font: look, maximumWidth: width)
    }

    private func redraw() {
        let stroke = WebCanvasStroke(instructions)
        WebRelay.drawCanvas(surface.node, stroke.numbers, words: stroke.words)
    }

    override func detach() {
        surface.detach()
        onPressed = nil
        onDragged = nil
        onReleased = nil
        super.detach()
    }
}

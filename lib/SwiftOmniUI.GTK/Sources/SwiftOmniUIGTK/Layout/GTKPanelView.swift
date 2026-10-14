// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A view over a `SwiftOmniUIPanel`: what SwiftOmniUI measures, places and draws itself - a layout, a colour box.
@MainActor
class GTKPanelView: GTKView {
    /// Whether a click beside the panel's children goes on to what is under it: an overlay laid over a window's pages.
    var passesBeside = false

    /// The outline a click stays within - a `.contentShape`'s - or none,
    /// where a point anywhere inside the bounds counts.
    var hitShape: ContainerShape?

    private var hitCommands: [Double]?
    private var hitPath: OpaquePointer?
    private var hitEvenOdd = false

    isolated deinit { if let hitPath { gsk_path_unref(hitPath) } }

    func setHitPath(_ commands: [Double]?, evenOdd: Bool) {
        guard commands != hitCommands || evenOdd != hitEvenOdd else { return }
        hitCommands = commands
        hitEvenOdd = evenOdd
        if let hitPath { gsk_path_unref(hitPath) }
        hitPath = commands.map { GTKShapeView.build($0, moved: [1, 0, 0, 1, 0, 0]) }
    }

    func contains(_ point: Point, in room: Rect) -> Bool {
        guard hitShape?.contains(point, in: room) ?? true else { return false }
        guard let hitPath else { return true }
        var native = graphene_point_t(x: Float(point.x), y: Float(point.y))
        return gsk_path_in_fill(hitPath, &native, hitEvenOdd ? GSK_FILL_RULE_EVEN_ODD : GSK_FILL_RULE_WINDING) != 0
    }

    init() {
        super.init { number in GTKPanel.make(number: number) }
    }

    /// Answers GTK's measure along one axis: the width across, or the height for the width `forSize`.
    func measure(across: Bool, forSize: Int32) -> Double {
        0
    }

    /// Ordinary panels can shrink. A scroll document supplies its complete
    /// extent on scrolling axes so the native viewport cannot compress it.
    func minimumSize(across: Bool, natural: Double) -> Double { 0 }

    /// Answers GTK's allocation of `width` by `height`.
    func allocate(width: Double, height: Double) {}

    /// Draws the panel, `width` by `height`: its children, in their order.
    func draw(_ snapshot: OpaquePointer, width: Double, height: Double) {
        drawChildren(snapshot)
    }

    /// Draws every child in the order the panel holds them, back to front.
    func drawChildren(_ snapshot: OpaquePointer) {
        var child = gtk_widget_get_first_child(widget)
        while let each = child {
            gtk_widget_snapshot_child(widget, each, snapshot)
            child = gtk_widget_get_next_sibling(each)
        }
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The native toolbar owns this surface; the authored view remains owned by
/// its mounted element and keeps its logical placing layout.
@MainActor
final class WinUISafeAreaBarHost: WinUILayoutView {
    let bar: WinUIView
    private var contribution: [Double] = []
    private var measurePending = false
    private var released = false
    private struct DrawingAncestor {
        weak var view: WinUIView?
    }
    private var drawingAncestors: [DrawingAncestor] = []
    var spacing: Double {
        max(0, bar.sourceElement?.parent?.number(.spacing) ?? 0)
    }

    init(bar: WinUIView) {
        self.bar = bar
        super.init()
        allowsNativeSafeBars = true
        bar.nativeSafeBarOwner = self
        synchronizeDrawingAncestors()
        bar.placingLayout?.holdChildren()
        setChildren([bar])
    }

    /// A promoted bar remains in the logical tree. Index its drawing
    /// dependencies when hosted and refresh the index as its logical place
    /// is committed, rather than searching ordinary content every frame.
    func synchronizeDrawingAncestors() {
        guard !released else { return }
        var ancestors: [WinUIView] = []
        var next = bar.sourceElement?.parent
        while let element = next {
            if let view = (element.native as? WinUIElement)?.view { ancestors.append(view) }
            next = element.parent
        }
        guard ancestors.count != drawingAncestors.count
            || !zip(ancestors, drawingAncestors).allSatisfy({ $0 === $1.view }) else { return }
        for ancestor in drawingAncestors { ancestor.view?.removeSafeBarDrawingDependency(bar) }
        drawingAncestors = ancestors.map { DrawingAncestor(view: $0) }
        for ancestor in ancestors { ancestor.addSafeBarDrawingDependency(bar) }
    }

    /// Logical contribution changes are committed outside native layout.
    func sourcePlaced(_ frame: Rect) {
        let metric = [frame.width, frame.height, spacing]
        guard metric != contribution else { return }
        contribution = metric
        guard !measurePending else { return }
        measurePending = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.measurePending = false
            guard !self.released else { return }
            self.direction = self.bar.sourceElement?.layoutDirection ?? .leftToRight
            self.invalidateMeasurements()
        }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        let item = WinUILayoutItem(view: bar, values: bar.sourceElement?.layoutValues ?? LayoutValues())
        let size = SingleChildArithmetic.size(of: item, padding: EdgeInsets(0), width: width)
        return LayoutSize(width: size.width, height: size.height + spacing)
    }

    override func prepareChildren(width: Double) {
        let item = WinUILayoutItem(view: bar, values: bar.sourceElement?.layoutValues ?? LayoutValues())
        let size = naturalSize(width: width.isFinite ? width : nil)
        let room = Rect(0, 0, width.isFinite ? width : size.width, max(0, size.height - spacing))
        prepareChild(item, at: SingleChildArithmetic.place(of: item, in: room,
                                                          padding: EdgeInsets(0), direction: direction))
    }

    override func arrange(in bounds: Rect) {
        bar.updateSafeBarDrawing()
        let item = WinUILayoutItem(view: bar, values: bar.sourceElement?.layoutValues ?? LayoutValues())
        bar.layout(SingleChildArithmetic.place(of: item,
            in: Rect(0, 0, bounds.width, max(0, bounds.height - spacing)),
            padding: EdgeInsets(0), direction: direction))
    }

    /// Detach from the native toolbar before returning ownership to the
    /// logical panel. Never insert one control into two native parents.
    func releaseBar() {
        released = true
        for ancestor in drawingAncestors { ancestor.view?.removeSafeBarDrawingDependency(bar) }
        drawingAncestors.removeAll()
        setChildren([])
        bar.nativeSafeBarOwner = nil
        bar.clearSafeBarDrawing()
        bar.placingLayout?.holdChildren()
    }
}

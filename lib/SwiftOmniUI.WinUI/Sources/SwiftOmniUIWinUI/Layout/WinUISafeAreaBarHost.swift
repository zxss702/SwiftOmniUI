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
    private struct Ancestor {
        weak var view: WinUIView?
    }
    private var drawingAncestors: [Ancestor] = []
    var onSourcePlaced: (() -> Void)?
    var spacing: Double {
        max(0, bar.sourceElement?.parent?.number(.spacing) ?? 0)
    }

    init(bar: WinUIView) {
        self.bar = bar
        super.init()
        allowsNativeSafeBars = true
        bar.nativeSafeBarOwner = self
        var ancestor = bar.sourceElement?.parent
        while let element = ancestor {
            if let view = element.winUI.view {
                view.followPromotedBar(bar)
                drawingAncestors.append(Ancestor(view: view))
            }
            ancestor = element.parent
        }
        bar.placingLayout?.holdChildren()
        setChildren([bar])
    }

    /// Logical contribution changes are committed outside native layout.
    func sourcePlaced(_ frame: Rect) {
        onSourcePlaced?()
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
        for ancestor in drawingAncestors { ancestor.view?.unfollowPromotedBar(bar) }
        drawingAncestors.removeAll()
        onSourcePlaced = nil
        setChildren([])
        bar.nativeSafeBarOwner = nil
        bar.clearSafeBarDrawing()
        bar.placingLayout?.holdChildren()
    }
}

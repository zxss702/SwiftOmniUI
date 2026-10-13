// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// What a ScrollView's scroller moves: its content where the core's scroll arithmetic puts it, in a document the
/// scroller makes at least as large as its viewport.
/// Design: docs/design/platforms/winui/layout.md#scrolling
@MainActor
final class WinUIScrollDocument: WinUILayoutView {
    /// The ScrollView this document is the content of; a lazy run under it
    /// climbs to it for the window.
    weak var scrollView: WinUIScrollView?

    /// The room inside the scroller's own edge, in DIPs.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// The pass's resolved padding; assigning it has no native side effects.
    var layoutPadding = EdgeInsets(0)
    var consumedInsets = EdgeInsets(0)

    var orientation = Axis.vertical {
        didSet { if orientation != oldValue { invalidateMeasurements() } }
    }

    /// The scroller's own measure stands on this document: a change beneath forgets it too, or the presenter
    /// keeps the extent it read last.
    override func invalidateMeasurements() {
        super.invalidateMeasurements()
        scrollView?.scroller.invalidateMeasure()
    }

    override func contentSize(width: Double?) -> LayoutSize {
        ScrollArithmetic.contentSize(of: items.first, padding: layoutPadding, orientation: orientation, width: width)
    }

    /// The scroller's presenter asks this size as it arranges - inside the pass, where a layout answers only
    /// what it last measured: the run's size is arithmetic already counted, safe to answer inside a pass, and
    /// the extent the presenter reads is the run's, not the room it stood in last.
    override func measure(width: Double, height: Double) -> LayoutSize {
        guard WinUIView.arranging == 0 else {
            guard placingLayout == nil else { return .zero }
            let size = naturalSize(width: width.isFinite ? width : nil)
            return LayoutSize(width: min(size.width, width), height: min(size.height, height))
        }
        return super.measure(width: width, height: height)
    }

    /// Its own size is the document's: never smaller than the viewport, which the scroller sees to.
    override func arrange(in bounds: Rect) {
        guard let item = items.first, item.isShown else { return }

        let arranged = ScrollArithmetic.arrange(
            item, padding: layoutPadding, orientation: orientation,
            in: LayoutSize(width: bounds.width, height: bounds.height))
        item.view.layout(arranged.place)
    }
    override func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        // The document's margins consumed the viewport's contributions.
        // Scrolling cannot make those contributions reappear in inner readers.
        SafeAreaContext(bounds: Rect(0, 0, place.width, place.height),
                        consumed: consumedInsets)
    }

}

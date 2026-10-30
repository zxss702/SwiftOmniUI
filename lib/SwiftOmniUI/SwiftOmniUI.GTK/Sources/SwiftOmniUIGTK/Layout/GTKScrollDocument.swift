// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// What a ScrollView's scroller moves: its content where the core's scroll arithmetic puts it, in a document the
/// viewport makes at least as large as itself.
/// Design: docs/design/platforms/gtk/layout.md#scrolling
@MainActor
final class GTKScrollDocument: GTKLayoutView {
    /// The native viewport owns the document; its arithmetic owner is the scroller.
    weak var scrollView: GTKScrollView?

    /// The room inside the scroller's own edge.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// The pass's resolved padding; assigning it has no native side effects.
    var layoutPadding = EdgeInsets(0)
    var consumedInsets = EdgeInsets(0)

    var orientation = Axis.vertical {
        didSet { if orientation != oldValue { invalidateMeasurements() } }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        ScrollArithmetic.contentSize(of: items.first, padding: layoutPadding, orientation: orientation, width: width)
    }

    override func minimumSize(across: Bool, natural: Double) -> Double {
        let scrolls = orientation == .both || (across ? orientation == .horizontal : orientation == .vertical)
        return scrolls ? natural : 0
    }

    override func arrange(in bounds: Rect) {
        guard let item = items.first, item.isShown else { return }

        let arranged = ScrollArithmetic.arrange(
            item, padding: layoutPadding, orientation: orientation,
            in: LayoutSize(width: bounds.width, height: bounds.height))
        item.view.layout(arranged.place)
    }
    override func context(for child: GTKView, at place: Rect) -> SafeAreaContext {
        // The document's margins consumed the viewport's contributions.
        // Scrolling cannot make those contributions reappear in inner readers.
        SafeAreaContext(bounds: Rect(0, 0, place.width, place.height),
                        consumed: consumedInsets)
    }

}

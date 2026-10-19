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
    override func invalidateOwnMeasurements() {
        super.invalidateOwnMeasurements()
        scrollView?.scroller.invalidateMeasure()
    }

    override func contentSize(width: Double?) -> LayoutSize {
        ScrollArithmetic.contentSize(of: items.first, padding: layoutPadding, orientation: orientation, width: width)
    }

    override var hasNativeProposals: Bool { true }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        guard let item = items.first, item.isShown else { return [] }
        let arranged = ScrollArithmetic.arrange(item, padding: layoutPadding, orientation: orientation,
                                                in: LayoutSize(width: width ?? size.width, height: size.height))
        return [NativeProposal(view: item.view, place: arranged.place)]
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

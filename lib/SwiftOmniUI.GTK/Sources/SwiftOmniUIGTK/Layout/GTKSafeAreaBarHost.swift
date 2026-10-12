// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// The native toolbar owns this surface; the authored view remains owned by
/// its mounted element and keeps its logical placing layout.
@MainActor
final class GTKSafeAreaBarHost: GTKLayoutView {
    let bar: GTKView
    var spacing: Double {
        max(0, bar.sourceElement?.parent?.number(.spacing) ?? 0)
    }

    init(bar: GTKView) {
        self.bar = bar
        super.init()
        allowsNativeSafeBars = true
        bar.nativeSafeBarOwner = self
        bar.placingLayout?.setChildren(bar.placingLayout?.heldViews() ?? [])
        setChildren([bar])
        gtk_widget_add_css_class(widget, "toolbar")
        gtk_widget_add_css_class(widget, GTKStyleSheet.safeAreaBar)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        let item = GTKLayoutItem(view: bar, values: bar.sourceElement?.layoutValues ?? LayoutValues())
        let size = SingleChildArithmetic.size(of: item, padding: EdgeInsets(0), width: width)
        return LayoutSize(width: size.width, height: size.height + spacing)
    }

    override func arrange(in bounds: Rect) {
        bar.updateSafeBarDrawing()
        let item = GTKLayoutItem(view: bar, values: bar.sourceElement?.layoutValues ?? LayoutValues())
        bar.layout(SingleChildArithmetic.place(of: item,
            in: Rect(0, 0, bounds.width, max(0, bounds.height - spacing)),
            padding: EdgeInsets(0), direction: direction))
    }

    /// Detach from the native toolbar before returning ownership to the
    /// logical panel. Never insert one control into two native parents.
    func releaseBar() {
        setChildren([])
        bar.nativeSafeBarOwner = nil
        bar.clearSafeBarDrawing()
        bar.placingLayout?.setChildren(bar.placingLayout?.heldViews() ?? [])
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// What a native button frame - a `GtkButton`'s, a `GtkMenuButton`'s - asks of the face it wears.
/// Design: docs/design/platforms/gtk/layout.md#measuring-a-widget
@MainActor
enum GTKFace {
    /// The frame's size for the room offered: the chrome GTK's own frame keeps around the face, plus the face
    /// measured in the room left inside it, so a face that bounds its own width - `.frame(maxWidth:)` - keeps that
    /// bound, the way the other hosts' buttons keep it.
    ///
    /// GTK asks a button's child for a size request with no width in mind (`gtk_widget_measure(…, -1)`), so the
    /// face's own answer is the width of its words alone and the button collapses onto them; measuring the face
    /// through the layout arithmetic at the width the button is offered is what the other hosts already do.
    static func size(of host: GTKWidget, wearing face: GTKView, width: Double?, height: Double?) -> LayoutSize {
        var least: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(host, GTK_ORIENTATION_HORIZONTAL, -1, &least, &natural, nil, nil)
        var faceLeast: Int32 = 0
        var faceNatural: Int32 = 0
        gtk_widget_measure(face.widget, GTK_ORIENTATION_HORIZONTAL, -1, &faceLeast, &faceNatural, nil, nil)
        let chrome = max(0, Double(natural - faceNatural))
        let measured = face.measure(width: width.map { max(0, $0 - chrome) }, height: height)
        let sized = width.map { max(Double(least), min(measured.width + chrome, $0.rounded(.down))) }
            ?? (measured.width + chrome)
        gtk_widget_measure(host, GTK_ORIENTATION_VERTICAL, Int32(sized.rounded()), &least, &natural, nil, nil)
        return LayoutSize(width: sized, height: Double(natural))
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A `.mask` realized: the mask's widget held like any child - measured and
/// allocated in the same room - but drawn only inside the mask's own pass, its
/// alpha cutting the content's.
@MainActor
final class GTKMaskedView: GTKZStackView {
    /// The mask's own view: a child the panel holds and places, never drawn
    /// beside the content.
    private var maskView: GTKView? {
        didSet { gtk_widget_queue_draw(widget) }
    }

    /// The first item is the content and drawn; every further item is the
    /// mask, held so it is measured and allocated, painted only as the mask.
    @discardableResult
    override func setItems(_ items: [GTKLayoutItem]) -> Bool {
        maskView = items.count > 1 ? items[1].view : nil
        return super.setItems(items)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        ZStackArithmetic.size(of: Array(items.filter { !$0.departing }.prefix(1)),
                              padding: padding, width: width)
    }

    /// The content under the mask's alpha: the mask rendered into the mask
    /// slot, the children into the source - the mask's own widget skipped in
    /// that pass.
    override func drawContent(_ snapshot: OpaquePointer) {
        guard let mask = maskView else {
            drawChildren(snapshot)
            return
        }

        gtk_snapshot_push_mask(snapshot, GSK_MASK_MODE_ALPHA)
        gtk_widget_snapshot_child(widget, mask.widget, snapshot)
        gtk_snapshot_pop(snapshot)
        var child = gtk_widget_get_first_child(widget)
        while let each = child {
            if each != mask.widget {
                gtk_widget_snapshot_child(widget, each, snapshot)
            }
            child = gtk_widget_get_next_sibling(each)
        }
        gtk_snapshot_pop(snapshot)
    }
}

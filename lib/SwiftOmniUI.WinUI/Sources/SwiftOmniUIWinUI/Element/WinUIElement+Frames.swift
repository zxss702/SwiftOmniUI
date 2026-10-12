// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// Where the element stands, said to the tree that reads it by the host layer's rule.
/// Design: docs/design/platforms/winui/layout.md#where-a-view-stands
extension WinUIElement: FrameReporter {
    /// Whether the tree reads where this element stands, and it has a view to stand.
    var readsFrame: Bool {
        view != nil && element.readsOwnFrame
    }

    /// Says where the element stands, where that changed (`MountedElement.reportFrame`).
    func reportFrame() {
        guard let host, let view else { return }
        let named = element.namedSpaceFrames { ancestor in
            guard let ancestorView = (ancestor.native as? WinUIElement)?.view else { return nil }
            let origin = ancestorView.origin
            let frame = ancestorView.laidOutFrame
            return Rect(x: origin.x, y: origin.y, width: frame.width, height: frame.height)
        }
        element.reportFrame(
            view.frameReport(safeArea: host.safeArea(of: element)), named: named, in: host.runtime)
    }
}

extension WinUIScrollView: FramedScroller {}

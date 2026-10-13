// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// Where the element stands, said to the tree that reads it by the host layer's rule.
/// Design: docs/design/platforms/gtk/layout.md#where-a-view-stands
extension GTKElement: FrameReporter {
    /// Whether the tree reads where this element stands, and it has a view to stand.
    var readsFrame: Bool {
        view != nil && element.readsOwnFrame
    }

    /// Says where the element stands, where that changed (`MountedElement.reportFrame`); nothing while it stands
    /// nowhere yet.
    func reportFrame() {
        guard let host, let numbers = view?.frameReport() else { return }
        let named = element.namedSpaceFrames { ($0.native as? GTKElement)?.view?.windowRect() }
        element.reportFrame(numbers, named: named, in: host.runtime,
                            geometryInsets: view?.safeAreaContext?.insets)
    }
}

extension GTKScrollView: FramedScroller {}

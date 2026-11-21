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
        let layoutGeneration = host.runtime.frames.layoutGeneration
        guard view.isAttached(forLayoutGeneration: layoutGeneration) else { return }
        let frame = view.laidOutFrame(forLayoutGeneration: layoutGeneration)
        // Retained navigation pages have no current layout. Their temporary
        // empty attachment must not replace a reader's last real proposal.
        if element.isGeometryReader, frame.width <= 0 || frame.height <= 0 { return }
        if element.readsOnlyDrawingSize {
            element.reportDrawingSize(Size(frame.width, frame.height), in: host.runtime)
            return
        }
        // Text's passive origin report does not read named coordinate spaces.
        // Walking its ancestors per label makes dense scrolling pay for data
        // that no handler consumes.
        let named = element.handler(.namedFramesChanged) == nil ? [] : element.namedSpaceFrames { ancestor in
            guard let ancestorView = (ancestor.native as? WinUIElement)?.view else { return nil }
            let origin = ancestorView.origin
            let frame = ancestorView.laidOutFrame(forLayoutGeneration: layoutGeneration)
            return Rect(x: origin.x, y: origin.y, width: frame.width, height: frame.height)
        }
        if let scroll = view as? WinUIScrollView, element.events[.scrollGeometryChanged] != nil,
           let numbers = scroll.scrollGeometryNumbers {
            element.reportScrollGeometry(numbers, in: host.runtime)
        }
        let reportGeneration = host.runtime.frames.reportGeneration
        element.reportFrame(
            view.frameReport(
                safeArea: host.frameReportCache.safeArea(
                    of: element, in: host, generation: reportGeneration,
                    layoutGeneration: layoutGeneration),
                frame: frame,
                cache: host.frameReportCache, generation: reportGeneration,
                layoutGeneration: layoutGeneration),
            named: named, in: host.runtime,
            geometryInsets: view.safeAreaContext?.insets)
    }
}

extension WinUIScrollView: FramedScroller {}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUIHost
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

/// A control of the application's own, standing in the tree as a view of this host that holds a reference of its own
/// to the control's element: placed, sized and shown like any other, the control held while its element lives.
@MainActor
final class WinUIHostedView<Control: WinUIControl>: WinUIView {
    /// The application's control.
    let control: Control
    private struct ViewportGeometry: Equatable {
        var outsets: EdgeInsets
        var insets: EdgeInsets
    }
    private var pendingViewport: ViewportGeometry?
    private var committedViewport: ViewportGeometry?

    override var registeredPropertiesAffectSize: Bool { control.contentAffectsSize }

    init(_ control: Control) {
        self.control = control
        let allocation: ((SwiftOmniUIObjectRef) -> SwiftOmniUIObjectRef?)? = control.scrollsUnderSafeArea
            ? { swiftomniui_winui_hosted_viewport_make($0) } : nil
        super.init(allocation: allocation) {
            _ in swiftomniui_winui_retain(control.element)
        }
    }

    override var carriesSafeAreaOutsets: Bool { control.scrollsUnderSafeArea || super.carriesSafeAreaOutsets }

    override func prepareAllocation(in bounds: Rect) {
        if control.scrollsUnderSafeArea { resolve(in: bounds) }
        super.prepareAllocation(in: bounds)
    }

    private func resolve(in bounds: Rect) {
        let context = layoutSafeArea(in: bounds)
        let viewport = context.bounds
        let geometry = ViewportGeometry(outsets: SafeAreaContext.insets(of: bounds, in: viewport),
                                        insets: SafeAreaContext.insets(of: context.safe, in: viewport))
        let alreadyQueued = pendingViewport != nil
        guard alreadyQueued || geometry != committedViewport else { return }
        pendingViewport = geometry
        guard !alreadyQueued else { return }
        // A measure can visit a destination while a transition is still arranging
        // the current slot. Use that slot, and change the viewport and document
        // margins together so a frame cannot show the top inset twice.
        WinUIDoorbell.afterPass { [weak self] in
            guard let self, let geometry = self.pendingViewport else { return }
            self.pendingViewport = nil
            guard !self.isDetached, geometry != self.committedViewport else { return }
            let insets = geometry.insets
            if insets != self.committedViewport?.insets {
                self.control.safeAreaInsetsDidChange(top: insets.top, right: insets.right,
                                                     bottom: insets.bottom, left: insets.left)
            }
            self.committedViewport = geometry
            let outsets = geometry.outsets
            swiftomniui_winui_hosted_viewport_set(self.layoutHandle, outsets.top, outsets.right,
                                                 outsets.bottom, outsets.left)
        }
    }

    override func measure(width: Double?, height: Double?) -> LayoutSize {
        if control.scrollsUnderSafeArea {
            return LayoutSize(width: width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0,
                              height: height.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0)
        }
        if !control.sizesToContentHeight, height?.isFinite != true {
            // A scrolling control has no intrinsic document height. Answer
            // the layout's size query without measuring its native viewport
            // at zero: doing so alternates the scroller's constraint with
            // its real allocation and can cycle its scrollbar layout.
            // prepareMeasure still measures the actual allocation before
            // the parent's normal Arrange, including the very first frame.
            return LayoutSize(width: width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0, height: 0)
        }
        return super.measure(width: width, height: height)
    }
}

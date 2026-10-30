// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A ProgressBar: the browser's `<progress>`, its share of the work done from 0 to 1, across the middle of a box that
/// takes the view's frame - so the bar keeps its own height whatever room the layout gives the view.
/// Design: docs/design/platforms/web/controls.md#indicators
@MainActor
final class WebProgressView: WebDOMView {
    private let bar = WebDOMView(tag: "progress")

    init() {
        super.init(tag: "div")
        attribute("class", "swiftomniui-progress")
        bar.attribute("max", "1")
        WebRelay.insert(bar.node, into: node, at: 0)
        setProgress(0)
    }

    override var named: WebDOMView { bar }

    func setProgress(_ progress: Double) {
        WebRelay.setNumber(bar.node, "value", ValueArithmetic.share(progress))
    }

    /// The colour of the work done; nil for the page's accent.
    func setTint(_ tint: HostValue?) {
        style("accent-color", WebCSS.color(tint))
        style("--swiftomniui-on", WebCSS.color(tint))
    }

    override func detach() {
        bar.detach()
        super.detach()
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// An ActivityIndicator: a ring turning while work goes on, at its own size in the middle of the view's frame - a
/// busy progress bar for assistive technology; stopped, it shows nothing and keeps its room.
/// Design: docs/design/platforms/web/controls.md#indicators
@MainActor
final class WebActivityView: WebDOMView {
    private let ring = WebDOMView(tag: "span")

    init() {
        super.init(tag: "div")
        attribute("class", "swiftomniui-indicator")
        attribute("role", "progressbar")
        ring.attribute("class", "swiftomniui-activity")
        WebRelay.insert(ring.node, into: node, at: 0)
        setRunning(false)
    }

    override var role: String? { "progressbar" }

    func setRunning(_ running: Bool) {
        ring.attribute("data-running", running ? "" : nil)
        attribute("aria-busy", running ? "true" : "false")
    }

    /// The ring's colour; nil for the page's accent.
    func setTint(_ tint: HostValue?) {
        style("--swiftomniui-on", WebCSS.color(tint))
    }

    override func detach() {
        ring.detach()
        super.detach()
    }
}

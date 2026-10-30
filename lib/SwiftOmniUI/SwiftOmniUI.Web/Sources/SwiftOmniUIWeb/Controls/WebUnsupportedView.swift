// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// An element no registration makes yet: its name, in the page's colour for errors, where it belongs.
@MainActor
final class WebUnsupportedView: WebDOMView {
    init(_ type: NodeType) {
        super.init(tag: "span")
        attribute("class", "swiftomniui-unsupported")
        WebRelay.setText(node, "Web: unsupported \(type.name)")
    }
}

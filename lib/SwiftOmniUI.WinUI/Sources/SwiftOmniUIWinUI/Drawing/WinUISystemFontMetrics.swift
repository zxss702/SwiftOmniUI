// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

@MainActor enum WinUISystemFontMetrics {
    static func read(_ descriptor: FontMetrics.Descriptor) -> FontMetrics? {
        var values = [Double](repeating: 0, count: 5)
        guard swiftomniui_winui_font_descriptor_metrics(descriptor.family ?? "", descriptor.size ?? 0,
            descriptor.style, descriptor.weight ?? 0, descriptor.attributes, descriptor.design, &values) else { return nil }
        return FontMetrics(pointSize: values[0], ascender: values[1], descender: values[2],
                           leading: values[3], capHeight: values[4])
    }
}

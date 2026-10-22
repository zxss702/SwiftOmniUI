// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

@MainActor enum WinUISystemFontMetrics {
    static func measure(_ text: String, descriptor: FontMetrics.Descriptor, room: Size) -> Size? {
        var size = [0.0, 0.0]
        let family = descriptor.family ?? (descriptor.design == 3 ? "Consolas" : descriptor.design == 1 ? "Cambria" : "")
        let weight = descriptor.weight ?? (descriptor.attributes & FontAttributes.bold.rawValue != 0 ? 700 : 400)
        guard swiftomniui_winui_measure_text(text, family, descriptor.size ?? 14, Int32(weight),
            descriptor.attributes & FontAttributes.italic.rawValue != 0 ? 1 : 0,
            room.width.isFinite ? room.width : 0, &size) != 0 else { return nil }
        return Size(size[0], size[1])
    }
    static func read(_ descriptor: FontMetrics.Descriptor) -> FontMetrics? {
        var values = [Double](repeating: 0, count: 5)
        guard swiftomniui_winui_font_descriptor_metrics(descriptor.family ?? "", descriptor.size ?? 0,
            descriptor.style, descriptor.weight ?? 0, descriptor.attributes, descriptor.design, &values) else { return nil }
        return FontMetrics(pointSize: values[0], ascender: values[1], descender: values[2],
                           leading: values[3], capHeight: values[4])
    }
}

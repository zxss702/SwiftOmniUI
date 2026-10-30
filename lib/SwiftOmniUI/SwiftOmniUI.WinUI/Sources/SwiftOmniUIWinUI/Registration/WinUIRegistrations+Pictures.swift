// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WinUIRegistrations {
    /// A picture from the application's folder, and the box of colour beside it.
    static func pictures(_ registry: Registry<WinUIView>) {
        registry.add(ImageContract.self, create: { _ in WinUIImageView() }) { image in
            image.applies([
                ImageContract.source, ImageElementContract.aspect, ImageContract.isResizable,
                FontElementContract.fontSize, FontElementContract.fontTextStyle,
                FontElementContract.fontWeight, FontElementContract.fontAttributes,
                TextStyleElementContract.foregroundStyle,
            ]) { view, values in
                view.apply(source: values[ImageContract.source], aspect: values[ImageElementContract.aspect] ?? .stretch,
                           resizable: values[ImageContract.isResizable] ?? false, font: TextMembers.look(of: values))
            }
        }

        registry.add(ColorPickerContract.self, create: { _ in WinUIColorBoxView() }) { box in
            box.applies([ColorPickerContract.color, ColorPickerContract.cornerRadius]) { view, values in
                view.apply(
                    color: values[ColorPickerContract.color]?.propValue,
                    corners: values[ColorPickerContract.cornerRadius]?.propValue)
            }
        }
    }
}

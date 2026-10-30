// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WebRegistrations {
    /// An Image: the picture it shows, and how it fits its room; a ColorPicker: its colour and its corners.
    static func pictures(_ registry: Registry<WebDOMView>) {
        registry.add(ImageContract.self, create: { _ in WebImageView() }) { image in
            image.applies([ImageContract.source, ImageElementContract.aspect, ImageContract.isResizable]) { view, values in
                let aspect = values[ImageContract.isResizable] == true
                    ? values[ImageElementContract.aspect] ?? .stretch : .center
                view.apply(source: values[ImageContract.source], aspect: aspect)
            }
        }
        registry.add(ColorPickerContract.self, create: { _ in WebColorBoxView() }) { box in
            box.applies([ColorPickerContract.color, ColorPickerContract.cornerRadius]) { view, values in
                view.apply(color: values[ColorPickerContract.color]?.propValue, corners: values[ColorPickerContract.cornerRadius])
            }
        }
    }
}

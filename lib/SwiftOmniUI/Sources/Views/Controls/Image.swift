// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Image`'s own properties, shared by the control and its `Style<Image>`.
public protocol ImageProperties: PropertyContainer {}

extension ImageProperties {
    /// Whether an animated picture - a GIF, an animated WebP - is running.
    @_spi(Host) public func isAnimating(_ value: Bool) -> Modified {
        setValue(ImageContract.isAnimating, value)
    }
}

/// A picture from the application's resources.
///
///     Image("tab_list.png")
///         .resizable()
///         .scaledToFit()
///         .frame(height: 20)
///
/// The name is a file among the application's image resources, and artwork
/// kept as an SVG is asked for by its PNG name: `tab_list.svg` is asked for as
/// `tab_list.png`.
///
/// A file, never an address: a name that looks like a url is looked for among
/// the resources like any other, and is not found.
///
/// Artwork that reads on one color scheme and not the other is drawn twice:
///
///     Image(light: "tab_list.png", dark: "tab_list_dark.png")
///
/// and the picture follows the system color scheme.
public struct Image: VisualElement, ImageElement, ImageProperties, FontElement, TextStyleElement {
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<Image>` is written against.
    public init() {
        node = Node(contract: ImageContract.self)
    }

    /// A picture from `source`. Takes a plain string too, since an ImageSource
    /// is expressible by one: `Image("tab_list.png")`.
    public init(_ source: ImageSource) {
        node = Node(contract: ImageContract.self)
        node.write(ImageContract.source, source)
    }

    /// One picture per color scheme, following the system color scheme.
    public init(light: String, dark: String) {
        self.init(ImageSource(light: light, dark: dark))
    }

    /// A picture in the app's images, by name - SwiftUI's `Image(_:)`:
    ///
    ///     Image("logo.png")
    public init(_ name: String) {
        self.init(ImageSource(name))
    }

    /// A symbol from the platform's own set, by its cross-platform name -
    /// `Image(systemName: "star")` draws SF Symbols on Apple's platforms, the
    /// Fluent icon of the name on Windows, the toolkit's theme icon elsewhere.
    ///
    /// The name is the contract, the glyph the host's: a name one platform's
    /// set does not know draws that platform's fallback glyph there.
    public init(systemName: String) {
        self.init(.symbol(systemName))
    }

    /// Allows the picture to resize to its frame, stretching unless a scaling strategy is specified.
    public func resizable() -> Modified {
        setValue(ImageContract.isResizable, true)
    }

    /// The picture scaled to fit the frame it is given, its own proportions
    /// kept - `.aspect(.fit)` spelled SwiftUI's way.
    public func scaledToFit() -> Modified {
        setValue(ImageElementContract.aspect, ContentMode.fit)
    }

    /// The picture scaled to fill the frame it is given, its own proportions
    /// kept. Add `.clipped()` to clip the overflow.
    public func scaledToFill() -> Modified {
        setValue(ImageElementContract.aspect, ContentMode.fill)
    }
}

extension Image {
    /// The source an `Image` carries, read off its node - what `Text(Image)`
    /// moves onto the picture's run.
    var imageSource: ImageSource? {
        node.props[ImageContract.source.token].flatMap { ImageSource($0) }
    }

    /// Whether the picture draws in its own colours or as a stencil of the
    /// foreground one - `.template` for a symbol that takes its tint.
    ///
    ///     Image("logo.png")
    ///         .renderingMode(.original)
    public func renderingMode(_ mode: TemplateRenderingMode) -> Modified {
        setValue(ImageContract.renderingMode, mode)
    }

    /// `isAnimating` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func isAnimating(_ state: Binding<Bool>) -> Modified {
        plain(.isAnimating, by: state)
    }
}

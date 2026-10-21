// SPDX-License-Identifier: Apache-2.0

/// Native, unrounded font metrics in the same logical units as `Font.system(size:)`.
/// Descenders are negative, matching AppKit/CoreText's baseline coordinates.
public struct FontMetrics: Sendable, Equatable {
    public let pointSize: Double
    public let ascender: Double
    public let descender: Double
    public let leading: Double
    public let capHeight: Double
    public init(pointSize: Double, ascender: Double, descender: Double, leading: Double, capHeight: Double) {
        self.pointSize = pointSize; self.ascender = ascender; self.descender = descender
        self.leading = leading; self.capHeight = capHeight
    }
    public var lineHeight: Double { ascender - descender + leading }

    /// Hosts cache the native resolution by this complete descriptor and their
    /// current font/theme generation. A failed native lookup remains nil.
    @_spi(Host) public struct Descriptor: Sendable, Hashable {
        public let family: String?
        public let size: Double?
        public let style: Int32
        public let weight: Double?
        public let design: Int32
        public let attributes: Int32
        public init(family: String?, size: Double?, style: Int32, weight: Double?, design: Int32, attributes: Int32) {
            self.family = family; self.size = size; self.style = style; self.weight = weight
            self.design = design; self.attributes = attributes
        }
    }
    /// Bound once during host startup, before application views are created.
    @_spi(Host) public nonisolated(unsafe) static var read: (@MainActor (Descriptor) -> FontMetrics?)?
}

public extension Font {
    /// Queries the actual platform font, including registered custom families.
    /// This requires a running desktop host and never substitutes ratio estimates.
    @MainActor var metrics: FontMetrics? {
        let family: String?, size: Double?, style: Int32
        switch basis {
        case .system(let points): family = nil; size = points; style = -1
        case .custom(let name, let points): family = name; size = points; style = -1
        case .textStyle(let textStyle): family = nil; size = nil; style = textStyle.rawValue
        }
        if let size, !size.isFinite || size <= 0 { return nil }
        if let weight, !weight.value.isFinite { return nil }
        return FontMetrics.read?(.init(family: family, size: size, style: style,
            weight: weight?.value, design: design?.rawValue ?? 0, attributes: attributes.rawValue))
    }
}

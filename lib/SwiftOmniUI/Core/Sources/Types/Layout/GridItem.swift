// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One column of a `LazyVGrid` - SwiftUI's `GridItem`.
///
///     LazyVGrid(columns: [GridItem(.adaptive(minimum: 256))]) { … }
public struct GridItem: Equatable, Sendable {
    /// How wide the column is - SwiftUI's `GridItem.Size`.
    public enum Size: Equatable, Sendable {
        /// Exactly this many points wide.
        case fixed(Double)

        /// A share of what is left over, at least `minimum` and at most
        /// `maximum` wide.
        case flexible(minimum: Double = 10, maximum: Double = .infinity)

        /// As many columns of at least `minimum` points as fit - the item
        /// stands for the count the room makes it.
        case adaptive(minimum: Double, maximum: Double = .infinity)
    }

    /// How wide the column is.
    public var size: Size

    /// The gap after this column, or the grid's own spacing where nil.
    public var spacing: Double?

    /// Where a cell's content sits in the column, or the grid's own where nil.
    public var alignment: Alignment?

    /// A column of `size`, `spacing` after it, its cells `alignment`d.
    public init(_ size: Size = .flexible(), spacing: Double? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

extension GridItem.Size {
    /// The track this size describes, its bounds dropped - what a grid counts.
    @_spi(Host) public var track: GridLength {
        switch self {
        case .fixed(let width): return .fixed(width)
        case .flexible, .adaptive: return .proportional(1)
        }
    }

    /// The bounds a `.flexible` or `.adaptive` size keeps; nil for `.fixed`,
    /// which its track already states.
    @_spi(Host) public var limits: (minimum: Double, maximum: Double)? {
        switch self {
        case .fixed: return nil
        case .flexible(let minimum, let maximum),
             .adaptive(let minimum, let maximum): return (minimum, maximum)
        }
    }
}

extension GridItem: HostRepresentable {
    /// Which of the three sizes an item is, as the number that crosses.
    enum Kind: Int32, Sendable {
        case fixed = 0
        case flexible = 1
        case adaptive = 2
    }

    /// The kind, its two bounds (a boundless top as -1), the spacing or -1,
    /// and the two alignment axes or -1 where the item keeps the grid's own.
    public var propValue: PropValue {
        let (kind, bounds): (Kind, [Double]) = switch size {
        case .fixed(let width): (.fixed, [width, -1])
        case .flexible(let minimum, let maximum): (.flexible, [minimum, maximum.isFinite ? maximum : -1])
        case .adaptive(let minimum, let maximum): (.adaptive, [minimum, maximum.isFinite ? maximum : -1])
        }
        return .values([
            .enumeration(kind.rawValue),
            .numbers(bounds),
            .number(spacing ?? -1),
            .enumeration(alignment?.horizontal.axis.rawValue ?? -1),
            .enumeration(alignment?.vertical.axis.rawValue ?? -1),
        ])
    }

    /// The item its parts name, or nil where they are not its parts.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard case .values(let parts) = propValue, parts.count == 5,
              case .enumeration(let kind) = parts[0], let kind = Kind(rawValue: kind),
              case .numbers(let bounds) = parts[1], let minimum = bounds.first,
              case .number(let spacing) = parts[2],
              case .enumeration(let horizontal) = parts[3],
              case .enumeration(let vertical) = parts[4]
        else { return nil }

        let maximum = bounds.count > 1 && bounds[1] >= 0 ? bounds[1] : Double.infinity
        switch kind {
        case .fixed: size = .fixed(minimum)
        case .flexible: size = .flexible(minimum: minimum, maximum: maximum)
        case .adaptive: size = .adaptive(minimum: minimum, maximum: maximum)
        }
        self.spacing = spacing >= 0 ? spacing : nil
        alignment = horizontal < 0 || vertical < 0 ? nil : Alignment(
            horizontal: HorizontalAlignment(AxisAlignment(rawValue: horizontal) ?? .fill),
            vertical: VerticalAlignment(AxisAlignment(rawValue: vertical) ?? .fill))
    }
}

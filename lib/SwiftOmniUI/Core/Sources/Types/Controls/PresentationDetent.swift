// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A presented sheet's sizes and dressing: `PresentationDetent` and `Visibility`.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// How tall a presented sheet may stand, one of `.presentationDetents`' list.
public enum PresentationDetent: Equatable, Sendable {
    /// About half the room.
    case medium

    /// The room itself.
    case large

    /// This much of the room.
    case fraction(Double)

    /// This tall, in points.
    case height(Double)

    /// The kind, which is what crosses.
    private enum Kind: Int32 {
        case medium = 0
        case large = 1
        case fraction = 2
        case height = 3
    }
}

extension PresentationDetent: HostRepresentable {
    /// The kind, with its measure where it has one.
    public var propValue: PropValue {
        switch self {
        case .medium: .enumeration(Kind.medium.rawValue)
        case .large: .enumeration(Kind.large.rawValue)
        case .fraction(let part): .values([.enumeration(Kind.fraction.rawValue), .number(part)])
        case .height(let height): .values([.enumeration(Kind.height.rawValue), .number(height)])
        }
    }

    /// The detent back, or nil where what crossed is not one.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        switch propValue {
        case .enumeration(let kind):
            switch Kind(rawValue: kind) {
            case .medium: self = .medium
            case .large: self = .large
            default: return nil
            }
        case .values(let pair):
            guard pair.count == 2, case .enumeration(let kind) = pair[0], case .number(let part) = pair[1]
            else { return nil }
            switch Kind(rawValue: kind) {
            case .fraction: self = .fraction(part)
            case .height: self = .height(part)
            default: return nil
            }
        default:
            return nil
        }
    }
}

/// Whether a control's chrome shows - what `.presentationDragIndicator`
/// takes.
public enum Visibility: Int32, Sendable {
    /// As the platform sees fit.
    case automatic = 0

    /// Always shown.
    case visible = 1

    /// Never shown.
    case hidden = 2
}

extension Visibility: HostRepresentable {}
extension Visibility: StateChoice {}

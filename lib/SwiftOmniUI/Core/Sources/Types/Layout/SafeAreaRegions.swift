// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The parts of the screen's unsafe strip a view may ignore - the container
/// strips, the keyboard strip, or both. What the SwiftUI-formed
/// `ignoresSafeArea` takes.
///
///     Color.cornflowerBlue.ignoresSafeArea()
///     EdgesFillingContent().ignoresSafeArea(.container, edges: .top)
///
/// The inverse of `SafeArea`, which says what a layout stays clear of: a
/// region ignored here is one dropped there.
public struct SafeAreaRegions: OptionSet, Sendable {
    /// The regions' bits.
    public let rawValue: Int8

    /// A set from its bits.
    public init(rawValue: Int8) {
        self.rawValue = rawValue
    }

    /// The container strips - the notch and the platform's bars.
    public static let container = SafeAreaRegions(rawValue: 1)

    /// The on-screen keyboard strip.
    public static let keyboard = SafeAreaRegions(rawValue: 2)

    /// Every strip.
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

extension SafeAreaRegions {
    /// What one edge stays clear of, these regions ignored.
    var stayingClearOf: SafeArea {
        switch self {
        case .all: return .none
        case .container: return .keyboard
        case .keyboard: return .container
        default: return .all
        }
    }
}

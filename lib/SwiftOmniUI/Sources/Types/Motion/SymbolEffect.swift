// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Symbol effects: the short-lived animations a symbol plays - a bounce when a
// value lands, a pulse while work runs. The kind crosses as a word; the host
// plays what it can.
// Design: docs/design/types/animation.md#symbol-effects

/// A named effect a symbol can play - what `.symbolEffect` takes.
///
/// `SymbolEffect` is an open protocol as in SwiftUI: the library ships the
/// common kinds, and any effect type naming a `symbolEffectToken` works.
public protocol SymbolEffect: Sendable {
    /// The effect's token as it crosses to the host: `"bounce"`, `"pulse"`,
    /// `"variableColor"`, `"scale"`, `"replace"`, `"appear"`, `"disappear"`.
    var symbolEffectToken: String { get }
}

/// A symbol that springs out and settles - `value:` plays it on every change.
public struct BounceSymbolEffect: SymbolEffect {
    /// "bounce", as the effect crosses to the host.
    public let symbolEffectToken = "bounce"

    /// The effect.
    public init() {}
}

/// A symbol whose opacity breathes - `.repeating` with `isActive:` keeps it
/// going, one shot otherwise.
public struct PulseSymbolEffect: SymbolEffect {
    /// "pulse", as the effect crosses to the host.
    public let symbolEffectToken = "pulse"

    /// The effect.
    public init() {}
}

/// A symbol whose layered colour cycles.
public struct VariableColorSymbolEffect: SymbolEffect {
    /// "variableColor", as the effect crosses to the host.
    public let symbolEffectToken = "variableColor"

    /// The effect.
    public init() {}
}

/// A symbol that grows or shrinks around its anchor.
public struct ScaleSymbolEffect: SymbolEffect {
    /// "scale", as the effect crosses to the host.
    public let symbolEffectToken = "scale"

    /// The effect.
    public init() {}
}

/// A symbol that swaps its drawing for another's.
public struct ReplaceSymbolEffect: SymbolEffect {
    /// "replace", as the effect crosses to the host.
    public let symbolEffectToken = "replace"

    /// The effect.
    public init() {}
}

/// A symbol arriving into view.
public struct AppearSymbolEffect: SymbolEffect {
    /// "appear", as the effect crosses to the host.
    public let symbolEffectToken = "appear"

    /// The effect.
    public init() {}
}

/// A symbol leaving view.
public struct DisappearSymbolEffect: SymbolEffect {
    /// "disappear", as the effect crosses to the host.
    public let symbolEffectToken = "disappear"

    /// The effect.
    public init() {}
}

extension SymbolEffect where Self == BounceSymbolEffect {
    /// `.symbolEffect(.bounce, ...)`.
    public static var bounce: BounceSymbolEffect { BounceSymbolEffect() }
}

extension SymbolEffect where Self == PulseSymbolEffect {
    /// `.symbolEffect(.pulse, ...)`.
    public static var pulse: PulseSymbolEffect { PulseSymbolEffect() }
}

extension SymbolEffect where Self == VariableColorSymbolEffect {
    /// `.symbolEffect(.variableColor, ...)`.
    public static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() }
}

extension SymbolEffect where Self == ScaleSymbolEffect {
    /// `.symbolEffect(.scale, ...)`.
    public static var scale: ScaleSymbolEffect { ScaleSymbolEffect() }
}

extension SymbolEffect where Self == ReplaceSymbolEffect {
    /// `.symbolEffect(.replace, ...)`.
    public static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() }
}

extension SymbolEffect where Self == AppearSymbolEffect {
    /// `.symbolEffect(.appear, ...)`.
    public static var appear: AppearSymbolEffect { AppearSymbolEffect() }
}

extension SymbolEffect where Self == DisappearSymbolEffect {
    /// `.symbolEffect(.disappear, ...)`.
    public static var disappear: DisappearSymbolEffect { DisappearSymbolEffect() }
}

/// How a symbol effect runs - what `.symbolEffect` takes in `options:`.
public struct SymbolEffectOptions: OptionSet, Equatable, Sendable {
    /// The set as its members' bits.
    public var rawValue: Int32

    /// A set from its members' bits.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Keep playing until the effect is taken off or made inactive.
    public static let repeating = SymbolEffectOptions(rawValue: 1 << 0)

    /// Play once - the default.
    public static let nonRepeating: SymbolEffectOptions = []

    /// The platform's own pace - the default.
    public static let `default`: SymbolEffectOptions = []
}

/// How a view swaps its content - what `.contentTransition` takes.
///
/// The kind crosses as a word; the host plays the closest swap its toolkit
/// has, so `.numericText` counts up where a platform can roll digits and
/// crossfades where it cannot.
public struct ContentTransition: Equatable, Sendable {
    /// The transition's token as it crosses: `"opacity"`, `"interpolate"`,
    /// `"identity"`, `"symbolEffect"`, `"numericText"`, `"numericTextDown"`.
    let token: String

    private init(_ token: String) {
        self.token = token
    }

    /// Fade the old content out as the new fades in.
    public static let opacity = ContentTransition("opacity")

    /// Blend between the two contents.
    public static let interpolate = ContentTransition("interpolate")

    /// Swap with no transition.
    public static let identity = ContentTransition("identity")

    /// The symbol's own replace effect, for a symbol whose drawing changes.
    public static let symbolEffect = ContentTransition("symbolEffect")

    /// Digits that roll to the new number - up by default, down with
    /// `countsDown`.
    public static func numericText(countsDown: Bool = false) -> ContentTransition {
        ContentTransition(countsDown ? "numericTextDown" : "numericText")
    }
}

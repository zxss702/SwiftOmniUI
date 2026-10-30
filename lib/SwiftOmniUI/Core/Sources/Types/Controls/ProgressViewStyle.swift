// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Progress styles: how a ProgressView shows the work - a bar that fills, a
// wheel that turns. The kind crosses as a word; the host draws the closest
// it has.
// Design: docs/design/views/controls.md#progress-view

/// A named style a `ProgressView` draws under - what `.progressViewStyle`
/// takes.
///
/// `ProgressViewStyle` is an open protocol as in SwiftUI: the library ships
/// the common kinds, and any style naming a `progressStyleToken` works.
public protocol ProgressViewStyle: Sendable {
    /// The style's token as it crosses to the host: `"automatic"`,
    /// `"linear"`, `"circular"`.
    var progressStyleToken: String { get }
}

/// The platform's own choice - a bar for a measured piece of work, a wheel
/// for an unmeasured one.
public struct AutomaticProgressViewStyle: ProgressViewStyle {
    /// "automatic", as the style crosses to the host.
    public let progressStyleToken = "automatic"

    /// The style.
    public init() {}
}

/// A bar that fills - what a measured piece of work draws anyway.
public struct LinearProgressViewStyle: ProgressViewStyle {
    /// "linear", as the style crosses to the host.
    public let progressStyleToken = "linear"

    /// The style.
    public init() {}
}

/// A wheel that turns - what an unmeasured piece of work draws anyway.
public struct CircularProgressViewStyle: ProgressViewStyle {
    /// "circular", as the style crosses to the host.
    public let progressStyleToken = "circular"

    /// The style.
    public init() {}
}

extension ProgressViewStyle where Self == AutomaticProgressViewStyle {
    /// `.progressViewStyle(.automatic)`.
    public static var automatic: AutomaticProgressViewStyle { AutomaticProgressViewStyle() }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
    /// `.progressViewStyle(.linear)`.
    public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
    /// `.progressViewStyle(.circular)`.
    public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() }
}

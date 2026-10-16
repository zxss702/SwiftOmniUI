// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `\.colorScheme` reads the appearance the host reports - light or dark, and
/// `system` where it has not said. Unwritten it answers live; a view that
/// reads it is rebuilt as the appearance moves.
struct ColorSchemeKey: EnvironmentKey {
    static var defaultValue: ColorScheme { StandardEnvironment.appInfo.colorScheme }
}

/// `\.accessibilityReduceMotion` reads whether the platform asks for less
/// motion - `false` where the platform has no such setting or has not said.
struct AccessibilityReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

struct IsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether controls in this branch allow user interaction.
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }

    /// The color scheme the host reports.
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }

    /// Whether the platform asks for less motion.
    public var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What the host knows, as objects of `@State` properties every view resolves with `@Environment`.
// Design: docs/design/types/environment.md#the-standard-environment

/// The one instance of each standard provider and the scope every render starts from.
/// Design: docs/design/types/environment.md#one-door-and-the-bottom-of-the-scope
enum StandardEnvironment {
    // Written by the host's reports and read by builds, both on the UI thread.
    nonisolated(unsafe) static let battery = Battery()
    nonisolated(unsafe) static let connectivity = Connectivity()
    nonisolated(unsafe) static let display = DeviceDisplay()
    nonisolated(unsafe) static let locale = LocaleInfo()
    nonisolated(unsafe) static let device = DeviceInfo()
    nonisolated(unsafe) static let appInfo = AppInfo()

    /// The application's session: one per process, its phase pushed by the host.
    nonisolated(unsafe) static let app = ApplicationSession()

    // What a view outside every scene, window or page reads; each of those offers its own, nearer.
    nonisolated(unsafe) static let scene = SceneSession()
    nonisolated(unsafe) static let windowScene = WindowSession()
    nonisolated(unsafe) static let page = PageSession()

    /// How a `Toggle` draws where nothing above it wrote `.toggleStyle`, and a
    /// `Label` where nothing wrote `.labelStyle` or `.labelsHidden`; likewise
    /// the control styles their modifiers name.
    static let toggleStyle = ToggleStyle.automatic
    static let labelStyle = LabelStyle.titleAndIcon
    static let buttonStyle = ButtonStyle.automatic
    static let textFieldStyle = TextFieldStyle.automatic
    static let pickerStyle = PickerStyle.automatic
    static let listStyle = ListStyle.automatic

    /// What every render starts its scope with, keyed as `.environment()` keys.
    nonisolated(unsafe) static let scope: [(key: ObjectIdentifier, object: AnyObject)] = [
        (key: ObjectIdentifier(Battery.self), object: battery),
        (key: ObjectIdentifier(Connectivity.self), object: connectivity),
        (key: ObjectIdentifier(DeviceDisplay.self), object: display),
        (key: ObjectIdentifier(LocaleInfo.self), object: locale),
        (key: ObjectIdentifier(DeviceInfo.self), object: device),
        (key: ObjectIdentifier(AppInfo.self), object: appInfo),
        (key: ObjectIdentifier(ApplicationSession.self), object: app),
        (key: ObjectIdentifier(SceneSession.self), object: scene),
        (key: ObjectIdentifier(WindowSession.self), object: windowScene),
        (key: ObjectIdentifier(PageSession.self), object: page),
        (key: ObjectIdentifier(ToggleStyle.self), object: toggleStyle),
        (key: ObjectIdentifier(LabelStyle.self), object: labelStyle),
        (key: ObjectIdentifier(ButtonStyle.self), object: buttonStyle),
        (key: ObjectIdentifier(TextFieldStyle.self), object: textFieldStyle),
        (key: ObjectIdentifier(PickerStyle.self), object: pickerStyle),
        (key: ObjectIdentifier(ListStyle.self), object: listStyle),
    ]

    /// The standard provider of a type: what an unfilled `@Environment` slot answers,
    /// such as the application's, built outside any render.
    static func object(for key: ObjectIdentifier) -> AnyObject? {
        scope.last(where: { $0.key == key })?.object
    }
}

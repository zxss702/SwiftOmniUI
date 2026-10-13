// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One kind of window a scene opens beside its main one: one window of it,
/// or - given `for:` - one per value.
///
///     WindowGroup(.fonts) { FontsWindow() }
///     WindowGroup(.document, for: UUID.self) { $id in DocumentWindow(id: id) }
///
/// The group says what the window is; the scene's session says when it opens:
///
///     @Environment private var scene: SceneSession
///
///     Button("Fonts").onClicked { try await scene.openWindow(.fonts) }
///     Button("Open").onClicked { try await scene.openWindow(.document, value: id) }
///
/// A window of a group belongs to its scene: it closes with the scene, and the
/// platform restores it to its scene for the same value, which is why the
/// value is `Codable`. A host without independent windows refuses
/// `openWindow` with `WindowError.unsupported`.
/// Group membership does not make an ordinary window a native owned or
/// transient window; explicit floating tools opt into that platform policy.
public struct WindowGroup {
    /// The kind of window.
    let type: WindowType

    /// The type of value the group opens one window per; nil for one window.
    let valueType: Any.Type?

    /// The window for one that is open, in the scene that has it open.
    let make: (_ opened: OpenedWindow, _ record: SceneRecord) -> WindowScene

    /// A value read back from its text: what a restored window is opened for.
    let restore: (_ text: String) -> AnyHashable?

    /// Whether its windows hide while another scene is in front.
    var hides = false

    /// Whether its windows float above the application's other windows.
    var floats = false

    /// How its windows settle their size against their content; nil for the
    /// platform's ordinary sizing.
    var resizability: WindowResizability? = nil

    /// The size its windows open at, in device units; nil for the platform's
    /// own.
    var defaultSize: (width: Double, height: Double)? = nil

    /// Where its windows open on the screen, the anchor landing the same way
    /// on window and work area; nil for the platform's own choice.
    var defaultPosition: UnitPoint? = nil

    /// The commands the group's windows offer, `.commands` appending them.
    var commands: [any Commands] = []

    /// A group that opens one window, in any scene that declares it.
    ///
    ///     WindowGroup(.debugInspector) { DebugInspector() }
    ///
    /// - Parameters:
    ///   - type: what a session's `openWindow` opens it by.
    ///   - window: the window.
    public init(_ type: WindowType, @WindowBuilder window: @escaping () -> WindowScene) {
        self.type = type
        valueType = nil
        make = { _, _ in window() }
        restore = { _ in nil }
    }

    /// A group that opens one window per value - a document per document, an
    /// inspector per item.
    ///
    ///     WindowGroup(.document, for: UUID.self) { $id in DocumentWindow(id: id) }
    ///
    /// The window is handed a binding to its own value: reading it says which
    /// value the window is for, and writing it makes the same window about
    /// another - which is also what the system restores it for.
    ///
    /// - Parameters:
    ///   - type: what a session's `openWindow` opens one by.
    ///   - value: the type of value one window stands for - anything
    ///     `Codable` and `Hashable`, so the platform can write it down.
    ///   - window: the window for one value.
    public init<Value: Codable & Hashable & SendableMetatype>(
        _ type: WindowType,
        for value: Value.Type,
        @WindowBuilder window: @escaping (Binding<Value>) -> WindowScene
    ) {
        self.type = type
        valueType = Value.self
        make = { opened, record in
            // The value the scene was built with; a write retargets this window,
            // and the scene, which reads what it has open, builds it again.
            let standing = opened.value?.base as! Value

            let binding = Binding<Value>(
                get: { standing },
                set: { record.retarget(opened.serial, to: $0) })

            return window(binding)
        }
        restore = { text in ValueText.read(Value.self, from: text).map(AnyHashable.init) }
    }

    /// Whether the group's windows hide while another scene of the
    /// application is the one in front - and come back when their own is.
    /// A host without that native policy leaves the windows visible.
    ///
    ///     WindowGroup(.fonts) { FontsWindow() }
    ///         .hidesWhenInactive(true)
    @_spi(Host) public func hidesWhenInactive(_ hides: Bool) -> WindowGroup {
        var copy = self
        copy.hides = hides
        return copy
    }

    /// Whether the group's windows float above the application's other
    /// windows - a tool that stays in sight over the main window it serves -
    /// while the application is in front. A host without native window levels
    /// leaves their order to the platform.
    ///
    ///     WindowGroup(.fonts) { FontsWindow() }
    ///         .floatsOnTop(true)
    @_spi(Host) public func floatsOnTop(_ floats: Bool) -> WindowGroup {
        var copy = self
        copy.floats = floats
        return copy
    }

    /// Where the group's windows open: `position`'s fractions across and down
    /// the screen's work area land the same fractions across and down the
    /// window - `.center` centers it, `.topLeading` its top left corner at the
    /// work area's.
    ///
    ///     WindowGroup(.main) { MainPage() }
    ///         .defaultPosition(.center)
    public func defaultPosition(_ position: UnitPoint) -> WindowGroup {
        var copy = self
        copy.defaultPosition = position
        return copy
    }

    /// Where the group's windows open, the fractions outright.
    public func defaultPosition(x: Double, y: Double) -> WindowGroup {
        defaultPosition(UnitPoint(x: x, y: y))
    }

    /// Where the group's windows open and the size they open at, in one ask -
    /// a placement's anchor, and its size where it is not `.zero`:
    ///
    ///     WindowGroup(.inspector) { Inspector() }
    ///         .defaultPlacement(WindowPlacement(position: .topTrailing, size: Size(320, 480)))
    ///
    /// `.automatic` asks nothing at all, the platform's own place and size
    /// standing.
    public func defaultPlacement(_ placement: WindowPlacement) -> WindowGroup {
        var copy = self
        copy.defaultPosition = placement.anchor
        copy.defaultSize = placement.extent.map { (width: $0.width, height: $0.height) }
        return copy
    }

    /// How the group's windows settle their size against their content -
    /// `.contentSize` has the window take the size its content asks for and
    /// no other:
    ///
    ///     WindowGroup(.settings) { SettingsWindow() }
    ///         .windowResizability(.contentSize)
    ///
    /// A host that cannot fix a window's size takes what it can of the
    /// constraint - `.contentMinSize` binds its least size.
    public func windowResizability(_ resizability: WindowResizability) -> WindowGroup {
        var copy = self
        copy.resizability = resizability
        return copy
    }

    /// The size the group's windows open at, in device units:
    ///
    ///     WindowGroup(.main) { MainWindow() }
    ///         .defaultSize(width: 1280, height: 800)
    ///
    /// The platform's own size stands where none is asked for, and a size the
    /// user later gives the window is its own.
    public func defaultSize(width: Double, height: Double) -> WindowGroup {
        var copy = self
        copy.defaultSize = (width: width, height: height)
        return copy
    }

    /// The size the group's windows open at, as one value.
    public func defaultSize(_ size: Size) -> WindowGroup {
        defaultSize(width: size.width, height: size.height)
    }
}

/// The SwiftUI spellings: `WindowGroup(for:)` with a view built off the
/// value's binding, and a group standing alone where a scene is asked for.
extension WindowGroup {
    /// A group that opens one window per value - a document per document -
    /// the windows' kind being the value's own type, as SwiftUI resolves it:
    ///
    ///     WindowGroup(for: URL.self) { $folder in EditorWindow(folder: folder) }
    ///
    /// The content is handed a binding to the window's value - `nil` until
    /// the window stands for one, and a write retargets the window, as
    /// `init(_:for:window:)` hands it.
    ///
    /// - Parameters:
    ///   - value: the type of value one window stands for - anything
    ///     `Codable` and `Hashable`, so the platform can write it down.
    ///   - content: the window's page for one value.
    public init<Value: Codable & Hashable & SendableMetatype, Content: View>(
        for value: Value.Type,
        @ViewBuilder content: @escaping (Binding<Value?>) -> Content
    ) {
        let content = Carry(content)
        self.init(WindowType(String(reflecting: Value.self)), for: value) { binding in
            // The window's scene conformance is main-actor bound; the group's
            // `make` always runs on the UI thread, where the window stands.
            MainActor.assumeIsolated {
                Window {
                    content.value(Binding(
                        get: { binding.wrappedValue },
                        set: { if let value = $0 { binding.wrappedValue = value } }))
                }
            }
        }
    }
}

/// A `WindowGroup` written where a scene is asked for: an app body built of
/// groups alone opens none until `openWindow` asks, and one written beside
/// windows stands among them.
extension WindowGroup: Scene {
    /// The scene of this group: its windows open as `openWindow` asks.
    public var windows: Windows { Windows { self } }
}

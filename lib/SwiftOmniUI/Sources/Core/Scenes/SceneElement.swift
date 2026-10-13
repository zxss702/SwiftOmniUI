// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A scene as the tree holds it, and the node its build answers: the main window,
// the windows open beside it, and the handlers of the host's reports.
// Design: docs/design/core/scenes.md#the-scene-tree

/// A scene as the tree holds it - a composed view, so each open scene has `@State`
/// of its own, paired under its number.
struct SceneElement: Element {
    /// Which scene.
    let record: SceneRecord

    /// What the application says a scene is.
    let scene: any Scene

    var node: Node {
        let authored = SceneElement.unwrapped(scene)

        var node = Node.composed(
            self, type: String(reflecting: type(of: authored)), scene: record
        ) { [record, scene] in
            SceneElement.build(record, scene)
        }

        node.id = record.id

        // What the application offered its scenes, and the scene's own session.
        node.environments = SceneElement.offered(by: scene)
            + [(key: ObjectIdentifier(SceneSession.self), object: record.session)]

        // `\.openWindow` acts on this scene's groups, wherever below it is read.
        node.environmentValues[keyPath: \.openWindow] = OpenWindowAction(record: record)

        return node
    }

    /// The scene's node: its main window first, then the windows it has open
    /// beside it, and the reports the host makes about them.
    static func build(_ record: SceneRecord, _ scene: any Scene) -> Node {
        let windows = scene.windows

        var declared: [WindowType: GroupShape] = [:]

        for group in windows.groups where declared[group.type] == nil {
            declared[group.type] = GroupShape(valueType: group.valueType, restore: group.restore)
        }

        record.declared = declared
        record.declaresMainWindow = windows.main != nil
        record.mainWindowType = (windows.main as? WindowSceneAsks)?.windowID.map(WindowType.init)

        var children: [Node] = []

        if let windowScene = windows.main, record.mainIsOpen {
            let own = windowScene as? WindowSceneAsks
            var main = windowScene.node(session: record.windowSession(SceneElement.mainKey))
            main.id = SceneElement.mainKey
            if let type = record.mainWindowType { main.write(WindowSceneContract.windowType, type) }
            main.append(commands: sceneMenus(of: windows))

            // The window's own asks win over its scene's defaults.
            if let size = own?.windowSize ?? windows.defaultSize {
                main.write(WindowSceneContract.width, size.width)
                main.write(WindowSceneContract.height, size.height)
            }
            if let position = own?.windowPosition ?? windows.defaultPosition {
                main.write(WindowSceneContract.defaultPosition, position)
            }
            if let resizability = own?.windowResizability ?? windows.resizability {
                main.write(WindowSceneContract.resizability, resizability)
            }
            for edit in windows.environmentEdits { edit(&main.environmentValues) }

            children = [main]
        }

        // Read here, so this scene is what builds again when a window opens in it.
        for opened in record.windows {
            guard let group = windows.groups.first(where: { $0.type == opened.type }) else {
                continue
            }

            let windowScene = group.make(opened, record)
            let own = windowScene as? WindowSceneAsks
            var window = windowScene.node(session: record.windowSession(opened.key))
            window.id = opened.key
            window.append(commands: sceneMenus(of: windows) + group.commands.flatMap { $0.commandNodes })

            // Written either way, so none of them is ever cleared off a window.
            // Design: docs/design/core/scenes.md#opening-windows
            window.write(WindowSceneContract.windowType, opened.type)
            window.describe(WindowSceneContract.windowValue, opened.text)
            window.write(WindowSceneContract.hidesWhenInactive, group.hides)
            window.write(WindowSceneContract.floatsOnTop, group.floats)
            if let resizability = own?.windowResizability ?? group.resizability ?? windows.resizability {
                window.write(WindowSceneContract.resizability, resizability)
            }
            for edit in windows.environmentEdits { edit(&window.environmentValues) }
            if let size = own?.windowSize ?? group.defaultSize ?? windows.defaultSize {
                window.write(WindowSceneContract.width, size.width)
                window.write(WindowSceneContract.height, size.height)
            }
            if let position = own?.windowPosition ?? group.defaultPosition ?? windows.defaultPosition {
                window.write(WindowSceneContract.defaultPosition, position)
            }

            children.append(window)
        }

        // A window that closed takes its session with it.
        record.keepWindowSessions()

        var node = Node(contract: SceneContract.self, children: children)
        node.environments = windows.environments

        // The user closed a window of the scene - its key is the payload.
        node.addHandler(SceneContract.windowClosed.token) {
            if let key = EventBuffer.current.value()?.string {
                record.closed(key: key)
            }
        }

        // The system restored one: its kind and its value's text. A render is asked for
        // either way - the host holds the window until it hears.
        node.addHandler(SceneContract.windowRestored.token) {
            if let name = EventBuffer.current.value(0)?.string {
                record.restored(kind: name, text: EventBuffer.current.value(1)?.string)
            }

            Renderer.shared.setNeedsRender()
        }

        // Its main window has gone - the user closed it - and the scene with it.
        node.addHandler(SceneContract.destroying.token) { Scenes.shared.ended(record) }

        // Where the scene stands, as the host sees it.
        node.addHandler(SceneContract.activated.token) { record.session.phase = .active }
        node.addHandler(SceneContract.deactivated.token) { record.session.phase = .inactive }
        node.addHandler(SceneContract.stopped.token) { record.session.phase = .background }

        return node
    }

    /// The scene-wide commands' menu nodes, each `Commands` flattened.
    private static func sceneMenus(of windows: Windows) -> [Node] {
        windows.commands.flatMap { $0.commandNodes }
    }

    /// What the tree knows a scene's main window by.
    nonisolated static let mainKey = "main"

    /// The scene the application wrote, under whatever wrapped it.
    static func unwrapped(_ scene: any Scene) -> any Scene {
        if let offering = scene as? OfferingScene { return unwrapped(offering.base) }
        if let placed = scene as? PlacedScene { return unwrapped(placed.base) }
        return scene
    }

    /// What `.environment(_:)` offered the scene, outermost first - so the one
    /// written last is nearest, the way it is on a view. A wrapper that edits
    /// the scene's windows offers what the wrapped scene does.
    static func offered(by scene: any Scene) -> [(key: ObjectIdentifier, object: AnyObject)] {
        if let offering = scene as? OfferingScene {
            return offered(by: offering.base) + [(key: offering.key, object: offering.object)]
        }
        if let placed = scene as? PlacedScene { return offered(by: placed.base) }
        if let boxed = scene as? AnyScene { return offered(by: boxed.base) }
        return []
    }
}

extension Node {
    /// Hangs the menus a scene's or a window group's `.commands` wrote off the
    /// window - a menu bar slot the window's own, which the host reads as the
    /// scene's menus beside the visible page's; nothing for none.
    mutating func append(commands menus: [Node]) {
        guard !menus.isEmpty else { return }
        var slot = Node(contract: MenuBarContract.self, children: menus)
        slot.key = "commands"
        children.append(slot)
    }
}

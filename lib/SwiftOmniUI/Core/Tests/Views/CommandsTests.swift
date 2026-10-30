// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The `.commands { … }` block and what stands in it.
//
// `Commands` is to `.commands` what `ToolbarContent` is to `.toolbar`: a
// group or a menu is an entry, and a `Commands` whose `body` lists entries
// composes them. These tests pin the node shape the block writes - a `MenuBar`
// slot on every window node, each menu a `CommandMenu`'s or a `CommandGroup`'s
// placement - so the host knows the scene's menus from the page's, which hang
// under the page.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private extension WindowType {
    static let palettes = WindowType("palettes")
}

/// A page with nothing on it.
private struct Blank: View {
    var body: some View { Text("blank") }
}

/// A window and nothing else.
private struct BlankWindow: WindowScene {
    var page: any Page { Blank() }
}

/// Commands made of others - `RunCommands` in ShenYan Code Edit is one of
/// these.
private struct Composed: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About") {}
        }
    }
}

/// The application every test stands behind: a scene of one main window
/// with commands on it, and a group of one with commands of its own.
private struct Studio: Scene {
    var windows: Windows {
        Windows {
            WindowGroup(.palettes) { BlankWindow() }
                .commands {
                    CommandMenu("Palettes") {
                        Button("Show") {}
                    }
                }
        } main: {
            BlankWindow()
        }
        .commands {
            CommandMenu("Run") {
                Button("Build") {}
                    .keyboardShortcut("b")
            }
            Composed()
        }
    }
}

private struct StudioApp: App {
    var body: some Scene { Studio() }
}

@MainActor final class CommandsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Scenes.shared.reset()
        Renderer.shared.clearInvalidation()
    }

    override func tearDown() {
        Scenes.shared.reset()
        super.tearDown()
    }

    /// The application's tree, the way `Renderer.root` builds it.
    private func tree(_ application: any App = StudioApp()) -> Node {
        Scenes.shared.tree(of: application)
    }

    /// The commands slot on a window patch or node - the MenuBar the
    /// window carries, not the page's, which hangs under the page.
    private func commandsSlot(in window: HostPatch) -> HostPatch? {
        window.children.first { $0.type == .menuBar }
    }

    private func commandsSlot(in window: Node) -> Node? {
        window.children.first { $0.type == .menuBar }
    }

    /// The main window's patch.
    private func mainWindow(in patch: HostPatch) throws -> HostPatch {
        try XCTUnwrap(patch.children.first?.children.first)
    }

    /// `.commands` on a scene writes a MenuBar slot on the window - the
    /// scene's menus.
    func testCommandsStandAsAMenuBarSlotOnTheWindow() throws {
        let patch = Renders().render(tree())
        let slot = try XCTUnwrap(commandsSlot(in: mainWindow(in: patch)))

        XCTAssertEqual(slot.children.map(\.type), [.menu, .menu])
    }

    /// A `CommandMenu` stands as a Menu node with its caption; a
    /// `CommandGroup` as one carrying the region it replaces.
    func testMenusAndGroupsCarryTheirCaptionAndPlacement() throws {
        let patch = Renders().render(tree())
        let slot = try XCTUnwrap(commandsSlot(in: mainWindow(in: patch)))

        XCTAssertEqual(slot.children[0].props[.text], .string("Run"))
        XCTAssertNil(slot.children[0].props[.placement])
        XCTAssertEqual(slot.children[1].props[.placement],
                       .enumeration(CommandGroupPlacement.appInfo.rawValue))
    }

    /// A `Button` in the entries is a menu item the host reads: its label's
    /// text under it, its `.keyboardShortcut` on it.
    func testAButtonInTheEntriesCarriesItsLabelAndShortcut() throws {
        let patch = Renders().render(tree())
        let slot = try XCTUnwrap(commandsSlot(in: mainWindow(in: patch)))
        let run = try XCTUnwrap(slot.children.first)

        let button = try XCTUnwrap(run.children.first { $0.type == .button })
        XCTAssertEqual(button.props[.text], .string("Build"))
        XCTAssertEqual(button.props[.shortcut],
                       .values([.name("b"), .enumeration(EventModifiers.command.rawValue)]))
        XCTAssertNotNil(button.events?[.clicked])
    }

    /// A `Commands` made of others flattens to the menus its body lists -
    /// `Composed` stands for the app-info group, in order after the menu
    /// written before it.
    func testAComposedCommandsFlattensToWhatItsBodyLists() throws {
        let patch = Renders().render(tree())
        let slot = try XCTUnwrap(commandsSlot(in: mainWindow(in: patch)))

        XCTAssertEqual(slot.children.map { $0.props[.placement] },
                       [nil, .enumeration(CommandGroupPlacement.appInfo.rawValue)])
        XCTAssertEqual(slot.children[1].children.map(\.type), [.button])
    }

    /// A group's `.commands` reach only the windows the group opens - the
    /// main window carries the scene's alone.
    func testAGroupsCommandsReachOnlyItsOwnWindows() async throws {
        let renders = Renders()
        renders.render(tree())
        try await Scenes.shared.list[0].session.openWindow(.palettes)

        let whole = renders.renderFromScratch(tree())
        let scene = try XCTUnwrap(whole.children.first)

        let main = try XCTUnwrap(scene.children.first { $0.id == .manual("main") })
        let palettes = try XCTUnwrap(scene.children.first { $0.id != .manual("main") })

        XCTAssertEqual(commandsSlot(in: main)?.children.count, 2)
        let slot = try XCTUnwrap(commandsSlot(in: palettes))
        XCTAssertEqual(slot.children.count, 3)
        XCTAssertEqual(try XCTUnwrap(slot.children.last).props[.text], .string("Palettes"))
    }

    /// Every menu is keyed by where it was written - the differ's name for
    /// one that moves or leaves.
    func testMenusAreKeyedByWhereTheyStood() throws {
        struct Keyed: Scene {
            var windows: Windows {
                Windows { BlankWindow() }
                    .commands {
                        CommandMenu("first") { Button("a") {} }
                        if true {
                            CommandMenu("branch") { Button("b") {} }
                        }
                        CommandMenu("last") { Button("c") {} }
                    }
            }
        }

        struct KeyedApp: App {
            var body: some Scene { Keyed() }
        }

        let window = try XCTUnwrap(
            tree(KeyedApp()).built.children.first?.built.children.first)
        let slot = try XCTUnwrap(commandsSlot(in: window))

        XCTAssertEqual(slot.children.map(\.key), ["0", "1.some.0", "2"])
    }

    /// A disabled command is a menu item that cannot be chosen.
    func testADisabledCommandCarriesIsEnabled() throws {
        struct Disabled: Scene {
            var windows: Windows {
                Windows { BlankWindow() }
                    .commands {
                        CommandGroup(replacing: .appInfo) {
                            Button("Nothing").disabled(true)
                        }
                    }
            }
        }

        struct DisabledApp: App {
            var body: some Scene { Disabled() }
        }

        let patch = Renders().render(tree(DisabledApp()))
        let slot = try XCTUnwrap(commandsSlot(in: mainWindow(in: patch)))

        XCTAssertEqual(
            try XCTUnwrap(slot.children.first?.children.first).props[.isEnabled], .bool(false))
    }

    /// `.commands` on a `WindowScene` itself - a scene of one window - lands
    /// the same as on a scene.
    func testCommandsOnAWindowSceneStandTheSame() throws {
        struct Alone: App {
            var body: some Scene {
                BlankWindow()
                    .commands {
                        CommandMenu("Run") { Button("Build") {} }
                    }
            }
        }

        let patch = Renders().render(tree(Alone()))
        let slot = try XCTUnwrap(commandsSlot(in: mainWindow(in: patch)))

        XCTAssertEqual(try XCTUnwrap(slot.children.first).props[.text], .string("Run"))
    }
}

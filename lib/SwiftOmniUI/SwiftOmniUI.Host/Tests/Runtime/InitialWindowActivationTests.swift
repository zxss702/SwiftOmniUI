// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// A plain launch identifies the first declared window independently of the active window.
@MainActor
final class InitialWindowActivationTests: XCTestCase {
    func testRepeatedActivationReusesTheFirstWindowAndScene() throws {
        let runtime = start()
        let main = try XCTUnwrap(runtime.initialWindowForActivation())
        let scene = try XCTUnwrap(Scenes.shared.record(id: "1"))
        try scene.open(WindowType("activation.editor"), value: 7)
        runtime.pump.turn()
        let editor = try XCTUnwrap(runtime.tree.root?.windows.last)
        runtime.windowStateChanged(editor, minimized: false, activated: true)
        runtime.settlePhases()

        // A restored second scene must not take precedence over the earliest scene.
        runtime.core.connectScene()
        runtime.pump.turn()
        for _ in 0..<5 {
            XCTAssertTrue(runtime.initialWindowForActivation() === main)
        }
        XCTAssertEqual(runtime.tree.root?.windows.count, 3)
        XCTAssertEqual(Scenes.shared.list.count, 2)
        XCTAssertTrue(runtime.tree.root?.windows.contains { $0 === editor } == true)
    }

    func testReopeningTheWelcomeWindowKeepsTheEditorsStateAndIdentity() throws {
        let runtime = start()
        let main = try XCTUnwrap(runtime.initialWindowForActivation())
        let scene = try XCTUnwrap(Scenes.shared.record(id: "1"))
        try scene.open(WindowType("activation.editor"), value: 7)
        runtime.pump.turn()
        let editor = try XCTUnwrap(runtime.tree.root?.windows.last)
        let label = try XCTUnwrap(editor.first(type: .text))
        let change = try XCTUnwrap(editor.first(type: .button)?.handler(.clicked))
        runtime.dispatch(change)
        XCTAssertEqual(label.value(.text)?.string, "Editor 7: 1")

        runtime.userClosed(main)
        XCTAssertEqual(runtime.tree.root?.windows.count, 1)
        let reopened = try XCTUnwrap(runtime.initialWindowForActivation())
        XCTAssertFalse(reopened === main)
        XCTAssertEqual(reopened.value(.windowType)?.name, "activation.welcome")
        XCTAssertEqual(runtime.tree.root?.windows.count, 2)
        XCTAssertTrue(runtime.tree.root?.windows.last === editor)
        XCTAssertTrue(editor.first(type: .text) === label)
        XCTAssertEqual(label.value(.text)?.string, "Editor 7: 1")
        XCTAssertTrue(runtime.initialWindowForActivation() === reopened)
    }

    func testALaunchAcceptedAfterTheLastCloseStartsOneFreshScene() throws {
        let runtime = start()
        let main = try XCTUnwrap(runtime.initialWindowForActivation())
        runtime.userClosed(main)
        XCTAssertTrue(runtime.tree.root?.windows.isEmpty == true)
        XCTAssertTrue(Scenes.shared.list.isEmpty)

        let reopened = try XCTUnwrap(runtime.initialWindowForActivation())
        XCTAssertFalse(reopened === main)
        XCTAssertEqual(runtime.tree.root?.windows.count, 1)
        XCTAssertEqual(Scenes.shared.list.count, 1)
        XCTAssertTrue(runtime.initialWindowForActivation() === reopened)
    }

    func testProgrammaticClosingLeavesNoWindowButActivationCanReopenIt() throws {
        let runtime = start()
        let scene = try XCTUnwrap(Scenes.shared.record(id: "1"))
        try scene.close(WindowType("activation.welcome"))
        runtime.pump.turn()
        XCTAssertTrue(runtime.tree.root?.windows.isEmpty == true)
        XCTAssertEqual(Scenes.shared.list.count, 1, "an empty scene must not keep the native process alive")

        XCTAssertNotNil(runtime.initialWindowForActivation())
        XCTAssertEqual(runtime.tree.root?.windows.count, 1)
        XCTAssertTrue(Scenes.shared.record(id: "1") === scene)
    }

    private func start() -> HostRuntime {
        stateUIUseApp(ActivationApplication())
        let runtime = HostRuntime.still()
        runtime.core.connectScene()
        runtime.pump.turn()
        return runtime
    }
}

private struct ActivationApplication: App {
    var body: some Scene {
        Window("Welcome", id: "activation.welcome") { Text("Welcome") }
        WindowGroup(WindowType("activation.editor"), for: Int.self) { number in
            Window { ActivationEditorPage(number: number.wrappedValue) }
        }
    }
}

private struct ActivationEditorPage: View {
    let number: Int
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Editor \(number): \(count)")
            Button("Change").onClicked { count += 1 }
        }
    }
}

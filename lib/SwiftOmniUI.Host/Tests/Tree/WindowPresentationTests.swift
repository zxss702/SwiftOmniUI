// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// What a window asks its host to show, as it changes.
@MainActor
final class WindowPresentationTests: XCTestCase {
    /// A window shows the first arrangement of pages among its children and its overlay, says each only when it
    /// changes, and is told it was made once.
    func testAWindowSaysWhatItShowsOnlyAsItChanges() throws {
        let runtime = HostRuntime.still()
        func window(_ children: [HostPatch]) -> HostPatch {
            var window = HostPatch(id: .manual("window"), type: .windowScene)
            window.events = .replace([.created: 5])
            window.children = .arranged(children)
            return window
        }
        runtime.tree.apply(window([HostPatch(id: .manual("page"), type: .page)]), complete: true)
        var told: [Int32] = []
        runtime.tree.tellPhase = { told.append($0) }
        let presentation = WindowPresentation()

        let first = presentation.show(try XCTUnwrap(runtime.tree.root), in: runtime.lifecycle)
        XCTAssertEqual(first.arrangement?.shown?.id, .manual("page"))
        XCTAssertNil(first.arrangement?.previous)
        XCTAssertEqual(told, [5])
        XCTAssertTrue(first.overlay == nil, "no overlay, before or now: nothing to say")

        let again = presentation.show(try XCTUnwrap(runtime.tree.root), in: runtime.lifecycle)
        XCTAssertNil(again.arrangement)
        XCTAssertTrue(again.overlay == nil, "nothing new to lay over")
        XCTAssertEqual(told, [5], "told it was made once")
    }

    /// A window's place and size are four requests, each said alone where the tree changed it; one it keeps, or
    /// takes away, moves nothing.
    func testAWindowsFrameIsFourRequestsEachAlone() throws {
        let runtime = HostRuntime.still()
        var window = HostPatch(id: .manual("window"), type: .windowScene)
        window.properties = [.x: .number(40), .width: .number(640)]
        runtime.tree.apply(window, complete: true)
        let presentation = WindowPresentation()
        let root = try XCTUnwrap(runtime.tree.root)
        func change(_ properties: [Prop: HostValue], clearing cleared: [Prop] = []) -> WindowFrame? {
            var patch = HostPatch(id: .manual("window"), type: .windowScene)
            patch.properties = properties
            patch.clearedProperties = cleared
            runtime.tree.apply(patch, complete: false)
            return presentation.show(root, in: runtime.lifecycle).frame
        }

        XCTAssertEqual(presentation.show(root, in: runtime.lifecycle).frame, WindowFrame(x: 40, width: 640))
        XCTAssertEqual(
            change([.x: .number(40), .width: .number(800), .height: .number(480)]), WindowFrame(width: 800, height: 480))
        XCTAssertNil(change([:]), "nothing changed: the window stays where the user put it")
        XCTAssertNil(change([:], clearing: [.x]), "a request taken away moves nothing")
        XCTAssertEqual(change([.x: .number(40)]), WindowFrame(x: 40), "asked again, it moves the window again")
        XCTAssertNil(change([.width: .number(-1)]), "a size below nothing asks for none")
    }

    /// A window's bounds are said the first time and where they change; a greatest below the least is the least.
    func testAWindowsGreatestSizeNeverStandsBelowItsLeast() throws {
        let runtime = HostRuntime.still()
        var window = HostPatch(id: .manual("window"), type: .windowScene)
        window.properties = [.minimumWidth: .number(400), .maximumWidth: .number(300), .maximumHeight: .number(900)]
        runtime.tree.apply(window, complete: true)
        let presentation = WindowPresentation()
        let root = try XCTUnwrap(runtime.tree.root)

        let bounds = try XCTUnwrap(presentation.show(root, in: runtime.lifecycle).bounds)
        XCTAssertEqual(bounds.minimumWidth, 400)
        XCTAssertEqual(bounds.maximumWidth, 400, "the least wins")
        XCTAssertNil(bounds.minimumHeight, "unsaid: the toolkit's own")
        XCTAssertEqual(bounds.maximumHeight, 900)
        XCTAssertNil(presentation.show(root, in: runtime.lifecycle).bounds, "said once until they change")
    }

    /// Only an explicitly floating tool has a native owner, said once until
    /// it changes. A scene's main window itself remains independent.
    func testAnExplicitlyFloatingToolBelongsToItsScenesMainWindow() throws {
        let runtime = HostRuntime.still()
        var tool = HostPatch(id: .manual("tool"), type: .windowScene)
        tool.properties = [.windowType: .name("tool"), .floatsOnTop: .bool(true)]
        var scene = HostPatch(id: .manual("scene"), type: .scene)
        scene.children = .arranged([tool, HostPatch(id: .manual("main"), type: .windowScene)])
        runtime.tree.apply(scene, complete: true)
        let main = try XCTUnwrap(runtime.tree.root?.first(id: .manual("main")))
        let owned = try XCTUnwrap(runtime.tree.root?.first(id: .manual("tool")))
        let (mainPresentation, toolPresentation) = (WindowPresentation(), WindowPresentation())

        let mainOwner = try XCTUnwrap(mainPresentation.show(main, in: runtime.lifecycle).owner, "said the first time")
        XCTAssertNil(mainOwner, "a main window belongs to none")
        XCTAssertTrue(toolPresentation.show(owned, in: runtime.lifecycle).owner??.id == .manual("main"),
                      "wherever it stands among the scene's windows")
        XCTAssertTrue(toolPresentation.show(owned, in: runtime.lifecycle).owner == nil, "said once until it changes")
    }

    func testNamedAndValueBackedWindowsRemainIndependentInTheSameScene() throws {
        let runtime = HostRuntime.still()
        var settings = HostPatch(id: .manual("settings"), type: .windowScene)
        settings.properties = [.windowType: .name("settings")]
        var document = HostPatch(id: .manual("document"), type: .windowScene)
        document.properties = [.windowType: .name("document"), .windowValue: .string("folder")]
        var scene = HostPatch(id: .manual("scene"), type: .scene)
        scene.children = .arranged([HostPatch(id: .manual("main"), type: .windowScene), settings, document])
        runtime.tree.apply(scene, complete: true)

        for id in ["settings", "document"] {
            let window = try XCTUnwrap(runtime.tree.root?.first(id: .manual(id)))
            let presentation = WindowPresentation()
            let owner = try XCTUnwrap(presentation.show(window, in: runtime.lifecycle).owner)
            XCTAssertNil(owner, "a window kind is not a request for native ownership")
            XCTAssertTrue(presentation.show(window, in: runtime.lifecycle).owner == nil)
        }
    }

    func testChangingTheFloatingPolicyReleasesAndRestoresNativeOwnership() throws {
        let runtime = HostRuntime.still()
        var tool = HostPatch(id: .manual("tool"), type: .windowScene)
        tool.properties = [.windowType: .name("tool"), .floatsOnTop: .bool(true)]
        var scene = HostPatch(id: .manual("scene"), type: .scene)
        scene.children = .arranged([HostPatch(id: .manual("main"), type: .windowScene), tool])
        runtime.tree.apply(scene, complete: true)
        let window = try XCTUnwrap(runtime.tree.root?.first(id: .manual("tool")))
        let presentation = WindowPresentation()
        XCTAssertEqual(presentation.show(window, in: runtime.lifecycle).owner??.id, .manual("main"))

        var update = HostPatch(id: tool.id, type: .windowScene)
        update.properties = [.floatsOnTop: .bool(false)]
        scene.children = .changed([update])
        runtime.tree.apply(scene, complete: false)
        let released = try XCTUnwrap(presentation.show(window, in: runtime.lifecycle).owner)
        XCTAssertNil(released, "removing a floating policy must clear the native owner")

        update.properties = [.floatsOnTop: .bool(true)]
        scene.children = .changed([update])
        runtime.tree.apply(scene, complete: false)
        XCTAssertEqual(presentation.show(window, in: runtime.lifecycle).owner??.id, .manual("main"))

        update.properties = [:]
        update.clearedProperties = [.floatsOnTop]
        scene.children = .changed([update])
        runtime.tree.apply(scene, complete: false)
        let cleared = try XCTUnwrap(presentation.show(window, in: runtime.lifecycle).owner)
        XCTAssertNil(cleared, "clearing the modifier restores ordinary platform ownership")
    }
}

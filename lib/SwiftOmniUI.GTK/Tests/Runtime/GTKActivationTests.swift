// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKActivationTests: XCTestCase {
    func testReactivationReopensWelcomeAndRetainsTheEditor() throws {
        try onUIThread {
            let host = GTKRenderer.running(application: GTKActivationApplication())
            let welcome = try XCTUnwrap(host.windows.first)
            try XCTUnwrap(host.views(GTKButtonView.self).first { $0.text == "Open editor" }).click()
            host.settle { host.windows.count == 2 }
            let editor = try XCTUnwrap(host.windows.last)
            XCTAssertFalse(editor === welcome)
            let label = try XCTUnwrap(host.views(GTKLabelView.self).first { $0.text == "Editor: 0" })
            try XCTUnwrap(host.views(GTKButtonView.self).first { $0.text == "Change" }).click()
            XCTAssertEqual(label.text, "Editor: 1")

            welcome.close()
            host.settle { host.windows.count == 1 }
            XCTAssertTrue(host.windows.first === editor)
            GTKRenderer.activated(host.application)
            host.settle { host.windows.count == 2 }
            let reopened = try XCTUnwrap(host.windows.first)
            XCTAssertFalse(reopened === welcome)
            XCTAssertTrue(host.windows.last === editor)
            XCTAssertTrue(host.views(GTKLabelView.self).contains { $0 === label })
            XCTAssertEqual(label.text, "Editor: 1")

            editor.present()
            for _ in 0..<5 { GTKRenderer.activated(host.application); host.step() }
            XCTAssertEqual(host.windows.count, 2)
            XCTAssertTrue(host.windows.first === reopened)
            XCTAssertTrue(host.windows.last === editor)
            XCTAssertEqual(gtk_widget_get_mapped(reopened.widget), 1)
            // Closing the last two real windows removes both native and declared windows.
            reopened.close()
            editor.close()
            host.settle { host.windows.isEmpty }
            XCTAssertTrue(host.windows.isEmpty)
            XCTAssertTrue(host.runtime.tree.root?.windows.isEmpty == true)
        }
    }

    func testRepeatedActivationKeepsTheExistingWelcomeWidget() throws {
        try onUIThread {
            let host = GTKRenderer.running(application: GTKActivationApplication())
            let welcome = try XCTUnwrap(host.windows.first)
            for _ in 0..<5 { GTKRenderer.activated(host.application); host.step() }
            XCTAssertEqual(host.windows.count, 1)
            XCTAssertTrue(host.windows.first === welcome)
            XCTAssertEqual(gtk_widget_get_mapped(welcome.widget), 1)
        }
    }
}

private struct GTKActivationApplication: App {
    var body: some Scene {
        Window("Welcome", id: "gtk.activation.welcome") { GTKActivationWelcome() }
        WindowGroup(WindowType("gtk.activation.editor")) { Window { GTKActivationEditor() } }
    }
}

private struct GTKActivationWelcome: View {
    @Environment private var scene: SceneSession

    var body: some View {
        let scene = self.scene
        return Button("Open editor").onClicked { try await scene.openWindow(WindowType("gtk.activation.editor")) }
    }
}

private struct GTKActivationEditor: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Editor: \(count)")
            Button("Change").onClicked { count += 1 }
        }
    }
}

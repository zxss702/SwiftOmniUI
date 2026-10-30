// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `@Bindable`: a view's handle on an `@Observable` model it was lent - the
// object to read, `$model.prop` the binding a control takes, and a write to a
// read property rebuilding the view that read it, through the scope the differ
// arms around every build.

import Observation
import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// A model of the kind an application ships: Swift's own `@Observable`.
@Observable
private final class Options {
    var sounds = true
    var volume = 0.5
    var note = ""
}

/// How many times a body was built.
private final class Tally {
    var builds = 0
}

/// A panel handed the model - SCE's shape: it shows one property and lends a
/// field another's binding.
private struct SettingsPanel: View {
    @Bindable var options: Options
    let tally: Tally

    var body: some View {
        tally.builds += 1
        _ = options.sounds
        return TextField($options.note)
    }
}

@MainActor final class BindableTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = Renderer.shared.renderHost(baseline: 0)
        XCTAssertFalse(Renderer.shared.needsRender)
    }

    /// `$model.prop` is a binding into the model: it reads the property, and a
    /// write through it lands where the model keeps it.
    func testADynamicMemberBindingReadsAndWritesTheProperty() {
        let options = Options()
        let bound = Bindable(wrappedValue: options)
        let note: Binding<String> = bound.note

        XCTAssertEqual(note.wrappedValue, "")
        note.wrappedValue = "Ada"
        XCTAssertEqual(options.note, "Ada")
    }

    /// `.animation` on a property binding keeps writing through it - what
    /// `Toggle(isOn: $options.sounds.animation(.snappy))` asks of it.
    func testAnAnimatedBindingStillWritesThrough() {
        let options = Options()
        let sounds: Binding<Bool> = Bindable(wrappedValue: options).sounds.animation(.snappy)

        sounds.wrappedValue = false

        XCTAssertFalse(options.sounds)
    }

    /// A field handed `$options.note` reads the property for its text as the
    /// node's props are packed - inside the building element's scope, the
    /// panel's: a write to `note` rebuilds the element that read it, which is
    /// the panel the field's node was built in.
    func testAPropertyBindingsReadRebuildsTheElementThatReadIt() {
        let options = Options()
        let panel = Tally()
        let renders = Renders()

        renders.render(stack([
            SettingsPanel(options: options, tally: panel).node,
        ], id: "root"))
        settled()
        XCTAssertEqual(panel.builds, 1)

        options.note = "for later"

        XCTAssertTrue(Renderer.shared.needsRender,
                      "the write reached the scope the field's build armed")
        _ = renders.revisit(changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(panel.builds, 2)
    }

    /// A property read in the panel's own body IS the panel's read: a write to
    /// `sounds` rebuilds it - and a second write after the rebuild is heard
    /// just the same, the scope armed again each build.
    func testAWriteToAReadPropertyRebuildsThePanelAndTheScopeReArms() {
        let options = Options()
        let panel = Tally()
        let renders = Renders()

        renders.render(stack([
            SettingsPanel(options: options, tally: panel).node,
        ], id: "root"))
        settled()

        options.sounds = false
        _ = renders.revisit(changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(panel.builds, 2)

        Renderer.shared.clearInvalidation()
        options.sounds = true

        XCTAssertTrue(Renderer.shared.needsRender,
                      "the scope the rebuild armed is live")
        _ = renders.revisit(changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(panel.builds, 3)
    }

    private func settled() {
        _ = Renderer.shared.renderHost(baseline: 0)
        XCTAssertFalse(Renderer.shared.needsRender)
    }
}

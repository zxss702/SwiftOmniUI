// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `PopoverContract` on a host: the card shows and goes as the state says, it carries what `content:` names, and a
/// dismissal the user makes writes the state false.
@_spi(Host) public enum PopoverTests: ConformanceFamily {
    public static let name = "Popover"

    public static var cases: [ConformanceCase] {
        [
            Aspects.holds(PopoverContract.arrowEdge, on: "Popover", .top, then: .bottom),
            ConformanceCase("aPopoverOpensAndClosesAsTheStateSays", proves: [
                Covered(PopoverContract.self), Covered(PopoverContract.isOpen),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let shown = State(wrappedValue: false)
                s.start {
                    VStack {
                        Text("Anchor")
                            .popover(isPresented: shown.projectedValue) { Text("card") }
                        Button("Show").onClicked { shown.wrappedValue = true }.id("show")
                        Button("Hide").onClicked { shown.wrappedValue = false }.id("hide")
                    }
                }
                let card = try s.element(ofType: .popover)

                s.expect(try s.held(PopoverContract.isOpen, on: card) ?? false, false, "closed at first")

                try s.perform(.activate, on: s.element("show"))
                try s.settle { try s.held(PopoverContract.isOpen, on: card) == true }
                s.expect(try s.held(PopoverContract.isOpen, on: card), true, "the state saying so shows it")

                try s.perform(.activate, on: s.element("hide"))
                try s.settle { try s.held(PopoverContract.isOpen, on: card) == false }
                s.expect(try s.held(PopoverContract.isOpen, on: card) ?? true, false, "and saying otherwise takes it")
            },
            ConformanceCase("aDismissalTheUserMakesWritesTheStateFalse", proves: [
                Covered(PopoverContract.dismissed), Covered(PopoverContract.isOpen),
            ]) { s in
                let shown = State(wrappedValue: true)
                s.start {
                    VStack {
                        Text("Anchor")
                            .popover(isPresented: shown.projectedValue) { Text("card") }
                    }
                }
                let card = try s.element(ofType: .popover)
                try s.settle { try s.held(PopoverContract.isOpen, on: card) == true }

                try s.perform(.close, on: card)
                s.settle { !shown.wrappedValue }

                s.expect(shown.wrappedValue, false, "the dismissal the user made reached the state")
                s.expect(try s.held(PopoverContract.isOpen, on: card) ?? true, false, "and the card is gone")
            },
        ]
    }
}

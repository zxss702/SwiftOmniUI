// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The binding modifiers' node-level half, so a modifier defined on `View` -
// which has no `Modified` of its own - can drive a property the same way an
// element's `-> Modified` helper does.
// Design: docs/design/views/bindings.md#the-image-never-the-value

extension Node {
    /// Carries a property from a state, written on the node itself: the image,
    /// never the value - nothing is read at build.
    mutating func drive<Value: StateValue>(
        _ property: Prop,
        on state: Binding<Value>,
        mode: StateMode,
        kind: StateKind
    ) {
        guard let image = state.image else {
            return
        }

        state.described?.wearThemedPair()

        driven[property] = StateRegistration(
            state: image,
            conversion: state.conversion,
            mode: mode,
            kind: kind,
            values: property.facts.moves.union(Value.moving),
            current: { state.wrappedValue.carried })
    }

    /// The same for a value the host can animate: `.property` carries it as a
    /// journey, any other kind as itself.
    mutating func drive<Value: Walked>(
        _ property: Prop,
        on state: Binding<Value>,
        mode: StateMode,
        kind: StateKind
    ) {
        guard kind == .property else {
            guard let image = state.image else {
                return
            }

            state.described?.wearThemedPair()

            drive(property, onImage: image, mode: mode, kind: kind,
                  moving: Value.moving, conversion: state.conversion)
            return
        }

        guard let image = state.journeyImage else {
            return
        }

        state.described?.wearThemedPair()

        drive(property, onImage: image, mode: mode, kind: kind,
              moving: JourneyLanes<Value>.moving, conversion: state.conversion)
    }

    /// The same registration over an image already made.
    mutating func drive(
        _ property: Prop,
        onImage image: HostStorage,
        mode: StateMode,
        kind: StateKind,
        moving: AnimationValues,
        conversion: Conversion? = nil
    ) {
        driven[property] = StateRegistration(
            state: image,
            conversion: conversion,
            mode: mode,
            kind: kind,
            values: property.facts.moves.union(moving))
    }

    /// A property the host animates from a state.
    mutating func driveJourney<Value: Walked>(_ property: Prop, by state: Binding<Value>) {
        guard let image = state.journeyImage else {
            return
        }

        state.described?.wearThemedPair()

        drive(property, onImage: image, mode: .inOut, kind: .property,
              moving: JourneyLanes<Value>.moving, conversion: state.conversion)
    }

    /// `driveJourney(_:by:)` over a member of the type its contract declares.
    mutating func driveJourney<Owner: Contract, Value: Walked & HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        by state: Binding<Value>
    ) {
        driveJourney(property.token, by: state)
    }

    /// A property the host sets as the state's value stands, with no
    /// animation; `.inOut` where the control reports it back.
    mutating func drivePlain<Value: StateValue>(_ property: Prop, by state: Binding<Value>, mode: StateMode = .out) {
        drive(property, on: state, mode: mode, kind: .plain)
    }

    /// `drivePlain(_:by:mode:)` over a member of the type its contract declares.
    mutating func drivePlain<Owner: Contract, Value: StateValue & HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        by state: Binding<Value>,
        mode: StateMode = .out
    ) {
        drivePlain(property.token, by: state, mode: mode)
    }

    /// Text the host writes into a property as the state changes.
    mutating func driveWords(_ property: Prop, by state: Binding<String>, mode: StateMode = .out) {
        drive(property, on: state, mode: mode, kind: .text)
    }

    /// `driveWords(_:by:mode:)` over a text member.
    mutating func driveWords<Owner: Contract>(
        _ property: ElementProperty<Owner, String>,
        by state: Binding<String>,
        mode: StateMode = .out
    ) {
        driveWords(property.token, by: state, mode: mode)
    }

    /// Writes the number of a carried state onto a property - how a drag is
    /// told where to report (`panX`, `panY`).
    mutating func driveNumber<Value: StateValue>(_ property: Prop, by state: Binding<Value>) {
        guard let image = state.image else {
            return
        }

        props[property] = .number(Double(Renderer.shared.number(for: image)))
    }
}

extension Node {
    /// The described two-way form, for a binding the host cannot carry - a part
    /// of a state, or one made from closures: the value read at build, and each
    /// report written back through the binding.
    /// Design: docs/design/views/bindings.md#two-way-controls
    mutating func describePlain(_ property: Prop, _ value: Binding<Bool>, on event: Event) {
        props[property] = .bool(value.wrappedValue)
        addHandler(event) {
            if let moved = EventBuffer.current.value()?.bool {
                value.wrappedValue = moved
            }
        }
    }

    /// The same, for a whole number - a choice.
    mutating func describePlain(_ property: Prop, _ value: Binding<Int>, on event: Event) {
        props[property] = .number(Double(value.wrappedValue))
        addHandler(event) {
            if let moved = EventBuffer.current.value()?.int {
                value.wrappedValue = moved
            }
        }
    }

    /// The same, for text - what a field typed into reports.
    mutating func describePlain(_ property: Prop, _ value: Binding<String>, on event: Event) {
        props[property] = .string(value.wrappedValue)
        addHandler(event) {
            if let typed = EventBuffer.current.value()?.string {
                value.wrappedValue = typed
            }
        }
    }

    /// The same, for a day - what a date picker reports.
    mutating func describePlain(_ property: Prop, _ value: Binding<CalendarDate>, on event: Event) {
        props[property] = value.wrappedValue.propValue
        addHandler(event) {
            if let chosen = CalendarDate(EventBuffer.current.value()) {
                value.wrappedValue = chosen
            }
        }
    }

    /// The same, for a time of day - what a time picker reports.
    mutating func describePlain(_ property: Prop, _ value: Binding<ClockTime>, on event: Event) {
        props[property] = value.wrappedValue.propValue
        addHandler(event) {
            if let chosen = ClockTime(EventBuffer.current.value()) {
                value.wrappedValue = chosen
            }
        }
    }
}

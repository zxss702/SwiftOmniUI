// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `@Bindable` lends an `@Observable` model's properties as bindings: `$model.prop`
// is a `Binding` the body hands a control. A body that reads a property is built
// again when the property is written - the observation scope the differ arms
// around every build.
// Design: docs/design/core/state.md#an-observable-model

import Observation

/// A view's handle on an `@Observable` model it was handed: the object itself to
/// read, and `$name.property` bindings to lend an input.
///
///     struct Settings: View {
///         @Bindable var options: Options
///
///         var body: some View {
///             Toggle("Sounds", isOn: $options.sounds)
///         }
///     }
///
/// The object is lent whole - a parent's, a `@State`'s, or the environment's
/// (`@Bindable var model = model` names a local one inside a body). A body that
/// reads one of its properties is built again when that property is written.
@propertyWrapper
@dynamicMemberLookup
public struct Bindable<Value: Observable> {
    /// The model.
    public var wrappedValue: Value

    /// Wraps the model the view was handed. `@Bindable var model` among a view's
    /// properties takes it in the view's initializer.
    /// - Parameter wrappedValue: the model this wraps.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// What `$model` is: this wrapper, whose `.property` reads a binding into
    /// the model.
    public var projectedValue: Bindable<Value> { self }

    /// A binding to one property of the model - `$model.prop`.
    public subscript<T>(
        dynamicMember keyPath: ReferenceWritableKeyPath<Value, T>
    ) -> Binding<T> {
        Binding(
            get: { wrappedValue[keyPath: keyPath] },
            set: { wrappedValue[keyPath: keyPath] = $0 })
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Slider`'s own properties, shared by the control and its `Style<Slider>`.
public protocol SliderProperties: PropertyContainer {}

extension SliderProperties {
    /// Where the thumb stands, between `minimum` and `maximum`. Usually given
    /// in the initializer.
    public func value(_ value: Double) -> Modified {
        setValue(SliderContract.value, value)
    }

    /// The value at the near end of the track, 0 until told otherwise.
    @_spi(Host) public func minimum(_ value: Double) -> Modified {
        setValue(SliderContract.minimum, value)
    }

    /// The value at the far end of the track, 1 until told otherwise - so a
    /// slider meant to run to 100 must say so.
    @_spi(Host) public func maximum(_ value: Double) -> Modified {
        setValue(SliderContract.maximum, value)
    }
}

/// A value picked by dragging a thumb along a native track.
///
///     Slider($volume)
///         .minimum(0)
///         .maximum(100)
///
/// Given a binding it shows the value and writes every drag back. Given a
/// number it shows that, and `.onValueChanged` is how the drag gets anywhere.
///
/// The range is 0 to 1 until `.minimum` and `.maximum` say otherwise.
public struct Slider: VisualElement, TintElement, SliderProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<Slider>` is written against.
    public init() {
        node = Node(contract: SliderContract.self)
    }

    /// A slider sitting at `value`. One-way: the drag goes nowhere without
    /// `.onValueChanged`.
    public init(_ value: Double) {
        node = Node(contract: SliderContract.self)
        node.write(SliderContract.value, value)
    }

    /// Two-way: shows what the state holds and writes back what the user drags,
    /// with no view rebuilt for it.
    ///
    ///     @State private var volume = 0.0
    ///
    ///     Slider($volume)
    ///
    /// An assignment (`volume = 1`) animates the thumb there under the
    /// element's animation; `$volume.journey` reads where the thumb is, and
    /// `try await $volume.journey.move(to: 1)` waits for the arrival.
    public init(_ value: Binding<Double>) {
        self = Slider().value(value)
    }

    /// A two-way slider over `bounds` - SwiftUI's `Slider(value:in:)` spelled
    /// with the binding alone, the range told once in the initializer.
    ///
    ///     Slider($gain, in: -20...60)
    public init(_ value: Binding<Double>, in bounds: ClosedRange<Double>) {
        self = Slider(value).minimum(bounds.lowerBound).maximum(bounds.upperBound)
    }

    /// A one-way slider over `bounds`, reporting through `.onValueChanged`.
    public init(_ value: Double, in bounds: ClosedRange<Double>) {
        self = Slider(value).minimum(bounds.lowerBound).maximum(bounds.upperBound)
    }

    /// SwiftUI's `Slider(value:in:onEditingChanged:)`: `editing` is `true` as
    /// the thumb is grabbed, `false` as it is let go.
    public init(
        _ value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self = Slider(value, in: bounds)
            .onDragStarted { onEditingChanged(true) }
            .onDragCompleted { onEditingChanged(false) }
    }

    // Design: docs/design/views/bindings.md#a-finger-takes-a-moving-thumb
    /// The same two-way value as `Slider($value)`, written as a modifier.
    ///
    ///     Slider($volume)
    ///     Slider().value($volume)
    ///
    /// A finger that takes a moving thumb stops its animation where the user
    /// holds it, and an awaiting move resumes with `false`.
    ///
    /// - Parameter value: the state the thumb shows and writes back into,
    ///   carried by the host as a journey.
    /// - Returns: the control, wearing and reporting that value.
    public func value(_ value: Binding<Double>) -> Modified {
        journey(SliderContract.value.token, by: value)
    }

    // MARK: Events

    /// Fires on every step of a drag, with the value dragged to, after a
    /// binding's write. Heavy work belongs in `.onDragCompleted`.
    @_spi(Host) public func onValueChanged(_ handler: @escaping ValueEventHandler<Double>) -> Self {
        onEvent(SliderContract.valueChanged, handler)
    }

    /// Runs when the thumb is grabbed - the start of a drag whose every step
    /// is an `onValueChanged`.
    @_spi(Host) public func onDragStarted(_ handler: @escaping EventHandler) -> Self {
        onEvent(SliderContract.dragStarted, handler)
    }

    /// Runs when the thumb is let go - where work too heavy for every step of
    /// the drag belongs.
    @_spi(Host) public func onDragCompleted(_ handler: @escaping EventHandler) -> Self {
        onEvent(SliderContract.dragCompleted, handler)
    }
}

extension Slider {
    /// `maximum` from a state, `$x`: the host sets each new value as it stands,
    /// and no view is rebuilt for it.
    @_spi(Host) public func maximum(_ state: Binding<Double>) -> Modified {
        plain(SliderContract.maximum.token, by: state)
    }

    /// `minimum` from a state, `$x`: the host sets each new value as it stands,
    /// and no view is rebuilt for it.
    @_spi(Host) public func minimum(_ state: Binding<Double>) -> Modified {
        plain(SliderContract.minimum.token, by: state)
    }
}

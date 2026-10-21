// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Effects on the whole element: a matched frame continuing across a move, a
// symbol's short animation, how drawn content swaps. Each writes what the
// element carries; the host plays what it can of it.
// Design: docs/design/types/animation.md#matched-geometry
// Design: docs/design/types/animation.md#symbol-effects

extension VisualElement {
    /// The identity the element's frame continues under: when this element
    /// leaves and one carrying the same `id` in the same namespace arrives
    /// elsewhere in the tree, the new element's frame animates from where the
    /// old one stood - the capsule that flies to the newly selected tab:
    ///
    ///     @Namespace private var selection
    ///
    ///     Button("One") {}
    ///         .background { selected ? Capsule()
    ///             .matchedGeometryEffect(id: "pill", in: selection) : nil }
    ///     Button("Two") {}
    ///         .background { !selected ? Capsule()
    ///             .matchedGeometryEffect(id: "pill", in: selection) : nil }
    ///
    /// - Parameters:
    ///   - id: the identity, inside `namespace`.
    ///   - namespace: the space the id means something in.
    ///   - properties: which parts of the geometry travel; `.frame` is the
    ///     default and the only part the host layer moves today.
    ///   - anchor: where geometry anchors while the two frames differ in size.
    ///   - isSource: whether this element offers its frame to a match. An
    ///     element written `isSource: false` only arrives at a match, never
    ///     provides the place one flies from.
    public func matchedGeometryEffect(
        id: some Hashable,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> ModifiedContent {
        revised {
            $0.write(VisualElementContract.matchedGeometry, "ns\(namespace.serial):\(id)")
            if !isSource {
                $0.write(VisualElementContract.matchedGeometrySource, false)
            }
        }
    }

    /// A symbol effect that plays once as the element arrives:
    ///
    ///     Image("check.png")
    ///         .symbolEffect(.bounce)
    public func symbolEffect(
        _ effect: some SymbolEffect,
        options: SymbolEffectOptions = .default
    ) -> ModifiedContent {
        revised {
            $0.write(VisualElementContract.symbolEffect, effect.symbolEffectToken)
            $0.write(VisualElementContract.symbolEffectOptions, options.rawValue == 0 ? 0 : Int(options.rawValue))
            $0.write(VisualElementContract.symbolEffectActive, true)
        }
    }

    /// A symbol effect triggered whenever `value` changes - a bounce when the
    /// task succeeds:
    ///
    ///     Image("check.png")
    ///         .symbolEffect(.bounce, value: done)
    public func symbolEffect(
        _ effect: some SymbolEffect,
        options: SymbolEffectOptions = .default,
        value: some Equatable
    ) -> ModifiedContent {
        revised {
            $0.write(VisualElementContract.symbolEffect, effect.symbolEffectToken)
            $0.write(VisualElementContract.symbolEffectOptions, options.rawValue == 0 ? 0 : Int(options.rawValue))
            $0.write(VisualElementContract.symbolEffectValue, String(describing: value))
        }
    }

    /// A continuous symbol effect while `isActive` holds - a pulse while the
    /// install runs:
    ///
    ///     Image("gear.png")
    ///         .symbolEffect(.pulse, options: .repeating, isActive: installing)
    public func symbolEffect(
        _ effect: some SymbolEffect,
        options: SymbolEffectOptions = .default,
        isActive: Bool
    ) -> ModifiedContent {
        revised {
            $0.write(VisualElementContract.symbolEffect, effect.symbolEffectToken)
            $0.write(VisualElementContract.symbolEffectOptions, options.rawValue == 0 ? 0 : Int(options.rawValue))
            $0.write(VisualElementContract.symbolEffectActive, isActive)
        }
    }

    /// How the element's content swaps when it changes - a rolling number, a
    /// fade, a symbol's own replace:
    ///
    ///     Text("\(count)")
    ///         .contentTransition(.numericText())
    ///
    /// The host plays the closest swap it has: a roll where it can roll, a
    /// fade elsewhere.
    public func contentTransition(_ transition: ContentTransition) -> ModifiedContent {
        setting(VisualElementContract.contentTransition, transition.token)
    }
}

extension VisualElement {
    /// How the element's drawing composites with what stands under it:
    ///
    ///     Rectangle().fill(.red)
    ///         .blendMode(.multiply)
    ///
    /// `normal` draws plainly; the rest blend by the mode the platform names.
    public func blendMode(_ mode: BlendMode) -> ModifiedContent {
        setting(VisualElementContract.blendMode, mode)
    }
}

extension View {
    /// How this view's content swaps, including after a modifier has erased
    /// the concrete `VisualElement` type. Uses the same host property as the
    /// element-level modifier.
    @_disfavoredOverload
    public func contentTransition(_ transition: ContentTransition) -> ModifiedContent {
        setting(VisualElementContract.contentTransition, transition.token)
    }

    /// The matched-geometry identity of this view's rendered element - the
    /// view-level spelling for calls on a chain already standing as `some
    /// View`:
    ///
    ///     content
    ///         .matchedGeometryEffect(id: "pill", in: selection)
    ///
    /// - Parameters:
    ///   - id: the identity, inside `namespace`.
    ///   - namespace: the space the id means something in.
    ///   - properties: which parts of the geometry travel; `.frame` is the
    ///     default and the only part the host layer moves today.
    ///   - anchor: where geometry anchors while the two frames differ in size.
    ///   - isSource: whether the element offers its frame to a match.
    public func matchedGeometryEffect(
        id: some Hashable,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> ModifiedContent {
        revised {
            $0.write(VisualElementContract.matchedGeometry, "ns\(namespace.serial):\(id)")
            if !isSource {
                $0.write(VisualElementContract.matchedGeometrySource, false)
            }
        }
    }

    /// Flattens the view's content into a single drawing before effects
    /// apply - an opacity written on a compositing group moves the whole
    /// drawing together rather than each part alone:
    ///
    ///     label.compositingGroup().opacity(0.5)
    public func compositingGroup() -> ModifiedContent {
        setting(VisualElementContract.compositingGroup, true)
    }

    /// Draws the view offscreen first, the rendered bitmap then drawn where
    /// the view stands - the platform's own rasterizer standing in for the
    /// GPU path SwiftUI takes:
    ///
    ///     graph.drawingGroup()
    public func drawingGroup() -> ModifiedContent {
        setting(VisualElementContract.drawingGroup, true)
    }
}

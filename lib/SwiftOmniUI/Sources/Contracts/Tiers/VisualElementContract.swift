// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What every drawn element has: its size and its bounds, how it is shown and
/// turned, whether it answers input and holds the keyboard focus, the visual
/// states it enters, and what a screen reader says about it.
public enum VisualElementContract: Contract {
    /// The tier's name.
    public static let name = "VisualElement"

    /// Every drawn element carries values in the tree.
    public static let tiers: [any Contract.Type] = [PropertyContainerContract.self]

    /// How the element's children take part in accessibility.
    public static let accessibilityChildBehavior = ElementProperty<Self, AccessibilityChildBehavior>(
        "accessibilityChildBehavior", layer: .native)

    /// How deep a heading the element is, for a user moving by headings.
    public static let accessibilityHeadingLevel = ElementProperty<Self, HeadingLevel>(
        "accessibilityHeadingLevel", layer: .native)

    /// What happens when the element is used, said after its label.
    public static let accessibilityHint = ElementProperty<Self, String>(
        "accessibilityHint", layer: .native)

    /// What a screen reader says the element is.
    public static let accessibilityLabel = ElementProperty<Self, String>(
        "accessibilityLabel", layer: .native)

    /// What a screen reader says the element is and does - its button-ness,
    /// chosen-ness and the rest, as a bit set.
    public static let accessibilityTraits = ElementProperty<Self, AccessibilityTraits>(
        "accessibilityTraits", layer: .native)

    /// Whether the element and everything in it are left out of what a screen
    /// reader reads.
    public static let automationExcludedWithChildren = ElementProperty<Self, Bool>(
        "automationExcludedWithChildren", layer: .native)

    /// What is drawn behind the element: a colour, or a brush.
    public static let background = ElementProperty<Self, Background>(
        "background", layer: .native)

    /// Gives the element the keyboard focus, answering whether it took it.
    public static let focus = ElementAct<Self, Void, Bool>("focus")

    /// The frame the element settled on, fed by the host into a state.
    public static let frame = ElementProperty<Self, Rect>("frame", layer: .structure)

    /// The height the element asks for.
    public static let height = ElementProperty<Self, Double>(
        "height", layer: .native, moves: .height)

    /// The tip shown under the pointer resting on the element - a `.help`
    /// text.
    public static let hint = ElementProperty<Self, String>("hint", layer: .native)

    /// The tip as a lookup key, as `TextElementContract.textKey` is for the
    /// elements that wear it.
    public static let hintKey = ElementProperty<Self, LocalizedStringKey>(
        "hintKey", layer: .native, travels: false)

    /// Whether input passes through the element to what is under it.
    public static let ignoresInput = ElementProperty<Self, Bool>("ignoresInput", layer: .native)

    /// Whether a screen reader skips the element.
    public static let isAccessibilityHidden = ElementProperty<Self, Bool>(
        "isAccessibilityHidden", layer: .native)

    /// Whether the element answers input.
    public static let isEnabled = ElementProperty<Self, Bool>("isEnabled", layer: .native)

    /// The platform moved the focus onto the element, or off it.
    public static let isFocusedChanged = ElementEvent<Self, Bool>(
        "isFocusedChanged", layer: .native)

    /// Whether the element is shown.
    public static let isVisible = ElementProperty<Self, Bool>("isVisible", layer: .native)

    /// Which way the element lays its content out.
    public static let layoutDirection = ElementProperty<Self, LayoutDirection>(
        "layoutDirection", layer: .native)

    /// The most height the element takes.
    public static let maximumHeight = ElementProperty<Self, Double>(
        "maximumHeight", layer: .native, moves: .height)

    /// The most width the element takes.
    public static let maximumWidth = ElementProperty<Self, Double>(
        "maximumWidth", layer: .native, moves: .width)

    /// The least height the element takes.
    public static let minimumHeight = ElementProperty<Self, Double>(
        "minimumHeight", layer: .native, moves: .height)

    /// The least width the element takes.
    public static let minimumWidth = ElementProperty<Self, Double>(
        "minimumWidth", layer: .native, moves: .width)

    /// How opaque the element is, from 0 to 1.
    public static let opacity = ElementProperty<Self, Double>(
        "opacity", layer: .native, moves: .opacity)

    /// Where across the element it turns and scales about, as a fraction.
    public static let pivotX = ElementProperty<Self, Double>(
        "pivotX", layer: .native, moves: .transform)

    /// Where down the element it turns and scales about, as a fraction.
    public static let pivotY = ElementProperty<Self, Double>(
        "pivotY", layer: .native, moves: .transform)

    /// How far the element is turned in the screen's plane, in degrees.
    public static let rotation = ElementProperty<Self, Angle>(
        "rotation", layer: .native, moves: .transform)

    /// How far the element is tipped about its horizontal axis, in degrees.
    public static let rotationX = ElementProperty<Self, Angle>(
        "rotationX", layer: .native, moves: .transform)

    /// How far the element is turned about its vertical axis, in degrees.
    public static let rotationY = ElementProperty<Self, Angle>(
        "rotationY", layer: .native, moves: .transform)

    /// How much the element is scaled, both ways.
    public static let scale = ElementProperty<Self, Double>(
        "scale", layer: .native, moves: .transform)

    /// How much the element is scaled across.
    public static let scaleX = ElementProperty<Self, Double>(
        "scaleX", layer: .native, moves: .transform)

    /// How much the element is scaled down.
    public static let scaleY = ElementProperty<Self, Double>(
        "scaleY", layer: .native, moves: .transform)

    /// The keyed style the element wears, by its key.
    public static let style = ElementProperty<Self, Name>("style", layer: .structure)

    /// How far the element is moved across from where its layout put it.
    public static let translationX = ElementProperty<Self, Double>(
        "translationX", layer: .native, moves: .place)

    /// How far the element is moved down from where its layout put it.
    public static let translationY = ElementProperty<Self, Double>(
        "translationY", layer: .native, moves: .place)

    /// Takes the keyboard focus off the element.
    public static let unfocus = ElementAct<Self, Void, Void>("unfocus")

    /// The width the element asks for.
    public static let width = ElementProperty<Self, Double>(
        "width", layer: .native, moves: .width)

    /// Which of its overlapping siblings in a grid or an absolute layout the element is drawn over.
    public static let zIndex = ElementProperty<Self, Double>("zIndex", layer: .native, travels: false)

    /// The blur the element is drawn with, in device units - 0 for none.
    public static let blur = ElementProperty<Self, Double>(
        "blur", layer: .native, moves: .opacity)

    /// How the element's drawing composites with what stands under it;
    /// `.blendMode` writes it.
    public static let blendMode = ElementProperty<Self, BlendMode>("blendMode", layer: .native)

    /// Whether the element's content is flattened into a single drawing
    /// before effects apply - `.compositingGroup` writes it.
    public static let compositingGroup = ElementProperty<Self, Bool>(
        "compositingGroup", layer: .native)

    /// Whether the element draws offscreen first - `.drawingGroup` writes
    /// it, the platform's own rasterizer standing in for a GPU where there
    /// is none.
    public static let drawingGroup = ElementProperty<Self, Bool>(
        "drawingGroup", layer: .native)

    /// How the element looks as it is inserted and as it is removed.
    public static let transition = ElementProperty<Self, AnyTransition>(
        "transition", layer: .native)

    /// The shadow the element drops, nil for none.
    public static let shadow = ElementProperty<Self, DropShadow>(
        "shadow", layer: .native)

    /// How the element swaps its drawn content - the kind `.contentTransition`
    /// names, as a word the host plays the closest swap it has for.
    public static let contentTransition = ElementProperty<Self, String>(
        "contentTransition", layer: .native)

    /// The matched-geometry identity `namespace:id` - an element with the same
    /// identity arriving where one left continues its frame across the change.
    public static let matchedGeometry = ElementProperty<Self, String>(
        "matchedGeometry", layer: .native)

    /// Whether a matched-geometry element provides its frame for others; an
    /// element written `isSource: false` takes part only as a destination.
    public static let matchedGeometrySource = ElementProperty<Self, Bool>(
        "matchedGeometrySource", layer: .native, cleared: false)

    /// The symbol effect the element plays, as a word - `"bounce"`, `"pulse"`
    /// and the like.
    public static let symbolEffect = ElementProperty<Self, String>(
        "symbolEffect", layer: .native)

    /// The effect's options as bits: 1 keeps it repeating.
    public static let symbolEffectOptions = ElementProperty<Self, Int>(
        "symbolEffectOptions", layer: .native)

    /// Whether a continuous effect is on.
    public static let symbolEffectActive = ElementProperty<Self, Bool>(
        "symbolEffectActive", layer: .native, cleared: false)

    /// The value a triggered effect fired on, as text - a change replays it.
    public static let symbolEffectValue = ElementProperty<Self, String>(
        "symbolEffectValue", layer: .native, cleared: false)

    /// The tier's own members.
    public static let members: [any ContractMember] = [
        blendMode,
        accessibilityChildBehavior, accessibilityHeadingLevel, accessibilityHint, accessibilityLabel,
        accessibilityTraits, automationExcludedWithChildren, background, blur, contentTransition,
        compositingGroup, drawingGroup, focus, frame, height, hint, hintKey,
        ignoresInput,
        isAccessibilityHidden, isEnabled, isFocusedChanged, isVisible, layoutDirection,
        matchedGeometry, matchedGeometrySource, maximumHeight, maximumWidth, minimumHeight,
        minimumWidth, opacity, pivotX, pivotY,
        rotation, rotationX, rotationY, scale, scaleX, scaleY, shadow, style, symbolEffect,
        symbolEffectActive, symbolEffectOptions, symbolEffectValue, transition, translationX,
        translationY, unfocus, width, zIndex,
    ]
}

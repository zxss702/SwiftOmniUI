# Animation and journeys

SwiftOmniUI describes a destination once. A native host that implements the
corresponding animation surface advances the visible value on its display clock,
while the Swift tree continues to say where the value is going. Animation
therefore does not create another state system or a frame-by-frame description
tree.

This chapter defines the semantic animation contract, not blanket platform
availability. An unverified host or unsupported `(NodeType, Prop)` pair must
still apply the final destination, normally by snapping. Only checked rows in
[Platform contract](../platform-contract.md) authorize reliance on the journey.

## Animation laws

`Animation` has two destination-seeking laws:

- `.eased(length, curve)` takes the stated number of milliseconds and lands on
  the destination exactly;
- `.spring(response:damping:)` keeps standing velocity when retargeted and
  settles on the destination rather than at an unrelated resting point.

Three special values select ownership:

- `.inherited` resolves through the value or element, then the application
  default, which starts at `.none`;
- `.none` snaps to the destination;
- `.custom` leaves the walk to a SwiftOmniUI engine attached to the state.

`Animation.standard` is a 200-millisecond cubic-out movement chosen by
`withAnimation()` or an explicit application setting. Reduced-animation input
may shorten or remove an animation, but never changes its destination.

## Described property animation

A property that depends on ordinary state rebuilds its reader once and places
the final value in `HostPatch`. A matching `HostTransition` tells the host how
to reach it:

```swift internals
struct MovingPanel: View {
    @State private var expanded = false

    var body: some View {
        VStack {
            ColorPicker(.cornflowerBlue)
                .frame(width: expanded ? 280 : 120)
                .cornerRadius(expanded ? 28 : 8)
                .animation(.spring(response: 280))

            Button("Resize").onClicked { expanded.toggle() }
        }
    }
}
```

The host interpolates only a semantic `(NodeType, Prop)` pair it implements and
only between compatible value shapes. Unknown pairs, discrete properties, a
first value with no representable native starting point, and incompatible
compound values snap to their destination. The platform matrix records which
animation surfaces have native tests.

### Selection precedence

For an ordinary described property, SwiftOmniUI chooses its law in this order:

1. the last `.animation(animation, values)` rule on that element whose group matches;
2. the element's `.animation(animation)` base rule;
3. `ApplicationSession.animation`;
4. `.none` when the application has not chosen an animation.

A later selective rule wins over an earlier matching rule. An element's rule
applies to that element, not recursively to its descendants. A composed view
may supply a default animation plan, and modifiers written where it is used are
merged over that plan.

`AnimationValues` groups semantic changes rather than platform properties:

| Group | Meaning |
| --- | --- |
| `.opacity` | opacity |
| `.colour` | every color-valued property |
| `.width` | requested, minimum, maximum, or host-reported width |
| `.height` | requested, minimum, maximum, or host-reported height |
| `.size` | width and height plus outline and corner sizes |
| `.place` | host-arranged position and translation |
| `.transform` | scale, rotation, and anchors |
| `.spacing` | padding, padding, stack spacing, and grid spacing |
| `.text` | font size, line height, and character spacing |
| `.all` | every property, including one with no narrower group |

This lets size snap while placement travels:

```swift quote
VStack { content }
    .animation(.spring(response: 240))
    .animation(.none, .size)
```

Properties that represent an identity, index, count, selection boundary,
range, region, or layout rule are discrete even when encoded as numbers. They
do not acquire an in-between meaning merely because an interpolator could
process their bytes.

## Journey is part of state

Every `@State` whose value conforms to `Walked` has a journey. The state itself
remains discrete: reading it returns the destination immediately. Its journey
exposes what the host is showing between writes:

| Member | Meaning |
| --- | --- |
| `value` | visible value on the current host frame |
| `destination` | the state's ordinary value |
| `velocity` | per-second velocity, lane by lane |
| `animation` | law owned by this value wherever it is attached |
| `move(to:_:)` | set a destination and await its outcome |
| `stop()` | stop at the standing value |
| `snap(to:)` | set standing value, destination, and zero velocity together |
| `convert` | derive another host-driven value from live journey lanes |

The built-in `Walked` values are `Double`, `Point`, `Rect`, `EdgeInsets`, and
`Color`. Each has a fixed set of numeric lanes. A part binding and a binding
made from get/set closures do not own the complete storage image a host needs
to walk; move the complete state instead.

An awaited move returns its outcome:

```swift quote
let arrived = try await $opacity.journey.move(
    to: 0.2,
    .eased(400, .cubicOut))

if !arrived {
    // A newer destination, another write, or stop() ended this animation.
}
```

`true` means the value reached that move's destination. `false` means a newer
destination, another write to the state, or `stop()` superseded it. An
animation that has nothing to cover completes with `true` immediately. A
custom-engine state also answers immediately because the engine, rather than
the host's animator, owns its completion.

The destination write happens before the handler first suspends. An unrelated
body rebuild does not restart or cancel a journey: the animation channel belongs
to the state storage and continues from its standing value and velocity. A
later animation passed to `move` is retained as that value's law, so subsequent
plain writes use it until `journey.animation` changes again.

For a host-carried state, animation selection is:

1. an explicit law supplied to `move(to:_:)`;
2. the state's law from `@State(animation:)` or `journey.animation`;
3. the attached element's resolved law when the state says `.inherited`;
4. the application law, which starts at `.none`.

One state is one host animation channel. Every control and driven property attached
to it observes the same standing value, destination, velocity, and completion.
Use separate states for independent animations.

## Stop, snap, and direct lane writes

`stop()` keeps the standing value and makes an active waiter return `false`.
`snap(to:)` synchronously makes the standing value and destination equal and
zeros velocity. It is the right operation for a measurement or report that was
observed rather than chosen as a destination.

Writing `journey.value` alone changes only the standing value. Writing
`journey.velocity` kicks the existing journey. These operations are primarily
for custom engines; an ordinary application decision writes the state or calls
`move(to:_:)`.

## Visibility and layout animation

`isVisible` is a semantic visibility transition for a host that implements its
animation contract. On a continuing element, hiding retains the element while it
leaves, removes it from hit testing during that animation, and hides it after
the animation lands. Showing starts from the hidden presentation and enters. The
first description has no before-state to cross, and `.animation(.none)` makes
visibility an immediate flag.

Child placement is not an ordinary authored property. A layout emits one
`HostLayoutMotion` containing a law and `AnimationLanes`; the host moves the
existing native child rectangle from its standing placement to the newly
arranged rectangle. `.place`, `.width`, and `.height` rules decide which lanes
travel. The Swift tree still sends only the final arrangement.

Why a layout arranges decides whether its children travel. An arrangement a
patch caused means the layout holds something different - a row inserted, a
card grown - so its children travel, under the layout's own animation or, where it
says nothing, the application's. A room that moves with no patch behind it - a
window resized, a sidebar dragged - is followed exactly, and so is a layout
whose own width changed: a child gliding after the user's hand is late on
every frame. A layout's first arrangement arrives. A size a child states for
itself arrives while its place still travels. Where a frame under the layout is
read - an `onFrameChanged` handler, a driven frame - every child arrives,
because each step of a walk would report a room nobody chose. A child that
joins a layout already standing fades in under the same law, unless a state
owns its opacity.

Visibility animation and layout animation are part of the cross-platform contract,
but an application relies on them only where [Platform contract](../platform-contract.md)
shows verified host support.

## Custom engines

`@State(animation: .custom)` fixes who animates the state when it is first
registered. An engine reads destination, standing value, velocity, and frame
timing, writes the next standing lanes, and returns `.again` while it needs
another frame or `.wait` until a followed state changes. An engine's own write
does not wake it.

See [State and reactivity](state-and-reactivity.md) for conversions, sampling,
and engine composition, and [Host contract](../internals/host-contract.md) for the native
display-cycle obligations.

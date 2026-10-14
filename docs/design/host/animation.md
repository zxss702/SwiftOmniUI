# Animation in the runtime

How a runtime animates: one animator advances every animation, one channel per
bound state feeds every control tied to it, and the animations a patch
describes are keyed by element and property. The timing laws are the core's,
`HostMotionLaw`; [the runtime](runtime.md) draws where these elements sit in a
frame.

## One animator

A value is animated by `Animator` alone. Every running animation is an
`Animation`: where each lane began, where it is going, its starting speed, its
timing and when it began. An animation is pure: its position is
`HostMotionLaw` at the time handed in, so a hand-wound clock reproduces every
frame. One advance moves every animation in `AnimationTarget` order - states
by number, then described properties by element and property, then layout
places by element - so two runs of the same frame write in the same order. An
animation that arrives leaves the animator, and with Reduce Animation every
animation arrives at once, at its destination.

## State channels

A host-carried `@State` has one channel, whatever number of controls are bound
to it. No control keeps its own copy of the animated value, so every bound
control stands at the same value and turns toward a new destination with the
same speed on the same frame. A control that joins mid-animation joins at the
value where the channel stands.

The channel is not a control's to end. It counts the controls wearing it; when
the last one lets go it goes too, but only once its animation has landed where
it was sent, so a control described again a moment later joins it where it
is. When the user takes the value on a two-way control, the animation stops
where the user holds it and its waiter hears that it was cut short.

## Described animation

A patch can describe how a property of an element moves to its new value.
`HostPatch.properties` stays the committed value; `DescribedMotion` owns only
the value drawn on the current frame, keyed by element and property. A new
animation of a property starts from where the running one stands, with its
speed.

A combined removal waits for every component, whose spring lanes can reach
rest on different frames. A component that finishes first retains its target
in `DescribedMotion` until the whole element leaves. It cannot fall back to
the authored value while another component still removes the view: opacity
zero must stay zero, rather than briefly making the old branch visible again.
Reviving or retargeting the component starts from its retained presentation
and releases that target; leaving clears all retained targets for the mount.
These settled targets hold no frame clock and do not affect ordinary property
animations.

The display cycle presents a component's final value before running its landing
callback. A removal therefore cannot erase its last output while the native view
is still attached. The parent drops that view while its departing status and
retained drawing still stand, then the element clears its motions and listeners.
The cycle also commits the resulting child-list and native-bar changes in the
same frame, even when no other property or state animation remains.

An insertion's supported drawing components are committed immediately when its
layout starts the transition. A snapshot between allocation and the next clock
tick sees the insertion phase, rather than briefly drawing the authored identity
before returning to the animation's start. This write changes drawing only;
it does not rebind children or rebuild the core tree.

A value moves as numeric lanes and only within one shape: a number, a list of
numbers of one length, a colour, or a structure whose kind and parts stay the
same - a gradient moves its geometry, stops and colours, never its kind or
stop count. A brush property moves only between two colours or two well-formed
brushes of one shape; anything else snaps. A themed value never moves.

## What travels

A host moves frame by frame only what its views present and whose values
travel: `TransitionSurface` names them, element type by element type - a
view's opacity, background, size and transform; a colour box's colour and
corners; a label's size and colour of type; a layout's padding and spacing;
a shape's fill and stroke; a window's place. A backend answers
`animates(_:)` from it, and the host layer then walks the value and hands
the backend each frame's. Every other pair arrives at once, rather than
keeping a animation alive that nothing shows: a host that answers no pair
animates nothing, however the tree asks.

Insertion and removal phases use this same native capability check. An
actual native view supports opacity and drawing transforms independently of
its type: pages, lazy containers and custom controls retain these transitions,
while type tables still limit their text, layout and control properties.
A scale's pivot is part of its supported drawing transform. GTK and WinUI
also advertise blur for every actual native view. Static radii, driven radii
and transition phases use the same native setter. A backend without blur
continues to omit that component instead of keeping an invisible animation
alive. Blur belongs to drawing, not measurement; its radius does not change
the frame, geometry reports or the lazy realization window.

What a moved value asks of the elements around it is the host layer's too
([one frame](runtime.md#one-frame)): a window's frame, a title bar's
colours and a stack's or a tabbed view's bar colours are the window's
chrome, which the host composes again on the frames that move them
(`WindowChrome.follows`).

Canvas and custom Shape drawing request local allocation sizes independently
of business geometry reports. GTK and WinUI read those dimensions directly
for a size-only reporter, without computing window transforms, named spaces
or safe-area coordinates on every scroll or animation frame. Equal sizes
produce no drawing feedback; views that also request positions retain full
frame reporting.

## Layout animation

`HostPatch.animation` carries standing layout configuration. A separate
`layoutTransition` carries the current transaction or armed animation gate,
including `withAnimation` timing, disabled animation and geometry feedback.
Carried layouts receive that transaction when a descendant changes placement.
The host uses it for insertion, movement and removal without replacing the
standing configuration. A lazy window requested by a data update keeps that
timing through its deferred realization; later ordinary content clears it,
and viewport recycling does not start data transitions.

A layout works out where each child goes; `LayoutMotion` decides where the
child stands on the way. Why an arrangement happens decides everything:

- A patch reached the layout since its last arrangement: it holds something
  different - a row inserted, a card grown - and its children animate to their
  new places, under the layout's own animation or else the application's. A child
  that joins fades in.
- No patch: the room itself is moving - a window resized, a sidebar dragged -
  and every child follows exactly, because a child that glides after the
  user's own hand is late on every frame. A layout whose own width changed is
  this case even with a patch: its width is its parent's to say.
- The first arrangement arrives: the first thing anyone sees is the thing itself.

A size a child states for itself arrives while its place animates: a stated
size is either still or already animating on its own. Where a frame under the
layout is read, every child arrives, because each frame of an animation would
hand the reader of that frame a room nobody chose. The same place asked for
again keeps its running animation, and a new place bends a running one from
where it has reached, at its speed. A layout's children hold no strong
reference: a view the tree dropped is not kept alive for its place.

A lazy scroll-anchor correction changes the viewport origin, not the rows'
logical destinations. Its offset compensates the current presentation before
placement bends toward the newly calculated row frame. An already travelling
row keeps its sampled velocity and animation law through that correction;
newly mounted rows still start at their actual places. Translating both an
animation's start and destination is reserved for a coordinate-system change,
not a scroll offset, or the animation can land beyond the row's layout frame.
The corrected origin is clamped to the new scroll reach before deriving this
offset, so removing an anchor cannot compensate a move the native scroller
would refuse to make.

Lazy measurement refinement is distinct from a resize or a new authored motion.
At an unchanged cross-axis size, replacing estimated extents can retarget a
running placement using its current velocity and law even without another
business patch. It does not start a journey for a stationary row. Resizes,
business geometry reads and reduced motion retain their immediate-arrival rules.

## Words at their destination

A child whose place travels is told where it is bound as it sets out
(`PlacedView.travels(to:)`), and that it is bound nowhere once it lands or
arrives. A view that lays out words lays them out at the size it is bound
for, its place travelling around them: at the widths the place passes
through, words that fit the destination on one line would break onto two
for as long as the place travels. Every other view stands at each size it
passes through.

## Showing and hiding

An element's showing moves by one rule on every host (`MountedElement`'s
`fadeIn`, `crossVisibility`); the host hands it the view (`FadingView`) and
what closes the layout over it. A child that joins a standing layout fades
in from nothing under the layout's animation, where its view presents opacity
and no state owns it; an opacity already on its way keeps its animation. A
change of visibility on an element already shown crosses under the
element's own animation or the application's: hidden, it fades out - standing
shown the while (`standsShown`) - and only as the fade ends, landed or cut
short, does it hide and its layout close over it; shown again mid-fade, it
comes back from the opacity it stands at; shown from nothing, it fades in.
Where nothing moves - no animation, or the user asked for less - nothing
crosses, and the view simply shows or hides.

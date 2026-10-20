# Animation

A plain state assignment updates the control immediately. `Animation` says how
an explicitly animated change moves, and the same vocabulary answers everywhere
it is said.

## One vocabulary in four places

```text
  application.animation = ...                  optional application-wide default
  .animation(nil)                              what this element does instead
  @State(animation: nil) var x                 what this state does instead, wherever it is shown
  $fade.journey.move(to: 0.1, .spring())    what this one write does instead
```

The tree describes where the interface is going; the host is how the screen
catches up. The renderer resolves these choices into a `HostTransition`
beside each changed property, or a `HostLayoutMotion` for a layout's
children, and a native host animates the presentation on its display frames
while the tree keeps the destination.

## Two laws

A animation has one of two shapes. An eased animation takes as long as it is told,
whatever the distance: the right law for something whose distance the author
knows, such as a fade, a page sliding in, or a card turning over. A spring
has no duration: it answers as quickly as its response says and settles when
it is done, so one whose destination changes carries on from the speed it
had rather than starting again. That is the right law for anything the user
can interrupt, such as a card being dragged or a value still being chosen.

## Every law arrives

Both laws arrive at what the tree said, and that is why there are only two.
A law with no destination - a throw, bled off, coming to rest wherever its
speed runs out - would leave the screen showing a value nothing described,
and because an absent field means unchanged, nothing could ever put it
right. The physics of a throw lives where a throw is: in the scroller.

## Custom animates in an engine

`.custom` is not a third law but a third animator. The host animates nothing,
and an engine of the application writes where the value is and how fast it
is going, frame by frame, toward a destination the state still holds. It is
said where the value is declared, `@State(animation: .custom)`, because which
side animates a state is fixed when the state is first registered with the
host. The host never sees `.custom`: what crosses is `.none` over the value
the engine wrote, so the host wears each frame as it comes.

## Inherited and none

`.inherited` is what a write means when it says nothing about animation: the
element's own animation, else the application's. The application starts at
`.none`, so an ordinary change arrives immediately. It is
what makes `move(to:)` without a animation and a plain assignment agree, so the
two differ only in being awaited. `.none` applies a change at once, and an
ordinary property that snaps carries no `HostTransition` beside its value.

Both are made of an eased animation of no duration on this side. On a carried
state they cross as themselves, the first of a law's three lanes naming
which, and an inherited law is resolved against the element's animation on its
way out.

## The standard animation

`Animation.standard` is one 200-millisecond eased animation on `.cubicOut`.
It can be chosen explicitly with `withAnimation` or as an application default.

## Spring numbers

A spring's response is at least 1 millisecond and its damping at least 0.05.
A damping of 1 comes to rest without overshooting. Below 1 a spring
overshoots and oscillates, which is a deliberate choice and never a default:
half a card's worth of wobble is what a user reads as a mistake.

## Easing curves

An easing is a curve from 0 to 1: given how far through its time an
animation is, it says how far through the change it should be. `.linear` is
the straight line, and every other curve is worth having only because it is
not. `In` curves start slowly, `Out` curves end slowly and `InOut` curves do
both, which is why `.cubicOut` suits something arriving on screen and
`.cubicIn` something leaving. The curves and the two laws are
[closed vocabularies](vocabularies.md#the-numbers-belong-to-swiftomniui).

## Groups of values

`AnimationValues` names groups rather than single properties, because that is
how a user thinks about what they are watching: where a view sits, how big
it is, its colours. A animation written on a view applies to all of them unless
it names some. A panel whose content changes shape says
`.animation(.none, .size)`: its children move to their new places and take
their new size at once, since a view growing out of nothing is the one
movement a user reads as a fault.

A colour's group is read off the value rather than from a list of property
names, so a colour property added later is in the group the day it arrives.
Every other property says its group through its member's `moves`; see
[moves](../contracts/member-facts.md#moves).

A selective rule steers the properties the tree describes. What a host
decides with no property of its own - where a layout puts its children,
showing and hiding - follows the plain
`.animation(_:)`. A child's placement is also split into `.place`, `.width` and
`.height`, so a rule can snap those parts alone.

## A plan per view

`.animation(_:)` and `.animation(_:_:)` build a `AnimationPlan`: one base answer and
the exceptions to it, in writing order. The last rule that names a value
answers for it, as a modifier written later does everywhere else. A plan
written on a view goes over the plan the view is made of: its base replaces
the view's own, and its rules come after, being the later word. The plan
stays in the core, and only its resolved `Animation` answers reach a host.

## Transactions

A `withAnimation` or `withTransaction` body does not animate anything itself:
it writes a `Transaction` - the animation the writes run under, and whether
they animate at all - which the writes it makes carry. `Renderer.stateChanged`
picks the calling thread's transaction up with the write, and the render it
asks for answers it.

The transaction rewrites only the render that answers the writes, never the
standing instruction a view declared. `.animation(_:)` says how a change
animates wherever it comes from; the transaction says how THIS change
animates. So the differ keeps two answers: the plan's, which stays written on
the element, and the render's, which the property transitions of this pass
take. A `.transaction(_:)` on a view rewrites the transaction for the views
below before either is asked, and `disablesAnimations` there answers `.none`
for everything.

`.animation(_:value:)` is a gate on the same idea: it compares the value it
watches against the one the previous render saw, and only a render where it
moved takes the gate's animation. The first render arms nothing, since there
is no change yet to answer.
A gate that fires overrides the write's animation locally, including
`.animation(nil, value:)`. An unarmed gate leaves the transaction intact;
`disablesAnimations` still prevents both from starting animations.

## Layout lanes

A host works out where a child sits from native measurement, so a placement
is not an ordinary property and cannot carry a property transition. A layout
sends `HostLayoutMotion` instead: its animation, and which lanes of a place
animate (`AnimationLanes`: x, y, width and height). A measured layout's children
take their sizes at once and animate only their place.

A layout that animates the way the application does says nothing at all:
`.inherited` is what it is until told otherwise, on both sides, so the
common case never reaches a host. What is said is an override, and its
going away.

## Transitions

A transition is a pair of phases - how the element differs as it arrives, and
as it leaves - each naming which of its drawn properties stand elsewhere:
opacity, an offset, a scale about a pivot, a blur, or a `move` measured by the
element's own room. `AnyTransition` composes them (`combined(with:)`,
`asymmetric(insertion:removal:)`) and crosses as one `PropValue`.

`.transition(_:)` writes it on the element; the contract carries it as a
structural value rather than a state-animated scalar, so a removal phase is
still there to be read as the element goes. An insertion plays in the layout's
`fadeIn`: the element's properties are described from the phase's standing to
the value the tree says, under the transition's own animation where
`.animation(_:)` names one. A removal keeps the child mounted - `isDeparting`
- its view deaf to input and outside the layout's room, and each component
rides to the phase's value; the last one to land leaves the tree and the
layout drops the view. A patch that describes the element again mid-flight
reverses it: `revive` rides the running components back to where they stand.

## Matched geometry

A `matchedGeometry` property names an element across a change: the id and its
`Namespace.ID` together make a key, and `matchedGeometrySource` says whether
the element's own frame is what the key stands for. When a source leaves, the
host sets its window frame aside under the key; when another element arrives
under the same key it takes the frame up and the layout flies the child from
there - the seat it is handed is the one its match left, so it lands where it
stands rather than appearing in place.

The frame is spent as it is taken: a match joins once, and the rest that
share the key appear ordinarily. A key that nobody picks up is bounded - only
the last few stand - and `isSource: false` names a follower: it inherits a
frame but leaves none.

## Symbol effects

`symbolEffect` writes a kind - `bounce`, `pulse`, `replace` and the rest of
the SwiftUI vocabulary - with `symbolEffectOptions`, `symbolEffectActive` and
`symbolEffectValue` beside it: which passes repeat, whether the effect runs,
and the value whose change replays a `value:` write.

A host plays what it can honestly. A host may carry `bounce` and `pulse` over
the whole view - a scale keyframe for the one, an opacity swing that
`isActive` gates for the other - where the per-layer effects have no layer to
name; `symbolEffectValue` moving is what replays either, as a plain write
plays on arrival. `contentTransition` is the same shape on the content
itself: the host sees `text`, `source` or `icon` move under it and crosses the
swap - a push for `numericText`, a fade for `interpolate`, nothing for
`identity`.

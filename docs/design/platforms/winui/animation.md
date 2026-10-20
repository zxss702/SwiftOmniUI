# Animation on WinUI

How the WinUI host moves what the core's animation elements say
([animation](../../host/animation.md)): which properties it draws on the way, how an
element is moved, turned and scaled, and when every animation arrives at
once. The frames come from `CompositionTarget.Rendering`
([runtime](runtime.md#one-frame)).

## What moves

What moves is the host layer's list ([what
travels](../../host/animation.md#what-travels)), and WinUI draws every pair it
names on each frame through the same setters a patch uses. A tint moving
reads its control's color scheme again on every frame - a template reads its
resources only as its color scheme is read ([a control's
accent](controls.md#a-controls-accent)); a bar's colour moving composes the
window's chrome again, and a window's place and size stand the window again.

A property's animation begins where the element stands: the opacity it is
drawn at, the value a slider's thumb shows.

Blur is an additional drawing capability for every actual WinUI view.
Declared blur transitions prepare their native presentation boundary before
insertion. The host clock updates the retained Gaussian effect's radius,
with the same lifetime and reversal rules as opacity and transforms. The
radius does not ask XAML to measure or arrange the view again.

## Moved, turned and scaled

An element is moved, turned and scaled by a `CompositeTransform`, its render
transform, drawn over the place its layout gave it, so moving one never moves
the layout's arithmetic. A translation is in DIPs, a rotation in degrees,
clockwise in the screen's plane; `scale` multiplies both axes over `scaleX`
and `scaleY`. SwiftOmniUI's pivot is a fraction of the element's size and the
transform's centre is in DIPs: the host puts it back each time the element is
placed at a new size. The element's own `Translation`, `Rotation`, `Scale` and
`CenterPoint` go unused: a layout cut to its outline takes the element's
visual ([a box and its brush](drawing.md#a-box-and-its-brush)), and WinUI
refuses those four to such an element.

## Less animation

A user who turns Windows' animation effects off - `UISettings.AnimationsEnabled`
false - asks for less animation, and SwiftOmniUI hears it so: every animation arrives
at its destination at once, and a journey's waiter hears it arrive.

## Joining and leaving

A stack is a travelling layout: when a patch reaches it, its children travel
to their new places ([layout animation](../../host/animation.md#layout-animation)). The
display's frame writes each travelling child's place between WinUI's layout
passes, and the place lands in the arrangement it asks for
([a place between passes](layout.md#a-place-between-passes)); that
arrangement asks for the same places and keeps the running animation.

When described geometry supplies a presentation frame, dependent layout lanes
follow it directly. A described height owns vertical placement and height
along its containing branch; other children and lanes in the same patch can
still animate. Subsequent samples translate
existing independent journeys by the change in the arithmetic target,
preserving their sampled frame and original clock. Arrange never samples a
new animation time, and an unchanged target never cancels a sibling's motion.
The consumed marker describes that update, not an active descendant's entire
animation lifetime. A changed allocation from a native window or page owner
is a new room; a coincident descendant animation sample cannot turn that
external resize into another presentation journey.

By the host layer's rule ([showing and
hiding](../../host/animation.md#showing-and-hiding)), a child that joins a
standing stack fades in while the others make room. A
child the tree hides fades out first, still holding its room, and only then
goes: the stack closes over it as over a row a patch removed. A child shown
again comes up from nothing, or, shown again on its way out, from where the
fade has reached. Under a layout that moves nothing, or with less animation, it
goes and comes at once.

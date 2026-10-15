# Layout on WinUI

SwiftOmniUI's layouts place their children by the core's arithmetic
([layout](../../host/layout.md)); WinUI measures and draws each child.

## A layout is a panel

Every SwiftOmniUI layout is the relay's panel, a `Panel` whose `MeasureOverride`
and `ArrangeOverride` call the host, which answers with the core's arithmetic
and measures and places each child through the relay. WinUI lays out by
asking: a child is placed only inside its parent's arrangement
([a place between passes](#a-place-between-passes)).

## Measured every pass

WinUI keeps each element's measure itself, and a child left unmeasured in a
pass that marked it stays marked, which sets the pass going again - a pass
that does not settle ends the process. So each measure the panel answers
measures every shown child; WinUI answers a child it measured at the same
size from what it kept, and measures one it did not.

A native control is measured at each width the arithmetic offers it. A
layout of SwiftOmniUI's asks for no room, so it is measured at the width of the
place it stands in: WinUI measures it again only where a change beneath
marked it. Put in a place of another width, it is measured there first, which
measures its own children at the widths its arrangement then gives them - a
control arranged at a width other than the one it was last measured at would
mark its layout again. Its size at any other width is the arithmetic's, kept
per width until WinUI measures it again or a change forgets it on the way up.
Measured at every width asked of it, a layout forgot its sizes each time and
measured its whole subtree again: some seven hundred sizings for one word six
grids deep, and 2910 measures - 150 ms of a debug build's frame - for one
card of the home page's run turned.

Arithmetic queries and native preparation have separate scopes. A
`naturalSize` query can measure native leaves to answer a new proposal, but
does not recursively prepare panels or replace lazy row geometry. Stacks,
grids, single-child containers and layers also calculate their child places in a
query scope, then prepare only the selected places during native measurement.
Repeated leaf probes read width-keyed answers without selecting another
native proposal. A new leaf probe marks its placing ancestors' native
preparation stale, while retaining their arithmetic answers. The selected
places prepare native leaves as well as panels before arrangement.
They read the resulting sizes again before answering, so an initially
estimated lazy extent is not retained as the parent's completed size.

Stacks, grids, layers and single-child containers cache the selected child
proposals beside their width-keyed arithmetic. Native preparation replays those
proposals without running `contentSize` again. If preparing a child changes an
answer to the same proposal, the enclosing arithmetic is recomputed. Specialized
layouts that commit geometry while measuring, including Lazy, retain one
`contentSize` pass. Preparation records are bounded and hold children weakly.

`ProgramWrite` ends each patch/frame's native invalidation batch. Swift caches
are cleared immediately, shared ancestors once until a measurement consumes
them; another write after that measurement invalidates them again. Native
measure/arrange requests are coalesced until the batch ends. Row invalidations
stop at the Lazy panel. Only changes to its returned extent propagate to the
scroll document; changing the widest visible row in a fixed-width vertical
stack is not such a change. The first measurement also reports its replacement
of the estimated scroll extent. Window content constraints reuse their sizing
while the queried views' measurement revisions and window constraints agree.

Preparation restores native child proposals even when their arithmetic
answers are cached. Changing the native proposal preserves the other
width-keyed answers; only changed content, a changed answer or provisional
measurement discards them. An independent measure from XAML still refreshes
the arithmetic and reports a changed size upward. Repeating a preparation
at the same width and revision does nothing unless a fresh query has changed
the subtree's native proposals. This avoids the former alternating
ideal/allocated-width queries clearing and rebuilding nested caches.
Only a completed native measure records the prepared subtree's width;
an arithmetic cache miss cannot overwrite that record.
GeometryReader retains its independent ideal size, but still prepares its
native children at the proposals selected by its placement arithmetic. Its
children cannot remain unmeasured merely because they do not determine the
reader's own natural size.

Nothing is measured while WinUI arranges: `Measure` written on an element
inside an arrangement marks it, the marked element is measured and arranged
again, and eight passes that never settle end the process with a layout
cycle. An arrangement asking a child's size is answered from what the pass
already measured, and a marked element WinUI measures again inside its own
arrangement is answered with what its last real measure said. The place a
child is newly put in is measured once the pass ends, posted on the
doorbell: the pass after measures it there, and the one after settles.

An arithmetic query that needed such an unprepared native proposal is
provisional and is not cached. Its temporary DesiredSize cannot become a lazy
row's committed natural extent. Native invalidation and child attachment are
also deferred when MeasureOverride or ArrangeOverride is active. Deferred
changes clear affected arithmetic and request native measure/arrange at the
owning root; they do not measure that root with an invented unbounded height.
Viewport realization includes the measurement revision, even if the viewport
coordinates have not changed. The current ArrangeOverride bounds propagate
safe contexts instead of reading the previous ActualSize during the callback.
Lazy rows and tracks prefer the current finite width to `standsAt`; the old
allocation is only a fallback when the parent left the width unspecified.
Only preparation or viewport reconciliation commits row measurements,
tracks and anchor corrections. Window minimum-size and ideal-size queries
read the committed geometry; a query for different grid tracks uses estimates
for those tracks without resetting the visible grid.
Writing an unchanged child place between passes does not invalidate its
parent again. ArrangeOverride still arranges every native child it holds.

Lazy viewport realization requests the estimated window as one batch, as
GTK does. The former one-unknown-run policy performed a synchronous core
render for each incoming row; reconciliation revisited the growing mounted
window, and each iteration arranged that window again. This multiplied
initialization work and restarted placement decisions before the fill had
settled. The viewport callback now waits for the requested render, refines
coverage from measured geometry, and commits one final arrangement. A
callback during native Measure or Arrange resumes after the pass. Native
proposal preparation, row revisions and the scroll look-ahead stay intact.
The realized window follows the actual ViewChanged offset, not an animated
scroll's final endpoint. It releases rows behind its look-ahead while a
scroll is still active; it does not keep the continuous path from the first
viewport to the eventual endpoint mounted until Idle. Program jumps still
announce and realize their destination before moving the native scroller.
ViewChanged supplies the current position for both realization and anchor
selection. EffectiveViewport supplies the clipped dimensions; once scroll
notices have begun, an effective-viewport event reads the current native offset
instead of restoring an old reported position. This also picks up a descendant
moved by layout. Anchor corrections shift both viewport records together.
Program-jump preparation translates the target scroll offset into descendant
coordinates; it does not publish that future position as an already visible
anchor before the native move.

GeometryReader accepts a safe allocation while retaining the remaining
environment. Native window chrome that already sits outside the content row
remains in that environment as an outside strip, read from committed metrics.
ScrollView can extend its viewport behind it; native chrome has an explicit
drawing order above that viewport. Geometry carries these remaining insets
beside the existing ten-number physical report. Unloaded views report no
geometry, so a retained navigation page cannot publish a false zero frame.
Native Image/Viewbox content is prepared at its intrinsic size rather than 0x0.

## A place between passes

A child's `Arrange` written outside its parent's arrangement does nothing, so
a view keeps the place it was last given and writes it according to when it
comes. Inside a pass - the host counts the arrangements under way - the place
is arranged at once. Between passes, as a display frame moves a travelling
child, the view asks the layout that placed it to arrange again
(`InvalidateArrange`); WinUI runs that arrangement before it draws the frame,
and the layout's arrangement gives the child the place it keeps.

A label whose place travels is arranged at its place's corner but at the size
the place is bound for ([words at their
destination](../../host/animation.md#words-at-their-destination)). WinUI would
keep its words on the one line the destination gives them anyway - it
arranges nothing smaller than it measured - but it cuts an element to the
place it is arranged in, so the words' ends would not be drawn until the
place arrived.

## A place filled

A control's style aligns it inside the place its parent arranges it in - a
`Button` to the left and to the middle, at the size it asked for - where a
SwiftOmniUI layout decides the place itself. So every element the host holds is
told to stretch across whatever place it is arranged in, once, as it is made:
the layout's place is the control's size.

## No room asked

WinUI arranges an element at no less than the size it last asked for in
`Measure`, and cuts it to the place it was given - so a child placed smaller
than its content would be laid out at its content's size and clipped, where
SwiftOmniUI places it at its place and lets it draw past its edges. A SwiftOmniUI
layout that another SwiftOmniUI layout places therefore asks WinUI for no room:
its parent reads its size from the core's arithmetic (`naturalSize`), and
WinUI arranges it exactly where the parent puts it. A layout WinUI itself
places - the window's content, a scroller's document - answers with the room
its children take, within the room offered. A native control keeps its own
measure, and WinUI clips it as it clips any control given too little room.

Measuring a child again inside an arrangement, at its place, is no answer: the
child's new size tells its parent to measure again, the next measure asks for
the whole content, and the pass never settles.

## A change told upward

WinUI hears of a child's new size only as a change in what the child asks
for, and a SwiftOmniUI layout placed by another asks for no room, as a picture
does. So a layout WinUI measures by itself - a picture read below it, words
changed - whose natural size has changed tells the layout placing it, which
measures again, and so on up; a layout measured inside its parent's own
measure is read there and tells nothing. A picture read after its layouts
were measured tells the layout holding it through the relay.

Content, child membership or layout-property changes also invalidate native
arrangement along the affected placing chain. A panel's zero DesiredSize can
remain unchanged while its children's places change; remeasurement alone is
not a reliable request for new child arrangements. Child attachment likewise
requests arrangement after committing the new native child list. No synchronous
`UpdateLayout` or window-wide redraw is needed for this handoff.

## Where a view stands

A view whose frame the tree reads - a state its frame drives, or a handler
for its changes - says where it stands on the display's next frame after a
layout pass or a scroll: its frame in its parent, its place in the window's
content, and that place from the page's corner, all in DIPs. The host hears
every SwiftOmniUI layout WinUI arranges and every scroller's movement, and asks
only the views that are read, in the order they were made; a view that did
not move says nothing. It speaks on a frame rather than inside WinUI's pass,
so what a handler renders is laid out in a pass of its own.

## Right to left

A layout mirrors its children by the host layer's arithmetic, never by
WinUI's `FlowDirection` ([right to left](../../host/layout.md#right-to-left)).
WinUI hands an element's direction down to everything in it, and an element
told right to left under one left to right is drawn mirrored whole: a panel
would mirror its places a second time, and a picture, a figure or a gradient
would be turned. So a control takes its element's direction - its words, the
side its mark stands on, the end a slider fills from - and a layout and a
drawing (a picture, a figure, a canvas, a colour box, the activity ring) stand
left to right, written so, never inherited. An ItemsView's items are placed
by WinUI's own list, which takes the element's direction - a grid fills from
the right - while each cell's content stands by the same rule. A web view
stands left to right: its page says its own direction. A control told right
to left is mirrored whole by WinUI, its background with it: a gradient there
runs the other way.

## Scrolling

A ScrollView is a SwiftOmniUI layout holding WinUI's `ScrollViewer`, which holds
the document the core's scroll arithmetic lays out - never smaller than the
viewport, and several children stacked down. The scroller is measured with no
room in the directions it scrolls: it measures its document without bound
there itself, so the extent is the document's, and asking for no room it
stands exactly where the layout places it.

A ScrollView reads the placement's `SafeAreaContext`, extends its native
viewport beneath unsafe strips, and adds the remaining insets to document
padding. Content receives a consumed context, so nested scrollers and inner
GeometryReaders do not repeat those margins. The scroll background covers
that viewport; explicit clipping limits the extension. `scrollTo` anchors
against the visible region after margins, with first and last content able to
scroll clear of the bars.

Measurement calculates sizes only: resolved document padding is arithmetic
state, while native padding invalidation, scrollbar margin writes and bar
ownership changes commit after the pass. A template search skips document
content and nested scrollers, retaining each indicator's original margin.
Template reloads reapply the current contribution without accumulating it.
Margin commits run on initial loading, changed insets, and template/theme
changes. Template changes use one LayoutUpdated notification, then remove
the handler; unrelated window layouts do not traverse every scroller's
template again. Unchanged resolved margins post no new commit.
Native scroller proposals first encountered during arrangement are prepared
after the pass. Size feedback to a placing layout is deferred as well.

The scroller says where its view stands through `ViewChanged`, and that the
user holds it through `DirectManipulationStarted` and `Completed`. The user's
movement is joined up to the display's next frame, which reports it to its
state and its handlers, and rests once it has stood still, as on every host
([a scroller's movement](../../host/runtime.md#a-scrollers-movement)).

## The program's move

`ChangeView` moves the view in a later frame, and its `ViewChanged` comes long
after the program's write has ended, so `ProgramWrite` cannot know it. The
host keeps the target it moved to - kept within the scroller's reach, as the
scroller keeps it - and takes the view arriving there as the program's; a
target the view already stands at is not moved to at all, as the scroller
would say nothing of it, and a user's hold forgets the target.

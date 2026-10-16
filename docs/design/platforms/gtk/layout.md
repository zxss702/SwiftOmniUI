# Layout on GTK

SwiftOmniUI's layouts place their children by the core's arithmetic
([layout](../../host/layout.md)); GTK measures and draws each widget.

## A layout is a panel

Every SwiftOmniUI layout is a `SwiftOmniUIPanel`, a widget subclass whose measure and
allocate call the host, which answers with the core's arithmetic and measures
and places each child. GTK lays out by asking: a child is allocated only
inside its parent's allocation, so a layout never places a child outside the
pass GTK runs. A child's size is whole logical pixels, and never less than the
least GTK measured it at; its position is a translation, which may fall
between pixels, so a travelling child moves smoothly.

## A place between passes

A child is allocated only inside its parent's allocation, so a view keeps the
place it was last given and writes it according to when it comes. Inside an
allocation - the host counts the allocations under way - the place is
allocated at once. Between allocations, as a display frame moves a travelling
child, the view asks the layout that placed it for a new allocation
(`gtk_widget_queue_allocate`); GTK runs it in the same frame, after the tick
that moved the child and before it draws, and the layout's arrangement gives
the child the place it keeps.

## Measured per axis

GTK asks a widget for its size one axis at a time: its width, then its height
for a width. A panel says it wants its height for its width, and answers the
width with the arithmetic's natural width and the height with the
arithmetic's height at the width GTK gives. Its least is nothing: what fits
where is the arithmetic's decision, and a panel whose least were its natural
size would hold the window at the size of its content. Each measure GTK asks
for measures the children again; GTK keeps each child's own answer until
something about it changes, so asking again costs little.

Lazy containers also retain each mounted row's arithmetic size by identity,
proposal and the row's measurement revision. A source update or a sibling's
insertion does not discard surviving rows' sizes. Allocation-only animation
frames reuse them; changed placement values or content invalidate the
affected row. When GTK requests a native measurement, the lazy container
revalidates retained proposals through GTK's own requisition cache, so native
text, font and CSS changes can still update row extents without a core patch.

## A change and its rows

A lazy arrangement the source patch reaches before the rows it added asks the
window again and stands down. The pass in between would otherwise spend the
change, and the rows the realization mounts would arrive with nothing to travel
under. GTK measures a row within the arrangement that places it, so what such a
run waits for is the window, not a measurement: the pass is held where the tree
has not yet answered what the run asked of it, or where a row the change added
stands in the built window unmounted.

The run keeps the timing that patch named across the pass in between - the
realization names no timing of its own - and spends it in the arrangement that
can place those rows, so an inserted row fades in and its neighbours travel
under the change's own law. A pass with no change waiting arranges at once, the
way an ordinary layout does: the rows already mounted keep the places the last
arrangement gave them. Every arrangement that begins takes the kept law with it,
so none outlives the change it belongs to.

## Measuring a widget

A widget's size counts its CSS padding, border and padding: a button measured
34 high draws its caption in the 24 inside that box. `gtk_widget_measure` and
`gtk_widget_allocate` both speak of the whole box, and where a widget stands
is read back with `gtk_widget_compute_bounds`, which does too;
`gtk_widget_get_width` and `gtk_widget_compute_point` are the box's inside.
A widget is measured at its natural width, no wider than offered and no
narrower than its least, and then at its natural height for that width - a
label wraps to the width it is given.

A native frame - a `GtkButton`'s, a `GtkMenuButton`'s - asks its child for a
size request with no width in mind, so a face bounding its own width
(`.frame(maxWidth:)`) is asked without that bound and answers with the width of
its words alone; the frame would then collapse onto them. The host measures
such a face itself, through the layout arithmetic, in the room the frame's own
requisition leaves inside its box, and keeps the frame's own answer for the
height at the width it chose. The bound is then kept the way the hosts that
measure their content at an available size keep it.

## Where a view stands

A view whose frame the tree reads - a state its frame drives, or a handler
for its changes - says where it stands on the display's next frame after a
layout or a scroll: its frame in its parent, its place in the window, and
that place from the top left of its page's content, beneath the page's own
header bar, all in logical pixels. The host hears every SwiftOmniUI panel GTK
allocates and every scroller's movement, and asks only the views that are
read, in the order they were made; a view that did not move says nothing. It
speaks on a frame rather than inside GTK's allocation, so what a handler
renders is laid out in a pass of its own. A view in no window, or one no
layout has placed yet - neither SwiftOmniUI's nor GTK's allocation - stands
nowhere and says nothing: a frame's tick comes before its layout, so a view
made just before it would otherwise say it stands at zero.

## Scrolling

A ScrollView is a SwiftOmniUI layout holding GTK's `GtkScrolledWindow`, which
holds the document the core's scroll arithmetic lays out - never smaller than
the viewport, and several children stacked down. GTK puts the document in a
`GtkViewport`, which the host tells to give it its natural size along the ways
the view scrolls and the viewport's own size across them. The document also
reports its complete natural extent as its minimum on scrolling axes, so the
native viewport cannot compress the document and lose scroll reach. A
way the view does not scroll holds the document to the viewport; a bar asked
never to show still scrolls.

A ScrollView reads the placement's `SafeAreaContext`, extends its native
viewport beneath unsafe strips, and adds the remaining insets to document
padding. Content receives a consumed context, so nested scrollers and inner
GeometryReaders do not repeat those margins. The scroll background covers
that viewport; explicit clipping limits the extension. `scrollTo` anchors
against the visible region after margins, with first and last content able to
scroll clear of the bars.

Indicator margins use this scroller's own `get_vscrollbar`/`get_hscrollbar`
parts, retaining their original margins. Padding and indicator updates are
coalesced after allocation. Page-level top bars join `AdwToolbarView`; local,
bottom and side bars keep independent transparent hosting.

The scroller says where its view stands through its adjustments'
`value-changed`, and that the user holds it - a touchpad's fingers down -
through a scroll controller's `scroll-begin` and `scroll-end`. The user's
movement is joined up to the display's next frame, which reports it to its
state and its handlers, and rests once it has stood still, as on every host
([a scroller's movement](../../host/runtime.md#a-scrollers-movement)). The
program moves the view by setting the adjustments, which GTK tells inside the
program's write: `ProgramWrite` drops that echo, and nothing else is kept.

A viewport owns its child: a view whose parent is not a SwiftOmniUI panel is not
taken out by the view as it goes, and the scroller takes its document out of
the viewport before it goes itself.
## Right to left

A layout mirrors its children by the host layer's arithmetic, never by GTK's
direction ([right to left](../../host/layout.md#right-to-left)). What a widget
draws of itself - where a field's words start, which end a slider fills from,
the side a check box's mark stands on - follows GTK's own direction, which
each element's widget takes from the element as it is made and as it turns.

GTK hands a widget's direction to none of its parts: below it, every widget
keeps the language's. So the host hands it on where words are written: to
the text a field, a search field or a stepper edit by, which GTK names
publicly as the editable's delegate (`gtk_editable_get_delegate`); to an
editor's text view; to the box a button stands its picture and caption in,
made in the button's direction whenever it is made again. An editor's
placeholder is laid over its text at a place from the left edge, and stays
there.

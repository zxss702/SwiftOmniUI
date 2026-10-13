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

Layout size arithmetic and native preparation are separate. A parent's
`WinUILayoutItem.size(offered:)` query reads `naturalSize(width:)`; it does not
prepare that child's native panel. The arithmetic keeps answers for multiple
widths until content invalidation discards them. Text and image leaves whose
changes the host explicitly invalidates keep measurements by proposal.
Native containers and input controls use XAML's own measure cache, so native
content and user edits can invalidate their sizes without a host property
write. Asking for an ideal width and then an
allocated width must not repeatedly discard every descendant's sizes or
switch every nested native panel between those widths.

`prepareMeasure(width:)` selects the native allocation, and
`prepareChildren(width:)` prepares shown children at the widths the layout
will give them. Stacks, grids and single-child layouts resolve those places
separately from their size queries. Preparation preserves the arithmetic
cache; a panel's own `MeasureOverride` does not repeat its child preparation
when answering that explicit preparation. A preparation already current at
the same width and revision skips its stable subtree. A native query that
changes a descendant's proposal, or invalidates its measure, marks just the
related placing ancestors as needing preparation. This hint does not discard
arithmetic or post another layout task. The next preparation restores those
branches before becoming current again. Scroll documents carry the hint to
their scroller, and promoted safe bars carry it to both their logical layout
and native bar host. This matters because XAML retains only its last native
proposal, while the host's arithmetic can retain several widths.
If preparing a child replaces an estimate or changes its revision, the
parent discards its own cached arithmetic before finishing that measure.
The current preparation carries the fresh result upward without scheduling
a separate ancestor traversal for every row.

An independent native measure refreshes that layout's arithmetic and reports
a changed natural size upward. A layout placed by another SwiftOmniUI layout
still returns zero native DesiredSize: its parent reads the arithmetic size
and gives it the exact allocated place. Native containers such as a window
or scroll presenter instead receive the content's measured size.

Lazy stacks and grids commit mounted row measurements, tracks and anchors
only during preparation at the selected native allocation. Other width
queries read document estimates without replacing the realized geometry or
requesting additional rows. A grid's alternative track count uses a constant
time estimate of unseen runs. The current finite allocation takes priority
on initialization and resize; the previous allocation is only a fallback
for an unspecified selected proposal. Surviving rows keep their measures,
and restoring a row's native proposal rechecks its revision before retaining
the old size. Unseen rows keep their estimates and remain unmounted.

No new native `Measure` proposal is applied while WinUI arranges. An
arrangement reads a kept result, or a provisional DesiredSize when that
proposal has not yet been prepared. Provisional arithmetic is not retained
as a completed measurement. The missing preparation is coalesced on the
doorbell after the pass, using the newest allocation, then its placing
ancestors receive the changed size. A viewport notification inside a native
measure or arrangement also defers its fill; it cannot prepare and arrange
the run at the previous `placed.width` during a resize.

Native invalidation and parent-child changes are deferred while a measure or
arrangement is active. Ancestor measurement invalidation is sent once until
fresh arithmetic is computed, independently of local cache disposal. Child
lists are compared before scheduling a commit, so an unchanged list posts no
work. Background painting uses pending children when present, preserving
newly realized rows instead of overwriting them with the old native list.
Deferred size feedback invalidates the owning root using the normal XAML
proposal; it does not prepare that root with an invented unbounded height.

Viewport realization includes the measurement revision even when its
coordinates have not changed. Once row geometry and the realized window
agree, another notice sends no realization. The current ArrangeOverride
bounds propagate safe contexts instead of reading the previous ActualSize
during the callback.

An incremental viewport fill measures each unknown run before requesting the
next, retaining the strict window bound for tall rows. It places the final
mounted window once after the synchronous fill, rather than arranging every
surviving native subtree after every incoming run. Accumulated anchor shifts
and insertion animations are consumed by that final placement. A fill that
awaits a deferred render places the measurements completed so far and resumes
after the pass.

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
is arranged at once. A position-only layout animation allocates the child's
native subtree at its destination once. Its current animated place remains
the reported place, and a presentation translation moves that allocation to
the current position. Each display frame changes that translation without
invalidating the parent lazy panel or arranging every surviving row again.
The final frame clears the translation after landing; clearing it before the
final frame would briefly show the destination between animation steps.

A journey that changes the child's size still asks the placing layout to
arrange again (`InvalidateArrange`), because its descendants really have new
room to lay out. Ordinary placements between passes also follow this path.
WinUI runs that arrangement before it draws the frame. Business frame reads
already make layout motion arrive immediately, so they keep the actual
allocation rather than receiving an intermediate animation proposal.

A lazy window clamps against the final allocated document capacity during a
size animation, rather than the current presentation height while row offsets
already describe the final geometry. This avoids repeatedly dropping and
realizing boundary rows as that height travels. An explicit fixed frame is
still the allocation's bound; geometry reports retain the current frame.
If a journey is retargeted before its new native allocation lands, its final
presentation translation stays until the committing arrangement, rather than
briefly returning to the previous target when the animator finishes.

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

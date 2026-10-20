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

Intrinsic answers and native allocations are separate. Native leaf answers
are cached by both proposed axes; a different proposal never reads the last
`DesiredSize` as its answer. Authored Custom Layout proposals retain the
difference between zero, unspecified and infinite axes. Native constraints
are normalized to XAML's single precision.

Native plan bounds and child rectangles use that same single precision before
descendant placement arithmetic runs. This also applies when an unspecified
axis takes its natural extent, and when Arrange prepares a child's allocation
from its parent's Double arithmetic. Two Double sizes converting to the same
XAML size select one native plan. Otherwise a VStack can compress a text leaf
at 304.944000244 DIPs during Measure, restore its uncompressed height using
304.944007874 DIPs during Arrange preparation, and make XAML repeatedly measure
the unchanged stack. Natural-size answers and shared host arithmetic remain
Double; the conversion belongs to the native plan boundary.

Stacks, grids, layers, single-child containers, safe-area bar hosts and Custom
Layout produce a completed `LayoutPlan`. A plan contains the actual bounds,
resolved layout values, safe-area context, child proposals, content revisions
and native attachment dependencies. Plans are bounded and hold views weakly.
Measure prepares the selected native children and refines the plan if a
native answer changes. Arrange consumes those same child rectangles rather
than rerunning placement arithmetic against unrelated native measurements.
Cached ZStack inset context is restored from the recorded bar rectangle.
Custom Layout forwards both axes through size, dimensions and placement.
Replacing the layout object invalidates its plan even with unchanged children.
Changes to a child's layout-value tags notify its nearest Custom Layout through
`HostPatch.customLayoutChanged`; the mounted revision invalidates that
container even when its LayoutBox and child identities remain unchanged.

A selected Measure proposal enters XAML so native dirtiness, resource changes
and template attachment are observed. An explicit preparation can reuse
proposal-keyed arithmetic while still checking its native children. A dirty
native callback refreshes its own arithmetic and retains unchanged descendants'
proposal-keyed answers. Only the affected dependency paths refresh; moving to
a different allocation alone reuses intrinsic answers. Ordinary arithmetic
ignores proposed height and retains its width cache; height-sensitive Custom
Layout keeps both axes.
If a native child changes its answer at the same proposal, its old intrinsic answers are
discarded and the enclosing plan is recomputed before placement. Merely
selecting a different proposal is not a content revision and does not clear
answers at other widths or heights.

Layout phases belong to each view. An ancestor can be arranging while a child
that has not entered Arrange is synchronously measured. The global native
layout depths remain active to protect structural changes; callbacks do not
reset them. A panel must not call native Measure, InvalidateMeasure or
UpdateLayout on itself or an arranging ancestor. A native-owned page receiving
new final bounds synchronously computes and prepares its child plan for those
bounds without reentering its own native Measure.

Preparing an Arrange allocation preserves native Measure results for both
SOUI panels and native XAML controls. It recursively prepares SOUI panels'
child plans. SplitView, scroll and item containers consume their completed
measurements and let XAML arrange their templates and pages at the final slot.
`WinUIView.layout` uses the same `prepareAllocation` contract before Arrange;
it does not remeasure native controls just because their final slot differs.
Animated text alone prepares its independent destination wrapping proposal,
which does not follow the changing presentation slot.
For example, a native Grid can measure a page at 792 DIPs but arrange it at
792.5714 DIPs on a 175% display. Measuring the page's framed child again at the
latter height changes its DesiredSize, dirties that same parent and repeats
the original Measure forever. Allocation plans carry the actual rectangles
without rewriting the native measure contract. A valid prepared allocation
can be reused only while its complete plan dependencies still match.

There is no provisional DesiredSize, deferred unknown-proposal measurement or
old animation allocation to repair on a later dispatcher turn. A presentation
frame records the latest place and requests the parent's Arrange; that pass
prepares the latest slot before arranging the child. Text's destination room
continues to control wrapping while its presentation travels.

Native child attachment, blur-boundary ownership and invalidation of an active
native view wait until layout ends. Deferred structural work requests the
next native layout itself. It never depends on another keystroke or scroll.
`ProgramWrite` coalesces shared ancestor invalidations until measurement consumes
their caches, and a later write can invalidate them again. Native input clears
logical size answers before its state report can render a new tree. An idle
logical owner is notified when an independent native measurement changes its
answer; a parent already completing a plan consumes the correction directly.

GeometryReader keeps its independent ideal size but prepares its children at
the allocations selected by its plan. Safe regions are rebased to current
bounds, preserving edge distances and consumed insets. Native-owned content
uses the actual column's allocation, including changes from sidebar toggles.
Promoted bars retain their logical identity and native ownership dependency.

A parent's selected safe-area projection is a plan input, not a content
change. Selecting it discards dependent arithmetic and plans synchronously,
without requesting another native Measure from the pass consuming it. Actual
environment changes still request layout, including independent container and
keyboard regions and chrome outside the local safe rectangle. Native chrome
height changes publish that environment after the active pass. A SplitView's
pane keeps its declared open width while closed; the native template clips
the pane rather than measuring its content at zero and arranging it at the
open width.

Safe-area arithmetic preserves exact zero contributions at fractional origins.
Consumed outsets compare original endpoints, and fully contained intervals
retain their original extents. A region covering a whole child axis uses that
child's exact local extent; unsafe and offscreen edges keep their coordinates.
Resizing applies region/layout differences before adding the new extent.
These identities prevent floating-point cancellation from repeatedly dirtying
unchanged content without discarding real subpixel safe-area contributions.

Lazy containers retain estimates only for unmeasured offscreen extents. Every
mounted visible row is measured at the current proposal before Stack or Grid
places it; neither an estimated frame nor a skipped cell substitutes for that
measurement. Native tree updates requested by a viewport callback complete
after the active pass, and their own invalidation resumes layout. Realization
follows actual scrolling and clipped viewport geometry; program destinations
remain a separate preparation request.

Intrinsic queries do not commit lazy row geometry. Selected native Measure
prepares row measurements and the extent index before building a plan;
allocation preparation resolves a changed slot from logical answers without
rewriting a native control's completed DesiredSize. Stack and Grid both consume
these prepared rectangles in Arrange. A row-position index change discards
placement plans even when the document's total extent stays the same.

Custom Button and Menu labels retain a native content-owner link. A label's
attachment-time font or size correction crosses that link to invalidate the
control and its logical layout ancestors, without replacing the control.

GeometryReader and frame feeds report committed native geometry on a display
frame, outside native layout. Unloaded views publish no false zero frame.
Native Image/Viewbox content is prepared at its intrinsic size.

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

## Desired size

Every panel reports its measured content size, with its frame applied and
bounded by the native proposal. A logical `placingLayout` does not make its
native desired size zero: XAML content presenters and effect wrappers also
consume that result. Native preparation measures the subtree at its selected
allocation before arrangement, so XAML does not retain an oversized intrinsic
proposal and enlarge the arranged subtree to match it. The logical parent
continues to read `naturalSize` for its own arithmetic.

Measuring a child again inside an arrangement, at its place, is no answer: the
child's new size tells its parent to measure again, the next measure asks for
the whole content, and the pass never settles.

## A change told upward

XAML observes a panel's changed DesiredSize when its measure completes.
The panel records its natural-size revision for logical row caches, without
explicitly invalidating its parent from inside MeasureOverride. State and
native resource changes still discard affected logical arithmetic before
requesting a native measure. A picture read after its layouts were measured
tells the layout holding it through the relay.

A lazy run's changed content extent reaches the scroll document even where the
run is not yet placed: the write names the scroller the run's own tree declares
where no placing layout reaches one, so a document first measured at the
estimates is not left standing under a bar while the rows stand at their
measures. Content and layout-property changes invalidate native measurement;
the completed measure also invalidates arrangement. Child attachment
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
A scroller's Measure proposal is prepared before native Arrange; its final
allocation does not explicitly call Measure on the scroller again. The viewport
bridge distinguishes ready, not ready and failed queries, writing geometry
only on success. A not-ready request waits through weak native Loaded and
LayoutUpdated subscriptions and resumes when the native viewport exists;
there is no guessed native-room rectangle or dispatcher retry loop. Ready
rectangles are the current native intersection of ancestor scroll presenters'
layout viewports, transformed into the descendant's coordinates. An empty
intersection is an offscreen window, not an attachment failure. Effective
viewport notifications trigger a fresh complete read instead of mixing an
old event's size with a new origin. Failed queries report an explicit native
error and do not register a pending retry.

Native `UIElement.Clip`, composition clips and alpha masks control drawing;
they do not alter the layout viewport or destroy its mounted rows. In
particular, a SplitView's temporarily empty animated clip must not clear a
prepared sidebar. Nested scroll presenters still intersect their actual
allocated windows, so an inner scroller outside its outer scroll viewport
remains virtualized. Viewport queries never acquire a handout Visual.

A lazy run under the scroller answers the document's cross size with the
widest row measured in the room it was given, and keeps that width for as
long as that is the room: the rows a moving window leaves behind do not
narrow it. A cross size that follows the window toggles the document's
extent - and the scroller's cross bar with it - between two states while the
list scrolls along its own axis, so a widened extent is committed to the
document once, when it grows. A newly mounted row completes its own native
proposal before receiving a visible frame. Estimates contribute to the
unmeasured offscreen extent, while visible Stack and Grid cells follow the
same measurement requirement.

Changing the cross-axis proposal invalidates row measurements through their
proposal keys, not by replacing the entire extent index with 44-point rows.
Previously measured offscreen extents remain estimates until those rows are
realized at the new width; only never-measured rows begin at 44. Grid runs
retain estimates while their cell grouping stays the same. A changed track
count invalidates that grouping and resets the run index.

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

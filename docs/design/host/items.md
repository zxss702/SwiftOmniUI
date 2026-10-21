# Items

What a platform's collection holds of one List, and what it tells the
tree, is decided once in the host layer (`ItemsCells`); a backend is the
toolkit's collection and its calls.

`ItemsLayout` defaults to eight points between items, whether stacked down,
across or in a grid. An explicit `spacing: 0` remains zero. This is separate
from the list's content padding. A backend applies the first layout even
when it equals the host's default, before publishing entries, so the native
collection receives that spacing on its first frame.

The entries cross as one property, every identity in order. A backend takes
them as they change (`takeEntries`) and shows one cell for each. When the
collection asks a cell for an entry (`hold`) that the tree has not built,
the host tells the tree which entries to build - the List's
`realizedChanged` - and the turn that follows builds them as children of the
list before the call returns: the cell shows its subtree at once. Asked
while a turn is under way - the toolkit calling back from inside a patch -
the entry arrives with that turn instead, and the backend puts it in its
cell as it appears.

What the user chooses is told in the order the items show, and a choice the
tree already holds is not told again; what the program selects, inside
`ProgramWrite`, is not the user's. An item opened is told by its identity; a
header or a footer is never chosen or opened.

## One cell an entry

A subtree stands in one cell at a time, and a collection does not promise
one cell an item: it may ask a second cell for an item before the first has
ended showing it - a row measured again, an item fetched ahead - and it
shows again, without asking, a cell that ended showing its item a moment
before, when the user scrolls back. So `ItemsCells` keeps the one cell
holding each entry (`ItemsHolding`), and three moments decide it:

- `hold` - the collection asked a cell for an entry: the cell takes it,
  from a cell before, which then shows nothing;
- `show` - a cell comes on screen: one that no longer holds its entry takes
  it again;
- `endShowing` - a cell ended showing its entry: the cells stop holding it
  only while that cell still holds it. Let go by the cell it left, the
  entry could leave the tree under the cell showing it - a hole.

After every patch to the list, `childrenChanged` holds each cell to the
subtree its entry has now: one built with the turn under way, or built
again after the one before was let go.

## Within reach

Every render walks the whole tree, so a render a cell would make a scroll
cost as much as the application is large. The tree builds the entries
within reach of the cells instead: as many before and after each cell as
the cells hold, eight at least. A cell coming on screen finds its entry
built and costs no render; one reaching past the built entries tells the
tree once, and the render builds a reach at a time. A cell that ends
showing its entry tells nothing: the entry stays built while it is within
reach, and leaves with the next render once the cells have moved away.
Cells far apart, after a jump, build around each and nothing between.

A cell holds an entry the collection shows, and never a name the list was
showing a moment before: a backend may bind a row while the list still shows
the entries of a write it owes, and a cell taking one of those would stand
over the entry of another place, or over none at all. An entry within reach
the tree holds no subtree for is asked for again: a cell whose entry the
tree let go of, because the reach moved under it, stands empty until that
entry is built again, and nothing else would ask for it.

## Changes one by one

A collection that applies a snapshot works out its own changes. One told its
changes one at a time - a recycler's adapter, a list model - takes them from
`ItemsChanges`: the positions removed from the old list, last first, then
the positions inserted into the new one, first first. The identities in both
that keep their order against each other - the longest rising run of their
new places - stay; every other one is removed and inserted, which is how a
move is told. `removedRuns` and `insertedRuns` gather neighbours into runs,
each told in one call, in the same order.

A backend that owes its toolkit a sequence of splices speaks a place from the
host layer's entries for as long as a write stands - owed, and under way - and
never from the toolkit's model: between one splice of the sequence and the next
the model names neither the list as it was nor the one it will be. A row the
splice itself binds is one of those. Given the model's own name it would stand
over the entry of another place, or over none at all - the row of the folder
the user opened among them. A write raised while one runs joins the queue
behind it, and one walk leads them all.

## The end reached

`EndReachedWatch`: the end is told as the last item in view comes within
`endReachedWithin` items of the last one, once. It is told again only after
the user scrolls away from the end, or once the list gains or loses items,
so a list waiting for more is not asked for more on every frame.

## A grid

`ItemsGrid`: a grid holds as many columns as fit items at least the
narrowest width, `spacing` apart, and one at least; the columns share what
is left of the width.

## A collection without groups

A recycler and a grid view know no groups, and share a grid's width equally
among their columns. `ItemsPlacement` stands the entries in one run for
them: in a list or a row the items of a group stand `spacing` apart and a
header or a footer keeps no room; in a grid each entry keeps room beside it
that makes it a column's width, `spacing` from the next, and a row after the
first keeps `spacing` above it. Where the collection lets an entry span
columns, a header or a footer spans them all and a group's last item what
its row has left, so every group starts a row; where it does not, every
entry takes the next cell.

## A tap

A collection that holds no choice of its own - a recycler - hears a tap and
nothing more. `ItemsTap` decides it: a list choosing none opens the item; a
list choosing one chooses it and opens it; a list choosing many adds the
item to the choice or takes it away, and opens nothing. A collection that
holds its choice itself tells what it holds (`userChose`) and what it opens
(`userActivated`).

## Scrolling to an item

`ScrollAnchor.place` says where the scroller stands for the item to stand at
the start of the room, its centre or its end. Nearest leaves an item wholly
in view where it is; otherwise it moves it the shorter way - to the start
when it stands before the room, to the end when after it. The scroller keeps
the place within its reach.
## The view moving

A toolkit moves a list's rows as it scrolls, often laying nothing out: a
view in a row stands elsewhere in its window though no layout placed it, and
a scroll of less than a row brings no row in whose layout would say so. Each
host tells the entries in view (`showing`) once the list's view has moved,
and the host layer then says that whoever reads a frame says it on the
display's next frame (runtime.md, `Where a view stands`). A host keeps no
road of its own for it.

## Lazy layout windows

Managed lazy containers share one immutable `HostLazySource` between the core
and mounted layout. It contains identity order, the position index, a predecessor
token and a range replacement or block move. View closures remain in the core.
The position index is a persistent identity map into an order-statistic
sequence: a local splice copies only its boundary paths and inserted rows.
The ordered array remains the boundary input, while mounted rows, extent
measurements and recycling query the shared index rather than rebuilding a
dictionary of every position. A direct caller needing a complete table may
still request one explicitly.
The direct host SPI still accepts `.items` as a fallback. Viewport patches carry
neither the full property nor another index. The source does not retain earlier
snapshots; a host skipping a version rebuilds its geometry once.

`ForEach` identities retain their Hashable values, scoped by declaration path.
Only new identities allocate descriptive host tokens; equal descriptions do not
merge unequal IDs. Ordinary collection replacements still need an ID scan to
discover edits, without comparing complete models or building offscreen rows.
An unchanged `Array` buffer, like an unchanged integer range, proves that its
identity sequence can be reused without reading any row IDs on a parent update.
The state walk stops at `ForEach`: its models are source data, while dynamic
properties of visible row views are discovered when those rows are built.
The latest collection and closures always provide requested rows, including
content changes at an unchanged identity.

`LazyCells` keeps scroll geometry for a lazy stack or grid. Each unmeasured
row stays at an extent of 44; a native measurement replaces only that row's
estimate and updates the document extent. Measured rows never change the
estimates of unseen rows. An immutable AVL sequence compresses uniform runs
and caches subtree counts and measured sums. Range edits change boundary paths
and inserted runs, without re-summing the complete measurement history. Aligned
grid edits retain unaffected runs; regrouping invalidates the affected suffix.
An unspecified lazy stack gap resolves to the stack default of eight points;
an explicit zero stays zero, including between a composed row's children.
Cross-axis proposal changes still invalidate measurements.

GTK and WinUI request a bounded viewport window
together, then replace its estimates with the mounted rows' measurements.
WinUI rechecks coverage after that render: newly measured tall rows may
reduce the requested range, and shorter rows may extend it. It does not run
a growing render and native arrangement for each unknown row. Look-ahead
and neighbour policy still bound realization; nothing requests the entire
source merely because its rows have no measurements yet. The actual window (or
a program jump's destination) is synchronous demand. A window the mounted
rows do not cover is demand as well: its rows are asked for in the turn that
asked, not left to the optional units of later frames. Only a window they
already cover is narrowed to its demand. A viewport of optional
neighbours on either side is prefetched on the UI thread in single-row (or
single-grid-run) units, only while time remains in the frame's four millisecond
work budget after visible rendering. A builder cannot be preempted; the deadline
is checked between units. Ready owners rotate within the same frame. A WinUI
owner stands optional work unless a change is still waiting for its rows,
and yields it then: that work is what fills the window ahead of a moving one,
and yielding until every mounted row has been measured yields exactly while
the window moves - the frames of a fling. A row mounted before its own
measurement arrives stands at its estimate, and the pass that follows corrects
it. New sources, direction changes, jumps and detach cancel or replace
stale work. Native layout and paint retain the rest of the frame. Images still
load synchronously when their row is requested.

Viewport-only reconciliation names retained source identities before
materializing content. Those rows reuse their rendered subtrees without
executing the row closure or constructing another view description. New
rows alone run their builders. Explicit ids and transparent fragments retain
their source identity independently of the ids mounted by the host.

WinUI records scroll and effective-viewport notices immediately and coalesces
their realization outside the native callback/layout stack. Program jumps can
still prepare their destination synchronously when measurement is allowed;
before the first effective-viewport notice, an attached scroller's allocated
room seeds the initial window even if WinUI reports a zero viewport. A jump
deferred by a native pass keeps its target until the pass completes.
It does not replace rows inside native measure or arrange. Pending work keeps
the frame clock held and can resume on the next composed frame as well as a
dispatcher turn.
It waits for requested fragments to commit before interpreting missing
native children as empty content, then arranges the resulting window once.
GTK and WinUI source changes keep surviving rows'
measurement caches. Their native revisions, placement values and cross-axis
proposals decide which rows need fresh measurement. A patch inside a mounted
row - a hover, a word, a spinner - is no source change: the run keeps every
measurement it holds, measures again the rows whose own view moved, holds no
mounted row as travelling and animates nothing for it. Costing the whole
window is what makes a hover, or one folder opened, cost what every folder
opened so far costs.

The mounted lazy element versions its shared identity snapshot separately from row
content. Viewport changes and drawing/row feedback do not read, compare or
rebuild the full identity index. Actual identity changes still require a source
scan; that scan is metadata work and does not build offscreen views. Settling
child patches uses identity tables rather than a nested linear search.
WinUI's ideal-size and window minimum-size queries read committed row
geometry. Native preparation at the selected width, or viewport
reconciliation, measures mounted rows and updates extents and anchors. A
speculative grid track count uses its own estimates without replacing the
visible grid's tracks or measurements.
WinUI follows actual scroll offsets and releases rows behind its look-ahead
while scrolling; an animation endpoint does not widen the window to include
the whole path. Program jumps realize the destination before the native move.
Scroll notices supply the actual window for anchor selection as well as row
realization. A later layout notification reads that current native position
and updates the clipped dimensions, rather than restoring an older offset.
Anchor corrections update both records; program-jump preparation keeps its
future target separate from the actual anchor until the native move.
An empty fragment is a zero-size row once its requested render has committed.
Zero-size rows leave unseen rows' 44-point estimates intact, so an empty
header cannot hide all the cards behind it.

A source insertion can move an existing row's destination outside the requested
window while its presentation remains on screen. Hosts retain those already
mounted, travelling identities until their placement journey ends, then release
them on the next viewport reconciliation. They also retain surviving mounted
rows for the first changed arrangement. These extra identities are requested
individually in source order; unbuilt rows between them and the viewport are
not realized. The normal bounded range still controls new initialization.

A run with no scroller to narrow it - a first mount, a re-parenting - told the
tree to build every row, and keeps that window only until a scroller clips it:
the window is taken again the moment one does, and the run narrows back to the
rows in reach. A window standing for the whole source would leave every row
built for good, and every later patch, hover and row measure costing what the
whole source costs. The identities a run asks to keep are the ones it still
holds a place for: a row the source has dropped is not retained by a placement
journey it has already left.

A row's own measure is kept beside the proposal it was taken at, and the row is
measured again only where its proposal, its view or its room has changed. A room
that returns - the bar toggling a scroller's cross size brings the last one
back, a scroller's own axis changes nothing - costs no measure at all, while the
arithmetic's extents, which are the room's, are taken again.


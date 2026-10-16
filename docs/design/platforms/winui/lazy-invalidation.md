# Lazy row updates and layout inputs

## Evidence and limits

The local arm64e SwiftUICore image was disassembled with `xcrun dyld_info
-uuid -disassemble /System/Library/Frameworks/SwiftUICore.framework/Versions/A/SwiftUICore`.
Its UUID is `641D6FF5-405D-3C0B-9F98-2D8524FC484B`. Addresses below belong to
that image, not to a stable API. This reads machine code; it does not run the
application, compile the package, or measure application performance.

The specialized dynamic body path for `Rectangle.AsymmetricalInset` calls
`_DynamicPropertyBuffer.update(container:phase:)` at `0x2245FB160`. It combines
that result with other change/value checks. At `0x2245FB2CC`, `tbz w8, #0,
0x2245fb2e4` bypasses the call to `ViewBodyAccessor.updateBody(of:changed:)`
at `0x2245FB2DC`. This is concrete evidence of a body evaluation gate. It does
not establish the exact equality strategy of every view or constant-time
updates for arbitrary collections.

The Lazy stack stopping path at `0x2245CF8F4`–`0x2245CF914` compares either
floating-point coordinates or integer bounds. The edit finalization path at
`0x2251CF968` branches to load the stored result; the other branch calls
`ForEachState.EditsBuilder.finalize()` at `0x2251CF9BC` and stores its result at
`0x2251CF9E0`. These support bounded layout traversal and cached edit results;
they do not show how much of a particular application's frame time each saves.

## The WinUI amplification

Core already tracks state readers and can retain unaffected row descriptions.
That alone did not prevent WinUI from doing redundant work after a sparse
patch. `WinUIElement.applied` recollected layout items on its ancestors even
when a child changed only its paint. Reading an item's `layoutValues` recursively
read the mounted descendants of stacks and grids to derive scroll and expansion
axes. Reading the same descendants through several ancestors repeated this
work. Cost depended on mounted subtree size and depth, independently of whether
offscreen bodies had been evaluated.

WinUI now owns a cache of those resolved layout inputs. The shared mounted
tree provides a child-reading hook, with its original recursive behavior as
the default for other hosts. WinUI uses cached child values. Layout-affecting
properties and direct membership changes invalidate the affected ancestor
chain; paint and handler changes do not. Animation presentation and departure
changes invalidate the same dependencies. Native size caches remain separate:
for example, changed text still invalidates measurement even though its
`LayoutValues` need not change.

Direct child order changes are distinguished from descendant updates. Ordinary
WinUI stack/grid/Lazy layouts reuse their layout item list for paint-only
patches. Lazy still consumes content revisions and request acknowledgements
on that path, so skipping item collection cannot strand a viewport request.
Specialized controls, custom layouts, and navigation keep their existing
child-update paths.

An existing row's changed geometry also marks the next Lazy placement as a
content change. It may animate only under the existing explicit motion law;
setting this flag does not supply an animation to ordinary hover updates.
When no native scroller relationship is installed yet, a declared same-axis
ScrollView prevents the temporary absence of that relationship from requesting
every row through `tellAll`. A later measure/arrange or viewport event establishes
the normal visible request. A truly unbounded Lazy container retains `tellAll`.

## Native ownership and premature arrangements

A promoted top safe-area bar has two owners: its logical layout supplies the
contribution, while a native toolbar host measures the actual control. Its
size invalidation must reach both. SplitView pages also have a native owner
outside `placingLayout`; intrinsic changes now request that owner's arrangement,
not only child replacement. This notification lives at the ownership boundary
instead of walking to the root again for every `setItems` call. Lazy retains its
existing measurement boundary.

Promoted bars register their drawing dependencies on logical ancestors. Opacity,
blur and transform updates notify that small set directly instead of searching
the entire mounted descendant tree on every animation frame. Releasing a bar
removes the registration. Ordinary rows with no promoted bars do no descendant
search for this purpose.

A WinUI Lazy Arrange can run before a requested window is acknowledged or its
new rows are measured. Stack/grid arrangements now keep their pending motion
and insertion markers across that intermediate pass, and a pass with no change
waiting is never held back. Only a ready arrangement consumes them.

Core now counts a lazy column or grid among the layouts that say how their
children animate (`NodeType.places`), so a write inside `withAnimation`, or a
query's own timing, reaches the lazy element at all; the host keeps that law
until the arrangement that can place the rows the deferred realization adds.
Inserted rows therefore fade in and their neighbours travel under the change's
own timing, instead of every row arriving at once. This does not supply
animation to an unanimated state write, nor does it change asynchronous
application loading into synchronous loading.

New regression code covers that intermediate Arrange, native ownership
invalidation, promoted-bar drawing, and a bottom editor's decoration/control
geometry across height and page changes. The bottom editor is not a promoted
top bar; the screenshots alone do not establish that both glitches have the
same cause. Independent JsonData tests cover URL/Bool state after reopening an
isolated store and after autosaving a fetched model. No persistence defect has
yet been established by source inspection, and none of these tests has run.

## Remaining differences and validation

This is dependency-based reuse in the WinUI host, not a reproduction of
AttributeGraph. Core still reconciles descriptions and emits host patches.
Initial identity discovery and actual structural edits may inspect the source
collection. Invalidating a layout dependency can still require visiting the
affected layout's mounted children; native creation, text measurement, and
Canvas drawing still cost work for newly visible rows. No O(1) claim is made
for folder expansion or every hover handler.

`WinUILazyInvalidationTests` covers hover after expanding and collapsing a
source from 100 to 10,000 rows, body and layout-input reuse, bounded realization,
derived expansion invalidation, and explicit motion with unchanged row IDs.
Existing native Lazy tests cover structural insertion/removal, scrolling,
spacing, and drawing. These tests were written/reviewed but not run. Runtime
latency, folder transition appearance, and fast-scroll blanking still require
Windows validation; disassembly cannot establish their improvement.

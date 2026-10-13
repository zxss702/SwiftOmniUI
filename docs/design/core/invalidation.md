# Invalidation

A write to a state rebuilds exactly the closures that read it. The fallback -
run the application's closure in full and diff the result - is always correct,
but for a large tree it builds every page so one label can change. The clean
walk needs two facts recorded as they happen.

## Two facts

```text
  reads     while a body or a container's content is built, every state it
            reads is recorded against THAT element (ReadScope, Core/Invalidation)
  changes   every write names the state it wrote (Renderer.stateChanged)

  tracked render: branch.subtreeReads ∩ changed = ∅ -> keep the whole branch
                  element.reads ∩ changed ≠ ∅       -> build that element again
                  otherwise                         -> walk toward changed readers
```

The identity in both is the storage, not the box. A `@State` box is rebuilt
with its view on every render and adopts its predecessor's storage, so the
storage is the one object that means "this piece of state" across renders. A
`@State` in a class has a storage of its own the same way, and a `Ticker` is
its own.

Each rendered element keeps the union of its build reads, its preference
transform reads and its children's settled branch indexes. A fresh node
builds that index once; a kept node refreshes it once after visiting its
changed descendants or realizing a lazy window. An unchanged row's controls
and preference folds are therefore not
walked again each time its lazy parent adds one more row. The union only
guides the walk; it does not add subscriptions to the renderer's live-reader
counts.

This pruning belongs to the tracked clean walk only. A full build, including
the subtrees it carries, still refolds preferences, because a host-pushed text
layout report can change an answer without writing a state. An explicitly
requested clean walk with no changed states keeps the same folding behavior.

## The reader is the closure that read

A read lands on the innermost open read scope. The differ opens one around
each build it runs - a composed view's body, or a bare container's content -
and a body constructs its children's placeholders, never their bodies. So the
reader of a state is the closure that read it: the innermost container whose
content did, or the body itself. Nothing outside that closure is built again
for it.

The scopes are a stack, although builds do not nest across elements in a
render, because a structural expansion in a test builds everything eagerly.

## Reads from other threads

`ReadScope.note` runs on every read of every state in the process, almost all
of them from handlers with no scope open, so the empty check is a relaxed
atomic load of the depth rather than a pass through the lock. The thread that
opens and closes scopes is the thread that renders, so a read there always
sees the truth. A pool thread may see a stale depth, and either way is
harmless: noting a read over-records a dependency, and skipping one records
nothing a pool-thread read was entitled to.

## Erring toward rebuilding

Every piece of the bookkeeping errs toward building too much, never toward
skipping: a recycled `ObjectIdentifier`, a read recorded from a pool thread
mid-render, a state read in a branch the body did not take this time. Each can
only add a dependency or a change that was not strictly needed, and the cost is
a subtree built and diffed for nothing. A dependency missed would be a frozen
interface. Writes therefore always land, and anything that cannot name what
changed falls back to the full build.

## Live readers

Each rendered element counts itself as a reader of what it read, for as long as
it lives: `RenderedNode.init` adds its reads to the renderer's count and
`deinit` takes them away. The root build counts what it read outside every
element. A write to a state no live element reads cannot change the screen, so
it asks for nothing - no dirty tree, no wake - and is counted in the tally's
`refused` column.

A regular build that read something else makes a new element. A kept lazy
source can add dependencies as its window builds new rows; changing its own
`reads` adjusts the live counts by the added and removed identities. The
branch index is refreshed after that window's reconciliation settles.

Preference transforms execute after the children have settled, in a separate
observed read scope. Their dependencies participate in the same branch index
and live-reader counts, but do not cause an unchanged body to rebuild. A
refold replaces this scope's reads and observation tokens rather than retaining
every previous fold. Nodes without transforms create no additional scope.

The focus store likewise refolds and compares its chain only while a live
`@FocusedValue` or `@FocusedSceneValue` reader can hear it. With no reader it
marks its cached answers dirty and defers the fold until the first later
read, which sees the latest rendered tree.

A state's own `readAtBuild` flag spares even the call to the renderer: a state
no build ever read has no reader to find. The flag is sticky - a state read
once and then abandoned goes on asking and is refused - which is the cheap
direction; what it makes free is a carried value nobody ever prints, written
forty times a second.

## Writes during a render

An element is counted as a reader when it is made, which is after its build
has read. A write landing between the read and the count would find no reader
and be dropped for good. So while `rendering` is set, every write goes on the
books unasked; the render that follows walks to nothing at worst.

## Why a view is described

`debugInfo()` answers which view is being described, how many times, and why,
in the author's own names. The differ already has the three facts within
reach and hands them to `BuildScope`:

```text
  the view     the composed view whose body, or whose container's content,
               is running now
  how often    how many times THIS element has been described, kept on the
               element so it survives renders that leave it alone
  why          the states this element read last time that were written since -
               the intersection the walk decided by
```

Nothing is computed until asked: the frame carries the two sets and the
intersection is taken inside `debugInfo()`, so a render nobody watches pays
for a counter and two assignments.

A state is named by the path the reflection walk reached it by - the author's
property name - which is the same path that pairs it with its predecessor. A
`@State` inside a class is named on the first touch of the model, and a state
nobody owns, such as a ticker, is named by its type.

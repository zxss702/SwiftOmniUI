# Diagnostics

Two instruments tell what the core is doing without changing it: the tally
of renders and live elements and the inspector's record of each render.
`debugInfo()`, which explains a single build in the author's names, is in
invalidation.md.

## The tally

```text
  renders    how many renders this process made
  empty      how many carried no patch - a write that changed no property
  refused    how many writes asked for nothing, because no live element read
             the state (invalidation.md)
  alive      how many rendered elements are alive now
```

`empty` is how a write that should have asked for nothing is found; `refused`
is the other half, what counting live readers spared beside what got through.
`alive` is counted in as each rendered element is made and out as it goes, so a
page that was left and still stands in memory shows as a number that does not
come back down. It tells a leaked page from memory the allocator has not handed
back yet, which a process's resident size cannot. A host reads the tally
through `HostBoundary.tally` and the per-cycle trace through
`HostBoundary.cycleTrace`, built only when the host's trace switch is on: this
side has no environment to read.

## The inspector

While an inspector records, the renderer opens a pass around every render and
the differ writes an entry for every composed view it reaches:

```text
  pass    road (walk, build, complete), causes in the author's names,
          microseconds describing, and the host's half: applying, per scene
          too, and the controls walked, made and kept
  entry   built  - with the reason it could not be carried
          carried - whole: not built, not compared, not sent
          walked  - only as the path to a view below it that was built
          each with its inclusive and its own time
```

Nothing runs while nobody looks: every hook in the differ is one read of
`recording`, false until an inspector opens, so an application that never opens
one pays a branch per composed view. Closing the inspector stops recording.
Passes can be formatted on demand without enabling automatic log output.

The inspector is not its own subject. It is a tree like any other, built again
whenever a pass lands, so its own views are muted - their time is kept apart and
they write no entries - and a pass caused by nothing but its own state, or one
that built nothing but its own views, is not kept, whichever road it took.
Otherwise every pass would record the inspector drawing the pass before it,
and after a failed apply a complete render the inspector kept would ask it to
draw again, for good.

A pass keeps at most `most` entries, and the record keeps the last `kept`
passes; the host's report is matched to its pass by generation.

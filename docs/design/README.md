# Design notes

The reasons behind SwiftOmniUI's code. A comment in the code says what a
declaration is in a line or three; the reason it is shaped so, the trap it
avoids and the rule it keeps are here, in the present tense.

## The golden rule

Comments stay under a quarter of every source file's lines; everything else
is a design note. The `///` documentation of a public declaration - what an
editor shows the developer on `.` - is not counted: it gives enough to choose
and use the declaration, and leaves how it works inside to these notes.

Where the code wants its reason, one line points here:

```text
/// Design: docs/design/<area>/<note>.md#<section>
```

The section is the heading's anchor: lowercase, letters and digits kept, each
run of spaces or hyphens one hyphen. `DesignNotesTests` checks that every
reference resolves, and holds the golden rule for every directory that meets
it.

## The notes

- [Architecture](architecture.md): the packages, one change end to end, and
  the threads, drawn.
- [Glossary](glossary.md): SwiftOmniUI's words and the common term for each.
- [`core/`](core/README.md): the core drawn - a state write to a patch, the
  display cycle, the UI thread and the typed boundary - and the reasons of each part.
- [`views/`](views/README.md): how an application's views become the
  described tree - composition, builders, modifiers, bindings, pages, styles.
- [`types/`](types/README.md): the values an application passes and how
  each reaches a host.
- [`contracts/`](contracts/README.md): how an element contract declares a
  node type, its tiers and its members, and who reads it.
- `host/`: the runtime every host shares - [the runtime](host/runtime.md),
  [the mounted tree](host/tree.md), [pages](host/pages.md), [layout](host/layout.md),
  [animation](host/animation.md), [patches](host/patches.md), and
  [conformance](host/conformance.md), the suite every host runs.
- `platforms/`: each platform's half of its runtime, one folder a platform.
  `platforms/android/`: [the runtime](platforms/android/runtime.md),
  [JNI](platforms/android/jni.md), [layout](platforms/android/layout.md),
  [controls](platforms/android/controls.md), [animation](platforms/android/animation.md),
  [drawing](platforms/android/drawing.md), [pages](platforms/android/pages.md),
  [conformance](platforms/android/conformance.md).
  `platforms/winui/`: [the relay](platforms/winui/relay.md),
  [the runtime](platforms/winui/runtime.md), [controls](platforms/winui/controls.md),
  [drawing](platforms/winui/drawing.md), [input](platforms/winui/input.md),
  [interop](platforms/winui/interop.md), [layout](platforms/winui/layout.md),
  [animation](platforms/winui/animation.md),
  [pages](platforms/winui/pages.md), [conformance](platforms/winui/conformance.md).
  `platforms/gtk/`: [the C API](platforms/gtk/c-api.md), [the runtime](platforms/gtk/runtime.md),
  [controls](platforms/gtk/controls.md), [drawing](platforms/gtk/drawing.md),
  [input](platforms/gtk/input.md), [interop](platforms/gtk/interop.md),
  [layout](platforms/gtk/layout.md), [animation](platforms/gtk/animation.md),
  [pages](platforms/gtk/pages.md).

## Writing a note

A note describes the current design: what it is, why, and what breaks if it
changes. It names no earlier design and no other product. Diagrams are text in
`text` blocks, so they read the same in an editor, in a diff and on the web.

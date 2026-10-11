# Contributing to SwiftOmniUI

SwiftOmniUI is one platform-neutral Swift model with independent native hosts.
Changes should make that model smaller, clearer, and more deterministic.

## Begin with evidence

Reproduce the behavior before changing it. A testable defect should have a
failing test that states the invariant. A native rendering or interaction issue
also needs a live Gallery check on the affected toolkit; a green core suite
proves only the contract it exercises.

## Change one vertical slice

A control, property, or event decision reaches every active layer together:

- Swift API and vocabulary;
- `HostContract` ownership;
- every applicable host;
- focused core and host tests;
- the Gallery, on every host the change reaches;
- the handbook (`README.md`, `docs/`, and public `///` documentation).

Update `docs/platform-contract.md` in the same slice. Add `✅` only when the
control or complete member group is implemented and exercised by that host's
tests; absent, partial, and unverified support stays unmarked.

Remove obsolete API, examples, and tests when the contract deliberately drops
the capability. Do not preserve aliases unless compatibility is an explicit
requirement.

## The public API is a SwiftUI subset

Anything SwiftUI has a model for keeps SwiftUI's name and semantics:
`App`, `NavigationSplitView`, `List`, `.fileImporter`, `.onAppear`. Where a
platform-neutral application needs what SwiftUI does not model, the addition
extends the same conceptual model - `application.persistentKeys` through
`@Environment(\.application)` is the shape of it. Vocabulary with no SwiftUI
equivalent - `ItemsView`, `SplitView`, `Dialogs.openFiles` - lands internal or
`@_spi(Host)`, never as the public name.

## Keep the core platform-neutral

Code under `lib/SwiftOmniUI/Sources` and `lib/SwiftOmniUI.Host/Sources` does not
import Foundation or a platform UI framework. Each host is a sibling package of
its own - `lib/SwiftOmniUI.Android`, `lib/SwiftOmniUI.WinUI`,
`lib/SwiftOmniUI.GTK`, `lib/SwiftOmniUI.Web` - standing on the host layer, with its build in
`.scripts/<Platform>`. Swift written for one host alone stands under that
host's condition - `#if ANDROID`, `#if WINUI`, `#if GTK`, `#if WEB` - which
its builds define.

The core schedules nothing on Foundation's `Timer` or `RunLoop`, or on
`DispatchQueue.main`: nothing drains them on Android or Windows. Work for the
UI thread goes to `MainActor`, and a timer is `Task.sleep` or `Ticker`. Memory
allocated in Swift is freed in Swift - never `strdup` and `free` - because
several C runtimes can share a Windows process.

Swift owns identity, diffing, state, journeys, and motion descriptions. Hosts
own native objects, platform callbacks, and display-frame property motion. Keep
renderers thin and derive richer behavior from SwiftOmniUI primitives where that
produces one honest cross-platform contract.

## Write current documentation

README, `docs/`, and public API documentation are the handbook. Describe what
SwiftOmniUI is now, why the current rule exists, and any current trap. Do not
narrate migration history or explain the API by comparison with another
framework.

Every public Swift declaration needs `///` documentation. Gallery pages use
minimal on-screen prose: show behavior directly and tell the user only what
they need to try.

## Test

Run the suite owned by the area while iterating, then every suite before
handing off a complete vertical change. In VS Code, run **SwiftOmniUI: Run Tests**
once per host the change reaches. From a terminal, `swift test` runs the core
suite on Linux, `xvfb-run` the GTK host's on a screen with no monitor, and
`.scripts/Android/test-android.sh <serial>` the Android host's on a device:

```bash
swift test
xvfb-run -a swift test --filter SwiftOmniUIGTKTests
.scripts/Android/test-android.sh emulator-5554
```

A plain `swift test` compiles no code under a host's condition, so it does not
test any host's half on its own.

Run the Gallery with **SwiftOmniUI: Debug** on each host the change reaches. From a
terminal:

```bash
.scripts/GTK/run-app.sh apps/Gallery debug
.scripts/Android/run-app.sh apps/Gallery debug emulator-5554
```

Run one application build at a time. Concurrent application builds share Swift
object directories and can silently execute stale output.

Open every pull request against `dev`, never `main`: `main` takes only the
releases merged from `dev`. A pull request runs the suites on `Windows` and
`Linux` - macOS serves development only; no suite runs on it.

## Keep changes reviewable

Every source under `lib/` starts with the project's two SPDX lines, apart from
the documented `Package.swift` exception. Preserve unrelated worktree changes;
they belong to their author.

A commit message is a short declarative sentence describing what is now true.
Do not include generated-by text or authorship trailers.

## Contribution terms

SwiftOmniUI is distributed under the Apache License 2.0. A submitted contribution
is accepted under the terms of the current [SwiftOmniUI contributor agreement](CLA.md)
as well as the project's source license. The first pull request from a
contributor triggers the repository's electronic CLA record; do not include
work owned by another party unless its source, license, and submission authority
are stated as required by that agreement.

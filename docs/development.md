# Project structure and development

## Repository layout

```text
Package.swift                      all SwiftOmniUI targets, products and test entry points
Sources/SwiftOmniUI/             the facade `import SwiftOmniUI` lands on
lib/SwiftOmniUI/Sources/               platform-neutral SwiftOmniUI core
lib/SwiftOmniUI/Tests/                 core tests and shared test support
lib/SwiftOmniUI.Host/                  the host layer every host stands on, and its tests
lib/SwiftOmniUI.Conformance/           the conformance suite every host's tests run
lib/SwiftOmniUI.Android/               Android Views host target, its Java layer and tests
lib/SwiftOmniUI.WinUI/                 WinUI host target, its C++/WinRT relay and tests
lib/SwiftOmniUI.GTK/                   GTK host target, Swift over GTK's C API, and tests
lib/SwiftOmniUI.Web/                   Web host target over WebAssembly
lib/SwiftOmniUI.VSCode/                the editor extension
.scripts/Android/                  Android Views builds, runs, devices and tests
.scripts/WinUI/                    WinUI builds, runs and tests, and the Windows App SDK
.scripts/GTK/                      GTK builds and runs
apps/Gallery/Sources/              platform-neutral Gallery application
apps/Gallery/Platforms/Android/    Gallery Android head
apps/Gallery/Platforms/WinUI/      Gallery WinUI head
apps/Gallery/Platforms/GTK/        Gallery GTK head
apps/Gallery/Platforms/Web/        Gallery Web head
apps/Gallery/Tests/                Gallery acceptance tests
apps/HelloWorld/Sources/           small platform-neutral example application
apps/HelloWorld/Platforms/Android/ HelloWorld Android head
apps/HelloWorld/Platforms/WinUI/   HelloWorld WinUI head
apps/HelloWorld/Platforms/GTK/     HelloWorld GTK head
apps/HelloWorld/Platforms/Web/     HelloWorld Web head
```

The core and the host layer never import Foundation or a platform UI
framework. App code may import Foundation. Platform frameworks remain inside host targets and
platform entry points.

Swift written for one host alone stands under the condition named for it:
`#if ANDROID`, `#if WINUI`, `#if GTK` and `#if WEB`, which every build of an
application for that host defines through its manifest, from
`SWIFTOMNIUI_HOST=android`, `winui`, `gtk` or `web`. `NativeProjectTests` refuses
any other mention of a host in the library and in the applications'
`Sources/`.

`SWIFTOMNIUI_HOST=gtk` is what makes a build a GTK one. An application's
manifest reads it and then declares the `Platforms/GTK` target, the product
it makes and the `SwiftOmniUIGTK` dependency, and defines `GTK` for every
module of the application. A manifest cannot read a compiler flag - a flag
reaches the targets of a build, never the manifest describing them - so no
`-Xswiftc -DGTK` is given beside the variable. Without it, `swift test`
declares no platform host target and compiles no line of one host's half, and a
`Platforms/GTK/` folder needs no condition inside it.

The host's own scripts set the variable for a build. The editor gets it from
the SwiftOmniUI extension (`lib/SwiftOmniUI.VSCode`):
choosing GTK in its status bar sets the variable for the Swift language
server and restarts it, which then resolves `Platforms/GTK` and completes the
code inside `#if GTK`, with no window reload. A
`swift.swiftEnvironmentVariables` setting naming the variable would override
that choice, so `.vscode/settings.json` sets none.

## Gallery

Gallery is the acceptance surface for the element contracts. Its examples
show behavior directly and keep on-screen prose to a title and, when needed,
one short instruction.

Across the catalog, applicable examples prove:

- a state read rebuilding only its reader;
- a host-carried binding updating without that rebuild;
- `Journey` and host-side animation.

Detailed teaching belongs in the Markdown documentation and public `///`
comments. A sample outside the active contract does not remain in the catalog.

### Adding a sample

A sample is a `SampleContent` under
`apps/Gallery/Sources/Samples/<Group>/`. Register it once in
`apps/Gallery/Sources/Gallery/Catalog.swift`; group pages, navigation, and the
home count derive from that catalog.

Keep the visible example and its `code` listing equivalent. The listing is the
smallest usable expression of the behavior: include state and helpers it names,
but leave Gallery-only decoration out. Give the sample a unique stable id and a
short title. Its summary is one instruction or result, not a second handbook.

A sample that owns vertical scrolling or a continuous drag must own its page
viewport; do not nest it under the page's scroller. Boolean choices are
switches and momentary actions are buttons. Add group artwork only when a new
contract category genuinely needs a group; resources and catalog reachability
are checked by `GalleryTests`.

## Changing the public contract

Treat one control, property, event, or host action as one vertical change:

1. Decide its cross-platform semantic name and ownership.
2. Add or change the public Swift declaration and its `///` documentation.
3. Declare the member in its element's contract - its name, its value's type
   and its layer; its host-SPI token follows from the member.
4. Decide what of it every host shares and write that part in the host layer
   first, with its pure tests ([host layer](internals/host-layer.md)); then implement
   every host claimed by the change, keeping native adapters thin.
5. Add focused core tests and direct native-host tests, and a conformance case
   where executing the contract shows the effect.
6. Add or update the smallest Gallery demonstration and handbook section.
7. Let the host say what it realizes, only after its tests pass. A member a
   registration takes or raises records itself: with `SWIFTOMNIUI_UPDATE_EXPORTS=1`,
   `SWIFTOMNIUI_HOST=gtk swift test --filter SwiftOmniUIGTKTests` and
   `.scripts/Android/test-android.sh <serial>` write `exports/gtk.txt` and
   `android.txt`, and the contracts name each member's owner when the
   documents are rendered. What a registry cannot know stays written by hand,
   in `GTKRealization` and `AndroidRealization` - every judgement: a partial
   record saying what is missing, what a host realizes none of, and what it
   presents with no view of its own.
   Then `SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests`
   writes `docs/controls/` and the tables of `platform-contract.md`.

Removing a capability follows the same path: remove stale vocabulary, host
branches, tests, samples, and documentation together. Do not leave an inert
modifier or compatibility alias unless compatibility is itself an explicit
contract.

## Build

Build the smaller example as a GTK application:

```bash
SWIFTOMNIUI_HOST=gtk swift build --package-path apps/HelloWorld --product HelloWorldGTK
```

In VS Code, the SwiftOmniUI extension (`lib/SwiftOmniUI.VSCode`) runs either
application: "SwiftOmniUI: Debug" and "SwiftOmniUI: Release" build and start the one
chosen in its status bar, on the host chosen there; installing it is under
[Working in VS Code](getting-started.md#working-in-vs-code).

The Android Views host builds on macOS with the swift.org toolchain, the Swift
SDK for Android, the NDK r30 and JDK 21. An application's Android head is
built, installed and started on a device by one script:

```bash
.scripts/Android/run-app.sh apps/HelloWorld debug emulator-5554
```

[Android Views host](hosts/android.md) lists what it needs and what it builds.

The WinUI host builds on Windows with the swift.org toolchain and Visual
Studio's C++ tools; its script fetches C++/WinRT and the Windows App SDK
itself. An application's WinUI head is built and started by one script:

```powershell
.scripts\WinUI\run-app.ps1 -App apps\HelloWorld
```

[WinUI host](hosts/winui.md) lists what it needs and what it builds.

The GTK host builds on Linux with the swift.org toolchain, GTK 4 and
libadwaita. An application's GTK head is built and started by one script:

```bash
.scripts/GTK/run-app.sh apps/HelloWorld
```

[GTK host](hosts/gtk.md) lists what it needs and what it builds.

## Test

Each suite keeps its sources beside its module and runs from the root package:

```bash
swift test
swift test --filter SwiftOmniUIHostTests
swift test --filter SwiftOmniUIConformanceTests
SWIFTOMNIUI_HOST=gtk swift test --filter SwiftOmniUIGTKTests
swift test --package-path apps/Gallery
```

The first suite covers core semantics and the typed boundary. The host
layer's suite proves the rules every host shares, pure, with no toolkit. The
conformance target's own tests prove its runner and that every member has
its case; each host's suite runs the cases themselves. The GTK suite drives
native GTK objects. The Gallery's treats Gallery as application behavior
and compiles the documentation examples. In VS Code, **SwiftOmniUI: Run Tests**
runs them as the chosen host.

The Android Views host's suite runs on a device, in a test APK:

```bash
.scripts/Android/test-android.sh emulator-5554
```

The WinUI host's suite runs on Windows, the Windows App SDK laid beside its
test runner first:

```powershell
.scripts\WinUI\test-winui.ps1
```

The GTK host's suite runs on Linux, in a desktop session whose display shows
its windows:

```bash
SWIFTOMNIUI_HOST=gtk swift test --filter SwiftOmniUIGTKTests
```

A passing unit suite does not prove native drawing or interaction. Exercise a
user-visible change in the running Gallery on the affected platform. Run only
one application build at a time because Swift build directories are shared by
the package graph.

On GitHub each suite has a workflow of its own, so each shows its own state,
the core apart from the hosts: **Core Linux** and **Core
Windows** (`build-linux.yml`, `build-windows.yml` - the core,
the host layer, Foundation and JsonData bridges, and the conformance runner),
and one for each host - **Android** (the test APK built on macOS, run on a
Linux emulator), **WinUI** and **GTK**.
A host's workflow holds every conformance verdict to its marks and never
writes them: a family whose verdicts changed fails there, and its marks are
written again on that platform's machine.

## What the tests hold

The core's tests assert on the typed patch a host is handed, each by the rule
it keeps - one changed number sends one property of one label, every control
carries only the members its contract declares - rather than comparing it
with a stored copy. A failing assertion names what changed and why it
matters; a deliberate change updates the assertion that states it.

The documentation examples are another executable check. Every exact
`swift` fence in `README.md` and `docs/` is type-checked by Gallery tests.
Mark a deliberately partial declaration or manifest as `swift quote`; keep
copyable application examples as plain `swift` so API drift fails visibly.

## Distribution boundary

The repository-root `Package.swift` declares core, Host, Foundation, JsonData,
platform hosts, WebView backends and test targets. Sources remain under `lib/`;
these directories have no child package manifests. Modules depend directly on
one another as targets and expose ordinary library products to consumers.
`SWIFTOMNIUI_HOST` selects the platform targets, including cross-compilation.
Foundation and JsonData bridging remain separate from the Foundation-free core.
JsonData is one external package dependency using its ordinary `JsonData` product.

Gallery and HelloWorld keep their application packages and consume SOUI products
from the root. Application dynamic products and final Android JNI libraries
retain their deployment roles; internal SOUI modules have no dynamic boundary.
An application's other dynamic dependencies still require actual link and runtime
verification before claiming that a process has one copy of a protocol.

A release has one version, stated in the editor extension's
`lib/SwiftOmniUI.VSCode/package.json`. Every other place that names it - the
published-package line in each application `Package.swift`, each Android head's
version, the bug report's example - names the same one, and
`ReleaseTests` holds them to it.

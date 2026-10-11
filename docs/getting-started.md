# Getting started

SwiftOmniUI applications keep their interface and application state in a
platform-neutral Swift module. A small native executable imports that module
and the selected host module. The same application module can therefore be
started by another host without changing its view tree.

Four native hosts are active - Android Views, WinUI 3, GTK 4 and Web - each
Swift, in the application's own process. The supported setup is a
SwiftOmniUI checkout: one root package declares the core and all host targets.
Applications select its products, and `SWIFTOMNIUI_HOST` selects the platform
targets without changing module names or imports.

## Requirements

- a checkout of this repository;
- VS Code and Node.js 20 or newer, for the SwiftOmniUI extension.

[Android Views host](hosts/android.md#requirements) lists what the
Android Views host needs, [WinUI host](hosts/winui.md#requirements) what the
WinUI host needs on Windows, and [GTK host](hosts/gtk.md#requirements) what
the GTK host needs on Linux.

With the extension installed ([Installing the extension](#installing-the-extension)),
**SwiftOmniUI: Check Toolchain** in the Command Palette looks on this machine for
what these pages list for its platform's hosts, and says what to install for
whatever is missing.

## Working in VS Code

VS Code is where SwiftOmniUI applications are built, run, debugged, and tested. The
SwiftOmniUI extension in `lib/SwiftOmniUI.VSCode` chooses the host and the application
once, and everything after that - the editor's completion, the launches, and
the suites - works as that host.

### Installing the extension

The extension is built from the checkout. From the repository root:

```bash
cd lib/SwiftOmniUI.VSCode
npm ci
npm run package
code --install-extension ../../artifacts/swiftomniui-*.vsix
```

`npm run package` writes `swiftomniui-<version>.vsix` into `artifacts/` at the repository root.
Without the `code` command on the path, use **Extensions: Install from VSIX…**
in the Command Palette and pick that file. Build and install it again after
pulling changes to the extension.

The extension installs the **Swift** extension (swiftlang) with it. Install
**LLDB DAP** for the Swift debugger.

### Running an application

Open the repository folder. The status bar shows two SwiftOmniUI items:

- **the host** - GTK on Linux, WinUI on Windows, Android or the Web on macOS.
  The editor works as that host: code under `#if GTK` is completed only while
  GTK is chosen, and as Android the language server compiles for Android with
  the Swift SDK for Android. Switching restarts the Swift language server
  without reloading the window.
- **the application** - Gallery, HelloWorld, or any other under `apps/`. It is
  remembered for the workspace.

While the host is Android a third item shows the device: an attached phone or
a running emulator, or an emulator started when it is picked.

Press **F5** to run **SwiftOmniUI: Debug**, or choose **SwiftOmniUI: Release** in Run
and Debug. On GTK and WinUI the application's head is built and started under
`lldb-dap`. On Android it is built, installed and started on the chosen device,
and its terminal follows the application's log; a Debug launch then attaches
`lldb-dap` to it, and a Release one runs without a debugger.

`.vscode/launch.json` holds only those two launches. The extension resolves
each one into the chosen host's own debugger.

### Commands

The Command Palette offers the rest under **SwiftOmniUI:**

| Command | What it does |
| --- | --- |
| Select Host | the hosts this machine offers, as the status bar item does |
| Select Android Device | the device or emulator an Android head runs on |
| Select App | the application F5 runs |
| Run Tests | the workspace's suites, run as the chosen host |
| New App in apps/ | a new application beside Gallery and HelloWorld, made by `.scripts/new-app.sh` |
| Clean Index | removes the language server's index and builds it again |
| Check Toolchain | what this machine has of what its hosts need, and what to install for the rest |

The extension's own README, `lib/SwiftOmniUI.VSCode/README.md`, describes each of
them in detail.

### From the command line

Every launch has a command-line equivalent. Build HelloWorld's GTK head from
the repository root:

```bash
SWIFTOMNIUI_HOST=gtk swift build --package-path apps/HelloWorld --product HelloWorldGTK
```

The variable is what makes it a GTK build: the manifest then declares the
GTK head and defines `GTK`, and without it `swift test` compiles no part
of one host's half; see
[Project structure and development](development.md).

Run HelloWorld's Android head on a device - `.scripts/Android/devices.sh list`
names the devices:

```bash
.scripts/Android/run-app.sh apps/HelloWorld debug emulator-5554
```

A new application is HelloWorld under another name, with every head
HelloWorld has. This makes `apps/Notes` (`.scripts/new-app.ps1 -Name Notes`
on Windows):

```bash
.scripts/new-app.sh Notes
```

## App shape

Every application follows one structural path:

```text
App -> Scene -> WindowScene -> Page -> View
```

Each type declares exactly one composition property. Runtime properties such
as styles, window title, geometry, and page title belong to session objects in
the environment.

```swift internals
struct NotesApp: App {
    var body: some Scene { NotesWindow() }
}

struct NotesWindow: WindowScene {
    var page: any Page { NotesPage() }
}

struct NotesPage: View {
    @Environment private var page: PageSession
    @State private var note = ""

    var body: some View {
        VStack {
            Text(note.isEmpty ? "A new note" : note)
            TextField($note).placeholder("Write something")
        }
        .spacing(12)
        .contentPadding(24)
        .onAppear { page.title = "Notes" }
    }
}
```

`App`, `Scene` and `WindowScene` are declarations, not native objects, and
so is the view a window shows as its page. Their sessions carry the identity
and mutable runtime state.
[Applications and sessions](interface/application-and-sessions.md) describes that model
in full.

## Two modules and one registration point

An application has two concerns:

```text
NotesUI                     NotesGTK
------------------------    ---------------------------
imports SwiftOmniUI             imports NotesUI
App and scenes      imports SwiftOmniUIGTK
windows and pages           locates native resources
state and styles            starts the GTK host
no toolkit imports          contains no application UI
```

The UI module exports one stable registration function. Registration names the
application type to the host; it does not build native controls itself.

```swift internals
struct RegisteredApp: App {
    var body: some Scene { RegisteredWindow() }
}

struct RegisteredWindow: WindowScene {
    var page: any Page { RegisteredPage() }
}

struct RegisteredPage: View {
    var body: some View { Text("Hello, SwiftOmniUI") }
}

@_cdecl("swiftomniui_app_register")
public func swiftomniui_app_register() {
    stateUIUseApp(RegisteredApp())
}
```

The GTK executable registers the module and starts the host:

```swift quote
import NotesUI
import SwiftOmniUIGTK

swiftomniui_app_register()
SwiftOmniUIGTK.run(applicationID: "com.swiftomniui.notes")
```

Registration and `run` happen once per process. All scenes and windows then
belong to one application tree, renderer generation, and native host. Opening a
new scene does not start another host; it asks that host to materialize another
native scene session. [GTK host](hosts/gtk.md) describes that head.

The Android head calls the same `swiftomniui_app_register`
when Android loads its library; [Android Views host](hosts/android.md)
describes that head.

The repository examples use this directory shape:

```text
apps/Notes/
  Package.swift
  Sources/
    NotesApp.swift
    NotesPage.swift
    Styles/
  Platforms/
    GTK/
      main.swift
    Android/
      build.gradle.kts
      AndroidManifest.xml
      Swift/
  Resources/
    AppIcon/
    Images/
  Tests/
```

The application target depends only on the `SwiftOmniUI` product. The executable
target depends on the application target and `SwiftOmniUIGTK`. Both targets
enable `NonisolatedNonsendingByDefault`; [Concurrency](interface/concurrency.md) explains
why that module-wide setting is part of the application contract.

## Controls and modifiers

A control's purpose value belongs in its initializer. Optional capabilities
are modifiers:

```swift internals
@State var accepted = false
@State var volume = 0.5

VStack {
    Text("Playback")
        .fontSize(24)

    Slider($volume)
        .minimum(0)
        .maximum(1)

    CheckBox($accepted)
}
```

A binding form is two-way where the control owns an editable value. Passing a
plain value describes it in one direction. A handler reports a user or
platform action; an application write does not synthesize that event.

The active surface and per-host evidence live in
[Platform contract](platform-contract.md). Public API documentation beside a
declaration explains its focused semantics.

## Adding source and resources

SwiftPM discovers every `.swift` file below a target's `path`; a source list is
unnecessary. Add application files below `Sources/` and keep native entry
points below `Platforms/<Host>/`.

Image names are application data. Put image files under the resource directory
passed to the host and refer to them through `ImageSource` or a string-literal
file name:

```swift
Image("swiftomniui_tile.png")
    .frame(height: 120)
    .horizontalAlignment(.center)
```

The GTK head reads `Resources/` beside its own sources, and the Android
head's build draws `Resources/Images` into the application's assets and its
icon from `Resources/AppIcon`. SwiftOmniUI's core does not read a filesystem or
choose a platform image class.

## Next steps

Read [State and reactivity](concepts/state-and-reactivity.md) before building data flow,
then [Applications and sessions](interface/application-and-sessions.md) for navigation
and multiple windows. Run the Gallery whenever a feature's behavior is easier
to understand by using it than by reading about it.

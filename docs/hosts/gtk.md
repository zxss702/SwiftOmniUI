# GTK host

The GTK host renders a SwiftOmniUI application with GTK 4 and libadwaita on
Linux. It is Swift, in the application's own process, beside the application
module and the library: it applies the typed sparse patches of the
[host contract](../internals/host-contract.md) directly and calls GTK and libadwaita
through their C API, with nothing beneath it in another language.

It presents SwiftOmniUI's controls, arrangements and pages over the runtime every
host shares - the [platform contract](../platform-contract.md#control-creation) says
which, member by member. Each page stands under a header bar of its own that
slides with it, a sidebar beside the detail or over it in a narrow window,
tabs chosen by a switcher in the header bar, as GNOME's applications stand.
Opacity, sizes and transforms animate, a turn in depth included, a stack's
children travel to their new places, and a child the tree hides fades out
first. A layout paints its own box and cuts what it holds to it. It shows any
other control's name in red where the control belongs, so a gap is visible
rather than silent. It looks as the desktop's own applications do:
libadwaita's widgets, and the light or dark style the desktop is set to.

```text
lib/SwiftOmniUI.GTK/
  Sources/SwiftOmniUIGTK/        the host: its runtime, elements, registrations, layout and window
  Sources/CSwiftOmniUIGTK/       GTK's and libadwaita's headers, found by pkg-config
  Tests/                     the host's suite, run by swift test
.scripts/GTK/
  run-app.sh                 builds an application's GTK head and starts it
apps/<App>/Platforms/GTK/
  main.swift                 the application's GTK head
```

## Requirements

The host builds on Linux, on arm64 or x64:

- Swift 6.4 from swift.org;
- GTK 4.14 and libadwaita 1.5 or newer, with their headers and pkg-config -
  on Ubuntu 24.04 or newer, `libgtk-4-dev` and `libadwaita-1-dev`;
- gdk-pixbuf's SVG loader, through which GTK reads a vector picture -
  `librsvg2-common`, which a desktop has and a minimal system may not;
- a desktop session to show the windows in, the test suite's included.

## The head

An application's GTK head is an executable. Its `main` names the application
and hands the thread to the host, under the application's reverse-DNS name:

```swift quote
import NotesUI
import SwiftOmniUIGTK

SwiftOmniUIGTK.run(applicationID: "com.example.notes") {
    swiftomniui_app_register()
}
```

The name is the one the desktop knows the application by. GTK keeps one
instance of it: launched again, the running application activates or reopens
its first declared main window, preserving other windows. Only the primary
process invokes the initialization closure. Closing the last window exits
the process.

`SWIFTOMNIUI_HOST=gtk` is what makes a build a GTK one: the application's manifest
reads it, declares the `Platforms/GTK` target, the executable it makes and the
`SwiftOmniUIGTK` dependency, and defines the `GTK` compilation condition for every
module of the application. Swift written for this host alone stands under
`#if GTK`.

A new application made in `apps/` - `.scripts/new-app.sh` - has a GTK head,
as HelloWorld does.

## Controls, acts, and events registered in Swift

An application extends the host from its GTK head. Registrations run in
`run`'s initialization closure on the UI thread, before the first render;
registering before `run` remains supported. Registering a contract or an act again
replaces the earlier registration. Every registration is written against the
application's own contracts, so they are `public`: the host lives in a module
of its own and must see them. The Gallery's GTK halves are in
`apps/Gallery/Platforms/GTK/Host/`.

### A control

A control of the application's own is an object that makes and holds the GTK
widget it shows, a `GTKControl`; `SwiftOmniUIControls.add` says which contract it
realizes:

```swift quote
public static func add<Realized: ElementContract, Made: GTKControl>(
    _ contract: Realized.Type,
    create: @escaping (GTKReports<Realized>) -> Made,
    members: (GTKRegistration<Realized, Made>) -> Void = { _ in })
```

- **`create`** makes the control once per element, and wires what it reports:
  `reports.raise(Contract.member, values)` for an event of the element's own,
  and `reports.report(property, value, as: event)` for a value the USER
  changed.
- **`members`** registers what the control takes: `property(_:_:)` hands a
  value over as the type its contract declares, `nil` where it is no longer
  described, and `raises(_:)` records an event the control raises.

```swift quote
SwiftOmniUIControls.add(TrafficLightContract.self, create: { reports -> TrafficLightWidget in
    let light = TrafficLightWidget()
    light.onLampTapped = { index in reports.raise(TrafficLightContract.lampTapped, index) }
    return light
}) { light in
    light.property(TrafficLightContract.signal) { control, signal in
        control.signal = signal ?? .stop
    }
    light.raises(TrafficLightContract.lampTapped)
}
```

The host places, sizes and shows the control's widget as it does its own -
margins, alignment, opacity, gestures, frame reports - and measures it by the
widget's own measure. A registered control is a leaf. A control that runs a
loop of its own - a `GtkGLArea` drawing with OpenGL through libepoxy - turns
on its widget's tick callback, which GTK calls
only while the widget is on screen, so nothing turns behind a page the user has
left; a value changed while it is stopped still asks for the one frame it
needs.

### An act

`SwiftOmniUIActs.add` registers a function the application calls by its act, and
`SwiftOmniUIActs.add(_:on:_:)` one aimed at the application's own element, handed
that element's control:

```swift quote
SwiftOmniUIActs.add(GalleryContract.readClipboard) { () -> String in
    clipboardText()
}

SwiftOmniUIActs.add(RatingBarContract.flash, on: RatingBarWidget.self) { bar in
    bar.flash()
}
```

A performer runs on the main thread, and may await - GTK reads the clipboard
asynchronously - the call answered once it returns. Its arguments and answer
are the act's own types; a call carrying anything else fails with the reason. A thrown error
fails the act, and so does an aim at nothing; an act nobody registered is
refused by name.

### An event without a control

`SwiftOmniUIEvents.raise` pushes an event of the application's that belongs to no
element, from any thread; `SwiftOmniUIEvents.raises` declares it before the host
runs, so a handler listening for one no source raises is told so.

```swift quote
SwiftOmniUIEvents.raises(GalleryContract.batteryChanged)
SwiftOmniUIEvents.raise(GalleryContract.batteryChanged, level, charging)
```

## Running

```bash
.scripts/GTK/run-app.sh apps/HelloWorld
```

`run-app.sh` stops a running copy of the head, builds it and starts it, its
output in the terminal. Everything a build writes stays in the application's
`.build/gtk/`, but for what the desktop shows the application by: its icon,
`Resources/AppIcon/appicon_gnome.svg`, and an entry starting this build, both
named by the application's ID and installed for the user in
`~/.local/share/icons` and `~/.local/share/applications`. GNOME finds a
window's icon through that entry. `release` builds the optimized head, `--detach` returns once
the application has started, and `--build-only` builds it and starts
nothing.

`install-app-icon.sh` owns that desktop-entry installation for both run and
deploy. Deploy rewrites the entry to launch the final deployed executable,
with paths quoted for desktop-entry Exec syntax. The entry's basename and Icon
use the same application ID as GTK; StartupWMClass retains the executable name
for X11 matching. The installed icon is
the application's own `Resources/AppIcon/appicon_gnome.svg`; an SVG embedding
the application's PNG artwork is also valid. This is a per-user installation,
not a system package installer. Direct `swift build` does not install it.

In VS Code, with **GTK** chosen in the status bar, **SwiftOmniUI: Debug** builds
the head with `run-app.sh --build-only` and starts it under `lldb-dap`, so a
breakpoint in the application's Swift holds from the first line.

## Testing

```bash
SWIFTOMNIUI_HOST=gtk swift test --filter SwiftOmniUIGTKTests
```

The suite is XCTest. GTK's widgets stand on the test thread with no main loop
running: the suite starts libadwaita once, registers an application for its
windows, and turns GLib's loop itself where GTK lays out and draws. The
windows open on the desktop's display, so the suite runs in a desktop
session.

# Architecture

SwiftOmniUI is a Swift core that describes native interfaces, and hosts that show
the description with each platform's own toolkit. This page draws the whole:
the package and its targets, what crosses between them, and where each part of the work runs.
[The runtime](host/runtime.md) draws a host's inside.

## The package and targets

```text
  apps/<App>                              one Swift package per application
    Sources/                              views, @State, handlers, engines
    Platforms/Android                     the Android head: Gradle and a Swift library
    Platforms/WinUI                       the WinUI head: an executable
    Platforms/GTK                         the GTK head: an executable
    Platforms/Web                         the Web head: a WebAssembly build and a page
        |
        |  depends on
        v
  SwiftOmniUI  (lib/SwiftOmniUI, a target; no Foundation; every platform)
    Sources/Views, Types, Contracts       what an application writes with
    Sources/Core                          state, keys, diffing, cycles, the typed boundary
        |
        |  @_spi(Host)
        v
  SwiftOmniUIHost  (lib/SwiftOmniUI.Host, a target)
    Sources                               the host layer every host stands on
        |
        |  typed HostRender / HostPatch
        v
  SwiftOmniUI.Web (lib/SwiftOmniUI.Web)                SwiftOmniUI.Android (lib/SwiftOmniUI.Android)
    Swift, compiled to WebAssembly, in the       Swift, in the application's process,
    page's own process                           Java beneath it through JNI
        |                                             |
        v                                             v
    DOM elements                                Android views

  SwiftOmniUI.WinUI (lib/SwiftOmniUI.WinUI)            SwiftOmniUI.GTK (lib/SwiftOmniUI.GTK)
    Swift, in the application's process,         Swift, in the application's process,
    C++/WinRT beneath it behind a C ABI          over GTK 4's and libadwaita's C API
        |                                             |
        v                                             v
    WinUI 3 elements                              GTK widgets

  lib/SwiftOmniUI.VSCode                      the editor extension: new application,
                                          build, run and debug for every head
```

The root manifest declares these modules as targets with direct dependencies.
Consumers select ordinary library products; SOUI has no internal dynamic-library
boundary. Application dynamic dependencies remain part of the final link graph.
Code in the platform's own language - Java
through JNI, C++/WinRT behind a C ABI - relays calls beneath the host and holds
no SwiftOmniUI logic.

## One change, end to end

```text
  the user taps a button              the user drags a slider
        |                                   |
        v                                   v
  handler on MainActor                report through CoreLink
  writes @State                       lands on the state, no rebuild
        |                                   |
        +-----------------+-----------------+
                          |
          a body read it  |  a control is bound to it
          (path 1)        |  (path 2)
                          v
  render: rebuild the bodies that read it, diff by key -> HostPatch
  cycle:  engines and conversions -> the bound states' changes
                          |
                          v
  host: PatchIntake applies the patch; StateChannels carry the bound values;
        Animator animates both; one walk of the tree sets native properties
                          |
                          v
                   native views on screen
```

The core owns state, keys, diffing, the timing laws and the engines. The host
owns native objects, their lifetime, input, layout integration and the display
frame, and never computes again what the core decides.

## Threads

```text
  UI thread                            MainActor: handlers, renders, the host's work
    runs jobs the core queues          UIThreadExecutor, drained by the host
                                       (CoreLink.runJobs())
  doorbell thread                      parked in CoreLink.waitForWork();
                                       wakes the UI thread when work arrives
  cooperative pool                     an application's own async work, off MainActor
```

A handler's `await` resumes on `MainActor`, whatever it awaited. The core uses
no platform timer, run loop or main queue: time comes from the host's frame
clock, and work reaches the UI thread through the host's doorbell.

## Where to read next

- [Glossary](glossary.md): SwiftOmniUI's words and the common term for each.
- [The runtime](host/runtime.md): a host's elements, one frame, one turn and a
  user's change, drawn.
- [Animation in the runtime](host/animation.md) and [patches in the
  runtime](host/patches.md): the reasons behind the host layer's elements.

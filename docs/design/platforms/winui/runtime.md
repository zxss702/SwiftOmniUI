# The WinUI runtime

The WinUI host is the runtime every host shares
([the runtime](../../host/runtime.md)), over WinUI 3: the core's host layer
supplies the mounted tree, the patch intake, the animator, the state channels,
the display cycle and the turn, and the WinUI half supplies what only the
toolkit can - the frame signal, the doorbell's post, the elements, their
layout, and the window around them. What WinUI asks of C++ stands in the relay beneath it
([the relay](relay.md)).

## The WinUI runtime

`WinUIRenderer` holds the parts every runtime holds alike (`HostRuntime`): the
core link, the intake, the mounted tree whose native halves are
`WinUIElement`s, the animator and what follows it, the display cycle on
WinUI's frame clock, and the pump. Its turn is the one every runtime keeps
(`Pump`): the jobs a resumed handler left, a pending display cycle, a render
when the core needs one, the handlers the render created, and then the acts -
on the interface their handler has just changed. A turn asked for inside a
turn runs when it ends, and an event raised while a patch applies waits for
the patch. What the renderer adds is WinUI's: the window, its sheets and its
chrome shown after each render, and the acts performed.

A view is let go of in the turn after its element left: its `deinit` is
`MainActor`'s, and a release outside a task's context puts it in the UI
executor's queue, which rings the doorbell. The WinUI element goes with it.

## Starting

The host pins Windows App SDK **2.5.1** (stable) in
`.scripts/WinUI/tools.ps1`. Component versions are independent: WinUI **2.3.9**,
Foundation **2.3.12**, InteractiveExperiences **2.1.9**, and Base **2.0.4** are
the aggregate release's dependency graph. Only the native components used by
the host are deployed; the aggregate's AI, ML and other optional engines are
not required. C++/WinRT inputs, the DirectX interop header and the generated
servicing version header share one projection stamp, invalidated by either
an aggregate or component version change.

SwiftPM does not run the Windows App SDK's MSBuild initializers. After loading
the runtime, the relay applies `RuntimeCompatibilityOptions.PatchLevel1` for
the pinned release before AppLifecycle can lock compatibility. Before either
`Application.Start` or embedded XAML initialization it enables the stable
`XamlOptionalChanges`: `DefaultStyleOptimizations`, `IconNoGridOptimization`,
`OptimizeApplyStyles`, and `DeferContextFlyoutInit`. They reduce default style
resolution, icon template nodes, redundant style application and eager text
context-menu creation. Both startup paths configure them once per process.
An unsupported change is an initialization error, rather than silently using
an older runtime with a new projection. The limited-access CompositionEngine
is not enabled. See [Microsoft's stable release notes](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0)
and [XAML change identifiers](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.settings.xamlchangeid?view=windows-app-sdk-2.0).

With deferred style application, a detached `TextBlock` is not a reliable
reader of a semantic font's applied dependency properties. The font reader
uses the native Style's resolved FontSize/FontWeight setters, traversing
BasedOn before derived setters, cached by the sealed Style identity. No
hidden visual tree is needed for measuring text or sizing symbols.

### Compatibility with the previous 1.8 deployment

The 2026-10-14 upgrade (`8664008b53134260eb206f4fedefa7f51bf32b10`)
changed both the deployed components and the optional XAML behaviors:

| Input | Previous deployment | Current deployment |
| --- | --- | --- |
| Windows App SDK | 1.8 | 2.5.1 |
| WinUI | 1.8.260528001 | 2.3.9 |
| Foundation | 1.8.260527000 | 2.3.12 |
| InteractiveExperiences | 1.8.260525001 | 2.1.9 |
| C++/WinRT | 3.0.260818.1 | 3.0.260818.1 |
| WebView2 | 1.0.3179.45 | 1.0.4258.31 |

`OptimizeApplyStyles` defers applying a style until the element enters the
tree; `DefaultStyleOptimizations` selects optimized control templates. Both
are explicit host opt-ins, not evidence that every native measurement or
layout algorithm changed. Detached controls must not assume their eventual
style is already applied, and the host must reconcile native viewport changes
without requiring a scroll event.

The source comparison of Microsoft's 1.8.9 (`e5e4cc817e24f89415a4cf44826130818492b42e`)
and 2.5.1 (`ba3a8d59e6de4e2b86ca4f61c78bc26ccf129afd`) releases found no
changes in `SplitView_Partial.cpp`, the original SplitView template,
`ScrollPresenter.cpp`, or `LayoutManager.cpp`. The
[optimized SplitView template](https://github.com/microsoft/microsoft-ui-xaml/blob/ba3a8d59e6de4e2b86ca4f61c78bc26ccf129afd/src/controls/dev/SplitView/SplitView_themeresources_perf2026.xaml)
changes several visual-state updates to setters; its leading inline pane
keeps the same layout. This comparison does not establish a native SDK
regression or replace a Windows runtime comparison. The host retains 2.5.1
and its performance opt-ins while fixing its own initial pane state, first
display-mode selection, layout/presentation boundaries and content preparation
([split views](pages.md#a-split-view)).

The head hands the thread to `SwiftOmniUIWinUI.run(applicationID:initializing:)`.
The relay loads the Windows App SDK, then uses `AppInstance.FindOrRegisterForKey`
to select one process for the application ID, or the executable's full path
when no ID is supplied. A secondary process redirects its activation and
returns without starting XAML or invoking the initialization closure. It
grants the primary process foreground permission before forwarding. The native
asynchronous redirection reports completion while the startup STA dispatches
COM messages. The wait also observes the destination's process handle, so a
process that exits before acknowledging the request cannot strand the launcher.

Only the primary starts WinUI's `App`. Its `OnLaunched` calls the host, whose
first act is to drain SwiftOmniUI's UI executor on that thread: the drain is
what makes the thread `MainActor`'s. The head's initialization closure registers
the application and its controls there before the first render. Existing heads
that register before `run()` remain supported.

Activation arguments are held as agile references until the first render and
drained on the UI dispatcher, including redirected requests received during
startup. A plain launch reuses the earliest scene's declared main window,
reopening it if only secondary windows remain; it restores a minimized window
before activation. After showing and activating the XAML window, the relay
requests foreground activation with `SetForegroundWindow`, using the permission
granted by the sender, so an existing first window is raised in front of other
applications. File and protocol activations retain their URL delivery.

The process is held only while the tree declares windows, rather than while
it retains scenes. When no windows remain, a low-priority dispatcher task
exits XAML after checking for accepted activations. It releases the instance
key before rejecting later requests as shutting down. A sender rechecks the
key after forwarding, allowing a launch concurrent with shutdown to become
the next primary. There is no background application hold.

The relay's startup object requests an 8 MiB executable stack with
`/STACK:8388608`. Windows otherwise reserves only 1 MiB: debug tree
reconciliation can exhaust that budget at ordinary view nesting depths.
The request travels with the object linked into the consuming executable;
DLLs cannot configure the executable's main-thread stack.

## A windowed application

The head links as a windowed application (`/SUBSYSTEM:WINDOWS`, its entry
still the C runtime's `main`), so one started by itself - from Explorer, a
shortcut - opens no console beside its window. One started from a console - a
terminal - still writes there: where the process was handed no output of its
own, the relay attaches it to the console of the process that started it
before WinUI starts, and points the C runtime's streams, and its descriptors
1 and 2, at that console. Output a caller sent elsewhere - a file, or the
debugger F5 starts it under, which shows it in the editor's debug console -
stays where it was sent. A windowed application is not waited for by the
shell that starts it, so `run-app.ps1` waits for it itself.

## An application with no XAML

WinUI's control resources, `XamlControlsResources`, name types such as the
acrylic brushes, and only an application that answers for the types
(`IXamlMetadataProvider`) lets the framework resolve them - an application the
XAML compiler would write, and the relay's `SwiftOmniUIApplication` writes by
hand, handing `XamlControlsXamlMetaDataProvider`'s answers on. The provider is
made on the first question, as the compiler's own is.

A test process runs no loop of WinUI's: it makes the application first and
then `WindowsXamlManager.InitializeForCurrentThread()`, which calls that
application's `OnLaunched` - where nothing starts - and a control takes its
template only in a window of that thread once the thread's messages ran.
Embedding does not claim an instance key or exit the test process when its
windows close. `.scripts/WinUI/test-window-lifecycle.ps1` separately exercises
real processes and normal window close requests against an already-built
application that starts one window, without building it.

## The doorbell

A handler that awaits resumes on `MainActor`, whose jobs wait in SwiftOmniUI's UI
executor until the host drains them. A thread of the host's own parks until
the core has work, and posts one turn to the UI thread's `DispatcherQueue`
through the relay; the turn runs on the UI thread among WinUI's own work.
What a layout pass decides - a split view's first room - waits in the doorbell
until the pass is over. It runs at the start of either the next posted turn
or the next composed frame, before that frame's user reports. The shared
queue is taken once, so the other callback cannot execute the same work
again. Pending work holds the frame clock; lazy realization and deferred
measurement therefore do not depend exclusively on dispatcher progress
during continuous input.

The thread is started from a nonisolated function: a closure written inside a
`MainActor` function is `MainActor`'s, and the runtime reports it as a data
race the moment another thread runs it.

## One frame

The frame clock subscribes to `CompositionTarget.Rendering` while something
holds it and lets go of it when nothing moves. Subscribed, WinUI composes at
the display's rate and raises the event before each frame it composes, so what
the frame moves is drawn in that same frame. The runtime's time is the
performance counter's, in milliseconds.

## The window

Each window element the tree holds is shown in a WinUI `WindowScene` of its own,
kept by a window controller in the tree's order; a window the tree no longer
holds is closed. The first is the scene's main window, where the application's
questions stand and whose screen the environment reads. A window element's
arrangement of pages is its window's content, under the window's chrome, which
names it after the visible page, else after the element's title
([the window's chrome](pages.md#the-windows-chrome)); the window is activated
the first time it shows a page, and told it was made once, in its turn
(`WindowPresentation`); the pages the window's modal stack presents stand on
sheets over it.

## A window's frame

A window stands where the host layer says its element asks ([a window's
frame](../../host/tree.md#a-windows-frame)): the place, the size and the
bounds the tree changed, each alone. The size is the content's, the chrome's
included, as WinUI's content reaches under it. WinUI's `AppWindow` takes
pixels, so each DIP is the window's DPI over 96 of them - known before
anything is laid out, where the root's rasterization scale is not. The size
is set as the whole window's, the content's asked for plus the frame around
it as it stands: `ResizeClient` would add the title bar's height again, which
the content already covers.

The bounds are the presenter's preferred least and greatest size. The
caption height comes from `AppWindow.TitleBar.Height`, converted from pixels
to DIPs, and fixes both states of the XAML title bar's row. A new page's
toolbar content does not change this contribution to window sizing. Reading
it neither measures the title bar's children nor calls `UpdateLayout`, which
would flush pending page layout inside window presentation and can realize
another lazy window before the current render returns. Window requests and
presenter properties are written only when their native pixel values differ;
the comparison uses the current presenter and DPI, rather than a DIP cache.

The traits ([a window's traits](../../host/tree.md#a-windows-traits)) are the
presenter's too - its maximize and minimize buttons, a button left unsaid
being WinUI's own, which lets the user press it, and its standing on top of
other windows for one that floats - and the backdrop: a translucent window's
is acrylic, and any other window's Mica, made again only where it turns.

## The application's phase

Each window's activation and its minimizing settle into the phases of the
application, its scenes and its windows by the host layer's rule ([the
application's phase](../../host/runtime.md#the-applications-phase)): the
relay tells the window's state at each of WinUI's events - whether it stands
minimized, and whether it is activated - because a window being minimized is
also told it lost its activation, in either order; a change of its size or
presenter tells it only where it is minimized. A window its scene hides is
`AppWindow.Hide`, and shown again without being activated; one hidden before
it was ever shown is activated as it is first shown. A floating window is
`IsAlwaysOnTop` while the application is in front. Only a window that explicitly
asks to float has its scene's main window as its native owner
(`GWLP_HWNDPARENT`), as a tool window is on Windows: above it, hidden while it
is minimized, and out of the taskbar and switcher (`IsShownInSwitchers`).
Ordinary `Window` and `WindowGroup` windows have no native owner and remain in
the switchers. Windows handles their activation and z-order; clicking one can
raise it above another. A window type records identity and scene membership,
without imposing owned-window order. A window hidden - with its
owner, or by its scene - tells its state as it hides and shows again
(`AppWindow.Changed`), off the screen while it is hidden. A window is told it was made before it is
first shown: WinUI tells it that it was activated inside `Activate`, before
the call returns.

## The environment

The host tells the core what it stands on as it starts: a desktop running
Windows - the device's maker, model, name and version, and whether it is a
virtual machine - the application's name, the system's color scheme, the user's
locale, the battery and the network; and the screen once there is a window,
at the system's scale, which a window on a second screen may not share, and
turned as Windows says (`dmDisplayOrientation`, quarters of the picture's
turn clockwise, the host layer's rotation). The color scheme is the one Windows
paints its controls in, so a colour written for light and dark reads as
WinUI's own text beside it. Windows says when the color scheme, the power, the
network or a screen's area changes - a tablet turned among them; the relay
posts each change to the UI thread, and the host tells the core again,
the screen with it, and renders what it changed.

## Acts

The acts the application calls are performed after each turn's render and
answered, a reply or a failure with its reason, so no caller waits on an act
nobody performs - by the host layer's performer, WinUI's part its toolkit's
(`WinUIActToolkit`, [acts](../../host/runtime.md#acts)). The time of day is the system's local time; the zone is the
one the locale reports, an IANA name; a zone's distance from UTC on a day is
ICU's - the ICU Windows carries - taken at the day's noon, so the day decides
summer time, and a zone ICU does not know fails the act. The screen reader is
told through the content of the window the user is in, cutting off what it
was saying. The focus
is put on the view the act names, or the first control in it that takes it;
WinUI has no way to leave the focus nowhere, so taking it off lends it to the
window's content for a moment, as no control, and the on-screen keyboard goes
with a field that loses it.

## Questions for the user

A question - an alert, a confirmation, a choice of actions, a prompt - is
WinUI's own dialog, over the window the user is in when its turn comes - the
one activated last, else the first - and its call waits under a ticket the
dialog hands back as the user answers; a ticket is one number across the
process, so an answer that arrives after its renderer has gone answers
nothing of another's. Questions are asked one at a time, in the order the
application asked them, by the host layer's queue ([questions for the
user](../../host/runtime.md#questions-for-the-user)): the next shows once the
one before is answered. A choice of actions is a
button a choice, the dangerous one first, and the pressed caption is the
answer - the cancelling one too; a dialog dismissed any other way, Escape
among them, answers that nothing was chosen. A prompt's field takes the
placeholder, the most characters and the keyboard its purpose asks for.

## Files

A file dialog is Windows' own, from the Windows App SDK's pickers
(`FileOpenPicker`, `FileSavePicker`), over the window the user is in, and it
waits its turn among the questions ([files](../../host/runtime.md#files)).
A dialog that opens filters by every kind's extensions, as one list; one that
saves offers each kind under its caption, the first as its default
extension. Windows shows the dialog on a thread of its own and hands back a
path: a save's contents are written to it beside the UI thread, and the file
is handed over only once they stand written - or the act fails with
Windows' reason. A file is read beside the UI thread too. A chosen file's
address is its path.

A file or an address is launched through `Launcher`, which answers whether
an application took it. Every answer reaches the host on the UI thread, by
the ticket the call was given.

`revealFile` uses SHParseDisplayName and SHOpenFolderAndSelectItems on a
COM-initialized worker, selecting the actual file or folder rather than
passing its path to LaunchUriAsync. The completion returns to the UI thread
through the existing launch ticket mechanism.

## Kept values

`@AppStorage` reads and writes Foundation's `UserDefaults.standard`, the same
store application/model code reads directly. Writes update memory immediately;
the persistence act calls corelibs `synchronize` to commit to disk. Old kept-file
values migrate only where defaults has no value. Declared defaults keys load
before the first render, and keys first declared later read defaults when claimed.

Windows keeps no store for an application that is no package, so the host
keeps one of its own for `@State(persistentKey:)`: a file in the user's local data, in a folder named
after the executable, holding the host layer's text ([kept
values](../../host/runtime.md#kept-values)). Every key the
application lists is read before the first scene connects and handed to the
core ahead of the first view; a key's new value writes the whole file again,
its keys in order, beside the old one first and then in its place, so a
failed write leaves the old. Windows restores no windows either, so the
scenes are kept the same way, in a second file beside it, by the host
layer's rule ([kept scenes](../../host/runtime.md#kept-scenes)): read as the
host starts, and written whenever the scenes it holds write another text.
The current window-session store is `open scenes.txt`. Closing the last
window writes an empty snapshot before native windows are closed and the
dispatcher schedules shutdown. A later ordinary launch opens the declared
initial window. Scenes retained without windows after programmatic closing
are excluded from restoration. The legacy `kept scenes.txt` is not read:
that format's lifecycle deliberately retained pre-close snapshots, with no
way to distinguish closed windows from an interrupted session. Application
preferences continue to use their separate stores.

## Self-contained

An application carries the Windows App SDK beside its executable, with no
package: the runtime of WinUI, Foundation and InteractiveExperiences, a
manifest registering every class each component declares - the registrations
the SDK's own build writes - and `resources.pri`, where WinUI's controls find
their resources. `.scripts/WinUI/tools.ps1` lays them out after each build,
the test runner's included, and owns the versions.

SDK payloads overwrite previous DLLs even when NuGet's file timestamps are
older or equal. Keeping the older files by timestamp could leave 1.8 DLLs
beside a 2.x manifest and projection. The resource index is refreshed from
the same WinUI package. `.scripts/WinUI/tests/self-contained.tests.ps1`
contains deployment-only regression fixtures for x64 and ARM64, including
incremental upgrades and optional WebView payloads.

The optional WebView backend pins WebView2 SDK **1.0.4258.31**. It deploys the
matching native WinRT component and loader only when linked. It continues to
use the system's Evergreen WebView2 Runtime; updating the SDK does not install
or update that browser engine. Microsoft's release requires runtime
**154.0.4258.31** or later for its full API surface
([WebView2 SDK release](https://learn.microsoft.com/en-us/microsoft-edge/webview2/release-notes/sdk/1-0-4258-31)).
In-memory HTML uses the request-source-aware `AddWebResourceRequestedFilter`
overload for document requests. Replacing a document at the same address
updates its contents without registering another filter. Shared/service
worker interception and experimental shared-cluster environments are not
enabled.

The SDK upgrade, font metrics and deployment have regression test code.
Native rendering and performance still require verification on Windows;
the upgrade was prepared without compiling or running tests.

The manifest stands beside the executable as `<name>.exe.manifest`, which
Windows reads for an executable carrying none of its own. It is not written
into the executable: the build records what it linked, and the next build
links an executable changed since again, even when nothing else has.

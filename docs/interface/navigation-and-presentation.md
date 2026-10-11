# Navigation and presentation

Navigation and presentation are readable application state. SwiftOmniUI does not
store a second router or command history beside that state. A host materializes
native containers and reports committed user actions back to the same
bindings.

## Navigation stack

`NavigationStack` renders a root page plus one destination for every element of
a typed path:

```swift quote
enum Route: Hashable {
    case note(Int)
    case settings
}

struct MainWindow: WindowScene {
    @State private var path: [Route] = []

    var page: any Page {
        NavigationStack($path) {
            HomePage(path: $path)
        } destination: { route in
            switch route {
            case .note(let id): NotePage(id: id, path: $path)
            case .settings: SettingsPage(path: $path)
            }
        }
    }
}
```

Navigation operations are ordinary array operations:

```swift quote
path.append(.note(42))  // push
path.removeLast()       // pop
path = []               // return to root
```

The root always exists. Each destination is identified by its route and stack
depth, so the same route may appear more than once without sharing page state.
A committed native back action truncates the bound path. A cancelled
interactive gesture changes neither the path nor the tree.

Pass the binding to every page that may change the path. A page that receives
only its value can read where it is, but cannot navigate on its owner's behalf.

## Tabs

`TabView` is built from a distinct collection of application values. A
selection binding says which one is showing:

```swift quote
enum Tab: Hashable, CaseIterable {
    case notes, search, settings
}

@State private var selected = Tab.notes

TabView(Tab.allCases) { tab in
    switch tab {
    case .notes: NotesPage()
    case .search: SearchPage()
    case .settings: SettingsPage()
    }
}
.selection($selected)
```

Assigning `selected` changes the visible tab. A user-selected tab is reported
into that same binding. Tab identity is the tab value, not its position, so
reordering distinct values retains their pages. Repeating a tab value would
claim one identity twice and is invalid application data.

A tab can contain its own `NavigationStack` and path. That arrangement keeps a
separate stack per tab because each path belongs to the application's state,
not to the tab host.

## Split view

`NavigationSplitView` owns two pages - a sidebar and a detail - and a two-way binding
saying whether the sidebar shows:

```swift quote
@State private var menuOpen = false

NavigationSplitView($menuOpen, sidebar: {
    MenuPage(isSidebarVisible: $menuOpen)
}, detail: {
    MainPage()
})
```

The sidebar is a page, so its header, rows, and actions are composed from the
same controls as any other page. SwiftOmniUI does not require a special menu-item
model. A committed native show or hide writes `menuOpen`; assigning the state
shows or hides the sidebar.

The host adapts presentation to the available space. The state contract stays
the same whether the two pages are temporarily overlaid or persistently side
by side. On Windows the
sidebar opens over the detail from the navigation button beside the back
button in the title bar, and the same button or a click outside it closes it.
On a phone the sidebar slides over the detail from
the leading edge, the detail shaded behind it, and a tap on the shade closes
it; on a wide tablet it stands beside the detail.

## Modal pages

Modal presentation belongs to the window. `ModalStack` maps an application
array to pages and is installed in `WindowSession`:

```swift quote
enum Sheet: Hashable {
    case settings
    case rename
}

@State private var sheets: [Sheet] = []
@Environment private var window: WindowSession

.onAppear {
    window.modalStack = ModalStack($sheets) { sheet in
        switch sheet {
        case .settings: SettingsPage(sheets: $sheets)
        case .rename: RenamePage(sheets: $sheets)
        }
    }
}
```

Appending presents, removing dismisses, and the last element is on top. A
native dismissal truncates the bound array to the number of pages still
presented. A modal page therefore carries its own dismissal route by receiving
the binding.

The stack belongs to the window rather than to whichever page happened to
present it. Replacing or closing that window tears down every modal it owns.

## Over every page

A window lays views of the application's over its page and every page
presented over it - a notice that stays while the pages change under it. They
are the window's too, `window.overlays`, each under a key the application
declares:

```swift internals
extension OverlayKey {
    static let offline = OverlayKey("offline")
}

struct OfflineNotice: View {
    @Environment private var window: WindowSession

    var body: some View {
        HStack {
            Text("Working offline")
            Button("Dismiss").onClicked { window.overlays[.offline] = nil }
        }
        .spacing(12)
        .horizontalAlignment(.center)
        .verticalAlignment(.start)
    }
}

struct LibraryPage: View {
    @Environment private var window: WindowSession
    @State private var offline = false

    var body: some View {
        Switch($offline)
            .onChange(of: offline) { window.overlays[.offline] = offline ? OfflineNotice() : nil }
    }
}
```

The layers stand in one ZStack, each written later over the ones before, and
`.zIndex` on a layer's view reorders them. A key is the layer's identity: a
view written again under it replaces the one there in its place, and the
other layers keep their controls as it comes and goes. Each view has the
page's whole area and stands where its alignments put it. A click beside it
goes on to what is under it; a layout of its own that fills the area passes a
click on with `.letsInputThrough(true)`. `nil` takes a layer away. A docked
inspector is one of these layers, over every other.

## Page titles and navigation furniture

A view shown as a page changes its `PageSession`. An arrangement is a page
already, with no session of its own, so it is told what it is by modifier:

```swift quote
NavigationStack($settingsPath) {
    SettingsHome(path: $settingsPath)
} destination: { route in
    SettingsDestination(route: route)
}
.title("Settings")
.icon("settings.png")
```

The container's title and icon describe it when it is an item in another
container, such as a tab. The title shown for the top page of a navigation
stack comes from that page's own `PageSession`.

A view such as `SearchField` can occupy the current page's navigation title
slot:

```swift quote
@Environment private var page: PageSession
@State private var query = ""

.onAppear {
    page.titleView = SearchField($query)
        .placeholder("Search")
}
```

## Toolbars

Toolbar items are page furniture, not views in page layout:

```swift quote
@Environment private var page: PageSession

page.toolbarItems = [
    ToolbarItem("Save")
        .id("save")
        .priority(0)
        .onClicked { try await save() },
    ToolbarItem("Delete")
        .id("delete")
        .placement(.overflow)
        .isDestructive(true)
        .onClicked { try await delete() },
]
```

`placement` distinguishes primary actions from actions behind native overflow.
Within either group, lower `priority` appears first and equal values retain
source order. The host chooses the native placement appropriate to the window
and available space. Give stable identities to items whose list can change.

On a desktop host a page's furniture is its window's title area: the top page's title
names the window, the way back is the system's back item, primary actions are
title items, and secondary ones sit in the title area's overflow menu. A tabbed
view on the window's page path shows its tabs in a row beneath the title area,
beside any sidebar, the tabs sharing its width with each picture beside its
title; one in a sidebar, a sheet or inside another tab is a tab view with its
tabs on the top edge of its content.

Page arrangements accept a flat `barBackgroundColor`. A `NavigationStack` also
accepts `barForegroundColor` for its title and native action affordances. Native tab
selectors keep their selected and unselected states, legible over a written
background. Leaving the background unwritten preserves the platform's
material. A written colour is
painted where the bars stand - the band the title area
covers over the visible content, with the page's title in `barForegroundColor` on it,
and the window's background, which a floating sidebar shows around it -
while the title area's own items keep the system's look. On a
translucent window the colour tints the window's material instead. Gradients
remain ordinary view composition where the application owns the surface.

## Menu bars and context menus

Desktop menu bars are also stored on `PageSession`:

```swift quote
page.menuBar = [
    Menu("File") {
        MenuItem("Save").onClicked { try await save() }
        Divider()
        Menu("Recent") {
            ForEach(recent) { file in
                MenuItem(file.name)
                    .id(file.id)
                    .onClicked { open(file) }
            }
        }
    }
    .id("file"),
]
```

The same item vocabulary can be attached to any view as a context menu:

```swift quote
Text(document.title)
    .contextMenu {
        MenuItem("Duplicate").onClicked { duplicate(document) }
        MenuItem("Delete")
            .isDestructive(true)
            .onClicked { delete(document) }
    }
```

Menu and toolbar structures are reconciled by identity like other ordered
children. A platform without that surface may omit its presentation; never put
the only route to an essential action behind a context menu. Consult
[Platform contract](../platform-contract.md) for verified support.

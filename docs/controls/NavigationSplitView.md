<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# NavigationSplitView

A page holding two: a sidebar at the side and the page beside it.

Layer: `adaptive`. Every base host presents it by its platform's conventions, keeping SwiftOmniUI's state contract.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [PageElement](tiers/PageElement.md)

| Mark | Meaning |
| :---: | --- |
| ✅ | Proven by every test of it that ran on that host. |
| ☑️ | Proven, the host recording what is missing. |
| – | Never on that host's family, which meets the contract there. |
| ❌ | A test of it failed. |
| ◐ | Some of its tests proved it, another could not run or read. |
| 🔌 | Proven only through the host's own entry or record, not the toolkit's. |
| · | The driver cannot yet do or read what its test needs. |
| ⏸ | Its test waits on a member the host does not realize. |
| ⌛ | Said at another revision of its family than it stands at. |
| empty | Not realized, or no run - the note says which. |

See [the dictionary](README.md) for how a mark is given.

| Host | Created | Members (19) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 1 ✅ | custom `ViewGroup`: a drawer where narrow, beside where wide |  |
| WinUI 3 | ✅ | 4 ✅ | `NavigationSplitView` |  |
| GTK 4 | ✅ | 4 – | `GtkPaned`; libadwaita `AdwOverlaySplitView` |  |
| Web |  |  | `<aside>` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Navigation/NavigationSplitViewContract.swift`.

## NavigationSplitView's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `isSidebarVisible` | property | `Bool` | native | 🔌 | ✅ | · |  | only through the host's own: read isSidebarVisible of NavigationSplitView: the split's own flag; the drawer slides on it; GTK 4: cannot read isSidebarVisible of NavigationSplitView - GTK's driver has no path for it yet |
| `isSidebarVisibleChanged` | event | `Bool` | adaptive | 🔌 | ✅ |  |  | only through the host's own: toggle on NavigationSplitView: the host's own entry the scrim's tap and the bar's button call; GTK 4: not realized |
| `columnVisibility` | property | `NavigationSplitViewVisibility` | native |  |  | · |  | GTK 4: cannot read columnVisibility of NavigationSplitView - GTK's driver has no path for it yet |
| `columnVisibilityChanged` | event | `NavigationSplitViewVisibility` | adaptive |  |  | · |  | GTK 4: cannot toggle on NavigationSplitView - GTK's driver has no path for it yet |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native | ✅ | ✅ |  |  | GTK 4: not realized |

## From [PageElement](tiers/PageElement.md)

What a page shows about itself where another container presents it as an item - a title and a picture.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `badge` | property | `String` | native |  |  | · |  | GTK 4: cannot read badge of NavigationSplitView - GTK's driver has no path for it yet |
| `document` | property | `String` | adaptive |  |  | – |  | GTK 4: GTK 4 names a window for a document in its title alone. |
| `icon` | property | `ImageSource` | adaptive | · |  |  |  | cannot read icon of NavigationSplitView - Android's driver has no path for it yet; WinUI 3: not realized; GTK 4: not realized |
| `interactiveDismissDisabled` | property | `Bool` | native |  |  | – |  | GTK 4: A GTK sheet is libadwaita's dialog: Escape and its close always take it. |
| `preferredColumnWidth` | property | `[Double]` | adaptive |  |  | · |  | GTK 4: cannot read preferredColumnWidth of NavigationSplitView - GTK's driver has no path for it yet |
| `presentationDetents` | property | `[PresentationDetent]` | native |  |  | – |  | GTK 4: A GTK sheet is libadwaita's dialog, sized by what it shows - detents are not its to take. |
| `presentationDragIndicator` | property | `Visibility` | native |  |  | – |  | GTK 4: A GTK sheet is libadwaita's dialog, which draws no grabber of its own. |
| `subtitle` | property | `String` | adaptive |  |  | · |  | GTK 4: cannot read subtitle of NavigationSplitView - GTK's driver has no path for it yet |
| `subtitleKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `title` | property | `String` | native | · | ✅ | · |  | cannot read title of NavigationSplitView - Android's driver has no path for it yet; GTK 4: cannot read title of NavigationSplitView - GTK's driver has no path for it yet |
| `titleKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `toolbarBackground` | property | `Visibility` | adaptive |  |  | · |  | GTK 4: cannot read toolbarBackground of NavigationSplitView - GTK's driver has no path for it yet |
| `toolbarVisibility` | property | `Visibility` | adaptive |  |  | · |  | GTK 4: cannot read toolbarVisibility of NavigationSplitView - GTK's driver has no path for it yet |
| `windowBackground` | property | `Color` | adaptive |  |  | · |  | GTK 4: cannot read windowBackground of NavigationSplitView - GTK's driver has no path for it yet |

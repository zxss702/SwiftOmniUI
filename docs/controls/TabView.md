<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# TabView

A page showing several pages, one at a time, with a bar to choose between them.

Layer: `adaptive`. Every base host presents it by its platform's conventions, keeping SwiftOmniUI's state contract.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [BarElement](tiers/BarElement.md) · [PageElement](tiers/PageElement.md)

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

| Host | Created | Members (18) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 1 ✅ | custom `LinearLayout` tab row |  |
| WinUI 3 | ✅ | 4 ✅ | `NavigationView` with a top pane |  |
| GTK 4 | ✅ |  | `GtkStack` + `GtkStackSwitcher`; libadwaita `AdwViewStack` |  |
| Web |  |  | ARIA `tablist` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Navigation/TabViewContract.swift`.

## TabView's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `currentPage` | property | `Int` | structure | · | ✅ | · |  | cannot choose on TabView - Android's driver has no path for it yet; GTK 4: cannot read currentPage of TabView - GTK's driver has no path for it yet |
| `currentPageChanged` | event | `Int` | adaptive | · | ✅ |  |  | cannot choose on TabView - Android's driver has no path for it yet; GTK 4: not realized |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native | ✅ | ✅ |  |  | GTK 4: not realized |

## From [BarElement](tiers/BarElement.md)

The bar a page arrangement draws: its colour.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `barBackgroundColor` | property | `Color` | adaptive | · |  |  |  | cannot read barBackgroundColor of TabView - Android's driver has no path for it yet; WinUI 3: not realized; GTK 4: not realized |

## From [PageElement](tiers/PageElement.md)

What a page shows about itself where another container presents it as an item - a title and a picture.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `badge` | property | `String` | native |  |  |  |  |  |
| `document` | property | `String` | adaptive |  |  |  |  |  |
| `icon` | property | `ImageSource` | adaptive | · |  |  |  | cannot read icon of TabView - Android's driver has no path for it yet; WinUI 3: not realized; GTK 4: not realized |
| `interactiveDismissDisabled` | property | `Bool` | native |  |  |  |  |  |
| `preferredColumnWidth` | property | `[Double]` | adaptive |  |  |  |  |  |
| `presentationDetents` | property | `[PresentationDetent]` | native |  |  |  |  |  |
| `presentationDragIndicator` | property | `Visibility` | native |  |  |  |  |  |
| `subtitle` | property | `String` | adaptive |  |  |  |  |  |
| `subtitleKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `title` | property | `String` | native | · | ✅ | · |  | cannot read title of TabView - Android's driver has no path for it yet; GTK 4: cannot read title of TabView - GTK's driver has no path for it yet |
| `titleKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `toolbarBackground` | property | `Visibility` | adaptive |  |  |  |  |  |
| `toolbarVisibility` | property | `Visibility` | adaptive |  |  |  |  |  |
| `windowBackground` | property | `Color` | adaptive |  |  |  |  |  |

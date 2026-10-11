<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Page

What a container shows as a screen: a window's page, a stack's root and destinations, a tab, either half of a split view, a sheet.

Layer: `adaptive`. Every base host presents it by its platform's conventions, keeping SwiftOmniUI's state contract.

Inherits: [PageElement](tiers/PageElement.md)

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

| Host | Created | Members (24) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 6 ✅ | custom `ViewGroup` |  |
| WinUI 3 | ✅ | 9 ✅ | `Page` |  |
| GTK 4 | ✅ | 4 ✅ | custom `GtkWidget` |  |
| Web |  |  | `<section>` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Structure/PageContract.swift`.

## Page's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `appearing` | event |  | adaptive | ◐ | ✅ | ◐ |  | cannot goBack on WindowScene - Android's driver has no path for it yet; GTK 4: waits on WindowScene.modalPopped |
| `backButtonTitle` | property | `String` | adaptive |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `background` | property | `Color` | native | ✅ | ✅ |  |  | GTK 4: not realized |
| `disappearing` | event |  | adaptive | ✅ | ✅ | ✅ |  |  |
| `hasBackButton` | property | `Bool` | adaptive | · |  |  |  | cannot read hasBackButton of Page - Android's driver has no path for it yet; WinUI 3: not realized; GTK 4: not realized |
| `hasNavigationBar` | property | `Bool` | adaptive | · | ✅ | · |  | cannot read hasNavigationBar of Page - Android's driver has no path for it yet; GTK 4: cannot read hasNavigationBar of Page - GTK's driver has no path for it yet |
| `navigatedFrom` | event |  | adaptive | ✅ | ✅ | ✅ |  |  |
| `navigatedTo` | event |  | adaptive | ✅ | ✅ | ✅ |  |  |
| `navigatingFrom` | event |  | adaptive | ✅ | ✅ | ✅ |  |  |
| `contentPadding` | property | `EdgeInsets` | native | ✅ | ✅ |  |  | GTK 4: not realized |

## From [PageElement](tiers/PageElement.md)

What a page shows about itself where another container presents it as an item - a title and a picture.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `badge` | property | `String` | native |  |  |  |  |  |
| `document` | property | `String` | adaptive |  |  |  |  |  |
| `icon` | property | `ImageSource` | adaptive | · |  |  |  | cannot read icon of Page - Android's driver has no path for it yet; WinUI 3: not realized; GTK 4: not realized |
| `interactiveDismissDisabled` | property | `Bool` | native |  |  |  |  |  |
| `preferredColumnWidth` | property | `[Double]` | adaptive |  |  |  |  |  |
| `presentationDetents` | property | `[PresentationDetent]` | native |  |  |  |  |  |
| `presentationDragIndicator` | property | `Visibility` | native |  |  |  |  |  |
| `subtitle` | property | `String` | adaptive |  |  |  |  |  |
| `subtitleKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `title` | property | `String` | native | · | ✅ | · |  | cannot read title of Page - Android's driver has no path for it yet; GTK 4: cannot read title of Page - GTK's driver has no path for it yet |
| `titleKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `toolbarBackground` | property | `Visibility` | adaptive |  |  |  |  |  |
| `toolbarVisibility` | property | `Visibility` | adaptive |  |  |  |  |  |
| `windowBackground` | property | `Color` | adaptive |  |  |  |  |  |

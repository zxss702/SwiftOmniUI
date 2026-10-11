<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# WindowScene

A window onto a page.

Layer: `structure`. It carries structure or protocol data rather than configuring a visual platform object.

Inherits nothing: every member below is its own.

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

| Host | Created | Members (25) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 2 ✅ | `Activity` |  |
| WinUI 3 | ✅ | 23 ✅ | `Window` |  |
| GTK 4 | ⏸ |  | `GtkApplicationWindow` | waits on WindowScene.created, not realized yet |
| Web |  |  | browser `window` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Structure/WindowSceneContract.swift`.

## WindowScene's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `activated` | event |  | adaptive | ✅ | ✅ |  |  | GTK 4: not realized |
| `created` | event |  | adaptive | ✅ | ✅ |  |  | GTK 4: not realized |
| `deactivated` | event |  | adaptive | 🔌 | ✅ |  |  | only through the host's own: switchAway on WindowScene: the host told the activity's phase, no activity moved; GTK 4: not realized |
| `destroying` | event |  | adaptive | 🔌 | ✅ |  |  | only through the host's own: close on WindowScene: the host told the activity's phase, no activity moved; GTK 4: not realized |
| `floatsOnTop` | property | `Bool` | adaptive |  | ✅ |  |  | not realized; GTK 4: not realized |
| `height` | property | `Double` | native |  | ✅ |  |  | not realized; GTK 4: not realized |
| `hidesWhenInactive` | property | `Bool` | adaptive |  | ✅ |  |  | not realized; GTK 4: not realized |
| `isMaximizable` | property | `Bool` | adaptive |  | ✅ |  |  | not realized; GTK 4: not realized |
| `isMinimizable` | property | `Bool` | adaptive |  | ✅ |  |  | not realized; GTK 4: not realized |
| `isTranslucent` | property | `Bool` | adaptive |  | ✅ |  |  | not realized; GTK 4: not realized |
| `maximumHeight` | property | `Double` | native |  | ✅ |  |  | not realized; GTK 4: not realized |
| `maximumWidth` | property | `Double` | native |  | ✅ |  |  | not realized; GTK 4: not realized |
| `minimumHeight` | property | `Double` | native |  | ✅ |  |  | not realized; GTK 4: not realized |
| `minimumWidth` | property | `Double` | native |  | ✅ |  |  | not realized; GTK 4: not realized |
| `modalPopped` | event | `Int` | adaptive | · | ✅ |  |  | cannot goBack on WindowScene - Android's driver has no path for it yet; GTK 4: not realized |
| `resizability` | property | `WindowResizability` | adaptive |  |  |  |  |  |
| `resumed` | event |  | adaptive | 🔌 | ✅ |  |  | only through the host's own: minimize on WindowScene: the host told the activity's phase, no activity moved; GTK 4: not realized |
| `stopped` | event |  | adaptive | 🔌 | ✅ |  |  | only through the host's own: minimize on WindowScene: the host told the activity's phase, no activity moved; GTK 4: not realized |
| `title` | property | `String` | native | · | ✅ |  |  | cannot read title of WindowScene - Android's driver has no path for it yet; GTK 4: not realized |
| `width` | property | `Double` | native |  | ✅ |  |  | not realized; GTK 4: not realized |
| `windowType` | property | `WindowType` | structure |  | ✅ |  |  | not realized; GTK 4: not realized |
| `windowValue` | property | `String` | structure |  | ✅ |  |  | not realized; GTK 4: not realized |
| `x` | property | `Double` | structure |  | ✅ |  |  | not realized; GTK 4: not realized |
| `y` | property | `Double` | structure |  | ✅ |  |  | not realized; GTK 4: not realized |
| `defaultPosition` | property | `UnitPoint` | adaptive |  |  |  |  |  |

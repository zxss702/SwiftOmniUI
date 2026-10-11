<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# App

The application at the root of a SwiftOmniUI tree, and what its host does for it with no control behind it: questions for the user, the files they open and save, what the system launches, the clock and the time zone, the screen reader, what is kept.

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

| Host | Created | Members (22) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 4 ✅ | `App` / structure |  |
| WinUI 3 | ✅ | 12 ✅ | `App` / structure |  |
| GTK 4 | ✅ | 4 ✅ | `GtkApplication` / structure |  |
| Web |  |  | `document` / structure | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Structure/AppContract.swift`.

## App's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `alert` | act | `(String, String, String) -> Void` |  | 🔌 | ✅ | · |  | only through the host's own: read a question: what the relay keeps of the dialog it showed; GTK 4: cannot read a question - GTK's driver has no path for it yet |
| `announce` | act | `(String) -> Void` |  | · | ✅ | · |  | cannot read what the screen reader said - Android's driver has no path for it yet; GTK 4: cannot read what the screen reader said - GTK's driver has no path for it yet |
| `chooseAction` | act | `(String, String?, String?, [String]) -> String?` |  | 🔌 | ✅ | · |  | only through the host's own: read a question: what the relay keeps of the dialog it showed; GTK 4: cannot read a question - GTK's driver has no path for it yet |
| `chooseFiles` | act | `(Bool, [String]) -> [String]` |  |  |  | · |  | GTK 4: cannot read a file dialog - GTK's driver has no path for it yet |
| `confirm` | act | `(String, String, String, String) -> Bool` |  | 🔌 | ✅ | · |  | only through the host's own: read a question: what the relay keeps of the dialog it showed; GTK 4: cannot read a question - GTK's driver has no path for it yet |
| `copyText` | act | `(String) -> Void` |  |  |  | ⏸ |  | GTK 4: waits on App.localizedString, not realized yet |
| `currentTime` | act | `() -> [Double]` |  | ✅ | ✅ | ✅ |  |  |
| `currentTimeZone` | act | `() -> String` |  | ✅ | ✅ | ✅ |  |  |
| `handlerFailed` | act | `(String) -> Void` |  | ✅ | ✅ | · |  | GTK 4: cannot read the log - GTK's driver has no path for it yet |
| `hideOnScreenKeyboard` | act | `() -> Bool` |  | · | ✅ | ✅ |  | cannot focus on TextField - Android's driver has no path for it yet |
| `launchFile` | act | `(ChosenFile) -> Bool` |  |  |  |  |  | GTK 4: not realized |
| `launchLink` | act | `(String) -> Bool` |  |  |  |  |  | GTK 4: not realized |
| `localizedString` | act | `(LocalizedStringKey) -> String` |  |  |  |  |  | GTK 4: not realized |
| `openFiles` | act | `([FileType], Bool) -> [ChosenFile]` |  |  |  |  |  | GTK 4: not realized |
| `openFolders` | act | `(Bool) -> [ChosenFile]` |  |  |  | · |  | GTK 4: cannot read a file dialog - GTK's driver has no path for it yet |
| `persistSceneValue` | act | `(Name, Name, PropValue) -> Void` |  |  | ✅ |  |  | not realized; GTK 4: not realized |
| `persistValue` | act | `(Name, PropValue) -> Void` |  | · | ✅ | · |  | cannot read what is kept - Android's driver has no path for it yet; GTK 4: cannot read what is kept - GTK's driver has no path for it yet |
| `prompt` | act | `(String, String, String, String, String?, Int?, InputPurpose, String) -> String?` |  | 🔌 | ✅ | · |  | only through the host's own: read a question: what the relay keeps of the dialog it showed; GTK 4: cannot read a question - GTK's driver has no path for it yet |
| `readFile` | act | `(ChosenFile) -> [UInt8]` |  |  |  |  |  | GTK 4: not realized |
| `saveFile` | act | `([UInt8], String, [FileType]) -> ChosenFile?` |  |  |  |  |  | GTK 4: not realized |
| `urlOpened` | event | `String` | provider |  |  |  |  | GTK 4: not realized |
| `utcOffset` | act | `(String?, CalendarDate?) -> Int` |  | ✅ | ✅ | ✅ |  |  |

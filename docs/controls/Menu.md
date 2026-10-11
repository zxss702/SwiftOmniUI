<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Menu

A menu: a caption and the entries it opens - on the menu bar, or one level down inside another menu.

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

| Host | Created | Members (4) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | · |  | `PopupMenu` / `MenuItem`; no menu bar | cannot read the menu of Text - Android's driver has no path for it yet |
| WinUI 3 | ✅ | 2 ✅ | `MenuFlyout` / `MenuBar` |  |
| GTK 4 | ✅ | 2 ✅ | `GMenu` in `GtkPopoverMenu` / `GtkPopoverMenuBar` |  |
| Web |  |  | ARIA `menu` / `menubar` (?) | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Menus/MenuContract.swift`.

## Menu's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `isEnabled` | property | `Bool` | native | · | ✅ | ✅ |  | cannot read the menu of Text - Android's driver has no path for it yet |
| `placement` | property | `CommandGroupPlacement` | adaptive |  |  |  |  | GTK 4: not realized |
| `text` | property | `String` | native | · | ✅ | ✅ |  | cannot read the menu of Text - Android's driver has no path for it yet |
| `textKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |

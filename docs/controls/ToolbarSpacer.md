<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# ToolbarSpacer

Room between the items of a page's toolbar - `ToolbarSpacer` writes it.

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

| Host | Created | Members (2) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views |  |  | `Toolbar` `MenuItem` | no run of it on these sources |
| WinUI 3 | ✅ |  | `CommandBar` `AppBarButton`; `AppBarSeparator` for a spacer |  |
| GTK 4 | ✅ |  | `GtkButton` in `GtkHeaderBar`; a spacer packs a separator |  |
| Web |  |  | `<button>` in an ARIA `toolbar` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Menus/ToolbarSpacerContract.swift`.

## ToolbarSpacer's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `placement` | property | `ToolbarItemPlacement` | adaptive |  | ❌ | · |  | WinUI 3: the driver cannot read placement of ToolbarSpacer, and says nothing of why; GTK 4: cannot read placement of ToolbarSpacer - GTK's driver has no path for it yet |
| `variant` | property | `ToolbarSpacerVariant` | adaptive |  | ❌ | · |  | WinUI 3: the driver cannot read variant of ToolbarSpacer, and says nothing of why; GTK 4: cannot read variant of ToolbarSpacer - GTK's driver has no path for it yet |

<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# ToolbarItem

An action in the page's native navigation or toolbar surface.

Layer: `structure`. It carries structure or protocol data rather than configuring a visual platform object.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [MenuItemElement](tiers/MenuItemElement.md)

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

| Host | Created | Members (10) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | · | 1 – | `Toolbar` `MenuItem` | cannot activate on ToolbarItem - Android's driver has no path for it yet |
| WinUI 3 | ✅ | 7 ✅ | `CommandBar` `AppBarButton`; `AppBarSeparator` for a spacer |  |
| GTK 4 | · |  | `GtkButton` in `GtkHeaderBar`; a spacer packs a separator | cannot activate on ToolbarItem - GTK's driver has no path for it yet |
| Web |  |  | `<button>` in an ARIA `toolbar` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Menus/ToolbarItemContract.swift`.

## ToolbarItem's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `placement` | property | `ToolbarItemPlacement` | adaptive | · | ✅ | · |  | cannot read placement of ToolbarItem - Android's driver has no path for it yet; GTK 4: cannot read placement of ToolbarItem - GTK's driver has no path for it yet |
| `priority` | property | `Int` | adaptive | · | ✅ | · |  | cannot read priority of ToolbarItem - Android's driver has no path for it yet; GTK 4: cannot read priority of ToolbarItem - GTK's driver has no path for it yet |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native | – | ✅ |  |  | An Android bar action is a menu entry, which holds no identifier: automation finds it by its title.; GTK 4: not realized |

## From [MenuItemElement](tiers/MenuItemElement.md)

What every item a user chooses from has - a menu's entry, a toolbar's item: a caption, a picture, and something to run.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `onClicked` (`clicked`) | event |  | native | · | ✅ | · |  | cannot activate on ToolbarItem - Android's driver has no path for it yet; GTK 4: cannot activate on ToolbarItem - GTK's driver has no path for it yet |
| `icon` | property | `ImageSource` | adaptive | · | ✅ | · |  | cannot read icon of ToolbarItem - Android's driver has no path for it yet; GTK 4: cannot read icon of ToolbarItem - GTK's driver has no path for it yet |
| `isDestructive` | property | `Bool` | adaptive | · |  |  |  | cannot read isDestructive of ToolbarItem - Android's driver has no path for it yet; WinUI 3: not realized; GTK 4: not realized |
| `isEnabled` | property | `Bool` | native | · | ✅ | · |  | cannot activate on ToolbarItem - Android's driver has no path for it yet; GTK 4: cannot activate on ToolbarItem - GTK's driver has no path for it yet |
| `shortcut` | property | `KeyboardShortcut` | native |  |  |  |  |  |
| `text` | property | `String` | native | · | ✅ | · |  | cannot read text of ToolbarItem - Android's driver has no path for it yet; GTK 4: cannot read text of ToolbarItem - GTK's driver has no path for it yet |
| `textKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |

<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Popover

A transient view presented over a window, anchored to the element that carries it - the platform's own popover, flyout, or anchored panel.

Layer: `adaptive`. Every base host presents it by its platform's conventions, keeping SwiftOmniUI's state contract.

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

| Host | Created | Members (3) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views |  |  | `PopupWindow` | no run of it on these sources |
| WinUI 3 | ⏸ |  | `Flyout` | waits on Popover.isOpen, not realized yet |
| GTK 4 | ⏸ |  | `GtkPopover` | waits on Popover.isOpen, not realized yet |
| Web |  |  | anchored popover (?) | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Menus/PopoverContract.swift`.

## Popover's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `isOpen` | property | `Bool` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `arrowEdge` | property | `Edge` | adaptive |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `dismissed` | event |  | adaptive |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |

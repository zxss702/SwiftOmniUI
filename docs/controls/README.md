# Control dictionary

Every element SwiftOmniUI declares - each control, and each part an application, its windows and its pages are made of - member by member, with what each target host's tests proved of it.

A page is its element's contract rendered: the members it declares itself, then one section per tier it wears, each linking that tier's page. Every member shows its kind - a property, an event or an act - its value, the layer that realizes it, and a mark for each platform, because a host realizes the same inherited member differently on different elements: a background is a layer colour on a label and a drawn fill on an outlined layout.

<!-- legend:begin -->
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
<!-- legend:end -->

A host's column is its tests' verdicts: each host's suite runs the conformance families - one for each contract, a case for every cell of every page - and writes what each said under `exports/marks/<host>/`, one line a member of an element, read here. A host's register - its records, what its runtime registers, what it never has - decides whether a case runs and what its verdict says, and nothing it declares marks a cell by itself. A tier's member is marked on every element wearing the tier, each by its own case. A row has one Notes cell for every host: each host's note prefixed by its name, joined by `; `. Nothing on a page is written by hand: `ControlDictionaryTests` fails when a page or a table below differs from the contracts and the verdicts, or when a verdict names what no contract declares, and `SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests` writes them again.

## Controls

The elements a layout positions - every one wears [View](tiers/View.md).

<!-- controls:begin -->
| Control | Members | Android Views | WinUI 3 | GTK 4 | Web |
| --- | ---: | :---: | :---: | :---: | :---: |
| [ActivityIndicator](ActivityIndicator.md) | 104 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Button](Button.md) | 131 | 59 ✅ · 1 ☑️ · 3 – | 66 ✅ | 22 ✅ · 11 – |  |
| [Canvas](Canvas.md) | 105 | 53 ✅ · 1 ☑️ · 3 – | 53 ✅ · 3 – | 18 ✅ · 14 – |  |
| [CheckBox](CheckBox.md) | 104 | 53 ✅ · 1 ☑️ · 3 – | 56 ✅ | 21 ✅ · 11 – |  |
| [ColorPicker](ColorPicker.md) | 103 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 16 ✅ · 14 – |  |
| [CustomLayout](CustomLayout.md) | 109 |  | 1 ✅ | 16 ✅ · 14 – |  |
| [DatePicker](DatePicker.md) | 118 | 53 ✅ · 1 ☑️ · 3 – | 63 ✅ · 1 ☑️ | 24 ✅ · 3 ☑️ · 11 – |  |
| [Ellipse](Ellipse.md) | 111 | 49 ✅ · 1 ☑️ · 3 – | 58 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Grid](Grid.md) | 114 | 55 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 16 ✅ · 14 – |  |
| [GridRow](GridRow.md) | 109 |  |  |  |  |
| [HStack](HStack.md) | 110 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ · 3 – | 16 ✅ · 14 – |  |
| [Image](Image.md) | 112 | 50 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 16 ✅ · 14 – |  |
| [LazyHGrid](LazyHGrid.md) | 115 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [LazyHStack](LazyHStack.md) | 113 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [LazyVGrid](LazyVGrid.md) | 115 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [LazyVStack](LazyVStack.md) | 113 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [Line](Line.md) | 115 | 53 ✅ · 1 ☑️ · 3 – | 62 ✅ · 3 – | 17 ✅ · 14 – |  |
| [List](List.md) | 112 | 60 ✅ · 1 ☑️ | 59 ✅ | 19 ✅ · 11 – |  |
| [Map](Map.md) | 108 |  |  |  |  |
| [Masked](Masked.md) | 109 |  |  | 17 ✅ · 14 – |  |
| [MenuButton](MenuButton.md) | 102 |  | 1 ✅ | 18 ✅ · 11 – |  |
| [Path](Path.md) | 112 | 50 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Picker](Picker.md) | 122 | 52 ✅ · 1 ☑️ · 3 – | 65 ✅ | 22 ✅ · 11 – |  |
| [Polygon](Polygon.md) | 113 | 51 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Polyline](Polyline.md) | 113 | 51 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 17 ✅ · 14 – |  |
| [PositionIndicator](PositionIndicator.md) | 108 |  |  |  |  |
| [ProgressBar](ProgressBar.md) | 104 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 17 ✅ · 14 – |  |
| [RadioButton](RadioButton.md) | 121 | 59 ✅ · 1 ☑️ · 3 – | 63 ✅ | 24 ✅ · 11 – |  |
| [Rectangle](Rectangle.md) | 112 | 50 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 17 ✅ · 14 – |  |
| [ScrollView](ScrollView.md) | 123 | 52 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 22 ✅ · 11 – |  |
| [SearchField](SearchField.md) | 130 | 62 ✅ · 1 ☑️ | 63 ✅ | 24 ✅ · 11 – |  |
| [Slider](Slider.md) | 108 | 55 ✅ · 1 ☑️ · 3 – | 57 ✅ | 23 ✅ · 13 – |  |
| [Stepper](Stepper.md) | 106 | 50 ✅ · 1 ☑️ · 3 – | 57 ✅ | 19 ✅ · 11 – |  |
| [Switch](Switch.md) | 104 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ | 21 ✅ · 11 – |  |
| [Text](Text.md) | 126 | 61 ✅ · 1 ☑️ · 3 – | 63 ✅ · 3 – | 18 ✅ · 15 – |  |
| [TextEditor](TextEditor.md) | 130 | 62 ✅ · 1 ☑️ | 70 ✅ | 24 ✅ · 11 – |  |
| [TextField](TextField.md) | 132 | 63 ✅ · 1 ☑️ | 68 ✅ | 23 ✅ · 11 – |  |
| [TimePicker](TimePicker.md) | 116 | 53 ✅ · 1 ☑️ · 3 – | 58 ✅ | 24 ✅ · 11 – |  |
| [TitleBar](TitleBar.md) | 104 |  |  |  |  |
| [VStack](VStack.md) | 110 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ · 3 – | 17 ✅ · 14 – |  |
| [WebView](WebView.md) | 111 | 54 ✅ · 1 ☑️ · 3 – |  | 20 ✅ · 11 – |  |
| [ZStack](ZStack.md) | 109 | 51 ✅ · 1 ☑️ · 3 – | 55 ✅ · 3 – | 16 ✅ · 14 – |  |
| **Met** - ✅ and – | 4746 | 1751 of 4746 met | 1822 of 4746 met | 1207 of 4746 met |  |
<!-- controls:end -->

## App structure

The scene, the window and the page an application is made of, the arrangements a page can be, the entries of its toolbar and menus, and the slots and parts the others hold.

<!-- structure:begin -->
| Part | Members | Android Views | WinUI 3 | GTK 4 | Web |
| --- | ---: | :---: | :---: | :---: | :---: |
| [App](App.md) | 22 | 4 ✅ | 12 ✅ | 4 ✅ |  |
| [Content](Content.md) | 0 |  |  |  |  |
| [ContextMenu](ContextMenu.md) | 0 |  |  |  |  |
| [Divider](Divider.md) | 0 |  |  |  |  |
| [LeadingContent](LeadingContent.md) | 0 |  |  |  |  |
| [Menu](Menu.md) | 4 |  | 2 ✅ | 2 ✅ |  |
| [MenuBar](MenuBar.md) | 0 |  |  |  |  |
| [MenuItem](MenuItem.md) | 8 | 1 – | 4 ✅ | 3 ✅ · 2 – |  |
| [ModalStack](ModalStack.md) | 0 |  |  |  |  |
| [NavigationSplitView](NavigationSplitView.md) | 19 | 1 ✅ | 4 ✅ | 4 – |  |
| [NavigationStack](NavigationStack.md) | 18 | 1 ✅ | 3 ✅ | 4 – |  |
| [Overlay](Overlay.md) | 0 |  |  |  |  |
| [Page](Page.md) | 24 | 6 ✅ | 9 ✅ | 4 ✅ · 4 – |  |
| [Pin](Pin.md) | 6 |  |  |  |  |
| [Popover](Popover.md) | 3 |  |  |  |  |
| [Scene](Scene.md) | 6 | 4 ✅ | 6 ✅ |  |  |
| [Span](Span.md) | 19 |  | 9 ✅ |  |  |
| [Spans](Spans.md) | 0 |  |  |  |  |
| [TabView](TabView.md) | 18 | 1 ✅ | 4 ✅ | 4 – |  |
| [TitleView](TitleView.md) | 0 |  |  |  |  |
| [ToolbarItem](ToolbarItem.md) | 10 | 1 – | 7 ✅ |  |  |
| [ToolbarItems](ToolbarItems.md) | 0 |  |  |  |  |
| [ToolbarSpacer](ToolbarSpacer.md) | 2 |  |  |  |  |
| [TrailingContent](TrailingContent.md) | 0 |  |  |  |  |
| [WindowScene](WindowScene.md) | 25 | 2 ✅ | 23 ✅ |  |  |
| **Met** - ✅ and – | 184 | 21 of 184 met | 83 of 184 met | 31 of 184 met |  |
<!-- structure:end -->

## Tiers

Members many elements share, declared once.

<!-- tiers:begin -->
- [PropertyContainer](tiers/PropertyContainer.md) - What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.
- [VisualElement](tiers/VisualElement.md) - What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.
- [View](tiers/View.md) - What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.
- [Layout](tiers/Layout.md) - What every layout has: the screen's unsafe strips it keeps clear of, and whether its children are clipped or let input through.
- [StackBase](tiers/StackBase.md) - What both stacks have: the space between their children.
- [InputView](tiers/InputView.md) - What every field a user types into has: the text's limits and caret, the keyboard it asks for, and the placeholder shown while it is empty.
- [Shape](tiers/Shape.md) - What every drawn shape has: what fills it, the line around it, how it fits its room, and a transform of its own drawing.
- [TextElement](tiers/TextElement.md) - What every element showing words has: the words, and the case they are drawn in.
- [TextStyleElement](tiers/TextStyleElement.md) - How text looks wherever it is drawn: its colour and the space between its letters.
- [FontElement](tiers/FontElement.md) - The font text is drawn in: its family, its size, its weight and slant, and whether it follows the user's text-size setting.
- [TextAlignmentElement](tiers/TextAlignmentElement.md) - Where text sits inside the space its own element was given.
- [LineHeightElement](tiers/LineHeightElement.md) - How far apart the lines of text are.
- [DecorableTextElement](tiers/DecorableTextElement.md) - The lines drawn through or under text.
- [PaddingElement](tiers/PaddingElement.md) - The space kept inside an element, around what it holds.
- [BorderElement](tiers/BorderElement.md) - What an element draws of its own box: the shape its background, its outline and its cut follow, and the outline.
- [ImageElement](tiers/ImageElement.md) - How a picture fills the room it was given.
- [TintElement](tiers/TintElement.md) - A control's one accent colour.
- [BarElement](tiers/BarElement.md) - The bar a page arrangement draws: its colour.
- [MenuItemElement](tiers/MenuItemElement.md) - What every item a user chooses from has - a menu's entry, a toolbar's item: a caption, a picture, and something to run.
- [PageElement](tiers/PageElement.md) - What a page shows about itself where another container presents it as an item - a title and a picture.
- [ControlSizeElement](tiers/ControlSizeElement.md) - How big a control draws - a button, a progress bar, a spinner.
- [ScrollContentElement](tiers/ScrollContentElement.md) - What shows behind a scrollable view's content - a list's or an editor's own canvas, where the platform draws one.
<!-- tiers:end -->

## Layers

Which layer realizes an element or a member - the word each page and each row uses.

<!-- layers:begin -->
- `native` - Every base host presents it with its native toolkit.
- `adaptive` - Every base host presents it by its platform's conventions, keeping SwiftOmniUI's state contract.
- `stateUI` - SwiftOmniUI composes it from smaller primitives before a host receives the tree.
- `structure` - It carries structure or protocol data rather than configuring a visual platform object.
- `provider` - An optional provider supplies it: a package, or the application that registers it with its hosts.
<!-- layers:end -->

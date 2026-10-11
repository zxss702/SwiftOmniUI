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
| [ActivityIndicator](ActivityIndicator.md) | 98 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 21 ✅ · 3 – |  |
| [Button](Button.md) | 125 | 59 ✅ · 1 ☑️ · 3 – | 66 ✅ | 26 ✅ |  |
| [Canvas](Canvas.md) | 99 | 53 ✅ · 1 ☑️ · 3 – | 53 ✅ · 3 – | 21 ✅ · 3 – |  |
| [CheckBox](CheckBox.md) | 98 | 53 ✅ · 1 ☑️ · 3 – | 56 ✅ | 25 ✅ |  |
| [ColorPicker](ColorPicker.md) | 97 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 20 ✅ · 3 – |  |
| [CustomLayout](CustomLayout.md) | 103 |  |  | 20 ✅ · 3 – |  |
| [DatePicker](DatePicker.md) | 112 | 53 ✅ · 1 ☑️ · 3 – | 63 ✅ · 1 ☑️ | 28 ✅ · 3 ☑️ |  |
| [Ellipse](Ellipse.md) | 105 | 49 ✅ · 1 ☑️ · 3 – | 58 ✅ · 3 – | 20 ✅ · 3 – |  |
| [Grid](Grid.md) | 108 | 55 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 24 ✅ · 3 – |  |
| [GridRow](GridRow.md) | 103 |  |  |  |  |
| [HStack](HStack.md) | 104 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ · 3 – | 21 ✅ · 3 – |  |
| [Image](Image.md) | 106 | 50 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 20 ✅ · 3 – |  |
| [LazyHGrid](LazyHGrid.md) | 109 |  |  | 20 ✅ · 3 – |  |
| [LazyHStack](LazyHStack.md) | 107 |  |  | 20 ✅ · 3 – |  |
| [LazyVGrid](LazyVGrid.md) | 109 |  |  | 20 ✅ · 3 – |  |
| [LazyVStack](LazyVStack.md) | 107 |  |  | 20 ✅ · 3 – |  |
| [Line](Line.md) | 109 | 53 ✅ · 1 ☑️ · 3 – | 62 ✅ · 3 – | 20 ✅ · 3 – |  |
| [List](List.md) | 106 | 60 ✅ · 1 ☑️ | 59 ✅ | 32 ✅ |  |
| [Map](Map.md) | 102 |  |  |  |  |
| [Masked](Masked.md) | 103 |  |  | 20 ✅ · 3 – |  |
| [MenuButton](MenuButton.md) | 96 |  |  | 22 ✅ |  |
| [Path](Path.md) | 106 | 50 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 20 ✅ · 3 – |  |
| [Picker](Picker.md) | 116 | 52 ✅ · 1 ☑️ · 3 – | 65 ✅ | 26 ✅ |  |
| [Polygon](Polygon.md) | 107 | 51 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 20 ✅ · 3 – |  |
| [Polyline](Polyline.md) | 107 | 51 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 20 ✅ · 3 – |  |
| [PositionIndicator](PositionIndicator.md) | 102 |  |  |  |  |
| [ProgressBar](ProgressBar.md) | 98 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 21 ✅ · 3 – |  |
| [RadioButton](RadioButton.md) | 115 | 59 ✅ · 1 ☑️ · 3 – | 63 ✅ | 28 ✅ |  |
| [Rectangle](Rectangle.md) | 106 | 50 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 20 ✅ · 3 – |  |
| [ScrollView](ScrollView.md) | 117 | 52 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 30 ✅ |  |
| [SearchField](SearchField.md) | 124 | 62 ✅ · 1 ☑️ | 63 ✅ | 28 ✅ |  |
| [Slider](Slider.md) | 102 | 55 ✅ · 1 ☑️ · 3 – | 57 ✅ | 27 ✅ · 2 – |  |
| [Stepper](Stepper.md) | 100 | 50 ✅ · 1 ☑️ · 3 – | 57 ✅ | 23 ✅ |  |
| [Switch](Switch.md) | 98 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ | 25 ✅ |  |
| [Text](Text.md) | 119 | 61 ✅ · 1 ☑️ · 3 – | 63 ✅ · 3 – | 22 ✅ · 3 – |  |
| [TextEditor](TextEditor.md) | 124 | 62 ✅ · 1 ☑️ | 70 ✅ | 28 ✅ |  |
| [TextField](TextField.md) | 126 | 63 ✅ · 1 ☑️ | 68 ✅ | 27 ✅ |  |
| [TimePicker](TimePicker.md) | 110 | 53 ✅ · 1 ☑️ · 3 – | 58 ✅ | 28 ✅ |  |
| [TitleBar](TitleBar.md) | 98 |  |  |  |  |
| [VStack](VStack.md) | 104 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ · 3 – | 21 ✅ · 3 – |  |
| [WebView](WebView.md) | 105 | 54 ✅ · 1 ☑️ · 3 – |  | 23 ✅ |  |
| [ZStack](ZStack.md) | 103 | 51 ✅ · 1 ☑️ · 3 – | 55 ✅ · 3 – | 20 ✅ · 3 – |  |
| **Met** - ✅ and – | 4493 | 1751 of 4493 met | 1812 of 4493 met | 945 of 4493 met |  |
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
| [NavigationSplitView](NavigationSplitView.md) | 19 | 1 ✅ | 4 ✅ |  |  |
| [NavigationStack](NavigationStack.md) | 18 | 1 ✅ | 3 ✅ |  |  |
| [Overlay](Overlay.md) | 0 |  |  |  |  |
| [Page](Page.md) | 24 | 6 ✅ | 9 ✅ | 4 ✅ |  |
| [Pin](Pin.md) | 6 |  |  |  |  |
| [Popover](Popover.md) | 3 |  |  |  |  |
| [Scene](Scene.md) | 6 | 4 ✅ | 6 ✅ |  |  |
| [Span](Span.md) | 19 |  | 9 ✅ |  |  |
| [Spans](Spans.md) | 0 |  |  |  |  |
| [TabView](TabView.md) | 18 | 1 ✅ | 4 ✅ |  |  |
| [TitleView](TitleView.md) | 0 |  |  |  |  |
| [ToolbarItem](ToolbarItem.md) | 10 | 1 – | 7 ✅ |  |  |
| [ToolbarItems](ToolbarItems.md) | 0 |  |  |  |  |
| [ToolbarSpacer](ToolbarSpacer.md) | 2 |  |  |  |  |
| [TrailingContent](TrailingContent.md) | 0 |  |  |  |  |
| [WindowScene](WindowScene.md) | 25 | 2 ✅ | 23 ✅ |  |  |
| **Met** - ✅ and – | 184 | 21 of 184 met | 83 of 184 met | 15 of 184 met |  |
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

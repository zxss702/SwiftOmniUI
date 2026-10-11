# Platform contract

This document is the shared delivery contract for SwiftOmniUI's hosts:
Android Views, WinUI 3, GTK 4, and Web DOM/CSS. It records the SwiftOmniUI
surface and the implementation evidence for each host.

## Reading the matrix

Every mark is the verdict of a test: each host's suite runs the conformance
families - one a contract, a case for every cell - and writes what each said
under `exports/marks/<host>/`, which the tables are rendered from. A case says
what it proves apart from what it only needs - a button whose click makes the
change - and its outcome is the verdict of what it proves alone. Nothing a
host merely implements or declares by hand earns a mark.

| Mark | Meaning |
| :---: | --- |
| ✅ | Every test of the member that ran on that host passed. |
| ☑️ | The member is proven by its tests, but the host's register records what is still missing; the element's page in [the control dictionary](controls/README.md) names it. |
| – | The member will never be met by that host's family - a phone with no menu bar, a desktop whose keyboard captions no return key, a view that takes no keyboard focus - and meets the contract there: the host's register, or the case that proved it absent, says why, and the Gallery shows that family no example of it. |
| ❌ | A test of the member failed on that host's last run; the note gives the first failure. |
| ◐ | Some of its tests proved it and another could not run or read; the note says which. |
| 🔌 | Its tests passed only through the host's own entry or record - an act the driver hands past the toolkit's input, a read of what the host keeps rather than what the toolkit holds - which the driver names; it is not counted as met. |
| · | The host realizes it, but its driver cannot yet do or read what the test needs. |
| ⏸ | Its test waits on another member the host does not realize. |
| ⌛ | The verdict was written at another revision of its family than it stands at: each run writes its family's revision over its verdicts, and a change that changes what a family's cases prove raises the family's in `lib/SwiftOmniUI.Conformance/revisions.txt`, so a verdict of another is stale until the host's suite runs the family again. It carries no note: what that run said is no verdict of the family as it stands. |
| empty | Not realized on that host, or no run of it; the note says which. It is deliberately not an estimate of how difficult the work will be. |

A host's totals count its ✅ and – as met. An element's ✅ under
[Control creation](#control-creation) means that host's own test proved it
makes the element. It does not imply that every member has been completed;
the member rows state that separately.

An element's row under [Contract members](#contract-members) counts its
members by mark. A tier's member and an act are marked only on the page of
each element that has it: one element may realize what another does not, so
no one mark says it for a host, and the tables naming them here carry none.

Member by member and element by element, the marks live in [the control
dictionary](controls/README.md). Every table of marks here that a contract can
say is rendered from the contracts and from each host's verdicts, as the
dictionary is: `SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter
ControlDictionaryTests` writes them, and the test fails while one differs -
also once a source a verdict rests on changes and the verdict turns stale. The
capabilities, the standard environment and the core view members name no
contract member and carry no mark.

The matrix describes observable SwiftOmniUI semantics. Platform classes are
implementation details. A host may choose another native class when it
preserves the same state, event, accessibility, lifetime, and animation contract.

## Target hosts

| Platform | Runtime | Boundary | Native toolkit |
| --- | --- | --- | --- |
| Linux desktop | Swift with the C API | typed `HostPatch` | GTK 4 |
| Android | Swift with JNI | typed `HostPatch` | Android Views |
| Windows | Swift with C++/WinRT behind a C ABI | typed `HostPatch` | WinUI 3 |
| Browser | Swift compiled to WebAssembly, under a JavaScript relay | typed `HostPatch` | DOM and CSS |

Every host is Swift in the application's process. Code in a platform's own
language - Java, C++/WinRT, JavaScript - relays calls beneath it and holds no
SwiftOmniUI logic.

Web is last in the implementation order. The native desktop and mobile hosts
settle the common semantics before they are mapped to the browser.

## Admission rule

A base control remains in SwiftOmniUI only when it has one honest semantic contract
across the target toolkits or is derived once in SwiftOmniUI from smaller accepted
primitives. An optional capability belongs to a provider package. A control,
property, or event that meets neither rule does not remain as an inert API.

A contract change is vertical. Public Swift API, host vocabulary, every
applicable host, tests, Gallery example, and documentation change together.
The core owns identity, state, diffing, and composition; the host is kept thin.

## Control creation

Every element contract, with the layer that realizes it and a ✅ for each
host whose own passing test proved it makes the element. An empty cell is not
proven there yet: the element's page says what it is on each host, how many
of its members each meets, and why a cell is empty.

<!-- creation:begin -->
| Element | Layer | Android Views | WinUI 3 | GTK 4 | Web |
| --- | --- | :---: | :---: | :---: | :---: |
| [ActivityIndicator](controls/ActivityIndicator.md) | native | ✅ | ✅ | ✅ |  |
| [App](controls/App.md) | structure | ✅ | ✅ | ✅ |  |
| [Button](controls/Button.md) | native | ✅ | ✅ | ✅ |  |
| [Canvas](controls/Canvas.md) | native | ✅ | ✅ | ✅ |  |
| [CheckBox](controls/CheckBox.md) | stateUI | ✅ | ✅ | ✅ |  |
| [ColorPicker](controls/ColorPicker.md) | native | ✅ | ✅ | ✅ |  |
| [Content](controls/Content.md) | structure |  |  |  |  |
| [ContextMenu](controls/ContextMenu.md) | structure | · | ✅ | ✅ |  |
| [CustomLayout](controls/CustomLayout.md) | native |  | ✅ | ✅ |  |
| [DatePicker](controls/DatePicker.md) | native | ✅ | ✅ | ✅ |  |
| [Divider](controls/Divider.md) | structure | · | ✅ | ✅ |  |
| [Ellipse](controls/Ellipse.md) | stateUI | ✅ | ✅ | ✅ |  |
| [Grid](controls/Grid.md) | stateUI | ✅ | ✅ | ✅ |  |
| [GridRow](controls/GridRow.md) | structure |  |  |  |  |
| [HStack](controls/HStack.md) | native | ✅ | ✅ | ❌ |  |
| [Image](controls/Image.md) | native | ✅ | ✅ | ✅ |  |
| [LazyHGrid](controls/LazyHGrid.md) | native |  | ✅ | ✅ |  |
| [LazyHStack](controls/LazyHStack.md) | native |  | ✅ | ✅ |  |
| [LazyVGrid](controls/LazyVGrid.md) | native |  | ✅ | ✅ |  |
| [LazyVStack](controls/LazyVStack.md) | native |  | ✅ | ✅ |  |
| [LeadingContent](controls/LeadingContent.md) | structure |  |  |  |  |
| [Line](controls/Line.md) | stateUI | ✅ | ✅ | ✅ |  |
| [List](controls/List.md) | native | ✅ | ✅ | ✅ |  |
| [Map](controls/Map.md) | provider |  |  |  |  |
| [Masked](controls/Masked.md) | native |  |  | ✅ |  |
| [Menu](controls/Menu.md) | structure | · | ✅ | ✅ |  |
| [MenuBar](controls/MenuBar.md) | structure |  | ✅ | ✅ |  |
| [MenuButton](controls/MenuButton.md) | native |  | ✅ | ✅ |  |
| [MenuItem](controls/MenuItem.md) | structure | · | ✅ | ✅ |  |
| [ModalStack](controls/ModalStack.md) | structure | ◐ | ✅ | ◐ |  |
| [NavigationSplitView](controls/NavigationSplitView.md) | adaptive | ✅ | ✅ | ✅ |  |
| [NavigationStack](controls/NavigationStack.md) | adaptive | ✅ | ✅ | ✅ |  |
| [Overlay](controls/Overlay.md) | structure | · | ✅ | · |  |
| [Page](controls/Page.md) | adaptive | ✅ | ✅ | ✅ |  |
| [Path](controls/Path.md) | stateUI | ✅ | ✅ | ✅ |  |
| [Picker](controls/Picker.md) | native | ✅ | ✅ | ✅ |  |
| [Pin](controls/Pin.md) | provider |  |  |  |  |
| [Polygon](controls/Polygon.md) | stateUI | ✅ | ✅ | ✅ |  |
| [Polyline](controls/Polyline.md) | stateUI | ✅ | ✅ | ✅ |  |
| [Popover](controls/Popover.md) | adaptive |  | ⏸ | ⏸ |  |
| [PositionIndicator](controls/PositionIndicator.md) | stateUI |  |  |  |  |
| [ProgressBar](controls/ProgressBar.md) | native | ✅ | ✅ | ✅ |  |
| [RadioButton](controls/RadioButton.md) | stateUI | ✅ | ✅ | ✅ |  |
| [Rectangle](controls/Rectangle.md) | stateUI | ✅ | ✅ | ✅ |  |
| [Scene](controls/Scene.md) | structure | ✅ | ✅ | ✅ |  |
| [ScrollView](controls/ScrollView.md) | native | ✅ | ✅ | ✅ |  |
| [SearchField](controls/SearchField.md) | native | ✅ | ✅ | ✅ |  |
| [Slider](controls/Slider.md) | native | ✅ | ✅ | ✅ |  |
| [Span](controls/Span.md) | structure | ✅ | ✅ | ✅ |  |
| [Spans](controls/Spans.md) | structure | ✅ | ✅ | ✅ |  |
| [Stepper](controls/Stepper.md) | native | ✅ | ✅ | ✅ |  |
| [Switch](controls/Switch.md) | native | ✅ | ✅ | ✅ |  |
| [TabView](controls/TabView.md) | adaptive | ✅ | ✅ | ✅ |  |
| [Text](controls/Text.md) | native | ✅ | ✅ | ✅ |  |
| [TextEditor](controls/TextEditor.md) | native | ✅ | ✅ | ✅ |  |
| [TextField](controls/TextField.md) | native | ✅ | ✅ | ✅ |  |
| [TimePicker](controls/TimePicker.md) | native | ✅ | ✅ | ✅ |  |
| [TitleBar](controls/TitleBar.md) | adaptive |  |  | ⏸ |  |
| [TitleView](controls/TitleView.md) | structure | ✅ | ✅ | ✅ |  |
| [ToolbarItem](controls/ToolbarItem.md) | structure | · | ✅ | · |  |
| [ToolbarItems](controls/ToolbarItems.md) | structure | · | ✅ | · |  |
| [ToolbarSpacer](controls/ToolbarSpacer.md) | structure |  | ✅ | ✅ |  |
| [TrailingContent](controls/TrailingContent.md) | structure |  |  |  |  |
| [VStack](controls/VStack.md) | native | ✅ | ✅ | ❌ |  |
| [WebView](controls/WebView.md) | native | ✅ |  |  |  |
| [WindowScene](controls/WindowScene.md) | structure | ✅ | ✅ | ⏸ |  |
| [ZStack](controls/ZStack.md) | native | ◐ | ✅ | ❌ |  |
<!-- creation:end -->

Page arrangements expose an optional flat `barBackgroundColor`. A
`NavigationStack` additionally exposes `barForegroundColor` for its title and native
action affordances. A tab selector keeps the toolkit's selected and unselected
appearance. An unwritten background retains the native material; SwiftOmniUI does
not ask a host to rasterize an arbitrary brush into page chrome.

`List` is the native virtualized collection. It presents identified
items as a list, a row or a grid, and SwiftOmniUI builds an item only when the
platform's collection shows it. Its host adapters map to `RecyclerView`,
WinUI `List`, `GtkListView` or `GtkGridView`, and a semantic DOM list/grid;
each member's mark is its case's
verdict on that host, as for every element.

`ForEach`, `GeometryReader`, `ScrollViewReader`, `PlacedLayout`, and `GalleryView` are
SwiftOmniUI compositions or readers rather than additional platform controls. The
core implements them once; their platform behavior depends only on the
primitive rows they use.

## Native control mapping

The table names the native class or API that each host adapts for a SwiftOmniUI
surface. It records no implementation status; the ✅ tables keep that. Where a
host already creates a node, its column names the class it uses.
`composed by SwiftOmniUI` marks a surface SwiftOmniUI derives from other rows,
`structure` a node that creates no native object, `—` a toolkit without an
honest native counterpart, and `(?)` a mapping that is not yet confirmed. A host
may still choose another class that preserves the same contract.

| SwiftOmniUI surface | Android Views | WinUI 3 | GTK 4 | Web |
| --- | --- | --- | --- | --- |
| `App` / `Scene` | `App` / structure | `App` / structure | `GtkApplication` / structure | `document` / structure |
| `WindowScene` | `Activity` | `Window` | `GtkApplicationWindow` | browser `window` |
| `Page` | custom `ViewGroup` | `Page` | custom `GtkWidget` | `<section>` |
| `NavigationStack` | custom `ViewGroup` stack + `Toolbar` | `Frame` | `GtkStack` + `GtkHeaderBar`; libadwaita `AdwNavigationView` | History API |
| `TabView` | custom `LinearLayout` tab row | `NavigationView` with a top pane | `GtkStack` + `GtkStackSwitcher`; libadwaita `AdwViewStack` | ARIA `tablist` |
| `NavigationSplitView` | custom `ViewGroup`: a drawer where narrow, beside where wide | `NavigationSplitView` | `GtkPaned`; libadwaita `AdwOverlaySplitView` | `<aside>` |
| `ModalStack` | full-screen `Dialog` (?) | `ContentDialog` (?) | modal `GtkWindow`; libadwaita `AdwDialog` | `<dialog>` with `showModal()` |
| `Overlay` | top child of a `FrameLayout` | top layer of a root `Grid` | `GtkOverlay` | positioned element above the page |
| `TitleBar` | — | `TitleBar` | `GtkHeaderBar` | — |
| `ContextMenu`, `MenuBar`, `Menu`, `MenuItem`, `Divider` | `PopupMenu` / `MenuItem`; no menu bar | `MenuFlyout` / `MenuBar` | `GMenu` in `GtkPopoverMenu` / `GtkPopoverMenuBar` | ARIA `menu` / `menubar` (?) |
| `MenuButton` | `PopupMenu` on a button | `DropDownButton` + `MenuFlyout` | `GtkMenuButton` + `GMenu` | `<details>` / ARIA `button` + `menu` |
| `Popover` | `PopupWindow` | `Flyout` | `GtkPopover` | anchored popover (?) |
| `ToolbarItems` / `ToolbarItem` / `ToolbarSpacer` | `Toolbar` `MenuItem` | `CommandBar` `AppBarButton`; `AppBarSeparator` for a spacer | `GtkButton` in `GtkHeaderBar`; a spacer packs a separator | `<button>` in an ARIA `toolbar` |
| `ZStack` | custom `ViewGroup` | `Canvas` | `GtkFixed` | `position: absolute` |
| `VStack` / `HStack` | custom `ViewGroup` | `StackPanel` | `GtkBox` | flexbox |
| `LazyVStack` / `LazyHStack` | custom `ViewGroup` driven the same | custom `Panel` driven the same | custom `GtkWidget` driven the same | custom element driven the same |
| `LazyVGrid` / `LazyHGrid` | custom `ViewGroup` driven the same | custom `Panel` driven the same | custom `GtkWidget` driven the same | custom element driven the same |
| `Grid` / `GridRow` | composed by SwiftOmniUI | composed by SwiftOmniUI | composed by SwiftOmniUI | composed by SwiftOmniUI |
| `CustomLayout` | custom `ViewGroup` driven the same | custom `Panel` driven the same | `GtkLayoutManager` on a `GtkWidget` | custom element driven the same |
| `Masked` | custom `ViewGroup` masked the same | `Opacity` over a masked `Panel` | `GskMaskNode` over the content child | CSS `mask-image` |
| `ScrollView` | `ScrollView` / `HorizontalScrollView` | `ScrollViewer` | `GtkScrolledWindow` | `overflow: auto` |
| `Text` / `Spans` / `Span` | `TextView`; `SpannableString` spans | `TextBlock`; `Run` inlines | `GtkLabel`; `PangoAttrList` runs | text element; `<span>` runs |
| `Button` | `Button` | `ToggleButton` | `GtkToggleButton` | `<button>` |
| `Image` | `ImageView` | `Image` | `GtkPicture` | `<img>` |
| `ColorPicker` | `View` + `GradientDrawable` | `Border` | custom `GtkWidget` snapshot | `<div>` |
| `TextField` | `EditText` | `TextBox` / `PasswordBox` | `GtkEntry` / `GtkPasswordEntry` | `<input>` |
| `TextEditor` | multi-line `EditText` | multi-line `TextBox` | `GtkTextView` | `<textarea>` |
| `SearchField` | `SearchView` | `AutoSuggestBox` | `GtkSearchEntry` | `<input type=search>` |
| `Picker` | `Spinner` | `ComboBox` | `GtkDropDown` | `<select>` |
| `DatePicker` | `DatePickerDialog` | `CalendarDatePicker` | `GtkCalendar` in a `GtkPopover` | `<input type=date>` |
| `TimePicker` | `TimePickerDialog` | `TimePicker` | — | `<input type=time>` |
| `Switch` | `Switch` | `ToggleSwitch` | `GtkSwitch` | checkbox `<input>` with `role=switch` |
| `CheckBox` | `CheckBox` | `CheckBox` | `GtkCheckButton` | `<input type=checkbox>` |
| `RadioButton` | `RadioButton` | `RadioButton` | grouped `GtkCheckButton` | `<input type=radio>` |
| `Slider` | `SeekBar` | `Slider` | `GtkScale` | `<input type=range>` |
| `Stepper` | custom `NumberPicker`-based view | `NumberBox` | `GtkSpinButton` | `<input type=number>` |
| `ProgressBar` | horizontal `ProgressBar` | `ProgressBar` | `GtkProgressBar` | `<progress>` |
| `ActivityIndicator` | indeterminate `ProgressBar` | `ProgressRing` | `GtkSpinner` | indeterminate `<progress>` |
| `Canvas` | `View` `onDraw(Canvas)` | Direct2D in a `SurfaceImageSource` | `GtkDrawingArea` | `<canvas>` |
| `Rectangle` / `Ellipse` | `View` drawing `Path` | `Microsoft.UI.Xaml.Shapes` | `GskPath` in a snapshot | inline SVG |
| `Line` / `Path` / `Polygon` / `Polyline` | `View` drawing `Path` | `Microsoft.UI.Xaml.Shapes` | `GskPath` in a snapshot | inline SVG |
| `PositionIndicator` | composed by SwiftOmniUI | composed by SwiftOmniUI | composed by SwiftOmniUI | composed by SwiftOmniUI |
| `WebView` | `WebView` | `WebView2` | WebKitGTK `WebKitWebView` | `<iframe>` (?) |
| `Map` / `Pin` | Google Play services `MapView` / `Marker` (?) | `MapControl` (?) | libshumate `ShumateMap` / `ShumateMarker` | — |
| `List` | AndroidX `RecyclerView` | `List` | `GtkListView` / `GtkGridView` | semantic list or grid |
| `Content`, `LeadingContent`, `TrailingContent`, `TitleView` | structure | structure | structure | structure |

### Completeness

Every element contract appears exactly once in the first column; each
element's page in the control dictionary takes its native counterparts from
here, and `ControlDictionaryTests` holds the table to that.

These surfaces lack an honest native counterpart on at least one target:

- `NavigationStack`: Android Views and GTK 4 without libadwaita have no page-stack control.
- `TabView`: Android Views has no framework tab bar; Web has no tab element.
- `NavigationSplitView`: Android Views depends on AndroidX `DrawerLayout`; Web has no native pane.
- `ModalStack`: Android Views has no modal page presentation; WinUI 3 shows one `ContentDialog` at a time, so its host stacks sheets of a dialog's look over the window.
- `TitleBar`: Android Views and Web have no window title bar.
- Menus: Android Views has no menu bar; Web has no native menu element.
- `Grid`: GTK 4 has no container with star and auto tracks.
- `Stepper`: Android Views has no stepper; `NumberPicker` is an integer wheel.
- `DatePicker`: GTK 4 has `GtkCalendar` but no date field.
- `TimePicker`: GTK 4 has no time picker.
- `Switch`: Web has no switch element.
- `ActivityIndicator`: Web has no spinner; an indeterminate `<progress>` draws a bar.
- `PositionIndicator`: Android Views and Web have no page indicator.
- `WebView`: GTK 4 depends on WebKitGTK; Web cannot observe navigation or set a user agent in a cross-origin `<iframe>`.
- `Map` / `Pin`: Web has no map element; Android Views, WinUI 3, and GTK 4 depend on Google Play services, a map service, and libshumate.
- `List`: Android Views depends on AndroidX `RecyclerView`; Web has no native virtualized list.

## Shared state, patch, and animation capabilities

What every host does with the renderer's patch and the animation it carries.
These carry no mark: no conformance case gives a verdict for a capability
as such, so none is claimed for any host.

- sparse `HostRender` / `HostPatch` application
- stable element identity and arranged children
- driven state modes and typed channel kinds
- native input committed before handler dispatch
- silent application writes
- host-driven Journey interpolation with eased and spring animation
- host-driven Journey retargeting with standing velocity
- sparse property transitions through `HostPatch.transitions`
- layout animation through `HostPatch.animation` and `AnimationLanes`
- Journey completion and interruption
- Journey stop and snap
- SwiftOmniUI display-cycle engines
- element teardown releases external native attachments

## Standard environment

SwiftOmniUI's seven standard environment domains, each a set of facts a host
supplies and keeps current. These carry no mark: no conformance case gives a
verdict for a domain as a whole, so none is claimed for any host.

- `Battery`: `chargeLevel`, `state`, `powerSource`, `energySaverStatus`
- `Connectivity`: `networkAccess`, `connectionProfiles`
- `DeviceDisplay`: `width`, `height`, `density`, `orientation`, `rotation`, `refreshRate`
- `LocaleInfo`: `language`, `region`, `name`, `timeZone`, `uses24HourClock`, `firstDayOfWeek`, `isMetric`
- `DeviceInfo`: `formFactor`, `platform`, `model`, `manufacturer`, `name`, `versionString`, `deviceType`
- `AppInfo`: `name`, `packageName`, `versionString`, `buildString`, `colorScheme`
- `ApplicationSession`: `phase`

The public provider and its fallback values exist whatever a host supplies.
[Environment](concepts/environment.md) defines that schema; the hosts' pages
say what each host supplies.

## Host acts

An act is what the application asks a host to do rather than describes: ask
the user a question, read the clock or the time zone, keep a value, take a
web view back or move a map. An act of the application's contract aims at
nothing; an element's act aims at one element of its kind. Calendar values are
portable SwiftOmniUI values; reading the current clock or time zone is a host act
because the host owns the active locale and zone database - `currentTime` is
`ClockTime.now()`, `currentTimeZone` is `TimeZoneInfo.local()`, and `utcOffset`
is `TimeZoneInfo.utcOffset(of:on:)`. The table names each act; its marks are
on the page of its element - a tier's act on the page of each element wearing
the tier.

<!-- acts:begin -->
| Act | Contract |
| --- | --- |
| `focus` | [VisualElement](controls/tiers/VisualElement.md) |
| `unfocus` | [VisualElement](controls/tiers/VisualElement.md) |
| `alert` | [App](controls/App.md) |
| `announce` | [App](controls/App.md) |
| `chooseAction` | [App](controls/App.md) |
| `chooseFiles` | [App](controls/App.md) |
| `confirm` | [App](controls/App.md) |
| `copyText` | [App](controls/App.md) |
| `currentTime` | [App](controls/App.md) |
| `currentTimeZone` | [App](controls/App.md) |
| `handlerFailed` | [App](controls/App.md) |
| `hideOnScreenKeyboard` | [App](controls/App.md) |
| `launchFile` | [App](controls/App.md) |
| `launchLink` | [App](controls/App.md) |
| `localizedString` | [App](controls/App.md) |
| `openFiles` | [App](controls/App.md) |
| `openFolders` | [App](controls/App.md) |
| `persistSceneValue` | [App](controls/App.md) |
| `persistValue` | [App](controls/App.md) |
| `prompt` | [App](controls/App.md) |
| `readFile` | [App](controls/App.md) |
| `saveFile` | [App](controls/App.md) |
| `utcOffset` | [App](controls/App.md) |
| `measureText` | [Canvas](controls/Canvas.md) |
| `scrollTo` | [List](controls/List.md) |
| `moveToRegion` | [Map](controls/Map.md) |
| `scrollToDescendant` | [ScrollView](controls/ScrollView.md) |
| `evaluateJavaScript` | [WebView](controls/WebView.md) |
| `goBack` | [WebView](controls/WebView.md) |
| `goForward` | [WebView](controls/WebView.md) |
| `reload` | [WebView](controls/WebView.md) |
<!-- acts:end -->

## Shared view members

A property or event of the three tiers every view wears -
[PropertyContainer](controls/tiers/PropertyContainer.md),
[VisualElement](controls/tiers/VisualElement.md) and
[View](controls/tiers/View.md) - is named here and marked on the page of each
view: every view realizes it apart, and one may have what another lacks. The
core view members are SwiftOmniUI's own API, which a host serves without a member
of its own; no case gives them a verdict of their own, so no page marks them:

- identity: `id`
- aimed control methods: `aim`
- core reactions: `onAppear`, `onDisappear`, `onChange`, `samples`, `engine`
- animation selection: `animation`, `AnimationValues`, `AnimationLanes`
- focus feed: `isFocused`

<!-- shared:begin -->
| Member | Tier | Kind |
| --- | --- | --- |
| `accessibilityIdentifier` | [PropertyContainer](controls/tiers/PropertyContainer.md) | property |
| `blendMode` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `accessibilityChildBehavior` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `accessibilityHeadingLevel` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `accessibilityHint` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `accessibilityLabel` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `accessibilityTraits` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `automationExcludedWithChildren` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `background` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `blur` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `contentTransition` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `compositingGroup` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `drawingGroup` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `frame` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `height` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `hint` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `hintKey` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `horizontalAlignmentDefault` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `ignoresInput` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `isAccessibilityHidden` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `isEnabled` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `isFocusedChanged` | [VisualElement](controls/tiers/VisualElement.md) | event |
| `isFrameContent` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `isGeometryReader` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `isLayoutDecoration` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `isVisible` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `layoutDirection` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `matchedGeometry` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `matchedGeometrySource` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `maximumHeight` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `maximumWidth` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `minimumHeight` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `minimumWidth` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `opacity` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `pivotX` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `pivotY` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `rotation` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `rotationX` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `rotationY` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `safeAreaInsetEdge` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `scale` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `scaleX` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `scaleY` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `shadow` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `style` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `symbolEffect` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `symbolEffectActive` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `symbolEffectOptions` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `symbolEffectValue` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `transition` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `translationX` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `translationY` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `verticalAlignmentDefault` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `width` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `zIndex` | [VisualElement](controls/tiers/VisualElement.md) | property |
| `allowDrop` | [View](controls/tiers/View.md) | property |
| `area` | [View](controls/tiers/View.md) | property |
| `canDrag` | [View](controls/tiers/View.md) | property |
| `coordinateSpaceName` | [View](controls/tiers/View.md) | property |
| `dragLeave` | [View](controls/tiers/View.md) | event |
| `dragOver` | [View](controls/tiers/View.md) | event |
| `dragStarting` | [View](controls/tiers/View.md) | event |
| `dragText` | [View](controls/tiers/View.md) | property |
| `onDrop` (`drop`) | [View](controls/tiers/View.md) | event |
| `dropCompleted` | [View](controls/tiers/View.md) | event |
| `dropPaths` | [View](controls/tiers/View.md) | event |
| `flex` | [View](controls/tiers/View.md) | property |
| `frameChanged` | [View](controls/tiers/View.md) | event |
| `gridColumn` | [View](controls/tiers/View.md) | property |
| `gridColumnSpan` | [View](controls/tiers/View.md) | property |
| `gridRow` | [View](controls/tiers/View.md) | property |
| `gridRowSpan` | [View](controls/tiers/View.md) | property |
| `horizontalAlignment` | [View](controls/tiers/View.md) | property |
| `horizontalContentAlignment` | [View](controls/tiers/View.md) | property |
| `horizontalGuide` | [View](controls/tiers/View.md) | property |
| `layoutPriority` | [View](controls/tiers/View.md) | property |
| `namedFramesChanged` | [View](controls/tiers/View.md) | event |
| `padding` | [View](controls/tiers/View.md) | property |
| `panTouchCount` | [View](controls/tiers/View.md) | property |
| `onPanUpdated` (`panUpdated`) | [View](controls/tiers/View.md) | event |
| `panXChannel` | [View](controls/tiers/View.md) | property |
| `panYChannel` | [View](controls/tiers/View.md) | property |
| `pinchUpdated` | [View](controls/tiers/View.md) | event |
| `pointerEntered` | [View](controls/tiers/View.md) | event |
| `pointerExited` | [View](controls/tiers/View.md) | event |
| `pointerMoved` | [View](controls/tiers/View.md) | event |
| `pointerPressed` | [View](controls/tiers/View.md) | event |
| `pointerReleased` | [View](controls/tiers/View.md) | event |
| `pointerStyle` | [View](controls/tiers/View.md) | property |
| `swipeDirection` | [View](controls/tiers/View.md) | property |
| `swipeThreshold` | [View](controls/tiers/View.md) | property |
| `onSwiped` (`swiped`) | [View](controls/tiers/View.md) | event |
| `tag` | [View](controls/tiers/View.md) | property |
| `tapCount` | [View](controls/tiers/View.md) | property |
| `onTapGesture` (`tapGesture`) | [View](controls/tiers/View.md) | event |
| `verticalAlignment` | [View](controls/tiers/View.md) | property |
| `verticalContentAlignment` | [View](controls/tiers/View.md) | property |
| `verticalGuide` | [View](controls/tiers/View.md) | property |
<!-- shared:end -->

## Control dictionary

Every control, and every part an application, its windows and its pages are made of, has its members in [the control dictionary](controls/README.md): one row per property, event and act, with a mark per platform. The counts below are rendered with it.

<!-- dictionary:begin -->
### Controls

| Control | Members | Android Views | WinUI 3 | GTK 4 | Web |
| --- | ---: | :---: | :---: | :---: | :---: |
| [ActivityIndicator](controls/ActivityIndicator.md) | 104 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Button](controls/Button.md) | 131 | 59 ✅ · 1 ☑️ · 3 – | 66 ✅ | 22 ✅ · 11 – |  |
| [Canvas](controls/Canvas.md) | 105 | 53 ✅ · 1 ☑️ · 3 – | 53 ✅ · 3 – | 18 ✅ · 14 – |  |
| [CheckBox](controls/CheckBox.md) | 104 | 53 ✅ · 1 ☑️ · 3 – | 56 ✅ | 21 ✅ · 11 – |  |
| [ColorPicker](controls/ColorPicker.md) | 103 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 16 ✅ · 14 – |  |
| [CustomLayout](controls/CustomLayout.md) | 109 |  | 1 ✅ | 16 ✅ · 14 – |  |
| [DatePicker](controls/DatePicker.md) | 118 | 53 ✅ · 1 ☑️ · 3 – | 63 ✅ · 1 ☑️ | 24 ✅ · 3 ☑️ · 11 – |  |
| [Ellipse](controls/Ellipse.md) | 111 | 49 ✅ · 1 ☑️ · 3 – | 58 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Grid](controls/Grid.md) | 114 | 55 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 16 ✅ · 14 – |  |
| [GridRow](controls/GridRow.md) | 109 |  |  |  |  |
| [HStack](controls/HStack.md) | 110 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ · 3 – | 16 ✅ · 14 – |  |
| [Image](controls/Image.md) | 112 | 50 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 16 ✅ · 14 – |  |
| [LazyHGrid](controls/LazyHGrid.md) | 115 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [LazyHStack](controls/LazyHStack.md) | 113 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [LazyVGrid](controls/LazyVGrid.md) | 115 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [LazyVStack](controls/LazyVStack.md) | 113 |  | 2 ✅ | 17 ✅ · 14 – |  |
| [Line](controls/Line.md) | 115 | 53 ✅ · 1 ☑️ · 3 – | 62 ✅ · 3 – | 17 ✅ · 14 – |  |
| [List](controls/List.md) | 112 | 60 ✅ · 1 ☑️ | 59 ✅ | 19 ✅ · 11 – |  |
| [Map](controls/Map.md) | 108 |  |  |  |  |
| [Masked](controls/Masked.md) | 109 |  |  | 17 ✅ · 14 – |  |
| [MenuButton](controls/MenuButton.md) | 102 |  | 1 ✅ | 18 ✅ · 11 – |  |
| [Path](controls/Path.md) | 112 | 50 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Picker](controls/Picker.md) | 122 | 52 ✅ · 1 ☑️ · 3 – | 65 ✅ | 22 ✅ · 11 – |  |
| [Polygon](controls/Polygon.md) | 113 | 51 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 17 ✅ · 14 – |  |
| [Polyline](controls/Polyline.md) | 113 | 51 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 17 ✅ · 14 – |  |
| [PositionIndicator](controls/PositionIndicator.md) | 108 |  |  |  |  |
| [ProgressBar](controls/ProgressBar.md) | 104 | 51 ✅ · 1 ☑️ · 3 – | 50 ✅ · 3 – | 17 ✅ · 14 – |  |
| [RadioButton](controls/RadioButton.md) | 121 | 59 ✅ · 1 ☑️ · 3 – | 63 ✅ | 24 ✅ · 11 – |  |
| [Rectangle](controls/Rectangle.md) | 112 | 50 ✅ · 1 ☑️ · 3 – | 59 ✅ · 3 – | 17 ✅ · 14 – |  |
| [ScrollView](controls/ScrollView.md) | 123 | 52 ✅ · 1 ☑️ · 3 – | 60 ✅ · 3 – | 22 ✅ · 11 – |  |
| [SearchField](controls/SearchField.md) | 130 | 62 ✅ · 1 ☑️ | 60 ✅ | 24 ✅ · 11 – |  |
| [Slider](controls/Slider.md) | 108 | 55 ✅ · 1 ☑️ · 3 – | 57 ✅ | 23 ✅ · 13 – |  |
| [Stepper](controls/Stepper.md) | 106 | 50 ✅ · 1 ☑️ · 3 – | 57 ✅ | 19 ✅ · 11 – |  |
| [Switch](controls/Switch.md) | 104 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ | 21 ✅ · 11 – |  |
| [Text](controls/Text.md) | 126 | 61 ✅ · 1 ☑️ · 3 – | 63 ✅ · 3 – | 18 ✅ · 15 – |  |
| [TextEditor](controls/TextEditor.md) | 130 | 62 ✅ · 1 ☑️ | 62 ✅ | 24 ✅ · 11 – |  |
| [TextField](controls/TextField.md) | 132 | 63 ✅ · 1 ☑️ | 58 ✅ | 23 ✅ · 11 – |  |
| [TimePicker](controls/TimePicker.md) | 116 | 53 ✅ · 1 ☑️ · 3 – | 58 ✅ | 24 ✅ · 11 – |  |
| [TitleBar](controls/TitleBar.md) | 104 |  |  |  |  |
| [VStack](controls/VStack.md) | 110 | 52 ✅ · 1 ☑️ · 3 – | 56 ✅ · 3 – | 17 ✅ · 14 – |  |
| [WebView](controls/WebView.md) | 111 | 54 ✅ · 1 ☑️ · 3 – |  | 20 ✅ · 11 – |  |
| [ZStack](controls/ZStack.md) | 109 | 51 ✅ · 1 ☑️ · 3 – | 55 ✅ · 3 – | 16 ✅ · 14 – |  |
| **Met** - ✅ and – | 4746 | 1751 of 4746 met | 1801 of 4746 met | 1207 of 4746 met |  |

### App structure

| Part | Members | Android Views | WinUI 3 | GTK 4 | Web |
| --- | ---: | :---: | :---: | :---: | :---: |
| [App](controls/App.md) | 22 | 4 ✅ | 12 ✅ | 4 ✅ |  |
| [Content](controls/Content.md) | 0 |  |  |  |  |
| [ContextMenu](controls/ContextMenu.md) | 0 |  |  |  |  |
| [Divider](controls/Divider.md) | 0 |  |  |  |  |
| [LeadingContent](controls/LeadingContent.md) | 0 |  |  |  |  |
| [Menu](controls/Menu.md) | 4 |  | 2 ✅ | 2 ✅ |  |
| [MenuBar](controls/MenuBar.md) | 0 |  |  |  |  |
| [MenuItem](controls/MenuItem.md) | 8 | 1 – | 4 ✅ | 3 ✅ · 2 – |  |
| [ModalStack](controls/ModalStack.md) | 0 |  |  |  |  |
| [NavigationSplitView](controls/NavigationSplitView.md) | 19 | 1 ✅ | 4 ✅ | 4 – |  |
| [NavigationStack](controls/NavigationStack.md) | 18 | 1 ✅ | 3 ✅ | 4 – |  |
| [Overlay](controls/Overlay.md) | 0 |  |  |  |  |
| [Page](controls/Page.md) | 24 | 6 ✅ | 9 ✅ | 4 ✅ · 4 – |  |
| [Pin](controls/Pin.md) | 6 |  |  |  |  |
| [Popover](controls/Popover.md) | 3 |  |  |  |  |
| [Scene](controls/Scene.md) | 6 | 4 ✅ | 6 ✅ |  |  |
| [Span](controls/Span.md) | 19 |  | 9 ✅ |  |  |
| [Spans](controls/Spans.md) | 0 |  |  |  |  |
| [TabView](controls/TabView.md) | 18 | 1 ✅ | 4 ✅ | 4 – |  |
| [TitleView](controls/TitleView.md) | 0 |  |  |  |  |
| [ToolbarItem](controls/ToolbarItem.md) | 10 | 1 – | 7 ✅ |  |  |
| [ToolbarItems](controls/ToolbarItems.md) | 0 |  |  |  |  |
| [ToolbarSpacer](controls/ToolbarSpacer.md) | 2 |  |  |  |  |
| [TrailingContent](controls/TrailingContent.md) | 0 |  |  |  |  |
| [WindowScene](controls/WindowScene.md) | 25 | 2 ✅ | 23 ✅ |  |  |
| **Met** - ✅ and – | 184 | 21 of 184 met | 83 of 184 met | 31 of 184 met |  |
<!-- dictionary:end -->

## Contract members

A row per contract with properties or events - the tiers, then the elements -
naming them: a property by its modifier's name, an event with the `on…`
modifier it is heard through beside it. "Count" is how many members the row
names. An element's row counts them by mark on each host; a tier's carries no
mark, its members marked on the page of each element wearing it. A contract's
acts are under [Host acts](#host-acts); each member's own mark, its value and
its layer are on the element's page in [the control dictionary](controls/README.md).

<!-- members:begin -->
### Tiers

| Tier | Members | Count |
| --- | --- | --- |
| [PropertyContainer](controls/tiers/PropertyContainer.md) | `accessibilityIdentifier` | 1 |
| [VisualElement](controls/tiers/VisualElement.md) | `blendMode`, `accessibilityChildBehavior`, `accessibilityHeadingLevel`, `accessibilityHint`, `accessibilityLabel`, `accessibilityTraits`, `automationExcludedWithChildren`, `background`, `blur`, `contentTransition`, `compositingGroup`, `drawingGroup`, `frame`, `height`, `hint`, `hintKey`, `horizontalAlignmentDefault`, `ignoresInput`, `isAccessibilityHidden`, `isEnabled`, `isFocusedChanged`, `isFrameContent`, `isGeometryReader`, `isLayoutDecoration`, `isVisible`, `layoutDirection`, `matchedGeometry`, `matchedGeometrySource`, `maximumHeight`, `maximumWidth`, `minimumHeight`, `minimumWidth`, `opacity`, `pivotX`, `pivotY`, `rotation`, `rotationX`, `rotationY`, `safeAreaInsetEdge`, `scale`, `scaleX`, `scaleY`, `shadow`, `style`, `symbolEffect`, `symbolEffectActive`, `symbolEffectOptions`, `symbolEffectValue`, `transition`, `translationX`, `translationY`, `verticalAlignmentDefault`, `width`, `zIndex` | 54 |
| [View](controls/tiers/View.md) | `allowDrop`, `area`, `canDrag`, `coordinateSpaceName`, `dragLeave`, `dragOver`, `dragStarting`, `dragText`, `onDrop` (`drop`), `dropCompleted`, `dropPaths`, `flex`, `frameChanged`, `gridColumn`, `gridColumnSpan`, `gridRow`, `gridRowSpan`, `horizontalAlignment`, `horizontalContentAlignment`, `horizontalGuide`, `layoutPriority`, `namedFramesChanged`, `padding`, `panTouchCount`, `onPanUpdated` (`panUpdated`), `panXChannel`, `panYChannel`, `pinchUpdated`, `pointerEntered`, `pointerExited`, `pointerMoved`, `pointerPressed`, `pointerReleased`, `pointerStyle`, `swipeDirection`, `swipeThreshold`, `onSwiped` (`swiped`), `tag`, `tapCount`, `onTapGesture` (`tapGesture`), `verticalAlignment`, `verticalContentAlignment`, `verticalGuide` | 43 |
| [Layout](controls/tiers/Layout.md) | `ignoresSafeArea`, `clipsContent`, `letsInputThrough`, `hitShape`, `scrollTargetLayout` | 5 |
| [StackBase](controls/tiers/StackBase.md) | `spacing` | 1 |
| [InputView](controls/tiers/InputView.md) | `cursorPosition`, `textContentType`, `isReadOnly`, `isSpellCheckEnabled`, `isTextPredictionEnabled`, `maximumLength`, `placeholder`, `placeholderKey`, `placeholderColor`, `selectionLength`, `onTextChanged` (`textChanged`) | 11 |
| [Shape](controls/tiers/Shape.md) | `aspect`, `fill`, `renderTransform`, `stroke`, `strokeBorder`, `strokeDashOffset`, `strokeDashPattern`, `strokeLineCap`, `strokeLineJoin`, `strokeMiterLimit`, `strokeWidth` | 11 |
| [TextElement](controls/tiers/TextElement.md) | `text`, `textKey`, `textCase`, `baselineOffset` | 4 |
| [TextStyleElement](controls/tiers/TextStyleElement.md) | `characterSpacing`, `foregroundStyle` | 2 |
| [FontElement](controls/tiers/FontElement.md) | `fontAttributes`, `fontAutoScalingEnabled`, `fontFamily`, `fontSize`, `fontTextStyle`, `fontWeight`, `fontDesign` | 7 |
| [TextAlignmentElement](controls/tiers/TextAlignmentElement.md) | `multilineTextAlignment`, `verticalTextAlignment` | 2 |
| [LineHeightElement](controls/tiers/LineHeightElement.md) | `lineHeight`, `lineSpacing` | 2 |
| [DecorableTextElement](controls/tiers/DecorableTextElement.md) | `textDecorations` | 1 |
| [PaddingElement](controls/tiers/PaddingElement.md) | `contentPadding` | 1 |
| [BorderElement](controls/tiers/BorderElement.md) | `shape`, `stroke`, `strokeWidth` | 3 |
| [ImageElement](controls/tiers/ImageElement.md) | `aspect` | 1 |
| [TintElement](controls/tiers/TintElement.md) | `tint` | 1 |
| [BarElement](controls/tiers/BarElement.md) | `barBackgroundColor` | 1 |
| [MenuItemElement](controls/tiers/MenuItemElement.md) | `onClicked` (`clicked`), `icon`, `isDestructive`, `isEnabled`, `shortcut`, `text`, `textKey` | 7 |
| [PageElement](controls/tiers/PageElement.md) | `badge`, `document`, `icon`, `interactiveDismissDisabled`, `preferredColumnWidth`, `presentationDetents`, `presentationDragIndicator`, `subtitle`, `subtitleKey`, `title`, `titleKey`, `toolbarBackground`, `toolbarVisibility`, `windowBackground` | 14 |
| [ControlSizeElement](controls/tiers/ControlSizeElement.md) | `controlSize` | 1 |
| [ScrollContentElement](controls/tiers/ScrollContentElement.md) | `scrollContentBackground` | 1 |

### Elements

| Element | Members | Count | Android Views | WinUI 3 | GTK 4 | Web |
| --- | --- | --- | :---: | :---: | :---: | :---: |
| [ActivityIndicator](controls/ActivityIndicator.md) | `isRunning`, `progressStyle` | 2 | 1 ✅ | 1 ✅ | 1 ✅ |  |
| [App](controls/App.md) | `urlOpened` | 1 |  |  |  |  |
| [Button](controls/Button.md) | `buttonStyle`, `onClicked` (`clicked`), `icon`, `iconPosition`, `iconSpacing`, `isOn`, `lineBreak`, `onPressed` (`pressed`), `onReleased` (`released`), `role`, `shortcut`, `onToggled` (`toggled`) | 12 | 4 ✅ | 3 ✅ | 1 ✅ |  |
| [Canvas](controls/Canvas.md) | `onDragged` (`dragged`), `drawable`, `onPressed` (`pressed`), `onReleased` (`released`) | 4 | 4 ✅ | 4 ✅ |  |  |
| [CheckBox](controls/CheckBox.md) | `isOn`, `onToggled` (`toggled`) | 2 | 2 ✅ | 2 ✅ | 2 ✅ |  |
| [ColorPicker](controls/ColorPicker.md) | `color`, `cornerRadius` | 2 | 2 ✅ | 2 ✅ |  |  |
| [DatePicker](controls/DatePicker.md) | `onClosed` (`closed`), `date`, `onDateChanged` (`dateChanged`), `format`, `isOpen`, `maximumDate`, `minimumDate`, `onOpened` (`opened`) | 8 |  | 7 ✅ · 1 ☑️ | 5 ✅ · 3 ☑️ |  |
| [Grid](controls/Grid.md) | `columnSpacing`, `columns`, `flowColumns`, `rowSpacing`, `rows` | 5 | 4 ✅ | 4 ✅ |  |  |
| [Image](controls/Image.md) | `isAnimating`, `renderingMode`, `source`, `isResizable` | 4 |  | 1 ✅ |  |  |
| [LazyHGrid](controls/LazyHGrid.md) | `items`, `columnSpacing`, `flowRows`, `rowSpacing`, `realizedChanged` | 5 |  | 1 ✅ | 1 ✅ |  |
| [LazyHStack](controls/LazyHStack.md) | `items`, `realizedChanged` | 2 |  | 1 ✅ | 1 ✅ |  |
| [LazyVGrid](controls/LazyVGrid.md) | `items`, `columnSpacing`, `flowColumns`, `rowSpacing`, `realizedChanged` | 5 |  | 1 ✅ | 1 ✅ |  |
| [LazyVStack](controls/LazyVStack.md) | `items`, `realizedChanged` | 2 |  | 1 ✅ | 1 ✅ |  |
| [Line](controls/Line.md) | `x1`, `x2`, `y1`, `y2` | 4 | 4 ✅ | 4 ✅ |  |  |
| [List](controls/List.md) | `items`, `itemsLayout`, `listStyle`, `selectionMode`, `selectedItems`, `selectionChanged`, `itemActivated`, `endReachedWithin`, `endReached`, `realizedChanged` | 10 | 8 ✅ | 9 ✅ |  |  |
| [Map](controls/Map.md) | `isScrollEnabled`, `isTrafficEnabled`, `isZoomEnabled`, `onMapClicked` (`mapClicked`), `mapType`, `region`, `showsUserLocation` | 7 |  |  |  |  |
| [Menu](controls/Menu.md) | `isEnabled`, `placement`, `text`, `textKey` | 4 |  | 2 ✅ | 2 ✅ |  |
| [MenuButton](controls/MenuButton.md) | `menuIndicator`, `menuStyle` | 2 |  |  |  |  |
| [NavigationSplitView](controls/NavigationSplitView.md) | `isSidebarVisible`, `isSidebarVisibleChanged`, `columnVisibility`, `columnVisibilityChanged` | 4 |  | 2 ✅ |  |  |
| [NavigationStack](controls/NavigationStack.md) | `barForegroundColor`, `popped` | 2 |  | 1 ✅ |  |  |
| [Page](controls/Page.md) | `appearing`, `backButtonTitle`, `background`, `disappearing`, `hasBackButton`, `hasNavigationBar`, `navigatedFrom`, `navigatedTo`, `navigatingFrom`, `contentPadding` | 10 | 6 ✅ | 8 ✅ | 4 ✅ |  |
| [Path](controls/Path.md) | `data` | 1 | 1 ✅ | 1 ✅ |  |  |
| [Picker](controls/Picker.md) | `onClosed` (`closed`), `isOpen`, `onOpened` (`opened`), `options`, `pickerStyle`, `selectedIndex`, `onSelectedIndexChanged` (`selectedIndexChanged`), `title`, `titleKey` | 9 | 2 ✅ | 7 ✅ | 3 ✅ |  |
| [Pin](controls/Pin.md) | `address`, `label`, `location`, `onPinClicked` (`pinClicked`), `onPinDetailsClicked` (`pinDetailsClicked`), `type` | 6 |  |  |  |  |
| [Polygon](controls/Polygon.md) | `fillRule`, `points` | 2 | 2 ✅ | 2 ✅ |  |  |
| [Polyline](controls/Polyline.md) | `fillRule`, `points` | 2 | 2 ✅ | 2 ✅ |  |  |
| [Popover](controls/Popover.md) | `isOpen`, `arrowEdge`, `dismissed` | 3 |  |  |  |  |
| [PositionIndicator](controls/PositionIndicator.md) | `count`, `hideSingle`, `indicatorColor`, `indicatorSize`, `indicatorsShape`, `maximumVisible`, `position`, `selectedIndicatorColor` | 8 |  |  |  |  |
| [ProgressBar](controls/ProgressBar.md) | `progress`, `progressStyle` | 2 | 1 ✅ | 1 ✅ | 1 ✅ |  |
| [RadioButton](controls/RadioButton.md) | `groupName`, `isOn`, `onToggled` (`toggled`) | 3 | 3 ✅ | 3 ✅ | 3 ✅ |  |
| [Rectangle](controls/Rectangle.md) | `cornerRadius` | 1 | 1 ✅ | 1 ✅ |  |  |
| [Scene](controls/Scene.md) | `activated`, `deactivated`, `destroying`, `stopped`, `windowClosed`, `windowRestored` | 6 | 4 ✅ | 6 ✅ |  |  |
| [ScrollView](controls/ScrollView.md) | `defaultScrollAnchor`, `horizontalScrollIndicators`, `isScrollDisabled`, `orientation`, `scrollBounceAxes`, `scrollBounceBehavior`, `scrollOffset`, `onScrollStopped` (`scrollStopped`), `scrollTargetBehavior`, `scrollXChanged`, `scrollYChanged`, `verticalScrollIndicators` | 12 | 2 ✅ | 7 ✅ | 2 ✅ |  |
| [SearchField](controls/SearchField.md) | `submitLabel`, `onSubmit` (`submitted`) | 2 | 1 ✅ | 1 ✅ | 1 ✅ |  |
| [Slider](controls/Slider.md) | `onDragCompleted` (`dragCompleted`), `onDragStarted` (`dragStarted`), `maximum`, `minimum`, `value`, `onValueChanged` (`valueChanged`) | 6 | 4 ✅ | 4 ✅ | 4 ✅ · 2 – |  |
| [Span](controls/Span.md) | `background`, `image` | 2 |  | 1 ✅ |  |  |
| [Stepper](controls/Stepper.md) | `maximum`, `minimum`, `step`, `value`, `onValueChanged` (`valueChanged`) | 5 |  | 5 ✅ |  |  |
| [Switch](controls/Switch.md) | `isOn`, `onToggled` (`toggled`) | 2 | 2 ✅ | 2 ✅ | 2 ✅ |  |
| [TabView](controls/TabView.md) | `currentPage`, `currentPageChanged` | 2 |  | 2 ✅ |  |  |
| [Text](controls/Text.md) | `lineBreak`, `lineLimit`, `minimumScaleFactor`, `selectable`, `textRenderer`, `textLayoutChanged`, `textFrameChanged` | 7 | 2 ✅ | 2 ✅ | 1 – |  |
| [TextEditor](controls/TextEditor.md) | `growsWithText` | 1 | 1 ✅ | 1 ✅ |  |  |
| [TextField](controls/TextField.md) | `isPassword`, `submitLabel`, `showsClearButton`, `onSubmit` (`submitted`), `textFieldStyle` | 5 | 2 ✅ |  | 1 ✅ |  |
| [TimePicker](controls/TimePicker.md) | `onClosed` (`closed`), `format`, `isOpen`, `onOpened` (`opened`), `time`, `onTimeChanged` (`timeChanged`) | 6 |  | 2 ✅ | 5 ✅ |  |
| [TitleBar](controls/TitleBar.md) | `barForegroundColor`, `icon`, `subtitle`, `title` | 4 |  |  |  |  |
| [ToolbarItem](controls/ToolbarItem.md) | `placement`, `priority` | 2 |  | 2 ✅ |  |  |
| [ToolbarSpacer](controls/ToolbarSpacer.md) | `placement`, `variant` | 2 |  |  |  |  |
| [WebView](controls/WebView.md) | `canGoBackChanged`, `canGoForwardChanged`, `onNavigated` (`navigated`), `onNavigating` (`navigating`), `onProcessTerminated` (`processTerminated`), `source`, `userAgent` | 7 | 2 ✅ |  |  |  |
| [WindowScene](controls/WindowScene.md) | `activated`, `created`, `deactivated`, `destroying`, `floatsOnTop`, `height`, `hidesWhenInactive`, `isMaximizable`, `isMinimizable`, `isTranslucent`, `maximumHeight`, `maximumWidth`, `minimumHeight`, `minimumWidth`, `modalPopped`, `resizability`, `resumed`, `stopped`, `title`, `width`, `windowType`, `windowValue`, `x`, `y`, `defaultPosition` | 25 | 2 ✅ | 23 ✅ |  |  |
<!-- members:end -->

A one-axis `ScrollView` owns input along its enabled axis. When it is nested,
a dominant input on its disabled axis passes to the nearest enclosing scroller.
This behavior is part of the shared contract and must be proved before a host's
`ScrollView` rows receive ✅.

## Complete host vocabulary

The inventory is rendered from the contracts: every node type an element
contract declares, and every name a member is declared under, so a review
sees a name enter or leave the contract. Each contract's `layer` says who
realizes the element and each of its members.

<!-- vocabulary:begin -->
### Controls and structural nodes

`ActivityIndicator`, `App`, `Button`, `Canvas`, `CheckBox`, `ColorPicker`,
`Content`, `ContextMenu`, `CustomLayout`, `DatePicker`, `Divider`, `Ellipse`,
`Grid`, `GridRow`, `HStack`, `Image`, `LazyHGrid`, `LazyHStack`, `LazyVGrid`,
`LazyVStack`, `LeadingContent`, `Line`, `List`, `Map`, `Masked`, `Menu`,
`MenuBar`, `MenuButton`, `MenuItem`, `ModalStack`, `NavigationSplitView`,
`NavigationStack`, `Overlay`, `Page`, `Path`, `Picker`, `Pin`, `Polygon`,
`Polyline`, `Popover`, `PositionIndicator`, `ProgressBar`, `RadioButton`,
`Rectangle`, `Scene`, `ScrollView`, `SearchField`, `Slider`, `Span`, `Spans`,
`Stepper`, `Switch`, `TabView`, `Text`, `TextEditor`, `TextField`, `TimePicker`,
`TitleBar`, `TitleView`, `ToolbarItem`, `ToolbarItems`, `ToolbarSpacer`,
`TrailingContent`, `VStack`, `WebView`, `WindowScene`, `ZStack`.

### Properties

`accessibilityChildBehavior`, `accessibilityHeadingLevel`, `accessibilityHint`,
`accessibilityIdentifier`, `accessibilityLabel`, `accessibilityTraits`,
`address`, `allowDrop`, `area`, `arrowEdge`, `aspect`,
`automationExcludedWithChildren`, `backButtonTitle`, `background`, `badge`,
`barBackgroundColor`, `barForegroundColor`, `baselineOffset`, `blendMode`,
`blur`, `buttonStyle`, `canDrag`, `characterSpacing`, `clipsContent`, `color`,
`columns`, `columnSpacing`, `columnVisibility`, `compositingGroup`,
`contentPadding`, `contentTransition`, `controlSize`, `coordinateSpaceName`,
`cornerRadius`, `count`, `currentPage`, `cursorPosition`, `data`, `date`,
`defaultPosition`, `defaultScrollAnchor`, `document`, `dragText`, `drawable`,
`drawingGroup`, `endReachedWithin`, `fill`, `fillRule`, `flex`, `floatsOnTop`,
`flowColumns`, `flowRows`, `fontAttributes`, `fontAutoScalingEnabled`,
`fontDesign`, `fontFamily`, `fontSize`, `fontTextStyle`, `fontWeight`,
`foregroundStyle`, `format`, `frame`, `gridColumn`, `gridColumnSpan`, `gridRow`,
`gridRowSpan`, `groupName`, `growsWithText`, `hasBackButton`,
`hasNavigationBar`, `height`, `hideSingle`, `hidesWhenInactive`, `hint`,
`hintKey`, `hitShape`, `horizontalAlignment`, `horizontalAlignmentDefault`,
`horizontalContentAlignment`, `horizontalGuide`, `horizontalScrollIndicators`,
`icon`, `iconPosition`, `iconSpacing`, `ignoresInput`, `ignoresSafeArea`,
`image`, `indicatorColor`, `indicatorSize`, `indicatorsShape`,
`interactiveDismissDisabled`, `isAccessibilityHidden`, `isAnimating`,
`isDestructive`, `isEnabled`, `isFrameContent`, `isGeometryReader`,
`isLayoutDecoration`, `isMaximizable`, `isMinimizable`, `isOn`, `isOpen`,
`isPassword`, `isReadOnly`, `isResizable`, `isRunning`, `isScrollDisabled`,
`isScrollEnabled`, `isSidebarVisible`, `isSpellCheckEnabled`,
`isTextPredictionEnabled`, `isTrafficEnabled`, `isTranslucent`, `isVisible`,
`isZoomEnabled`, `items`, `itemsLayout`, `label`, `layoutDirection`,
`layoutPriority`, `letsInputThrough`, `lineBreak`, `lineHeight`, `lineLimit`,
`lineSpacing`, `listStyle`, `location`, `mapType`, `matchedGeometry`,
`matchedGeometrySource`, `maximum`, `maximumDate`, `maximumHeight`,
`maximumLength`, `maximumVisible`, `maximumWidth`, `menuIndicator`, `menuStyle`,
`minimum`, `minimumDate`, `minimumHeight`, `minimumScaleFactor`, `minimumWidth`,
`multilineTextAlignment`, `opacity`, `options`, `orientation`, `padding`,
`panTouchCount`, `panXChannel`, `panYChannel`, `pickerStyle`, `pivotX`,
`pivotY`, `placeholder`, `placeholderColor`, `placeholderKey`, `placement`,
`pointerStyle`, `points`, `position`, `preferredColumnWidth`,
`presentationDetents`, `presentationDragIndicator`, `priority`, `progress`,
`progressStyle`, `region`, `renderingMode`, `renderTransform`, `resizability`,
`role`, `rotation`, `rotationX`, `rotationY`, `rows`, `rowSpacing`,
`safeAreaInsetEdge`, `scale`, `scaleX`, `scaleY`, `scrollBounceAxes`,
`scrollBounceBehavior`, `scrollContentBackground`, `scrollOffset`,
`scrollTargetBehavior`, `scrollTargetLayout`, `selectable`, `selectedIndex`,
`selectedIndicatorColor`, `selectedItems`, `selectionLength`, `selectionMode`,
`shadow`, `shape`, `shortcut`, `showsClearButton`, `showsUserLocation`,
`source`, `spacing`, `step`, `stroke`, `strokeBorder`, `strokeDashOffset`,
`strokeDashPattern`, `strokeLineCap`, `strokeLineJoin`, `strokeMiterLimit`,
`strokeWidth`, `style`, `submitLabel`, `subtitle`, `subtitleKey`,
`swipeDirection`, `swipeThreshold`, `symbolEffect`, `symbolEffectActive`,
`symbolEffectOptions`, `symbolEffectValue`, `tag`, `tapCount`, `text`,
`textCase`, `textContentType`, `textDecorations`, `textFieldStyle`, `textKey`,
`textRenderer`, `time`, `tint`, `title`, `titleKey`, `toolbarBackground`,
`toolbarVisibility`, `transition`, `translationX`, `translationY`, `type`,
`userAgent`, `value`, `variant`, `verticalAlignment`,
`verticalAlignmentDefault`, `verticalContentAlignment`, `verticalGuide`,
`verticalScrollIndicators`, `verticalTextAlignment`, `width`,
`windowBackground`, `windowType`, `windowValue`, `x`, `x1`, `x2`, `y`, `y1`,
`y2`, `zIndex`.

### Events

`activated`, `appearing`, `canGoBackChanged`, `canGoForwardChanged`, `clicked`,
`closed`, `columnVisibilityChanged`, `created`, `currentPageChanged`,
`dateChanged`, `deactivated`, `destroying`, `disappearing`, `dismissed`,
`dragCompleted`, `dragged`, `dragLeave`, `dragOver`, `dragStarted`,
`dragStarting`, `drop`, `dropCompleted`, `dropPaths`, `endReached`,
`frameChanged`, `isFocusedChanged`, `isSidebarVisibleChanged`, `itemActivated`,
`mapClicked`, `modalPopped`, `namedFramesChanged`, `navigated`, `navigatedFrom`,
`navigatedTo`, `navigating`, `navigatingFrom`, `opened`, `panUpdated`,
`pinchUpdated`, `pinClicked`, `pinDetailsClicked`, `pointerEntered`,
`pointerExited`, `pointerMoved`, `pointerPressed`, `pointerReleased`, `popped`,
`pressed`, `processTerminated`, `realizedChanged`, `released`, `resumed`,
`scrollStopped`, `scrollXChanged`, `scrollYChanged`, `selectedIndexChanged`,
`selectionChanged`, `stopped`, `submitted`, `swiped`, `tapGesture`,
`textChanged`, `textFrameChanged`, `textLayoutChanged`, `timeChanged`,
`toggled`, `urlOpened`, `valueChanged`, `windowClosed`, `windowRestored`.

### Acts

`alert`, `announce`, `chooseAction`, `chooseFiles`, `confirm`, `copyText`,
`currentTime`, `currentTimeZone`, `evaluateJavaScript`, `focus`, `goBack`,
`goForward`, `handlerFailed`, `hideOnScreenKeyboard`, `launchFile`,
`launchLink`, `localizedString`, `measureText`, `moveToRegion`, `openFiles`,
`openFolders`, `persistSceneValue`, `persistValue`, `prompt`, `readFile`,
`reload`, `saveFile`, `scrollTo`, `scrollToDescendant`, `unfocus`, `utcOffset`.
<!-- vocabulary:end -->

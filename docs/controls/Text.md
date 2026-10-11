<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Text

A read-only piece of text.

Layer: `native`. Every base host presents it with its native toolkit.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [VisualElement](tiers/VisualElement.md) · [View](tiers/View.md) · [TextElement](tiers/TextElement.md) · [TextStyleElement](tiers/TextStyleElement.md) · [FontElement](tiers/FontElement.md) · [TextAlignmentElement](tiers/TextAlignmentElement.md) · [LineHeightElement](tiers/LineHeightElement.md) · [DecorableTextElement](tiers/DecorableTextElement.md) · [PaddingElement](tiers/PaddingElement.md)

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

| Host | Created | Members (119) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 61 ✅ · 1 ☑️ · 3 – | `TextView`; `SpannableString` spans |  |
| WinUI 3 | ✅ | 63 ✅ · 3 – | `TextBlock`; `Run` inlines |  |
| GTK 4 | ✅ | 22 ✅ · 3 – | `GtkLabel`; `PangoAttrList` runs |  |
| Web |  |  | text element; `<span>` runs | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Text/TextContract.swift`.

## Text's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `lineBreak` | property | `LineBreak` | native | ✅ | ✅ | ◐ |  | GTK 4: cannot read lineBreak of Text - GTK's driver has no path for it yet |
| `lineLimit` | property | `Int` | native | ✅ | ✅ | ◐ |  | GTK 4: cannot read lineLimit of Text - GTK's driver has no path for it yet |
| `minimumScaleFactor` | property | `Double` | native |  |  |  |  |  |
| `selectable` | property | `Bool` | native |  |  |  |  |  |
| `textRenderer` | property | `String` | native |  |  |  |  |  |
| `textLayoutChanged` | event | `TextLayoutReport` | native |  |  |  |  |  |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native | ✅ | ✅ |  |  | GTK 4: not realized |

## From [VisualElement](tiers/VisualElement.md)

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `blendMode` | property | `BlendMode` | native |  |  |  |  |  |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |  |  |  |  |  |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native | · | ✅ | · |  | cannot read a heading's level - Android marks a heading, not its level; GTK 4: cannot read accessibilityHeadingLevel of Text - GTK's driver has no path for it yet |
| `accessibilityHint` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityHint of Text - GTK's driver has no path for it yet |
| `accessibilityLabel` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityLabel of Text - GTK's driver has no path for it yet |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  |  |  |  |
| `automationExcludedWithChildren` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read automationExcludedWithChildren of Text - GTK's driver has no path for it yet |
| `background` | property | `Background` | native | ✅ | ✅ | · |  | GTK 4: cannot read background of Text - GTK's driver has no path for it yet |
| `blur` | property | `Double` | native |  |  |  |  |  |
| `contentTransition` | property | `String` | native |  |  |  |  |  |
| `compositingGroup` | property | `Bool` | native |  |  |  |  |  |
| `drawingGroup` | property | `Bool` | native |  |  |  |  |  |
| `focus` | act | `() -> Bool` |  | – | – | – |  | Text takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Text takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Text takes no keyboard focus here: it refuses it, and nothing is heard |
| `frame` | property | `Rect` | structure | ✅ | ✅ | ✅ |  |  |
| `height` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `hint` | property | `String` | native |  |  |  |  |  |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `ignoresInput` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isAccessibilityHidden` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read isAccessibilityHidden of Text - GTK's driver has no path for it yet |
| `isEnabled` | property | `Bool` | native |  |  | ✅ |  | not realized; WinUI 3: not realized |
| `isFocusedChanged` | event | `Bool` | native | – | – | – |  | Text takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Text takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Text takes no keyboard focus here: it refuses it, and nothing is heard |
| `isVisible` | property | `Bool` | native | ✅ | ✅ | ✅ |  |  |
| `layoutDirection` | property | `LayoutDirection` | native |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read layoutDirection of Text - GTK's driver has no path for it yet |
| `matchedGeometry` | property | `String` | native |  |  |  |  |  |
| `matchedGeometrySource` | property | `Bool` | native |  |  |  |  |  |
| `maximumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `maximumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `opacity` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `pivotX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotX of Text - GTK's driver has no path for it yet |
| `pivotY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotY of Text - GTK's driver has no path for it yet |
| `rotation` | property | `Angle` | native | ✅ | ✅ | · |  | GTK 4: cannot read rotation of Text - GTK's driver has no path for it yet |
| `rotationX` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationX of Text - GTK's driver has no path for it yet |
| `rotationY` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationY of Text - GTK's driver has no path for it yet |
| `scale` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scale of Text - GTK's driver has no path for it yet |
| `scaleX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleX of Text - GTK's driver has no path for it yet |
| `scaleY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleY of Text - GTK's driver has no path for it yet |
| `shadow` | property | `DropShadow` | native |  |  |  |  |  |
| `style` | property | `Name` | structure | ✅ | ✅ | ✅ |  |  |
| `symbolEffect` | property | `String` | native |  |  |  |  |  |
| `symbolEffectActive` | property | `Bool` | native |  |  |  |  |  |
| `symbolEffectOptions` | property | `Int` | native |  |  |  |  |  |
| `symbolEffectValue` | property | `String` | native |  |  |  |  |  |
| `transition` | property | `AnyTransition` | native |  |  |  |  |  |
| `translationX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationX of Text - GTK's driver has no path for it yet |
| `translationY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationY of Text - GTK's driver has no path for it yet |
| `unfocus` | act | `() -> Void` |  | – | – | – |  | Text takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Text takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Text takes no keyboard focus here: it refuses it, and nothing is heard |
| `width` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `zIndex` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [View](tiers/View.md)

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `allowDrop` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `area` | property | `Area` | structure | ✅ | ✅ | ✅ |  |  |
| `canDrag` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `coordinateSpaceName` | property | `String` | stateUI |  |  |  |  |  |
| `dragLeave` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dragOver` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dragStarting` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dragText` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onDrop` (`drop`) | event | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dropCompleted` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dropPaths` | event | `([String], Point)` | native |  |  |  |  |  |
| `flex` | property | `Double` | stateUI |  |  |  |  |  |
| `frameChanged` | event | `[Double]` | native | ✅ | ✅ | ✅ |  |  |
| `gridColumn` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `gridColumnSpan` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `gridRow` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `gridRowSpan` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `horizontalAlignment` | property | `AxisAlignment` | native | ✅ | ✅ | ✅ |  |  |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `horizontalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |
| `layoutPriority` | property | `Double` | stateUI |  |  |  |  |  |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  |  |
| `padding` | property | `EdgeInsets` | native | ✅ | ✅ | ✅ |  |  |
| `panTouchCount` | property | `Int` | structure | ☑️ | ✅ | · |  | The host layer hears a one-finger pan only; any other `panTouchCount` turns the pan off.; GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `panXChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `panYChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native | ✅ | ✅ | · |  | GTK 4: cannot pinch on Text - GTK's driver has no path for it yet |
| `pointerEntered` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Text - GTK's driver has no path for it yet |
| `pointerExited` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Text - GTK's driver has no path for it yet |
| `pointerMoved` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Text - GTK's driver has no path for it yet |
| `pointerPressed` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Text - GTK's driver has no path for it yet |
| `pointerReleased` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Text - GTK's driver has no path for it yet |
| `pointerStyle` | property | `PointerStyle` | native |  |  |  |  |  |
| `swipeDirection` | property | `SwipeDirection` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `swipeThreshold` | property | `Double` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on Text - GTK's driver has no path for it yet |
| `tag` | property | `PropValue` | stateUI |  |  |  |  |  |
| `tapCount` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot tap on Text - GTK's driver has no path for it yet |
| `onTapGesture` (`tapGesture`) | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot tap on Text - GTK's driver has no path for it yet |
| `verticalAlignment` | property | `AxisAlignment` | native | ✅ | ✅ | ✅ |  |  |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `verticalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |

## From [TextElement](tiers/TextElement.md)

What every element showing words has: the words, and the case they are drawn in.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `text` | property | `String` | native | ◐ | ✅ | ✅ |  | cannot slide on Slider - Android's driver has no path for it yet |
| `textKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `textCase` | property | `TextCase` | native | ✅ | ✅ | ✅ |  |  |
| `baselineOffset` | property | `Double` | native |  |  |  |  |  |

## From [TextStyleElement](tiers/TextStyleElement.md)

How text looks wherever it is drawn: its colour and the space between its letters.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `characterSpacing` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read characterSpacing of Text - GTK's driver has no path for it yet |
| `foregroundStyle` | property | `Color` | native | ✅ | ✅ | · |  | GTK 4: cannot read foregroundStyle of Text - GTK's driver has no path for it yet |

## From [FontElement](tiers/FontElement.md)

The font text is drawn in: its family, its size, its weight and slant, and whether it follows the user's text-size setting.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `fontAttributes` | property | `FontAttributes` | native | ✅ | ✅ | · |  | GTK 4: cannot read fontAttributes of Text - GTK's driver has no path for it yet |
| `fontAutoScalingEnabled` | property | `Bool` | adaptive |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `fontFamily` | property | `Name` | native | · | ✅ | · |  | cannot read a family - Android's typeface keeps no family's name; GTK 4: cannot read fontFamily of Text - GTK's driver has no path for it yet |
| `fontSize` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read fontSize of Text - GTK's driver has no path for it yet |
| `fontTextStyle` | property | `FontTextStyle` | native |  |  |  |  |  |
| `fontWeight` | property | `Weight` | native |  |  |  |  |  |
| `fontDesign` | property | `FontDesign` | native |  |  |  |  |  |

## From [TextAlignmentElement](tiers/TextAlignmentElement.md)

Where text sits inside the space its own element was given.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `multilineTextAlignment` | property | `TextAlignment` | native | ✅ | ✅ | · |  | GTK 4: cannot read multilineTextAlignment of Text - GTK's driver has no path for it yet |
| `verticalTextAlignment` | property | `TextAlignment` | native | ✅ | ✅ | · |  | GTK 4: cannot read verticalTextAlignment of Text - GTK's driver has no path for it yet |

## From [LineHeightElement](tiers/LineHeightElement.md)

How far apart the lines of text are.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `lineHeight` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read lineHeight of Text - GTK's driver has no path for it yet |
| `lineSpacing` | property | `Double` | native |  |  |  |  |  |

## From [DecorableTextElement](tiers/DecorableTextElement.md)

The lines drawn through or under text.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `textDecorations` | property | `TextDecorations` | native | ✅ | ✅ | · |  | GTK 4: cannot read textDecorations of Text - GTK's driver has no path for it yet |

## From [PaddingElement](tiers/PaddingElement.md)

The space kept inside an element, around what it holds.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `contentPadding` | property | `EdgeInsets` | native | ✅ | ✅ | · |  | GTK 4: cannot read contentPadding of Text - GTK's driver has no path for it yet |

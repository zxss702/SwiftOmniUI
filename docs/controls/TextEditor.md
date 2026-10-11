<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# TextEditor

A text field of several lines.

Layer: `native`. Every base host presents it with its native toolkit.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [VisualElement](tiers/VisualElement.md) · [View](tiers/View.md) · [InputView](tiers/InputView.md) · [TextElement](tiers/TextElement.md) · [TextStyleElement](tiers/TextStyleElement.md) · [FontElement](tiers/FontElement.md) · [TextAlignmentElement](tiers/TextAlignmentElement.md) · [PaddingElement](tiers/PaddingElement.md) · [ControlSizeElement](tiers/ControlSizeElement.md) · [ScrollContentElement](tiers/ScrollContentElement.md)

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

| Host | Created | Members (130) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 62 ✅ · 1 ☑️ | multi-line `EditText` |  |
| WinUI 3 | ✅ | 62 ✅ | multi-line `TextBox` |  |
| GTK 4 | ✅ | 24 ✅ · 11 – | `GtkTextView` |  |
| Web |  |  | `<textarea>` | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Text/TextEditorContract.swift`.

## TextEditor's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `growsWithText` | property | `Bool` | native | ✅ | ✅ | ❌ |  | GTK 4: true expected, false came - grown with its words |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native | ✅ | ✅ |  |  | GTK 4: not realized |

## From [VisualElement](tiers/VisualElement.md)

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `blendMode` | property | `BlendMode` | native |  |  | – |  | GTK 4: GTK composites every view normally; a blend pass over its own content draws nothing yet. |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |  |  | – |  | GTK 4: GTK's accessibility bridge answers no child behaviour yet. |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native | · | ✅ | · |  | cannot read a heading's level - Android marks a heading, not its level; GTK 4: cannot read accessibilityHeadingLevel of TextEditor - GTK's driver has no path for it yet |
| `accessibilityHint` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityHint of TextEditor - GTK's driver has no path for it yet |
| `accessibilityLabel` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityLabel of TextEditor - GTK's driver has no path for it yet |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  | – |  | GTK 4: GTK's accessibility bridge answers no traits yet. |
| `automationExcludedWithChildren` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read automationExcludedWithChildren of TextEditor - GTK's driver has no path for it yet |
| `background` | property | `Background` | native | ✅ |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `blur` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `contentTransition` | property | `String` | native |  |  | – |  | GTK 4: GTK swaps a label's words with no transition yet. |
| `compositingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `drawingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `focus` | act | `() -> Bool` |  | ✅ | ✅ | ✅ |  |  |
| `frame` | property | `Rect` | structure | ✅ | ✅ | ✅ |  |  |
| `height` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `hint` | property | `String` | native |  |  | · |  | GTK 4: cannot read hint of TextEditor - GTK's driver has no path for it yet |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `horizontalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `ignoresInput` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isAccessibilityHidden` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read isAccessibilityHidden of TextEditor - GTK's driver has no path for it yet |
| `isEnabled` | property | `Bool` | native | ◐ | ✅ | ✅ |  | waits on TextEditor.isReadOnly |
| `isFocusedChanged` | event | `Bool` | native | ✅ | ✅ | ✅ |  |  |
| `isFrameContent` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isGeometryReader` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isLayoutDecoration` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isVisible` | property | `Bool` | native | ✅ | ✅ | ✅ |  |  |
| `layoutDirection` | property | `LayoutDirection` | native |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read layoutDirection of TextEditor - GTK's driver has no path for it yet |
| `matchedGeometry` | property | `String` | native |  |  | – |  | GTK 4: GTK's layout motion flies no matched child into place yet. |
| `matchedGeometrySource` | property | `Bool` | native |  |  | – |  | GTK 4: GTK's layout motion flies no matched child into place yet. |
| `maximumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `maximumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `opacity` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `pivotX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotX of TextEditor - GTK's driver has no path for it yet |
| `pivotY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotY of TextEditor - GTK's driver has no path for it yet |
| `rotation` | property | `Angle` | native | ✅ | ✅ | · |  | GTK 4: cannot read rotation of TextEditor - GTK's driver has no path for it yet |
| `rotationX` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationX of TextEditor - GTK's driver has no path for it yet |
| `rotationY` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationY of TextEditor - GTK's driver has no path for it yet |
| `safeAreaInsetEdge` | property | `Edge` | structure |  |  |  |  | GTK 4: not realized |
| `scale` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scale of TextEditor - GTK's driver has no path for it yet |
| `scaleX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleX of TextEditor - GTK's driver has no path for it yet |
| `scaleY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleY of TextEditor - GTK's driver has no path for it yet |
| `shadow` | property | `DropShadow` | native |  |  |  |  | GTK 4: not realized |
| `style` | property | `Name` | structure | ✅ | ✅ | ✅ |  |  |
| `symbolEffect` | property | `String` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectActive` | property | `Bool` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectOptions` | property | `Int` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectValue` | property | `String` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `transition` | property | `AnyTransition` | native |  |  | · |  | GTK 4: cannot read transition of TextEditor - GTK's driver has no path for it yet |
| `translationX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationX of TextEditor - GTK's driver has no path for it yet |
| `translationY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationY of TextEditor - GTK's driver has no path for it yet |
| `unfocus` | act | `() -> Void` |  | ✅ | ✅ | ✅ |  |  |
| `verticalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `width` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `zIndex` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [View](tiers/View.md)

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `allowDrop` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `area` | property | `Area` | structure | ✅ | ✅ | ✅ |  |  |
| `canDrag` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `coordinateSpaceName` | property | `String` | stateUI |  |  |  |  | GTK 4: not realized |
| `dragLeave` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dragOver` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dragStarting` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dragText` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onDrop` (`drop`) | event | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dropCompleted` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `dropPaths` | event | `([String], Point)` | native |  |  |  |  | GTK 4: not realized |
| `flex` | property | `Double` | stateUI |  |  |  |  | GTK 4: not realized |
| `frameChanged` | event | `[Double]` | native | ✅ | ✅ | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `gridColumn` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `gridColumnSpan` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `gridRow` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `gridRowSpan` | property | `Int` | stateUI | ✅ | ✅ | ✅ |  |  |
| `horizontalAlignment` | property | `AxisAlignment` | native | ✅ | ✅ | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `horizontalGuide` | property | `[Double]` | stateUI |  |  | · |  | GTK 4: cannot read horizontalGuide of TextEditor - GTK's driver has no path for it yet |
| `layoutPriority` | property | `Double` | stateUI |  |  | · |  | GTK 4: cannot read layoutPriority of TextEditor - GTK's driver has no path for it yet |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  | GTK 4: not realized |
| `padding` | property | `EdgeInsets` | native | ✅ | ✅ | ✅ |  |  |
| `panTouchCount` | property | `Int` | structure | ☑️ | ✅ | · |  | The host layer hears a one-finger pan only; any other `panTouchCount` turns the pan off.; GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `panXChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `panYChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native | ✅ | ✅ | · |  | GTK 4: cannot pinch on TextEditor - GTK's driver has no path for it yet |
| `pointerEntered` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on TextEditor - GTK's driver has no path for it yet |
| `pointerExited` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on TextEditor - GTK's driver has no path for it yet |
| `pointerMoved` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on TextEditor - GTK's driver has no path for it yet |
| `pointerPressed` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on TextEditor - GTK's driver has no path for it yet |
| `pointerReleased` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on TextEditor - GTK's driver has no path for it yet |
| `pointerStyle` | property | `PointerStyle` | native |  |  | – |  | GTK 4: GTK sets a widget's cursor only through the frame's display, which the element layer does not own yet. |
| `swipeDirection` | property | `SwipeDirection` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `swipeThreshold` | property | `Double` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on TextEditor - GTK's driver has no path for it yet |
| `tag` | property | `PropValue` | stateUI |  |  |  |  | GTK 4: not realized |
| `tapCount` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot tap on TextEditor - GTK's driver has no path for it yet |
| `onTapGesture` (`tapGesture`) | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot tap on TextEditor - GTK's driver has no path for it yet |
| `verticalAlignment` | property | `AxisAlignment` | native | ✅ | ✅ | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `verticalGuide` | property | `[Double]` | stateUI |  |  | · |  | GTK 4: cannot read verticalGuide of TextEditor - GTK's driver has no path for it yet |

## From [InputView](tiers/InputView.md)

What every field a user types into has: the text's limits and caret, the keyboard it asks for, and the placeholder shown while it is empty.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `cursorPosition` | property | `Int` | native | ✅ |  | · |  | GTK 4: cannot read cursorPosition of TextEditor - GTK's driver has no path for it yet |
| `textContentType` | property | `InputPurpose` | adaptive |  |  | · |  | not realized; GTK 4: cannot read textContentType of TextEditor - GTK's driver has no path for it yet |
| `isReadOnly` | property | `Bool` | native |  |  | ◐ |  | not realized; GTK 4: cannot read isReadOnly of TextEditor - GTK's driver has no path for it yet |
| `isSpellCheckEnabled` | property | `Bool` | native |  |  | · |  | not realized; GTK 4: cannot read isSpellCheckEnabled of TextEditor - GTK's driver has no path for it yet |
| `isTextPredictionEnabled` | property | `Bool` | native |  |  | · |  | not realized; GTK 4: cannot read isTextPredictionEnabled of TextEditor - GTK's driver has no path for it yet |
| `maximumLength` | property | `Int` | native | ◐ | ✅ | ✅ |  | cannot read maximumLength of TextEditor - Android's field keeps no bound of SwiftOmniUI's: the host cuts what is typed, and typing proves it |
| `placeholder` | property | `String` | native | ✅ |  | · |  | GTK 4: cannot read placeholder of TextEditor - GTK's driver has no path for it yet |
| `placeholderKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `placeholderColor` | property | `Color` | native | ✅ |  | · |  | GTK 4: cannot read placeholderColor of TextEditor - GTK's driver has no path for it yet |
| `selectionLength` | property | `Int` | native | ✅ |  | · |  | GTK 4: cannot read selectionLength of TextEditor - GTK's driver has no path for it yet |
| `onTextChanged` (`textChanged`) | event | `String` | native | ✅ | ✅ | ✅ |  |  |

## From [TextElement](tiers/TextElement.md)

What every element showing words has: the words, and the case they are drawn in.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `text` | property | `String` | native | ◐ | ✅ | ✅ |  | waits on TextEditor.isReadOnly |
| `textKey` | property | `LocalizedStringKey` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `textCase` | property | `TextCase` | native | ✅ | ✅ | ✅ |  |  |
| `baselineOffset` | property | `Double` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |

## From [TextStyleElement](tiers/TextStyleElement.md)

How text looks wherever it is drawn: its colour and the space between its letters.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `characterSpacing` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `foregroundStyle` | property | `Color` | native | ✅ | ✅ | · |  | GTK 4: cannot read foregroundStyle of TextEditor - GTK's driver has no path for it yet |

## From [FontElement](tiers/FontElement.md)

The font text is drawn in: its family, its size, its weight and slant, and whether it follows the user's text-size setting.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `fontAttributes` | property | `FontAttributes` | native | ✅ | ✅ | · |  | GTK 4: cannot read fontAttributes of TextEditor - GTK's driver has no path for it yet |
| `fontAutoScalingEnabled` | property | `Bool` | adaptive |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `fontFamily` | property | `Name` | native | · | ✅ | · |  | cannot read a family - Android's typeface keeps no family's name; GTK 4: cannot read fontFamily of TextEditor - GTK's driver has no path for it yet |
| `fontSize` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read fontSize of TextEditor - GTK's driver has no path for it yet |
| `fontTextStyle` | property | `FontTextStyle` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `fontWeight` | property | `Weight` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `fontDesign` | property | `FontDesign` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |

## From [TextAlignmentElement](tiers/TextAlignmentElement.md)

Where text sits inside the space its own element was given.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `multilineTextAlignment` | property | `TextAlignment` | native |  | ✅ | · |  | not realized; GTK 4: cannot read multilineTextAlignment of TextEditor - GTK's driver has no path for it yet |
| `verticalTextAlignment` | property | `TextAlignment` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [PaddingElement](tiers/PaddingElement.md)

The space kept inside an element, around what it holds.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `contentPadding` | property | `EdgeInsets` | native |  |  |  |  | GTK 4: not realized |

## From [ControlSizeElement](tiers/ControlSizeElement.md)

How big a control draws - a button, a progress bar, a spinner.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `controlSize` | property | `ControlSize` | adaptive |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |

## From [ScrollContentElement](tiers/ScrollContentElement.md)

What shows behind a scrollable view's content - a list's or an editor's own canvas, where the platform draws one.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `scrollContentBackground` | property | `Visibility` | native |  |  |  |  | WinUI 3: not realized; GTK 4: not realized |

<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# View

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

Wears: [VisualElement](VisualElement.md)

Worn by: [ActivityIndicator](../ActivityIndicator.md) · [Button](../Button.md) · [Canvas](../Canvas.md) · [CheckBox](../CheckBox.md) · [ColorPicker](../ColorPicker.md) · [CustomLayout](../CustomLayout.md) · [DatePicker](../DatePicker.md) · [Ellipse](../Ellipse.md) · [Grid](../Grid.md) · [GridRow](../GridRow.md) · [HStack](../HStack.md) · [Image](../Image.md) · [LazyHGrid](../LazyHGrid.md) · [LazyHStack](../LazyHStack.md) · [LazyVGrid](../LazyVGrid.md) · [LazyVStack](../LazyVStack.md) · [Line](../Line.md) · [List](../List.md) · [Map](../Map.md) · [Masked](../Masked.md) · [MenuButton](../MenuButton.md) · [Path](../Path.md) · [Picker](../Picker.md) · [Polygon](../Polygon.md) · [Polyline](../Polyline.md) · [PositionIndicator](../PositionIndicator.md) · [ProgressBar](../ProgressBar.md) · [RadioButton](../RadioButton.md) · [Rectangle](../Rectangle.md) · [ScrollView](../ScrollView.md) · [SearchField](../SearchField.md) · [Slider](../Slider.md) · [Stepper](../Stepper.md) · [Switch](../Switch.md) · [Text](../Text.md) · [TextEditor](../TextEditor.md) · [TextField](../TextField.md) · [TimePicker](../TimePicker.md) · [TitleBar](../TitleBar.md) · [VStack](../VStack.md) · [WebView](../WebView.md) · [ZStack](../ZStack.md)

Declared in `lib/SwiftOmniUI/Sources/Contracts/Tiers/ViewContract.swift`.

How each of them realizes these members is on its own page.

| Member | Kind | Value | Layer |
| --- | --- | --- | --- |
| `allowDrop` | property | `Bool` | native |
| `area` | property | `Area` | structure |
| `canDrag` | property | `Bool` | native |
| `coordinateSpaceName` | property | `String` | stateUI |
| `dragLeave` | event |  | native |
| `dragOver` | event |  | native |
| `dragStarting` | event |  | native |
| `dragText` | property | `String` | native |
| `onDrop` (`drop`) | event | `String` | native |
| `dropCompleted` | event |  | native |
| `dropPaths` | event | `([String], Point)` | native |
| `flex` | property | `Double` | stateUI |
| `frameChanged` | event | `[Double]` | native |
| `gridColumn` | property | `Int` | stateUI |
| `gridColumnSpan` | property | `Int` | stateUI |
| `gridRow` | property | `Int` | stateUI |
| `gridRowSpan` | property | `Int` | stateUI |
| `horizontalAlignment` | property | `AxisAlignment` | native |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |
| `horizontalGuide` | property | `[Double]` | stateUI |
| `layoutPriority` | property | `Double` | stateUI |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |
| `padding` | property | `EdgeInsets` | native |
| `panTouchCount` | property | `Int` | structure |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native |
| `panXChannel` | property | `Int` | structure |
| `panYChannel` | property | `Int` | structure |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native |
| `pointerEntered` | event |  | native |
| `pointerExited` | event |  | native |
| `pointerMoved` | event | `Point?` | native |
| `pointerPressed` | event | `Point?` | native |
| `pointerReleased` | event | `Point?` | native |
| `pointerStyle` | property | `PointerStyle` | native |
| `swipeDirection` | property | `SwipeDirection` | structure |
| `swipeThreshold` | property | `Double` | structure |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native |
| `tag` | property | `PropValue` | stateUI |
| `tapCount` | property | `Int` | structure |
| `onTapGesture` (`tapGesture`) | event |  | native |
| `verticalAlignment` | property | `AxisAlignment` | native |
| `verticalContentAlignment` | property | `AxisAlignment` | native |
| `verticalGuide` | property | `[Double]` | stateUI |

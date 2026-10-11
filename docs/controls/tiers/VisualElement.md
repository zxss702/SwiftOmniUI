<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# VisualElement

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

Wears: [PropertyContainer](PropertyContainer.md)

Worn by: [ActivityIndicator](../ActivityIndicator.md) · [Button](../Button.md) · [Canvas](../Canvas.md) · [CheckBox](../CheckBox.md) · [ColorPicker](../ColorPicker.md) · [CustomLayout](../CustomLayout.md) · [DatePicker](../DatePicker.md) · [Ellipse](../Ellipse.md) · [Grid](../Grid.md) · [GridRow](../GridRow.md) · [HStack](../HStack.md) · [Image](../Image.md) · [LazyHGrid](../LazyHGrid.md) · [LazyHStack](../LazyHStack.md) · [LazyVGrid](../LazyVGrid.md) · [LazyVStack](../LazyVStack.md) · [Line](../Line.md) · [List](../List.md) · [Map](../Map.md) · [Masked](../Masked.md) · [MenuButton](../MenuButton.md) · [Path](../Path.md) · [Picker](../Picker.md) · [Polygon](../Polygon.md) · [Polyline](../Polyline.md) · [PositionIndicator](../PositionIndicator.md) · [ProgressBar](../ProgressBar.md) · [RadioButton](../RadioButton.md) · [Rectangle](../Rectangle.md) · [ScrollView](../ScrollView.md) · [SearchField](../SearchField.md) · [Slider](../Slider.md) · [Stepper](../Stepper.md) · [Switch](../Switch.md) · [Text](../Text.md) · [TextEditor](../TextEditor.md) · [TextField](../TextField.md) · [TimePicker](../TimePicker.md) · [TitleBar](../TitleBar.md) · [VStack](../VStack.md) · [WebView](../WebView.md) · [ZStack](../ZStack.md)

Declared in `lib/SwiftOmniUI/Sources/Contracts/Tiers/VisualElementContract.swift`.

How each of them realizes these members is on its own page.

| Member | Kind | Value | Layer |
| --- | --- | --- | --- |
| `blendMode` | property | `BlendMode` | native |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native |
| `accessibilityHint` | property | `String` | native |
| `accessibilityLabel` | property | `String` | native |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |
| `automationExcludedWithChildren` | property | `Bool` | native |
| `background` | property | `Background` | native |
| `blur` | property | `Double` | native |
| `contentTransition` | property | `String` | native |
| `compositingGroup` | property | `Bool` | native |
| `drawingGroup` | property | `Bool` | native |
| `focus` | act | `() -> Bool` |  |
| `frame` | property | `Rect` | structure |
| `height` | property | `Double` | native |
| `hint` | property | `String` | native |
| `hintKey` | property | `LocalizedStringKey` | native |
| `horizontalAlignmentDefault` | property | `AxisAlignment` | structure |
| `ignoresInput` | property | `Bool` | native |
| `isAccessibilityHidden` | property | `Bool` | native |
| `isEnabled` | property | `Bool` | native |
| `isFocusedChanged` | event | `Bool` | native |
| `isFrameContent` | property | `Bool` | structure |
| `isGeometryReader` | property | `Bool` | structure |
| `isLayoutDecoration` | property | `Bool` | structure |
| `isVisible` | property | `Bool` | native |
| `layoutDirection` | property | `LayoutDirection` | native |
| `matchedGeometry` | property | `String` | native |
| `matchedGeometrySource` | property | `Bool` | native |
| `maximumHeight` | property | `Double` | native |
| `maximumWidth` | property | `Double` | native |
| `minimumHeight` | property | `Double` | native |
| `minimumWidth` | property | `Double` | native |
| `opacity` | property | `Double` | native |
| `pivotX` | property | `Double` | native |
| `pivotY` | property | `Double` | native |
| `rotation` | property | `Angle` | native |
| `rotationX` | property | `Angle` | native |
| `rotationY` | property | `Angle` | native |
| `safeAreaInsetEdge` | property | `Edge` | structure |
| `scale` | property | `Double` | native |
| `scaleX` | property | `Double` | native |
| `scaleY` | property | `Double` | native |
| `shadow` | property | `DropShadow` | native |
| `style` | property | `Name` | structure |
| `symbolEffect` | property | `String` | native |
| `symbolEffectActive` | property | `Bool` | native |
| `symbolEffectOptions` | property | `Int` | native |
| `symbolEffectValue` | property | `String` | native |
| `transition` | property | `AnyTransition` | native |
| `translationX` | property | `Double` | native |
| `translationY` | property | `Double` | native |
| `unfocus` | act | `() -> Void` |  |
| `verticalAlignmentDefault` | property | `AxisAlignment` | structure |
| `width` | property | `Double` | native |
| `zIndex` | property | `Double` | native |

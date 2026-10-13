<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# CustomLayout

Places its children by an author's own `Layout` - a container whose measure and place passes run the layout object's methods rather than a built-in arithmetic.

Layer: `native`. Every base host presents it with its native toolkit.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [VisualElement](tiers/VisualElement.md) · [View](tiers/View.md) · [Layout](tiers/Layout.md) · [PaddingElement](tiers/PaddingElement.md) · [BorderElement](tiers/BorderElement.md)

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

| Host | Created | Members (111) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views |  |  | custom `ViewGroup` driven the same | no run of it on these sources |
| WinUI 3 | ✅ | 1 ✅ | custom `Panel` driven the same |  |
| GTK 4 | ✅ | 16 ✅ · 14 – | `GtkLayoutManager` on a `GtkWidget` |  |
| Web |  |  | custom element driven the same | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Layouts/CustomLayoutContract.swift`.

## CustomLayout's own members

CustomLayout declares no members of its own.

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native |  |  |  |  | GTK 4: not realized |

## From [VisualElement](tiers/VisualElement.md)

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `blendMode` | property | `BlendMode` | native |  |  | – |  | GTK 4: GTK composites every view normally; a blend pass over its own content draws nothing yet. |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |  |  | – |  | GTK 4: GTK's accessibility bridge answers no child behaviour yet. |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native |  |  | · |  | GTK 4: cannot read accessibilityHeadingLevel of CustomLayout - GTK's driver has no path for it yet |
| `accessibilityHint` | property | `String` | native |  |  | · |  | GTK 4: cannot read accessibilityHint of CustomLayout - GTK's driver has no path for it yet |
| `accessibilityLabel` | property | `String` | native |  |  | · |  | GTK 4: cannot read accessibilityLabel of CustomLayout - GTK's driver has no path for it yet |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  | – |  | GTK 4: GTK's accessibility bridge answers no traits yet. |
| `automationExcludedWithChildren` | property | `Bool` | native |  |  | · |  | GTK 4: cannot read automationExcludedWithChildren of CustomLayout - GTK's driver has no path for it yet |
| `background` | property | `Background` | native |  |  | · |  | GTK 4: cannot read background of CustomLayout - GTK's driver has no path for it yet |
| `blur` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `contentTransition` | property | `String` | native |  |  | – |  | GTK 4: GTK swaps a label's words with no transition yet. |
| `compositingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `drawingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `focus` | act | `() -> Bool` |  |  |  | – |  | GTK 4: CustomLayout takes no keyboard focus here: it refuses it, and nothing is heard |
| `frame` | property | `Rect` | structure |  |  | ✅ |  |  |
| `height` | property | `Double` | native |  |  | ✅ |  |  |
| `hint` | property | `String` | native |  |  | · |  | GTK 4: cannot read hint of CustomLayout - GTK's driver has no path for it yet |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `horizontalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `ignoresInput` | property | `Bool` | native |  |  | · |  | GTK 4: cannot read what reaches CustomLayout - GTK's driver has no path for it yet |
| `isAccessibilityHidden` | property | `Bool` | native |  |  | · |  | GTK 4: cannot read isAccessibilityHidden of CustomLayout - GTK's driver has no path for it yet |
| `isEnabled` | property | `Bool` | native |  |  | ✅ |  |  |
| `isFocusedChanged` | event | `Bool` | native |  |  | – |  | GTK 4: CustomLayout takes no keyboard focus here: it refuses it, and nothing is heard |
| `isFrameContent` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isGeometryReader` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isLayoutDecoration` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isVisible` | property | `Bool` | native |  |  | ✅ |  |  |
| `layoutDirection` | property | `LayoutDirection` | native |  |  | · |  | GTK 4: cannot read layoutDirection of CustomLayout - GTK's driver has no path for it yet |
| `matchedGeometry` | property | `String` | native |  |  | – |  | GTK 4: GTK's layout motion flies no matched child into place yet. |
| `matchedGeometrySource` | property | `Bool` | native |  |  | – |  | GTK 4: GTK's layout motion flies no matched child into place yet. |
| `maximumHeight` | property | `Double` | native |  |  | ✅ |  |  |
| `maximumWidth` | property | `Double` | native |  |  | ✅ |  |  |
| `minimumHeight` | property | `Double` | native |  |  | ✅ |  |  |
| `minimumWidth` | property | `Double` | native |  |  | ✅ |  |  |
| `opacity` | property | `Double` | native |  |  | ✅ |  |  |
| `pivotX` | property | `Double` | native |  |  | · |  | GTK 4: cannot read pivotX of CustomLayout - GTK's driver has no path for it yet |
| `pivotY` | property | `Double` | native |  |  | · |  | GTK 4: cannot read pivotY of CustomLayout - GTK's driver has no path for it yet |
| `rotation` | property | `Angle` | native |  |  | · |  | GTK 4: cannot read rotation of CustomLayout - GTK's driver has no path for it yet |
| `rotationX` | property | `Angle` | native |  |  | · |  | GTK 4: cannot read rotationX of CustomLayout - GTK's driver has no path for it yet |
| `rotationY` | property | `Angle` | native |  |  | · |  | GTK 4: cannot read rotationY of CustomLayout - GTK's driver has no path for it yet |
| `safeAreaInsetEdge` | property | `Edge` | structure |  |  |  |  | GTK 4: not realized |
| `scale` | property | `Double` | native |  |  | · |  | GTK 4: cannot read scale of CustomLayout - GTK's driver has no path for it yet |
| `scaleX` | property | `Double` | native |  |  | · |  | GTK 4: cannot read scaleX of CustomLayout - GTK's driver has no path for it yet |
| `scaleY` | property | `Double` | native |  |  | · |  | GTK 4: cannot read scaleY of CustomLayout - GTK's driver has no path for it yet |
| `shadow` | property | `DropShadow` | native |  |  |  |  | GTK 4: not realized |
| `style` | property | `Name` | structure |  |  | ✅ |  |  |
| `symbolEffect` | property | `String` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectActive` | property | `Bool` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectOptions` | property | `Int` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectValue` | property | `String` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `transition` | property | `AnyTransition` | native |  |  | · |  | GTK 4: cannot read transition of CustomLayout - GTK's driver has no path for it yet |
| `translationX` | property | `Double` | native |  |  | · |  | GTK 4: cannot read translationX of CustomLayout - GTK's driver has no path for it yet |
| `translationY` | property | `Double` | native |  |  | · |  | GTK 4: cannot read translationY of CustomLayout - GTK's driver has no path for it yet |
| `unfocus` | act | `() -> Void` |  |  |  | – |  | GTK 4: CustomLayout takes no keyboard focus here: it refuses it, and nothing is heard |
| `verticalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `width` | property | `Double` | native |  |  | ✅ |  |  |
| `zIndex` | property | `Double` | native |  |  |  |  | GTK 4: not realized |

## From [View](tiers/View.md)

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `allowDrop` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `area` | property | `Area` | structure |  |  | ❌ |  | GTK 4: [100.0, 100.0, 100.0, 100.0] expected, [28.0, 18.0, 28.0, 18.0] came - its room's lower right quarter |
| `canDrag` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `coordinateSpaceName` | property | `String` | stateUI |  |  |  |  | GTK 4: not realized |
| `dragLeave` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dragOver` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dragStarting` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dragText` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `onDrop` (`drop`) | event | `String` | native |  |  |  |  | GTK 4: not realized |
| `dropCompleted` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dropPaths` | event | `([String], Point)` | native |  |  |  |  | GTK 4: not realized |
| `flex` | property | `Double` | stateUI |  |  |  |  | GTK 4: not realized |
| `frameChanged` | event | `[Double]` | native |  | ✅ | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `gridColumn` | property | `Int` | stateUI |  |  | ✅ |  |  |
| `gridColumnSpan` | property | `Int` | stateUI |  |  | ✅ |  |  |
| `gridRow` | property | `Int` | stateUI |  |  | ✅ |  |  |
| `gridRowSpan` | property | `Int` | stateUI |  |  | ✅ |  |  |
| `horizontalAlignment` | property | `AxisAlignment` | native |  |  | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `horizontalGuide` | property | `[Double]` | stateUI |  |  | · |  | GTK 4: cannot read horizontalGuide of CustomLayout - GTK's driver has no path for it yet |
| `layoutPriority` | property | `Double` | stateUI |  |  | · |  | GTK 4: cannot read layoutPriority of CustomLayout - GTK's driver has no path for it yet |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  | GTK 4: not realized |
| `padding` | property | `EdgeInsets` | native |  |  | ✅ |  |  |
| `panTouchCount` | property | `Int` | structure |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `panXChannel` | property | `Int` | structure |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `panYChannel` | property | `Int` | structure |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native |  |  | · |  | GTK 4: cannot pinch on CustomLayout - GTK's driver has no path for it yet |
| `pointerEntered` | event |  | native |  |  | · |  | GTK 4: cannot hover on CustomLayout - GTK's driver has no path for it yet |
| `pointerExited` | event |  | native |  |  | · |  | GTK 4: cannot hover on CustomLayout - GTK's driver has no path for it yet |
| `pointerMoved` | event | `Point?` | native |  |  | · |  | GTK 4: cannot hover on CustomLayout - GTK's driver has no path for it yet |
| `pointerPressed` | event | `Point?` | native |  |  | · |  | GTK 4: cannot hover on CustomLayout - GTK's driver has no path for it yet |
| `pointerReleased` | event | `Point?` | native |  |  | · |  | GTK 4: cannot hover on CustomLayout - GTK's driver has no path for it yet |
| `pointerStyle` | property | `PointerStyle` | native |  |  | – |  | GTK 4: GTK sets a widget's cursor only through the frame's display, which the element layer does not own yet. |
| `swipeDirection` | property | `SwipeDirection` | structure |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `swipeThreshold` | property | `Double` | structure |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native |  |  | · |  | GTK 4: cannot pan on CustomLayout - GTK's driver has no path for it yet |
| `tag` | property | `PropValue` | stateUI |  |  |  |  | GTK 4: not realized |
| `tapCount` | property | `Int` | structure |  |  | · |  | GTK 4: cannot tap on CustomLayout - GTK's driver has no path for it yet |
| `onTapGesture` (`tapGesture`) | event |  | native |  |  | · |  | GTK 4: cannot tap on CustomLayout - GTK's driver has no path for it yet |
| `verticalAlignment` | property | `AxisAlignment` | native |  |  | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `verticalGuide` | property | `[Double]` | stateUI |  |  | · |  | GTK 4: cannot read verticalGuide of CustomLayout - GTK's driver has no path for it yet |

## From [Layout](tiers/Layout.md)

What every layout has: the screen's unsafe strips it keeps clear of, and whether its children are clipped or let input through.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `ignoresSafeArea` | property | `SafeAreaEdges` | adaptive |  |  |  |  | GTK 4: not realized |
| `clipsContent` | property | `Bool` | native |  |  | · |  | GTK 4: cannot read clipsContent of CustomLayout - GTK's driver has no path for it yet |
| `letsInputThrough` | property | `Bool` | native |  |  | · |  | GTK 4: cannot read letsInputThrough of CustomLayout - GTK's driver has no path for it yet |
| `hitShape` | property | `ContainerShape` | native |  |  | · |  | GTK 4: cannot read hitShape of CustomLayout - GTK's driver has no path for it yet |
| `scrollTargetLayout` | property | `Bool` | adaptive |  |  |  |  | GTK 4: not realized |
| `clipPath` | property | `[Double]` | native |  |  |  |  |  |
| `clipFillRule` | property | `FillRule` | native |  |  |  |  |  |

## From [PaddingElement](tiers/PaddingElement.md)

The space kept inside an element, around what it holds.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `contentPadding` | property | `EdgeInsets` | native |  |  | · |  | GTK 4: cannot read contentPadding of CustomLayout - GTK's driver has no path for it yet |

## From [BorderElement](tiers/BorderElement.md)

What an element draws of its own box: the shape its background, its outline and its cut follow, and the outline.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `shape` | property | `ContainerShape` | stateUI |  |  | · |  | GTK 4: cannot read shape of CustomLayout - GTK's driver has no path for it yet |
| `stroke` | property | `Brush` | stateUI |  |  | · |  | GTK 4: cannot read stroke of CustomLayout - GTK's driver has no path for it yet |
| `strokeWidth` | property | `Double` | stateUI |  |  | · |  | GTK 4: cannot read strokeWidth of CustomLayout - GTK's driver has no path for it yet |

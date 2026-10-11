<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Map

A map of the world, with pins on it.

Layer: `provider`. An optional provider supplies it: a package, or the application that registers it with its hosts.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [VisualElement](tiers/VisualElement.md) · [View](tiers/View.md)

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

| Host | Created | Members (108) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views |  |  | Google Play services `MapView` / `Marker` (?) | not realized |
| WinUI 3 |  |  | `MapControl` (?) | not realized |
| GTK 4 |  |  | libshumate `ShumateMap` / `ShumateMarker` | not realized |
| Web |  |  | no honest native counterpart | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Controls/MapContract.swift`.

## Map's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `isScrollEnabled` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isTrafficEnabled` | property | `Bool` | provider |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isZoomEnabled` | property | `Bool` | provider |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onMapClicked` (`mapClicked`) | event | `Location` | provider |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `mapType` | property | `MapType` | provider |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `moveToRegion` | act | `(Double, Double, Double) -> Void` |  |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `region` | property | `MapRegion` | provider |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `showsUserLocation` | property | `Bool` | provider |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [VisualElement](tiers/VisualElement.md)

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `blendMode` | property | `BlendMode` | native |  |  |  |  | GTK 4: not realized |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |  |  |  |  | GTK 4: not realized |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `accessibilityHint` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `accessibilityLabel` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  |  |  | GTK 4: not realized |
| `automationExcludedWithChildren` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `background` | property | `Background` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `blur` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `contentTransition` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `compositingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `drawingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `focus` | act | `() -> Bool` |  |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `frame` | property | `Rect` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `height` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `hint` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `horizontalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `ignoresInput` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isAccessibilityHidden` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isEnabled` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isFocusedChanged` | event | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isFrameContent` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isGeometryReader` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isLayoutDecoration` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isVisible` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `layoutDirection` | property | `LayoutDirection` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `matchedGeometry` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `matchedGeometrySource` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `maximumHeight` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `maximumWidth` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `minimumHeight` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `minimumWidth` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `opacity` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pivotX` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pivotY` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `rotation` | property | `Angle` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `rotationX` | property | `Angle` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `rotationY` | property | `Angle` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `safeAreaInsetEdge` | property | `Edge` | structure |  |  |  |  | GTK 4: not realized |
| `scale` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `scaleX` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `scaleY` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `shadow` | property | `DropShadow` | native |  |  |  |  | GTK 4: not realized |
| `style` | property | `Name` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `symbolEffect` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `symbolEffectActive` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `symbolEffectOptions` | property | `Int` | native |  |  |  |  | GTK 4: not realized |
| `symbolEffectValue` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `transition` | property | `AnyTransition` | native |  |  |  |  | GTK 4: not realized |
| `translationX` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `translationY` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `unfocus` | act | `() -> Void` |  |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `verticalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `width` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `zIndex` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [View](tiers/View.md)

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `allowDrop` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `area` | property | `Area` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
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
| `frameChanged` | event | `[Double]` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridColumn` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridColumnSpan` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridRow` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridRowSpan` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `horizontalAlignment` | property | `AxisAlignment` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `horizontalGuide` | property | `[Double]` | stateUI |  |  |  |  | GTK 4: not realized |
| `layoutPriority` | property | `Double` | stateUI |  |  |  |  | GTK 4: not realized |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  | GTK 4: not realized |
| `padding` | property | `EdgeInsets` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `panTouchCount` | property | `Int` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `panXChannel` | property | `Int` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `panYChannel` | property | `Int` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pointerEntered` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pointerExited` | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pointerMoved` | event | `Point?` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pointerPressed` | event | `Point?` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pointerReleased` | event | `Point?` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `pointerStyle` | property | `PointerStyle` | native |  |  |  |  | GTK 4: not realized |
| `swipeDirection` | property | `SwipeDirection` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `swipeThreshold` | property | `Double` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `tag` | property | `PropValue` | stateUI |  |  |  |  | GTK 4: not realized |
| `tapCount` | property | `Int` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onTapGesture` (`tapGesture`) | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `verticalAlignment` | property | `AxisAlignment` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `verticalGuide` | property | `[Double]` | stateUI |  |  |  |  | GTK 4: not realized |

<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# GridRow

One row of cells inside a `Grid` - structure the grid reads while it lays its cells out, never an element a host mounts.

Layer: `structure`. It carries structure or protocol data rather than configuring a visual platform object.

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

| Host | Created | Members (103) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views |  |  | composed by SwiftOmniUI | no run of it on these sources |
| WinUI 3 |  |  | composed by SwiftOmniUI | no run of it on these sources |
| GTK 4 |  |  | composed by SwiftOmniUI | no run of it on these sources |
| Web |  |  | composed by SwiftOmniUI | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Layouts/GridRowContract.swift`.

## GridRow's own members

GridRow declares no members of its own.

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native |  |  |  |  | GTK 4: not realized |

## From [VisualElement](tiers/VisualElement.md)

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `blendMode` | property | `BlendMode` | native |  |  |  |  |  |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |  |  |  |  |  |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native |  |  |  |  | GTK 4: not realized |
| `accessibilityHint` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `accessibilityLabel` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  |  |  |  |
| `automationExcludedWithChildren` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `background` | property | `Background` | native |  |  |  |  | GTK 4: not realized |
| `blur` | property | `Double` | native |  |  |  |  |  |
| `contentTransition` | property | `String` | native |  |  |  |  |  |
| `compositingGroup` | property | `Bool` | native |  |  |  |  |  |
| `drawingGroup` | property | `Bool` | native |  |  |  |  |  |
| `focus` | act | `() -> Bool` |  |  |  |  |  | GTK 4: not realized |
| `frame` | property | `Rect` | structure |  |  |  |  | GTK 4: not realized |
| `height` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `hint` | property | `String` | native |  |  |  |  |  |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `ignoresInput` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `isAccessibilityHidden` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `isEnabled` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `isFocusedChanged` | event | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `isVisible` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `layoutDirection` | property | `LayoutDirection` | native |  |  |  |  | GTK 4: not realized |
| `matchedGeometry` | property | `String` | native |  |  |  |  |  |
| `matchedGeometrySource` | property | `Bool` | native |  |  |  |  |  |
| `maximumHeight` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `maximumWidth` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `minimumHeight` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `minimumWidth` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `opacity` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `pivotX` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `pivotY` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `rotation` | property | `Angle` | native |  |  |  |  | GTK 4: not realized |
| `rotationX` | property | `Angle` | native |  |  |  |  | GTK 4: not realized |
| `rotationY` | property | `Angle` | native |  |  |  |  | GTK 4: not realized |
| `scale` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `scaleX` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `scaleY` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `shadow` | property | `DropShadow` | native |  |  |  |  |  |
| `style` | property | `Name` | structure |  |  |  |  | GTK 4: not realized |
| `symbolEffect` | property | `String` | native |  |  |  |  |  |
| `symbolEffectActive` | property | `Bool` | native |  |  |  |  |  |
| `symbolEffectOptions` | property | `Int` | native |  |  |  |  |  |
| `symbolEffectValue` | property | `String` | native |  |  |  |  |  |
| `transition` | property | `AnyTransition` | native |  |  |  |  |  |
| `translationX` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `translationY` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `unfocus` | act | `() -> Void` |  |  |  |  |  | GTK 4: not realized |
| `width` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `zIndex` | property | `Double` | native |  |  |  |  | GTK 4: not realized |

## From [View](tiers/View.md)

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `allowDrop` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `area` | property | `Area` | structure |  |  |  |  | GTK 4: not realized |
| `canDrag` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `coordinateSpaceName` | property | `String` | stateUI |  |  |  |  |  |
| `dragLeave` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dragOver` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dragStarting` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dragText` | property | `String` | native |  |  |  |  | GTK 4: not realized |
| `onDrop` (`drop`) | event | `String` | native |  |  |  |  | GTK 4: not realized |
| `dropCompleted` | event |  | native |  |  |  |  | GTK 4: not realized |
| `dropPaths` | event | `([String], Point)` | native |  |  |  |  |  |
| `flex` | property | `Double` | stateUI |  |  |  |  |  |
| `frameChanged` | event | `[Double]` | native |  |  |  |  | GTK 4: not realized |
| `gridColumn` | property | `Int` | stateUI |  |  |  |  | GTK 4: not realized |
| `gridColumnSpan` | property | `Int` | stateUI |  |  |  |  | GTK 4: not realized |
| `gridRow` | property | `Int` | stateUI |  |  |  |  | GTK 4: not realized |
| `gridRowSpan` | property | `Int` | stateUI |  |  |  |  | GTK 4: not realized |
| `horizontalAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `horizontalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |
| `layoutPriority` | property | `Double` | stateUI |  |  |  |  |  |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  |  |
| `padding` | property | `EdgeInsets` | native |  |  |  |  | GTK 4: not realized |
| `panTouchCount` | property | `Int` | structure |  |  |  |  | GTK 4: not realized |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native |  |  |  |  | GTK 4: not realized |
| `panXChannel` | property | `Int` | structure |  |  |  |  | GTK 4: not realized |
| `panYChannel` | property | `Int` | structure |  |  |  |  | GTK 4: not realized |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native |  |  |  |  | GTK 4: not realized |
| `pointerEntered` | event |  | native |  |  |  |  | GTK 4: not realized |
| `pointerExited` | event |  | native |  |  |  |  | GTK 4: not realized |
| `pointerMoved` | event | `Point?` | native |  |  |  |  | GTK 4: not realized |
| `pointerPressed` | event | `Point?` | native |  |  |  |  | GTK 4: not realized |
| `pointerReleased` | event | `Point?` | native |  |  |  |  | GTK 4: not realized |
| `pointerStyle` | property | `PointerStyle` | native |  |  |  |  |  |
| `swipeDirection` | property | `SwipeDirection` | structure |  |  |  |  | GTK 4: not realized |
| `swipeThreshold` | property | `Double` | structure |  |  |  |  | GTK 4: not realized |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native |  |  |  |  | GTK 4: not realized |
| `tag` | property | `PropValue` | stateUI |  |  |  |  |  |
| `tapCount` | property | `Int` | structure |  |  |  |  | GTK 4: not realized |
| `onTapGesture` (`tapGesture`) | event |  | native |  |  |  |  | GTK 4: not realized |
| `verticalAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `verticalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |

## From [Layout](tiers/Layout.md)

What every layout has: the screen's unsafe strips it keeps clear of, and whether its children are clipped or let input through.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `ignoresSafeArea` | property | `SafeAreaEdges` | adaptive |  |  |  |  | GTK 4: not realized |
| `clipsContent` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `letsInputThrough` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `hitShape` | property | `ContainerShape` | native |  |  |  |  | GTK 4: not realized |
| `scrollTargetLayout` | property | `Bool` | adaptive |  |  |  |  |  |

## From [PaddingElement](tiers/PaddingElement.md)

The space kept inside an element, around what it holds.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `contentPadding` | property | `EdgeInsets` | native |  |  |  |  | GTK 4: not realized |

## From [BorderElement](tiers/BorderElement.md)

What an element draws of its own box: the shape its background, its outline and its cut follow, and the outline.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `shape` | property | `ContainerShape` | stateUI |  |  |  |  | GTK 4: not realized |
| `stroke` | property | `Brush` | stateUI |  |  |  |  | GTK 4: not realized |
| `strokeWidth` | property | `Double` | stateUI |  |  |  |  | GTK 4: not realized |

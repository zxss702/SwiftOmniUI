<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# TitleBar

An authored title area attached to a window.

Layer: `adaptive`. Every base host presents it by its platform's conventions, keeping SwiftOmniUI's state contract.

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

| Host | Created | Members (98) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views |  |  | no honest native counterpart | not realized |
| WinUI 3 |  |  | `TitleBar` | not realized |
| GTK 4 | ⏸ |  | `GtkHeaderBar` | waits on TitleBar.title, not realized yet |
| Web |  |  | no honest native counterpart | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Structure/TitleBarContract.swift`.

## TitleBar's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `barForegroundColor` | property | `Color` | adaptive |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read barForegroundColor of TitleBar - GTK's driver has no path for it yet |
| `icon` | property | `ImageSource` | adaptive |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `subtitle` | property | `String` | adaptive |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `title` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [PropertyContainer](tiers/PropertyContainer.md)

What anything carrying values in the tree has - a control, a `Style`, a text run: the name automation finds it by.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `accessibilityIdentifier` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [VisualElement](tiers/VisualElement.md)

What every drawn element has: its size and its bounds, how it is shown and turned, whether it answers input and holds the keyboard focus, the visual states it enters, and what a screen reader says about it.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `blendMode` | property | `BlendMode` | native |  |  |  |  |  |
| `accessibilityChildBehavior` | property | `AccessibilityChildBehavior` | native |  |  |  |  |  |
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `accessibilityHint` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `accessibilityLabel` | property | `String` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  |  |  |  |
| `automationExcludedWithChildren` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `background` | property | `Background` | native |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read background of TitleBar - GTK's driver has no path for it yet |
| `blur` | property | `Double` | native |  |  |  |  |  |
| `contentTransition` | property | `String` | native |  |  |  |  |  |
| `compositingGroup` | property | `Bool` | native |  |  |  |  |  |
| `drawingGroup` | property | `Bool` | native |  |  |  |  |  |
| `focus` | act | `() -> Bool` |  |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `frame` | property | `Rect` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `height` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `hint` | property | `String` | native |  |  |  |  |  |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `ignoresInput` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isAccessibilityHidden` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isEnabled` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isFocusedChanged` | event | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isVisible` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `layoutDirection` | property | `LayoutDirection` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `matchedGeometry` | property | `String` | native |  |  |  |  |  |
| `matchedGeometrySource` | property | `Bool` | native |  |  |  |  |  |
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
| `scale` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `scaleX` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `scaleY` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `shadow` | property | `DropShadow` | native |  |  |  |  |  |
| `style` | property | `Name` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `symbolEffect` | property | `String` | native |  |  |  |  |  |
| `symbolEffectActive` | property | `Bool` | native |  |  |  |  |  |
| `symbolEffectOptions` | property | `Int` | native |  |  |  |  |  |
| `symbolEffectValue` | property | `String` | native |  |  |  |  |  |
| `transition` | property | `AnyTransition` | native |  |  |  |  |  |
| `translationX` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `translationY` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `unfocus` | act | `() -> Void` |  |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `width` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `zIndex` | property | `Double` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |

## From [View](tiers/View.md)

What every view a layout positions has: where it sits in its layout, the space kept around it, and the gestures, drags and frame reports it answers.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `allowDrop` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `area` | property | `Area` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
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
| `frameChanged` | event | `[Double]` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridColumn` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridColumnSpan` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridRow` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `gridRowSpan` | property | `Int` | stateUI |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `horizontalAlignment` | property | `AxisAlignment` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `horizontalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `horizontalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |
| `layoutPriority` | property | `Double` | stateUI |  |  |  |  |  |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  |  |
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
| `pointerStyle` | property | `PointerStyle` | native |  |  |  |  |  |
| `swipeDirection` | property | `SwipeDirection` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `swipeThreshold` | property | `Double` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `tag` | property | `PropValue` | stateUI |  |  |  |  |  |
| `tapCount` | property | `Int` | structure |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `onTapGesture` (`tapGesture`) | event |  | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `verticalAlignment` | property | `AxisAlignment` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `verticalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |

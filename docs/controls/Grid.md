<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Grid

Arranges its children in rows and columns.

Layer: `stateUI`. SwiftOmniUI composes it from smaller primitives before a host receives the tree.

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

| Host | Created | Members (108) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 55 ✅ · 1 ☑️ · 3 – | composed by SwiftOmniUI |  |
| WinUI 3 | ✅ | 59 ✅ · 3 – | composed by SwiftOmniUI |  |
| GTK 4 | ✅ | 24 ✅ · 3 – | composed by SwiftOmniUI |  |
| Web |  |  | composed by SwiftOmniUI | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Layouts/GridContract.swift`.

## Grid's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `columnSpacing` | property | `Double` | stateUI | ✅ | ✅ | ✅ |  |  |
| `columns` | property | `[GridLength]` | stateUI | ✅ | ✅ | ✅ |  |  |
| `flowColumns` | property | `[GridItem]` | stateUI |  |  |  |  |  |
| `rowSpacing` | property | `Double` | stateUI | ✅ | ✅ | ✅ |  |  |
| `rows` | property | `[GridLength]` | stateUI | ✅ | ✅ | ✅ |  |  |

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
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native | · | ✅ | · |  | cannot read a heading's level - Android marks a heading, not its level; GTK 4: cannot read accessibilityHeadingLevel of Grid - GTK's driver has no path for it yet |
| `accessibilityHint` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityHint of Grid - GTK's driver has no path for it yet |
| `accessibilityLabel` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityLabel of Grid - GTK's driver has no path for it yet |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  |  |  |  |
| `automationExcludedWithChildren` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read automationExcludedWithChildren of Grid - GTK's driver has no path for it yet |
| `background` | property | `Background` | native | ✅ | ✅ | · |  | GTK 4: cannot read background of Grid - SwiftOmniUI draws a layout's box on GTK's snapshot, which holds none of its background; its drawing proves it |
| `blur` | property | `Double` | native |  |  |  |  |  |
| `contentTransition` | property | `String` | native |  |  |  |  |  |
| `compositingGroup` | property | `Bool` | native |  |  |  |  |  |
| `drawingGroup` | property | `Bool` | native |  |  |  |  |  |
| `focus` | act | `() -> Bool` |  | – | – | – |  | Grid takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Grid takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Grid takes no keyboard focus here: it refuses it, and nothing is heard |
| `frame` | property | `Rect` | structure | ✅ | ✅ | ✅ |  |  |
| `height` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `hint` | property | `String` | native |  |  |  |  |  |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  |  |
| `ignoresInput` | property | `Bool` | native | · | ✅ | · |  | cannot read what reaches Grid - Android's driver has no path for it yet; GTK 4: cannot read what reaches Grid - GTK's driver has no path for it yet |
| `isAccessibilityHidden` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read isAccessibilityHidden of Grid - GTK's driver has no path for it yet |
| `isEnabled` | property | `Bool` | native |  |  | ✅ |  | not realized; WinUI 3: not realized |
| `isFocusedChanged` | event | `Bool` | native | – | – | – |  | Grid takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Grid takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Grid takes no keyboard focus here: it refuses it, and nothing is heard |
| `isVisible` | property | `Bool` | native | ✅ | ✅ | ✅ |  |  |
| `layoutDirection` | property | `LayoutDirection` | native |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read layoutDirection of Grid - GTK's driver has no path for it yet |
| `matchedGeometry` | property | `String` | native |  |  |  |  |  |
| `matchedGeometrySource` | property | `Bool` | native |  |  |  |  |  |
| `maximumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `maximumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `opacity` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `pivotX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotX of Grid - GTK's driver has no path for it yet |
| `pivotY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotY of Grid - GTK's driver has no path for it yet |
| `rotation` | property | `Angle` | native | ✅ | ✅ | · |  | GTK 4: cannot read rotation of Grid - GTK's driver has no path for it yet |
| `rotationX` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationX of Grid - GTK's driver has no path for it yet |
| `rotationY` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationY of Grid - GTK's driver has no path for it yet |
| `scale` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scale of Grid - GTK's driver has no path for it yet |
| `scaleX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleX of Grid - GTK's driver has no path for it yet |
| `scaleY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleY of Grid - GTK's driver has no path for it yet |
| `shadow` | property | `DropShadow` | native |  |  |  |  |  |
| `style` | property | `Name` | structure | ✅ | ✅ | ✅ |  |  |
| `symbolEffect` | property | `String` | native |  |  |  |  |  |
| `symbolEffectActive` | property | `Bool` | native |  |  |  |  |  |
| `symbolEffectOptions` | property | `Int` | native |  |  |  |  |  |
| `symbolEffectValue` | property | `String` | native |  |  |  |  |  |
| `transition` | property | `AnyTransition` | native |  |  |  |  |  |
| `translationX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationX of Grid - GTK's driver has no path for it yet |
| `translationY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationY of Grid - GTK's driver has no path for it yet |
| `unfocus` | act | `() -> Void` |  | – | – | – |  | Grid takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Grid takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Grid takes no keyboard focus here: it refuses it, and nothing is heard |
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
| `panTouchCount` | property | `Int` | structure | ☑️ | ✅ | · |  | The host layer hears a one-finger pan only; any other `panTouchCount` turns the pan off.; GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `panXChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `panYChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native | ✅ | ✅ | · |  | GTK 4: cannot pinch on Grid - GTK's driver has no path for it yet |
| `pointerEntered` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Grid - GTK's driver has no path for it yet |
| `pointerExited` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Grid - GTK's driver has no path for it yet |
| `pointerMoved` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Grid - GTK's driver has no path for it yet |
| `pointerPressed` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Grid - GTK's driver has no path for it yet |
| `pointerReleased` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Grid - GTK's driver has no path for it yet |
| `pointerStyle` | property | `PointerStyle` | native |  |  |  |  |  |
| `swipeDirection` | property | `SwipeDirection` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `swipeThreshold` | property | `Double` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on Grid - GTK's driver has no path for it yet |
| `tag` | property | `PropValue` | stateUI |  |  |  |  |  |
| `tapCount` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot tap on Grid - GTK's driver has no path for it yet |
| `onTapGesture` (`tapGesture`) | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot tap on Grid - GTK's driver has no path for it yet |
| `verticalAlignment` | property | `AxisAlignment` | native | ✅ | ✅ | ✅ |  |  |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  |  |
| `verticalGuide` | property | `[Double]` | stateUI |  |  |  |  |  |

## From [Layout](tiers/Layout.md)

What every layout has: the screen's unsafe strips it keeps clear of, and whether its children are clipped or let input through.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `ignoresSafeArea` | property | `SafeAreaEdges` | adaptive |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `clipsContent` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read clipsContent of Grid - GTK's driver has no path for it yet |
| `letsInputThrough` | property | `Bool` | native |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read letsInputThrough of Grid - GTK's driver has no path for it yet |
| `hitShape` | property | `ContainerShape` | native |  |  | · |  | GTK 4: cannot read hitShape of Grid - GTK's driver has no path for it yet |
| `scrollTargetLayout` | property | `Bool` | adaptive |  |  |  |  |  |

## From [PaddingElement](tiers/PaddingElement.md)

The space kept inside an element, around what it holds.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `contentPadding` | property | `EdgeInsets` | native | ✅ | ✅ | ◐ |  | GTK 4: cannot read contentPadding of Grid - GTK's driver has no path for it yet |

## From [BorderElement](tiers/BorderElement.md)

What an element draws of its own box: the shape its background, its outline and its cut follow, and the outline.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `shape` | property | `ContainerShape` | stateUI | · | ✅ | · |  | cannot read shape of Grid - SwiftOmniUI draws a layout's box in a drawable of its own, which holds none of its shape; its drawing proves it; GTK 4: cannot read shape of Grid - SwiftOmniUI draws a layout's box on GTK's snapshot, which holds none of its shape; its drawing proves it |
| `stroke` | property | `Brush` | stateUI | · | ✅ | · |  | cannot read stroke of Grid - SwiftOmniUI draws a layout's box in a drawable of its own, which holds none of its stroke; its drawing proves it; GTK 4: cannot read stroke of Grid - SwiftOmniUI draws a layout's box on GTK's snapshot, which holds none of its stroke; its drawing proves it |
| `strokeWidth` | property | `Double` | stateUI | · | ✅ | · |  | cannot read strokeWidth of Grid - SwiftOmniUI draws a layout's box in a drawable of its own, which holds none of its strokeWidth; its drawing proves it; GTK 4: cannot read strokeWidth of Grid - SwiftOmniUI draws a layout's box on GTK's snapshot, which holds none of its strokeWidth; its drawing proves it |

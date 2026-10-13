<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Polygon

A closed outline through a list of points.

Layer: `stateUI`. SwiftOmniUI composes it from smaller primitives before a host receives the tree.

Inherits: [PropertyContainer](tiers/PropertyContainer.md) · [VisualElement](tiers/VisualElement.md) · [View](tiers/View.md) · [Shape](tiers/Shape.md)

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

| Host | Created | Members (116) | Realization | Notes |
| --- | :---: | --- | --- | --- |
| Android Views | ✅ | 52 ✅ · 1 ☑️ · 3 – | `View` drawing `Path` |  |
| WinUI 3 | ✅ | 61 ✅ · 3 – | `Microsoft.UI.Xaml.Shapes` |  |
| GTK 4 | ✅ | 17 ✅ · 14 – | `GskPath` in a snapshot |  |
| Web |  |  | inline SVG | no host yet |

Declared in `lib/SwiftOmniUI/Sources/Contracts/Elements/Shapes/PolygonContract.swift`.

## Polygon's own members

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `fillRule` | property | `FillRule` | stateUI | ✅ | ✅ | · |  | GTK 4: cannot read the colour of Grid - GTK's driver has no path for it yet |
| `points` | property | `[Point]` | stateUI | ✅ | ✅ | · |  | GTK 4: cannot read the colour of Grid - GTK's driver has no path for it yet |

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
| `accessibilityHeadingLevel` | property | `HeadingLevel` | native | · | ✅ | · |  | cannot read a heading's level - Android marks a heading, not its level; GTK 4: cannot read accessibilityHeadingLevel of Polygon - GTK's driver has no path for it yet |
| `accessibilityHint` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityHint of Polygon - GTK's driver has no path for it yet |
| `accessibilityLabel` | property | `String` | native | ✅ | ✅ | · |  | GTK 4: cannot read accessibilityLabel of Polygon - GTK's driver has no path for it yet |
| `accessibilityTraits` | property | `AccessibilityTraits` | native |  |  | – |  | GTK 4: GTK's accessibility bridge answers no traits yet. |
| `automationExcludedWithChildren` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read automationExcludedWithChildren of Polygon - GTK's driver has no path for it yet |
| `background` | property | `Background` | native | ✅ |  |  |  | WinUI 3: not realized; GTK 4: not realized |
| `blur` | property | `Double` | native |  |  |  |  | GTK 4: not realized |
| `contentTransition` | property | `String` | native |  |  | – |  | GTK 4: GTK swaps a label's words with no transition yet. |
| `compositingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `drawingGroup` | property | `Bool` | native |  |  |  |  | GTK 4: not realized |
| `focus` | act | `() -> Bool` |  | – | – | – |  | Polygon takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Polygon takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Polygon takes no keyboard focus here: it refuses it, and nothing is heard |
| `frame` | property | `Rect` | structure | ✅ | ✅ | ✅ |  |  |
| `height` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `hint` | property | `String` | native |  |  | · |  | GTK 4: cannot read hint of Polygon - GTK's driver has no path for it yet |
| `hintKey` | property | `LocalizedStringKey` | native |  |  |  |  | GTK 4: not realized |
| `horizontalAlignmentDefault` | property | `AxisAlignment` | structure |  |  |  |  | GTK 4: not realized |
| `ignoresInput` | property | `Bool` | native |  |  |  |  | not realized; WinUI 3: not realized; GTK 4: not realized |
| `isAccessibilityHidden` | property | `Bool` | native | ✅ | ✅ | · |  | GTK 4: cannot read isAccessibilityHidden of Polygon - GTK's driver has no path for it yet |
| `isEnabled` | property | `Bool` | native |  |  | ✅ |  | not realized; WinUI 3: not realized |
| `isFocusedChanged` | event | `Bool` | native | – | – | – |  | Polygon takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Polygon takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Polygon takes no keyboard focus here: it refuses it, and nothing is heard |
| `isFrameContent` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isGeometryReader` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isLayoutDecoration` | property | `Bool` | structure |  |  |  |  | GTK 4: not realized |
| `isVisible` | property | `Bool` | native | ✅ | ✅ | ✅ |  |  |
| `layoutDirection` | property | `LayoutDirection` | native |  |  | · |  | not realized; WinUI 3: not realized; GTK 4: cannot read layoutDirection of Polygon - GTK's driver has no path for it yet |
| `matchedGeometry` | property | `String` | native |  |  | – |  | GTK 4: GTK's layout motion flies no matched child into place yet. |
| `matchedGeometrySource` | property | `Bool` | native |  |  | – |  | GTK 4: GTK's layout motion flies no matched child into place yet. |
| `maximumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `maximumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumHeight` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `minimumWidth` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `opacity` | property | `Double` | native | ✅ | ✅ | ✅ |  |  |
| `pivotX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotX of Polygon - GTK's driver has no path for it yet |
| `pivotY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read pivotY of Polygon - GTK's driver has no path for it yet |
| `rotation` | property | `Angle` | native | ✅ | ✅ | · |  | GTK 4: cannot read rotation of Polygon - GTK's driver has no path for it yet |
| `rotationX` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationX of Polygon - GTK's driver has no path for it yet |
| `rotationY` | property | `Angle` | native | ✅ |  | · |  | WinUI 3: not realized; GTK 4: cannot read rotationY of Polygon - GTK's driver has no path for it yet |
| `safeAreaInsetEdge` | property | `Edge` | structure |  |  |  |  | GTK 4: not realized |
| `scale` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scale of Polygon - GTK's driver has no path for it yet |
| `scaleX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleX of Polygon - GTK's driver has no path for it yet |
| `scaleY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read scaleY of Polygon - GTK's driver has no path for it yet |
| `shadow` | property | `DropShadow` | native |  |  |  |  | GTK 4: not realized |
| `style` | property | `Name` | structure | ✅ | ✅ | ✅ |  |  |
| `symbolEffect` | property | `String` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectActive` | property | `Bool` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectOptions` | property | `Int` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `symbolEffectValue` | property | `String` | native |  |  | – |  | GTK 4: GTK's pictures are painted, not animated as symbols. |
| `transition` | property | `AnyTransition` | native |  |  | · |  | GTK 4: cannot read transition of Polygon - GTK's driver has no path for it yet |
| `translationX` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationX of Polygon - GTK's driver has no path for it yet |
| `translationY` | property | `Double` | native | ✅ | ✅ | · |  | GTK 4: cannot read translationY of Polygon - GTK's driver has no path for it yet |
| `unfocus` | act | `() -> Void` |  | – | – | – |  | Polygon takes no keyboard focus here: it refuses it, and nothing is heard; WinUI 3: Polygon takes no keyboard focus here: it refuses it, and nothing is heard; GTK 4: Polygon takes no keyboard focus here: it refuses it, and nothing is heard |
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
| `horizontalGuide` | property | `[Double]` | stateUI |  |  | · |  | GTK 4: cannot read horizontalGuide of Polygon - GTK's driver has no path for it yet |
| `layoutPriority` | property | `Double` | stateUI |  |  | · |  | GTK 4: cannot read layoutPriority of Polygon - GTK's driver has no path for it yet |
| `namedFramesChanged` | event | `[NamedSpaceFrame]` | native |  |  |  |  | GTK 4: not realized |
| `padding` | property | `EdgeInsets` | native | ✅ | ✅ | ✅ |  |  |
| `panTouchCount` | property | `Int` | structure | ☑️ | ✅ | · |  | The host layer hears a one-finger pan only; any other `panTouchCount` turns the pan off.; GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `onPanUpdated` (`panUpdated`) | event | `(GesturePhase, Double, Double, Point?, Point?)` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `panXChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `panYChannel` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `pinchUpdated` | event | `(GesturePhase, Double, Point)` | native | ✅ | ✅ | · |  | GTK 4: cannot pinch on Polygon - GTK's driver has no path for it yet |
| `pointerEntered` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Polygon - GTK's driver has no path for it yet |
| `pointerExited` | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Polygon - GTK's driver has no path for it yet |
| `pointerMoved` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Polygon - GTK's driver has no path for it yet |
| `pointerPressed` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Polygon - GTK's driver has no path for it yet |
| `pointerReleased` | event | `Point?` | native | ✅ | ✅ | · |  | GTK 4: cannot hover on Polygon - GTK's driver has no path for it yet |
| `pointerStyle` | property | `PointerStyle` | native |  |  | – |  | GTK 4: GTK sets a widget's cursor only through the frame's display, which the element layer does not own yet. |
| `swipeDirection` | property | `SwipeDirection` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `swipeThreshold` | property | `Double` | structure | ✅ | ✅ | · |  | GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `onSwiped` (`swiped`) | event | `SwipeDirection` | native | ✅ | ✅ | · |  | GTK 4: cannot pan on Polygon - GTK's driver has no path for it yet |
| `tag` | property | `PropValue` | stateUI |  |  |  |  | GTK 4: not realized |
| `tapCount` | property | `Int` | structure | ✅ | ✅ | · |  | GTK 4: cannot tap on Polygon - GTK's driver has no path for it yet |
| `onTapGesture` (`tapGesture`) | event |  | native | ✅ | ✅ | · |  | GTK 4: cannot tap on Polygon - GTK's driver has no path for it yet |
| `verticalAlignment` | property | `AxisAlignment` | native | ✅ | ✅ | ❌ |  | GTK 4: 200.0 expected, 0.0 came - at the end of a room 300 wide |
| `verticalContentAlignment` | property | `AxisAlignment` | native |  |  |  |  | GTK 4: not realized |
| `verticalGuide` | property | `[Double]` | stateUI |  |  | · |  | GTK 4: cannot read verticalGuide of Polygon - GTK's driver has no path for it yet |

## From [Shape](tiers/Shape.md)

What every drawn shape has: what fills it, the line around it, how it fits its room, and a transform of its own drawing.

| Member | Kind | Value | Layer | Android Views | WinUI 3 | GTK 4 | Web | Notes |
| --- | --- | --- | --- | :---: | :---: | :---: | :---: | --- |
| `aspect` | property | `ContentMode` | native | ◐ | ✅ | · |  | cannot read aspect of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its aspect; its drawing proves it; GTK 4: cannot read the colour of Polygon - GTK's driver has no path for it yet |
| `fill` | property | `Brush` | stateUI | ◐ | ✅ | · |  | cannot read fill of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its fill; its drawing proves it; GTK 4: cannot read the colour of Polygon - GTK's driver has no path for it yet |
| `renderTransform` | property | `ViewTransform` | native | ◐ | ✅ | · |  | cannot read renderTransform of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its renderTransform; its drawing proves it; GTK 4: cannot read the colour of Polygon - GTK's driver has no path for it yet |
| `stroke` | property | `Brush` | stateUI | ◐ | ✅ | · |  | cannot read stroke of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its stroke; its drawing proves it; GTK 4: cannot read the colour of Polygon - GTK's driver has no path for it yet |
| `strokeBorder` | property | `Brush` | stateUI |  |  |  |  | GTK 4: not realized |
| `strokeDashOffset` | property | `Double` | stateUI | · | ✅ | · |  | cannot read strokeDashOffset of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its strokeDashOffset; its drawing proves it; GTK 4: cannot read strokeDashOffset of Polygon - SwiftOmniUI draws a shape on GTK's snapshot, which holds none of its strokeDashOffset; its drawing proves it |
| `strokeDashPattern` | property | `[Double]` | stateUI | · | ✅ | · |  | cannot read strokeDashPattern of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its strokeDashPattern; its drawing proves it; GTK 4: cannot read strokeDashPattern of Polygon - SwiftOmniUI draws a shape on GTK's snapshot, which holds none of its strokeDashPattern; its drawing proves it |
| `strokeLineCap` | property | `LineCap` | stateUI | · | ✅ | · |  | cannot read strokeLineCap of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its strokeLineCap; its drawing proves it; GTK 4: cannot read strokeLineCap of Polygon - SwiftOmniUI draws a shape on GTK's snapshot, which holds none of its strokeLineCap; its drawing proves it |
| `strokeLineJoin` | property | `LineJoin` | stateUI | · | ✅ | · |  | cannot read strokeLineJoin of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its strokeLineJoin; its drawing proves it; GTK 4: cannot read strokeLineJoin of Polygon - SwiftOmniUI draws a shape on GTK's snapshot, which holds none of its strokeLineJoin; its drawing proves it |
| `strokeMiterLimit` | property | `Double` | stateUI | · | ✅ | · |  | cannot read strokeMiterLimit of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its strokeMiterLimit; its drawing proves it; GTK 4: cannot read strokeMiterLimit of Polygon - SwiftOmniUI draws a shape on GTK's snapshot, which holds none of its strokeMiterLimit; its drawing proves it |
| `strokeWidth` | property | `Double` | stateUI | ◐ | ✅ | · |  | cannot read strokeWidth of Polygon - SwiftOmniUI draws a shape in its view's onDraw, which holds none of its strokeWidth; its drawing proves it; GTK 4: cannot read the colour of Polygon - GTK's driver has no path for it yet |
| `fillRule` | property | `FillRule` | stateUI | ✅ | ✅ | · |  | GTK 4: cannot read the colour of Grid - GTK's driver has no path for it yet |
| `strokeDashInPathUnits` | property | `Bool` | stateUI |  |  |  |  |  |
| `strokePhaseInPathUnits` | property | `Bool` | stateUI |  |  |  |  |  |

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What every view a layout positions has: where it sits in its layout, the
/// space kept around it, and the gestures, drags and frame reports it answers.
public enum ViewContract: Contract {
    /// The tier's name.
    public static let name = "View"

    /// Every view is drawn.
    public static let tiers: [any Contract.Type] = [VisualElementContract.self]

    /// Whether the view accepts what is dropped on it.
    public static let allowDrop = ElementProperty<Self, Bool>("allowDrop", layer: .native, cleared: false)

    /// The part of the enclosing ZStack's room the view stands in.
    public static let area = ElementProperty<Self, Area>("area", layer: .structure, travels: false)

    /// Whether the view can be dragged.
    public static let canDrag = ElementProperty<Self, Bool>("canDrag", layer: .native, cleared: false)

    /// A drag left the view without being let go.
    public static let dragLeave = ElementEvent<Self, Void>("dragLeave", layer: .native)

    /// A drag is over the view, not yet let go.
    public static let dragOver = ElementEvent<Self, Void>("dragOver", layer: .native)

    /// A drag of the view is starting.
    public static let dragStarting = ElementEvent<Self, Void>("dragStarting", layer: .native)

    /// The text a drag of the view carries.
    public static let dragText = ElementProperty<Self, String>("dragText", layer: .native, cleared: false)

    /// Something was dropped on the view, with the text it carried.
    public static let drop = ElementEvent<Self, String>("drop", layer: .native)

    /// A drag that started on the view ended, wherever it ended.
    public static let dropCompleted = ElementEvent<Self, Void>("dropCompleted", layer: .native)

    /// Files were dropped on the view: their paths, and where the drop landed
    /// in the view's own frame.
    public static let dropPaths = ElementEvent<Self, ([String], Point)>("dropPaths", layer: .native)

    /// The name this view gives its own coordinate space, which measurements
    /// inside it read through `.named(name)`; `.coordinateSpace` writes it.
    public static let coordinateSpaceName = ElementProperty<Self, String>(
        "coordinateSpaceName", layer: .stateUI, travels: false)

    /// The view settled on a frame: ten numbers - x, y, width, height, the
    /// window's x and y, and the safe area's frame in the window.
    public static let frameChanged = ElementEvent<Self, [Double]>("frameChanged", layer: .native)

    /// Internal drawing feedback: width and height, independent of scroll position.
    @_spi(Host) public static let drawingSizeChanged = ElementEvent<Self, [Double]>("drawingSizeChanged", layer: .native)

    /// The pointer's look while it is over the view; `.pointerStyle` writes it.
    public static let pointerStyle = ElementProperty<Self, PointerStyle>("pointerStyle", layer: .native)

    /// How loudly the view asks for its natural size when the layout runs
    /// short - a higher one keeps its size while lower ones give theirs up;
    /// `.layoutPriority` writes it.
    public static let layoutPriority = ElementProperty<Self, Double>(
        "layoutPriority", layer: .stateUI, travels: false)

    /// The horizontal alignment slot this view overrides, and the point in its
    /// own frame it aligns by - [slot, offset]; `.alignmentGuide` writes it.
    public static let horizontalGuide = ElementProperty<Self, [Double]>(
        "horizontalGuide", layer: .stateUI, travels: false)

    /// The vertical alignment slot this view overrides, and the point in its
    /// own frame it aligns by - [slot, offset]; `.alignmentGuide` writes it.
    public static let verticalGuide = ElementProperty<Self, [Double]>(
        "verticalGuide", layer: .stateUI, travels: false)

    /// The view stretches to share the room left over along its layout's axis,
    /// never less than this long. What a `Spacer` writes.
    public static let flex = ElementProperty<Self, Double>("flex", layer: .stateUI, travels: false)

    /// Which column of a Grid the view sits in.
    public static let gridColumn = ElementProperty<Self, Int>("gridColumn", layer: .stateUI, travels: false)

    /// How many columns of a Grid the view spans.
    public static let gridColumnSpan = ElementProperty<Self, Int>(
        "gridColumnSpan", layer: .stateUI, travels: false)

    /// Which row of a Grid the view sits in.
    public static let gridRow = ElementProperty<Self, Int>("gridRow", layer: .stateUI, travels: false)

    /// How many rows of a Grid the view spans.
    public static let gridRowSpan = ElementProperty<Self, Int>("gridRowSpan", layer: .stateUI, travels: false)

    /// How the view uses the width its layout offers.
    public static let horizontalAlignment = ElementProperty<Self, AxisAlignment>(
        "horizontalAlignment", layer: .native)

    /// Where the view's contents stand inside the bounds `frame` gave it, across.
    public static let horizontalContentAlignment = ElementProperty<Self, AxisAlignment>(
        "horizontalContentAlignment", layer: .native)

    /// Where the view's contents stand inside the bounds `frame` gave it, down.
    public static let verticalContentAlignment = ElementProperty<Self, AxisAlignment>(
        "verticalContentAlignment", layer: .native)

    /// The named coordinate spaces enclosing the view, innermost first, each
    /// its declaring view's frame in window coordinates; sent with a frame
    /// report, ahead of its numbers.
    public static let namedFramesChanged = ElementEvent<Self, [NamedSpaceFrame]>(
        "namedFramesChanged", layer: .native)

    /// The remaining safe-area environment, independent of the allocated
    /// frame. Carried beside the existing ten-number frame report.
    public static let safeAreaInsetsChanged = ElementEvent<Self, EdgeInsets>(
        "safeAreaInsetsChanged", layer: .native)

    /// The space kept outside the view, between it and its neighbours.
    public static let padding = ElementProperty<Self, EdgeInsets>("padding", layer: .native, moves: .spacing)

    /// How many pointers a pan must have.
    public static let panTouchCount = ElementProperty<Self, Int>(
        "panTouchCount", layer: .structure, travels: false, cleared: false)

    /// The view is being dragged: the phase, how far across and down since the
    /// pan began, and where it began and is now, in the view's own
    /// coordinates, where the platform says them.
    public static let panUpdated = ElementEvent<Self, (GesturePhase, Double, Double, Point?, Point?)>(
        "panUpdated", layer: .native)

    /// The number of the state a drag's distance across is written into.
    public static let panXChannel = ElementProperty<Self, Int>(
        "panXChannel", layer: .structure, travels: false)

    /// The number of the state a drag's distance down is written into.
    public static let panYChannel = ElementProperty<Self, Int>(
        "panYChannel", layer: .structure, travels: false)

    /// Two fingers moved apart or together: the phase, the scale since the
    /// last report, and the pinch's centre as a fraction of the view.
    public static let pinchUpdated = ElementEvent<Self, (GesturePhase, Double, Point)>(
        "pinchUpdated", layer: .native)

    /// A pointer entered the view.
    public static let pointerEntered = ElementEvent<Self, Void>("pointerEntered", layer: .native)

    /// A pointer left the view.
    public static let pointerExited = ElementEvent<Self, Void>("pointerExited", layer: .native)

    /// A pointer moved over the view, where the platform says where.
    public static let pointerMoved = ElementEvent<Self, Point?>("pointerMoved", layer: .native)

    /// A pointer button went down over the view, where the platform says where.
    public static let pointerPressed = ElementEvent<Self, Point?>("pointerPressed", layer: .native)

    /// A pointer button came up over the view, where the platform says where.
    public static let pointerReleased = ElementEvent<Self, Point?>("pointerReleased", layer: .native)

    /// Which ways a swipe on the view is listened for.
    public static let swipeDirection = ElementProperty<Self, SwipeDirection>(
        "swipeDirection", layer: .structure, cleared: false)

    /// How far a swipe must travel to count, in device units.
    public static let swipeThreshold = ElementProperty<Self, Double>(
        "swipeThreshold", layer: .structure, travels: false, cleared: false)

    /// The view was swiped, the one dominant direction it went.
    public static let swiped = ElementEvent<Self, SwipeDirection>("swiped", layer: .native)

    /// A marker the view's container reads to name it - what a `Picker`'s
    /// selection or a `TabView`'s current tab is matched against. Never
    /// crosses on its own; the container reads it off the child.
    public static let tag = ElementProperty<Self, PropValue>("tag", layer: .stateUI, travels: false)

    /// How many taps in a row a tap on the view takes.
    public static let tapCount = ElementProperty<Self, Int>(
        "tapCount", layer: .structure, travels: false, cleared: false)

    /// The view was tapped.
    public static let tapGesture = ElementEvent<Self, Void>("tapGesture", layer: .native)

    /// How the view uses the height its layout offers.
    public static let verticalAlignment = ElementProperty<Self, AxisAlignment>(
        "verticalAlignment", layer: .native)

    /// The tier's own members.
    public static let members: [any ContractMember] = [
        allowDrop, area, canDrag, coordinateSpaceName, dragLeave,
        dragOver, dragStarting, dragText, drop, dropCompleted, dropPaths, flex, frameChanged, drawingSizeChanged, gridColumn,
        gridColumnSpan, gridRow, gridRowSpan, horizontalAlignment, horizontalContentAlignment, horizontalGuide,
        layoutPriority,
        namedFramesChanged, safeAreaInsetsChanged, padding, panTouchCount,
        panUpdated, panXChannel, panYChannel, pinchUpdated, pointerEntered, pointerExited,
        pointerMoved, pointerPressed, pointerReleased, pointerStyle, swipeDirection, swipeThreshold, swiped,
        tag, tapCount, tapGesture, verticalAlignment, verticalContentAlignment, verticalGuide,
    ]
}

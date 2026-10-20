// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The gestures a view hears.
// Design: docs/design/views/modifiers.md#gestures

extension View {
    // MARK: Tap

    /// Runs when the view is tapped by the platform's native recognizer.
    ///
    ///     HStack { … }
    ///         .onTapGesture { path.append(.details(id)) }
    ///
    /// The whole view answers, not a button inside it.
    public func onTapGesture(_ handler: @escaping EventHandler) -> ModifiedContent {
        hearing(ViewContract.tapGesture, handler)
    }

    /// The same, for a double tap or more: `count` taps in a row.
    ///
    ///     Text("Reset").onTapGesture(count: 2) { taps = 0 }
    public func onTapGesture(
        count: Int,
        _ handler: @escaping EventHandler
    ) -> ModifiedContent {
        revised {
            $0.write(ViewContract.tapCount, count)
            $0.addHandler(ViewContract.tapGesture.token, handler)
        }
    }

    // MARK: Swipe

    /// Runs when the view is swiped, with the one dominant direction it went.
    ///
    ///     VStack { … }
    ///         .onSwiped(direction: [.left, .right]) { direction in
    ///             if direction == .left { items.removeLast() }
    ///         }
    ///
    /// - Parameters:
    ///   - direction: which ways to listen for. A view that listens for nothing
    ///     recognizes nothing, so the default is every direction.
    ///   - threshold: how far a swipe must travel to count, in device units.
    @_spi(Host) public func onSwiped(
        direction: SwipeDirection = .all,
        threshold: Double? = nil,
        _ handler: @escaping ValueEventHandler<SwipeDirection>
    ) -> ModifiedContent {
        revised {
            $0.write(ViewContract.swipeDirection, direction)
            $0.describe(ViewContract.swipeThreshold, threshold)
            $0.addHandler(ViewContract.swiped.token) {
                // A payload that does not read leaves the handler alone.
                if let direction = SwipeDirection(EventBuffer.current.value()) {
                    try await handler(direction)
                }
            }
        }
    }

    // MARK: Pan

    /// Writes how far the view has been dragged across into a state, with no
    /// view rebuilt as it moves.
    ///
    ///     @State private var turn = 0.0
    ///
    ///     ColorPicker(.transparent).panX($turn)
    ///
    /// The distance `onPanUpdated` reports, for an `.engine(following:)` to
    /// follow frame by frame. A drag moves the value on from where it stood, so
    /// a second drag carries on where the first left off.
    ///
    /// - Parameter value: the state the distance is written into.
    @_spi(Host) public func panX(_ value: Binding<Double>) -> ModifiedContent {
        revised { $0.driveNumber(ViewContract.panXChannel.token, by: value) }
    }

    /// Writes how far the view has been dragged down into a state, with no view
    /// rebuilt as it moves; see `panX(_:)`.
    ///
    ///     ColorPicker(.transparent).panY($turn)
    ///
    /// - Parameter value: the state the distance is written into.
    @_spi(Host) public func panY(_ value: Binding<Double>) -> ModifiedContent {
        revised { $0.driveNumber(ViewContract.panYChannel.token, by: value) }
    }

    /// Runs as the view is dragged, from the moment it starts until it is let
    /// go.
    ///
    ///     ColorPicker(.cornflowerBlue)
    ///         .offset(x: offsetX)
    ///         .onPanUpdated { pan in
    ///             if pan.phase == .running { offsetX = pan.totalX }
    ///         }
    ///
    /// The totals are measured from where the pan began.
    ///
    /// - Parameter touchCount: how many simultaneous pointers the host must
    ///   require. A host that cannot distinguish that count does not recognize
    ///   the gesture when the requested count is unsupported.
    @_spi(Host) public func onPanUpdated(
        touchCount: Int? = nil,
        _ handler: @escaping ValueEventHandler<PanUpdate>
    ) -> ModifiedContent {
        revised {
            $0.describe(ViewContract.panTouchCount, touchCount)
            $0.addHandler(ViewContract.panUpdated.token) {
                if let (phase, totalX, totalY, start, location) = MemberValues.carried(
                    EventBuffer.current, by: ViewContract.panUpdated.name,
                    as: GesturePhase.self, Double.self, Double.self, Point?.self, Point?.self) {
                    try await handler(PanUpdate(
                        phase: phase, totalX: totalX, totalY: totalY, start: start, location: location))
                }
            }
        }
    }

    // MARK: Drag

    /// Attaches a gesture to the view - a `DragGesture`, reporting each move
    /// it makes once it has begun.
    ///
    ///     @State private var offset = Size.zero
    ///     ColorPicker(.cornflowerBlue)
    ///         .gesture(
    ///             DragGesture()
    ///                 .onChanged { value in offset = value.translation }
    ///                 .onEnded { _ in offset = .zero }
    ///         )
    ///
    /// The view answers the drag itself; a gesture that needs the drag to move
    /// a state without rebuilding the view uses `.panX(_:)`/`.panY(_:)` in
    /// place of it.
    public func gesture(_ gesture: some Gesture) -> ModifiedContent {
        guard let drag = gesture as? ChangedDragGesture else { return revised { _ in } }

        var passed = false
        return revised {
            $0.addHandler(ViewContract.panUpdated.token) {
                guard let (phase, totalX, totalY, start, location) = MemberValues.carried(
                    EventBuffer.current, by: ViewContract.panUpdated.name,
                    as: GesturePhase.self, Double.self, Double.self, Point?.self, Point?.self)
                else { return }

                switch phase {
                case .started:
                    passed = drag.minimumDistance <= 0
                    fallthrough
                case .running:
                    passed = passed
                        || (totalX * totalX + totalY * totalY).squareRoot() >= drag.minimumDistance
                    guard passed else { return }
                    if let changed = drag.changed {
                        changed(
                            DragGesture.Value(
                                startLocation: start ?? Point(x: 0, y: 0),
                                location: location ?? Point(x: 0, y: 0),
                                translation: Size(width: totalX, height: totalY)))
                    }
                case .completed, .canceled:
                    defer { passed = false }
                    passed = passed
                        || (totalX * totalX + totalY * totalY).squareRoot() >= drag.minimumDistance
                    guard passed, let ended = drag.ended else { return }
                    ended(
                        DragGesture.Value(
                            startLocation: start ?? Point(x: 0, y: 0),
                            location: location ?? Point(x: 0, y: 0),
                            translation: Size(width: totalX, height: totalY)))
                }
            }
        }
    }

    // MARK: Pinch

    /// Runs as two fingers move apart or together.
    ///
    /// `scale` is relative - the change since the last report, not since the
    /// pinch began - so a view being pinched multiplies rather than assigns.
    @_spi(Host) public func onPinchUpdated(_ handler: @escaping ValueEventHandler<PinchUpdate>) -> ModifiedContent {
        hearing(ViewContract.pinchUpdated) { phase, scale, origin in
            try await handler(PinchUpdate(phase: phase, scale: scale, scaleOrigin: origin))
        }
    }

    // MARK: Pointer

    /// Continuously reports a pointer's position in the view's local space.
    public func onContinuousHover(perform: @escaping (HoverPhase) -> Void) -> ModifiedContent {
        onPointerMoved { perform(.active($0)) }
            .onPointerExited { perform(.ended) }
    }

    /// Runs when a pointer enters the view.
    ///
    /// A pointer is a mouse, a trackpad or a pen; on a touch-only device these
    /// never fire.
    @_spi(Host) public func onPointerEntered(_ handler: @escaping EventHandler) -> ModifiedContent {
        hearing(ViewContract.pointerEntered, handler)
    }

    /// Runs when a pointer leaves the view - the other half of a hover.
    @_spi(Host) public func onPointerExited(_ handler: @escaping EventHandler) -> ModifiedContent {
        hearing(ViewContract.pointerExited, handler)
    }

    /// Runs as a pointer's hover over the view begins and ends - `true` on
    /// entering, `false` on leaving. The SwiftUI spelling of the pair above:
    ///
    ///     .onHover { hovering in isHovered = hovering }
    ///
    /// A pointer is a mouse, a trackpad or a pen; on a touch-only device it
    /// never runs.
    /// `onHover(_:)` under SwiftUI's `perform:` label.
    @_disfavoredOverload
    public func onHover(perform: @escaping (Bool) -> Void) -> ModifiedContent {
        onHover(perform)
    }

    /// `onHover(perform:)` under the trailing-closure spelling.
    public func onHover(_ perform: @escaping (Bool) -> Void) -> ModifiedContent {
        onPointerEntered { perform(true) }
            .onPointerExited { perform(false) }
    }

    /// Runs as the pointer moves over the view, with where it is in the view's
    /// own coordinates; a move the platform gives no position for does not run
    /// it.
    @_spi(Host) public func onPointerMoved(_ handler: @escaping ValueEventHandler<Point>) -> ModifiedContent {
        hearing(ViewContract.pointerMoved) { point in
            if let point {
                try await handler(point)
            }
        }
    }

    /// Runs when a pointer button goes down over the view, with where it went
    /// down in the view's own coordinates.
    @_spi(Host) public func onPointerPressed(_ handler: @escaping ValueEventHandler<Point>) -> ModifiedContent {
        hearing(ViewContract.pointerPressed) { point in
            if let point {
                try await handler(point)
            }
        }
    }

    /// Runs when the pointer button comes back up, with where it came up.
    @_spi(Host) public func onPointerReleased(_ handler: @escaping ValueEventHandler<Point>) -> ModifiedContent {
        hearing(ViewContract.pointerReleased) { point in
            if let point {
                try await handler(point)
            }
        }
    }

    // MARK: Drag and drop

    /// Makes the view draggable, carrying `text` with it.
    ///
    ///     Text(item)
    ///         .draggable(text: item)
    ///
    /// Text is the portable drag payload. `onDragStarting` runs when the drag
    /// starts, too late to decide what is carried: a native drag needs its
    /// payload at once.
    public func draggable(
        text: String,
        canDrag: Bool = true,
        onDragStarting: EventHandler? = nil
    ) -> ModifiedContent {
        revised {
            $0.write(ViewContract.dragText, text)
            $0.write(ViewContract.canDrag, canDrag)

            if let onDragStarting = onDragStarting {
                $0.addHandler(ViewContract.dragStarting.token, onDragStarting)
            }
        }
    }

    /// Runs when a drag that started here ends, wherever it ended.
    @_spi(Host) public func onDropCompleted(_ handler: @escaping EventHandler) -> ModifiedContent {
        hearing(ViewContract.dropCompleted, handler)
    }

    /// Accepts what is dropped on the view, with the text it carried.
    ///
    ///     VStack { … }
    ///         .onDrop { text in items.append(text) }
    public func onDrop(_ handler: @escaping ValueEventHandler<String>) -> ModifiedContent {
        revised {
            $0.write(ViewContract.allowDrop, true)
            $0.addHandler(ViewContract.drop.token) {
                if let text = MemberValues.carried(
                    EventBuffer.current, by: ViewContract.drop.name, as: String.self) {
                    try await handler(text)
                }
            }
        }
    }

    /// Accepts files dropped on the view.
    ///
    ///     VStack { … }
    ///         .dropDestination { paths, _ in
    ///             paths.forEach(import)
    ///             return true
    ///         } isTargeted: { hovering in
    ///             highlight = hovering
    ///         }
    ///
    /// A path is whatever the platform calls a file - turn it into a `URL`
    /// where one is wanted with `URL(fileURLWithPath:)`. `isTargeted` hears
    /// `true` as a drag that offers files moves in over the view and `false`
    /// as it leaves or lands, where the platform says so.
    ///
    /// - Parameters:
    ///   - action: what runs with the dropped paths and where the drop landed;
    ///     whether the drop was taken.
    ///   - isTargeted: whether a drag offering files is over the view.
    public func dropDestination(
        action: @escaping ValueEventHandler<[String], Point>,
        isTargeted: ((Bool) -> Void)? = nil
    ) -> ModifiedContent {
        revised {
            $0.write(ViewContract.allowDrop, true)
            $0.addHandler(ViewContract.dropPaths.token) {
                isTargeted?(false)
                if let (paths, point) = MemberValues.carried(
                    EventBuffer.current, by: ViewContract.dropPaths.name,
                    as: [String].self, Point.self) {
                    _ = try await action(paths, point)
                }
            }
            if let isTargeted {
                $0.addHandler(ViewContract.dragOver.token) { isTargeted(true) }
                $0.addHandler(ViewContract.dragLeave.token) { isTargeted(false) }
            }
        }
    }

    /// Runs while a drag is over the view, before it is let go.
    @_spi(Host) public func onDragOver(_ handler: @escaping EventHandler) -> ModifiedContent {
        hearing(ViewContract.dragOver, handler)
    }

    /// Runs when a drag leaves the view without being let go - the mirror of
    /// `onDragOver`, and where a highlight put up there is taken down.
    @_spi(Host) public func onDragLeave(_ handler: @escaping EventHandler) -> ModifiedContent {
        hearing(ViewContract.dragLeave, handler)
    }
}

extension View {
    /// The pointer's look while it is over the view, on a platform with a
    /// pointer at all:
    ///
    ///     Text("Drag to resize")
    ///         .pointerStyle(.rowResize)
    ///
    /// A `pointerStyle` deeper in wins over one outside, as the pointer hears
    /// from the deepest view under it.
    public func pointerStyle(_ style: PointerStyle) -> ModifiedContent {
        setting(ViewContract.pointerStyle, style)
    }

    /// How loudly the view asks for its natural size when the layout runs
    /// short: a higher priority keeps its size while lower ones give theirs
    /// up; equal priorities share what is left.
    ///
    ///     Text(name).layoutPriority(1)
    public func layoutPriority(_ value: Double) -> ModifiedContent {
        revised { $0.write(ViewContract.layoutPriority, value) }
    }

    /// The point this view answers a horizontal alignment with - the place in
    /// its own frame that lands on the alignment the parent asks for:
    ///
    ///     Image("check.png")
    ///         .alignmentGuide(.leading) { _ in 10 }
    ///
    /// - Parameters:
    ///   - guide: the alignment whose answer this overrides.
    ///   - computeValue: the guide's place in the view's own frame. It runs as
    ///     the view describes, ahead of the host's measurement - a constant
    ///     places exactly; `dimensions` reads 0 there.
    public func alignmentGuide(
        _ guide: HorizontalAlignment,
        computeValue: @escaping (ViewDimensions) -> Double
    ) -> ModifiedContent {
        revised {
            $0.write(
                ViewContract.horizontalGuide,
                [Double(guide.axis.rawValue), computeValue(ViewDimensions())])
        }
    }

    /// The point this view answers a vertical alignment with - the place in
    /// its own frame that lands on the alignment the parent asks for:
    ///
    ///     InlineMath(tex)
    ///         .alignmentGuide(.firstTextBaseline) { _ in baseline }
    ///
    /// - Parameters:
    ///   - guide: the alignment whose answer this overrides.
    ///   - computeValue: the guide's place in the view's own frame. It runs as
    ///     the view describes, ahead of the host's measurement - a constant
    ///     places exactly; `dimensions` reads 0 there.
    public func alignmentGuide(
        _ guide: VerticalAlignment,
        computeValue: @escaping (ViewDimensions) -> Double
    ) -> ModifiedContent {
        revised {
            $0.write(
                ViewContract.verticalGuide,
                [Double(guide.axis.rawValue), computeValue(ViewDimensions())])
        }
    }
}

extension View {
    /// How the triggers of `Menu` buttons inside this view draw - a `Menu`
    /// keeping its own wins over the inherited one:
    ///
    ///     Menu { MenuItem("One").onClicked { pick(1) } } label: { Text("Pick") }
    ///         .menuStyle(.borderlessButton)
    @_disfavoredOverload
    public func menuStyle(_ style: some MenuStyle) -> ModifiedContent {
        revised { $0.writeInherited(MenuButtonContract.menuStyle, style.menuStyleToken) }
    }

    /// Whether `Menu` buttons inside this view show the mark that says they
    /// open a menu.
    @_disfavoredOverload
    public func menuIndicator(_ visibility: MenuIndicatorVisibility) -> ModifiedContent {
        revised { $0.writeInherited(MenuButtonContract.menuIndicator, visibility) }
    }
}

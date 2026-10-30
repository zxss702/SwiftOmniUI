// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// One control at a time: what each one puts in the patch.
//
// The other tests here are about the MECHANISM - identity, memoization, handler
// ids - and controls appear in them only as material. This file is about the
// CONTRACT of each control: a modifier is written in Swift, a property crosses
// the host boundary, and nothing between the two says they agree on the name.
//
// That gap is silent by design. An unknown property is ignored rather than
// reported, so a modifier a host has not caught up with does nothing at
// all, looks exactly like one that works, and no test that exercises the
// mechanism will ever notice.
//
// So every control is built here with every modifier it declares. Four tests
// keep the set honest:
//
//   testEveryControlCarriesOnlyWhatItsContractDeclares   no name a host would guess at
//   testEveryModifierIsExercised    a modifier missing from a case fails HERE
//   testEveryControlHasACase        a new control with no case fails HERE
//   testTheSharedTierIsCoveredOnce  the protocol tiers, on one tree
//
// The tier modifiers - padding, contentPadding, fontSize, horizontalAlignment - are
// deliberately NOT repeated per control. They live on protocols and are applied
// by one shared host path, so covering them once per control would prove one
// rule two dozen times. That is what the protocol tiers are for; the `Elements`
// case covers them once, on a stack holding a label.

import Foundation
import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// One control, built with everything of its own that it can do.
private struct ControlCase {
    /// The SwiftOmniUI node type, which is also what the case is called.
    let name: String

    /// The files under Views/ whose modifiers this case has to exercise.
    let sources: [String]

    let node: Node

    init(_ name: String, source: String, _ element: any Element) {
        self.init(name, sources: [source], element)
    }

    init(_ name: String, sources: [String], _ element: any Element) {
        self.name = name
        self.sources = sources
        self.node = element.node
    }
}

@MainActor final class ControlTests: XCTestCase {
    /// A turn, a sizing, a lean and a move, STATED rather than computed: a
    /// chain like `.rotate(15).scaleEffect(x: 1.5).skew(10, 5)` puts a libm result in
    /// the patch, and the host's maths library is not part of this library's
    /// contract. The six numbers are binary fractions, which every platform
    /// holds to the bit, and they are still a SHEAR - the two axes are not at a
    /// right angle - which is the part only a geometry can draw. What the chain
    /// itself works out is asserted in MotionTests.
    private static var leaned: ViewTransform {
        var transform = ViewTransform.identity
        transform.a = 1.5
        transform.b = 0.375
        transform.c = -0.25
        transform.d = 0.9375
        transform.tx = 6
        transform.ty = 7
        return transform
    }

    /// Built on demand rather than stored: a Node holds the closures its events
    /// run, so the list is not Sendable and cannot be a static `let` under
    /// Swift 6 - the same rule that decided where the library keeps its state.
    private static var cases: [ControlCase] {
        // The numbering starts over, so a case says the same numbers whichever
        // test read this first: a state number is issued from a counter the
        // whole process shares. See Renderer+Cycle.swift.
        Renderer.shared.clearStates()

        // A binding needs somewhere to live; a State is a reference, so this is
        // the same thing an application holds.
        let followed = State(wrappedValue: 0.0)
        let offset = State(wrappedValue: Point.zero)
        let hasBack = State(false)
        let hasForward = State(false)
        let chosen = State<String?>(wrappedValue: "two")

        let case0 =             ControlCase("Text", source: "Text.swift",
                Text("Total")
                    .lineBreak(.tailTruncation)
                    .lineHeight(1.5)
                    .lineSpacing(8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .baselineOffset(2)
                    .textRenderer(ProbeTextRenderer())
                    .textSelection(.enabled)
                    .textDecorations([.underline, .strikethrough])
                    // The runs go here rather than in a case of their own: a
                    // Span is not a view, so it has no case, and Text.swift
                    // is the file that declares it.
                    .spans {
                        TextSpan("let ")
                            .foregroundStyle(.purple)
                            .background(.whiteSmoke)
                            .fontSize(13)
                            .fontFamily("Menlo")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .fontAttributes(.bold)
                            .fontWeight(.medium)
                            .fontDesign(.serif)
                            .fontTextStyle(.caption)
                            .fontAutoScalingEnabled(false)
                            .characterSpacing(0.5)
                            .lineHeight(1.2)
                            .textDecorations(.underline)

                        TextSpan("counter").foregroundStyle(.steelBlue)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader))
        let case0b =            ControlCase("TextImage", source: "Text.swift",
                Text(Image("tab_list.png")) + Text(" marked")
                    .baselineOffset(1))
        let case1 =             ControlCase("Button", source: "Button.swift",
                Button("Increment", role: .destructive)
                    .stroke(.gray)
                    .strokeWidth(1)
                    .shape(.roundedRectangle(8))
                    .lineBreak(.noWrap)
                    .icon("tab_list.png")
                    .iconPosition(.leading)
                    .iconSpacing(8)
                    .isOn(true)
                    .onToggled { _ in }
                    .onClicked {}
                    .onPressed {}
                    .onReleased {}
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent))
        let case2 =             ControlCase("IconButton", source: "Button.swift",
                Button(icon: "tab_list.png")
                    .aspect(.fit)
                    .onClicked {})
        let case3 =             ControlCase("TextField", source: "TextField.swift",
                TextField("Ada")
                    .isPassword(false)
                    .showsClearButton(true)
                    .onTextChanged { _ in }
                    .onSubmit {}
                    .submitLabel(.done)
                    .textFieldStyle(.roundedBorder))
        let case4 =             ControlCase("TextEditor", source: "TextEditor.swift",
                TextEditor("Notes")
                    .growsWithText(true)
                    .onTextChanged { _ in })
        let case5 =             ControlCase("Image", source: "Image.swift",
                Image("tab_list.png")
                    .resizable()
                    .renderingMode(.original)
                    .aspect(.fill)
                    .isAnimating(true))
        let case6 =             ControlCase("Picker", source: "Picker.swift",
                Picker("Size", selection: State("Medium").projectedValue) {
                    Text("Small")
                    Text("Medium")
                    Text("Large")
                }
                    .tint(.gray)
                    .isOpen(false)
                    .onSelectedIndexChanged { _ in }
                    .onOpened {}
                    .onClosed {}
                    .pickerStyle(.automatic))
        let case7 =             ControlCase("DatePicker", source: "DatePicker.swift",
                DatePicker(CalendarDate(year: 2026, month: 8, day: 2))
                    .date(CalendarDate(year: 2026, month: 8, day: 9))
                    .minimumDate(CalendarDate(year: 2026, month: 1, day: 1))
                    .maximumDate(CalendarDate(year: 2026, month: 12, day: 31))
                    .format("D")
                    .isOpen(false)
                    .onDateChanged { _ in }
                    .onOpened {}
                    .onClosed {})
        let case8 =             ControlCase("TimePicker", source: "TimePicker.swift",
                TimePicker(ClockTime(hour: 9, minute: 30))
                    .time(ClockTime(hour: 21, minute: 5, second: 30))
                    .format("t")
                    .isOpen(false)
                    .onTimeChanged { _ in }
                    .onOpened {}
                    .onClosed {})
        let case9 =             ControlCase("Switch", source: "Switch.swift",
                Switch(true)
                    .isOn(true)
                    .tint(.green)
                    .onToggled { _ in })
        let case10 =             ControlCase("CheckBox", source: "CheckBox.swift",
                CheckBox(true)
                    .isOn(true)
                    .tint(.firebrick)
                    .onToggled { _ in })
        let case11 =             ControlCase("RadioButton", source: "RadioButton.swift",
                RadioButton("Medium")
                    .text("Medium")
                    .isOn(true)
                    .groupName("size")
                    .textCase(.uppercase)
                    .stroke(.gray)
                    .strokeWidth(1)
                    .shape(.roundedRectangle(8))
                    .onToggled { _ in })
        let case12 =             ControlCase("Slider", source: "Slider.swift",
                Slider(40)
                    .minimum(0)
                    .maximum(100)
                    .tint(.cornflowerBlue)
                    .onValueChanged { _ in }
                    .onDragStarted {}
                    .onDragCompleted {})
        let case13 =             ControlCase("Stepper", source: "Stepper.swift",
                Stepper(4)
                    .value(4)
                    .minimum(1)
                    .maximum(12)
                    .step(2)
                    .onValueChanged { _ in })
        let case14 =             ControlCase("SearchField", source: "SearchField.swift",
                SearchField("al")
                    .onTextChanged { _ in }
                    .onSubmit {}
                    .submitLabel(.search)
                    .tint(.gray))
        let case15 =             ControlCase("ActivityIndicator", source: "ActivityIndicator.swift",
                ActivityIndicator(true)
                    .progressViewStyle(.circular)
                    .isRunning(true)
                    .tint(.cornflowerBlue))
        let case16 =             ControlCase("ProgressBar", source: "ProgressBar.swift",
                ProgressBar(0.4)
                    .progressViewStyle(.linear)
                    .progress(0.4)
                    .tint(.cornflowerBlue))
        let case17 =             ControlCase("ColorPicker", source: "ColorPicker.swift",
                ColorPicker(.cornflowerBlue)
                    .cornerRadius(8))
        let case18 =             ControlCase("PositionIndicator", source: "PositionIndicator.swift",
                PositionIndicator()
                    .count(3)
                    .position(1)
                    .indicatorColor(.lightGray)
                    .selectedIndicatorColor(.cornflowerBlue)
                    .indicatorSize(8)
                    .maximumVisible(5)
                    .indicatorsShape(.square)
                    .hideSingle(false))
        // The dots as VIEWS - the second shape the same control takes:
        // the items run the template here, and the host counts them itself.
        let case19 =             ControlCase("IndicatorDots", source: "PositionIndicator.swift",
                PositionIndicator(["one", "two", "three"]) { name in
                    Text("*").id(name)
                }
                .position(1))
        let case20 =             ControlCase("Grid", sources: ["Grid.swift", "GridRow.swift"],
                Grid(horizontalSpacing: 8, verticalSpacing: 12) {
                    GridRow(alignment: .bottom) {
                        Text("Top left")
                        Text("Top right")
                    }

                    Text("Spanning both")
                }
                .rows(.fixed(70), .auto)
                .columns(.fill, .proportional(2))
                .rowSpacing(12)
                .columnSpacing(8))
        // A `Grid` also runs as a flow grid - `flowColumns` standing in for
        // `columns` - the shape `LazyVGrid` took before it became an element
        // of its own. The case carries the member by hand.
        var flowGrid =              Grid { Text("a"); Text("b") }
        flowGrid.node.write(GridContract.flowColumns, [GridItem(.adaptive(minimum: 80))])
        let case20a =            ControlCase("Grid", sources: ["Grid.swift", "GridRow.swift"],
                flowGrid)
        // The lazy family as its view writes it: a composed view, so the case
        // is its body built - the element, the items and the spacing it
        // declares, and `realizedChanged` carried for the host to answer.
        let case20b =           ControlCase("LazyVGrid", source: "LazyVGrid.swift",
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 128, maximum: 764), spacing: 12, alignment: .leading),
                        GridItem(.adaptive(minimum: 128, maximum: 764)),
                    ],
                    spacing: 12
                ) {
                    Text("A cell")
                    Text("Another")
                }
                .horizontalAlignment(.center)
                // The `maximumWidth` a cell asks with fills its column - the
                // prop the file reads it by, carried here on the grid.
                .frame(maxWidth: .infinity)
                .node.built)
        let case20c =           ControlCase("LazyHGrid", source: "LazyVGrid.swift",
                LazyHGrid(
                    rows: [
                        GridItem(.fixed(80), spacing: 8),
                        GridItem(.flexible(minimum: 60, maximum: 120)),
                    ],
                    spacing: 8
                ) {
                    Text("A cell")
                    Text("Another")
                }
                .verticalAlignment(.fill)
                .frame(maxHeight: .infinity)
                .node.built)
        let case20d =           ControlCase("LazyVStack", source: "LazyStacks.swift",
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("A row")
                    Text("Another")
                }
                .horizontalAlignment(.center)
                .frame(maxWidth: .infinity)
                .node.built)
        let case20e =           ControlCase("LazyHStack", source: "LazyStacks.swift",
                LazyHStack(alignment: .top, spacing: 6) {
                    Text("A row")
                    Text("Another")
                }
                .verticalAlignment(.fill)
                .frame(maxHeight: .infinity)
                .node.built)
        let case21 =             ControlCase("VStack", source: "StackLayouts.swift",
                VStack(alignment: .leading, spacing: 12) {
                    Text("One")
                    Circle()
                })
        let case22 =             ControlCase("HStack", source: "StackLayouts.swift",
                HStack(alignment: .top, spacing: 6) {
                    Text("One")
                })
        let case23 =             ControlCase("ZStack", source: "ZStack.swift",
                ZStack(alignment: .bottomTrailing) {
                    ColorPicker(.cornflowerBlue)
                        .area(.proportional(0, 0, 1, 0.5))

                    Text("Bottom right")
                }
                .stroke(.lightGray)
                .strokeWidth(1)
                .shape(.roundedRectangle(12))
                .clipsContent(true))
        let case24 =             ControlCase("ScrollView", source: "ScrollView.swift",
                ScrollView {
                    Text("content")
                }
                .orientation(.both)
                .defaultScrollAnchor(.bottom)
                .isScrollDisabled(!false)
                .scrollBounceBehavior(.basedOnSize)
                .scrollTargetBehavior(.viewAligned())
                .verticalScrollIndicators(.hidden)
                .horizontalScrollIndicators(.visible)
                // The offset is ONE POINT - both axes on one state - written
                // by the host on its own frames and walked by it on a write.
                .scrollOffset(offset.projectedValue)
                .onScrollStopped {}
                // The axes form, last: it is the view-level spelling, which
                // answers a ModifiedContent rather than the control's own.
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal))
        // The collection as its view writes it: every entry's identity, the
        // layout, the choice, and what choosing, opening and scrolling to the
        // end raise. A composed view, so the case is its body built.
        let case25 =             ControlCase("List", source: "List.swift",
                List(["one", "two"]) { Text($0) }
                    .header(Text("Words"))
                    .itemsLayout(.grid(minimumItemWidth: 120, spacing: 8))
                    .selection(chosen.projectedValue)
                    .onItemActivated { _ in }
                    .onEndReached(within: 5) {}
                    .listStyle(.sidebar)
                    .node.built)
        // Both halves of a map: the control, and the pins on it. A Pin is
        // not a control of its own - it is a marker on the map - so this
        // case is where its modifiers are exercised as well. Where the
        // map LOOKS is an act (moveToRegion), checked with the other acts
        // in ActCallShapeTests rather than here.
        let case26 =             ControlCase("Map", source: "Map.swift",
                Map(latitude: 52.2297, longitude: 21.0122, radiusMeters: 3000)
                    .mapType(.hybrid)
                    .isScrollEnabled(true)
                    .isZoomEnabled(true)
                    .isTrafficEnabled(false)
                    .showsUserLocation(false)
                    .pins {
                        Pin("Royal Castle")
                            .address("Plac Zamkowy 4")
                            .type(.place)
                            .location(latitude: 52.2479, longitude: 21.0155)
                            .onPinClicked {}
                            .onPinDetailsClicked {}

                        Pin("Second")
                            .label("Lazienki Park")
                            .location(latitude: 52.2151, longitude: 21.0355)
                    }
                    .onMapClicked { _ in })
        // The case's source is the URL form; HTML written in place
        // travels as a list under the same name - the brush rule, one
        // level up. The canGoBack and canGoForward bindings are watches
        // rather than events.
        let case27 =             ControlCase("WebView", source: "WebView.swift",
                WebView("https://example.com/docs")
                    .userAgent("SwiftOmniUI/1.0")
                    .canGoBack(hasBack.projectedValue)
                    .canGoForward(hasForward.projectedValue)
                    .onNavigating { _ in }
                    .onNavigated { _ in }
                    .onProcessTerminated {})
        // The window's authored title area. Its three slots are structural
        // children whose root views retain ordinary identity and events.
        let case28 =             ControlCase("TitleBar", source: "TitleBar.swift",
                TitleBar("SwiftOmniUI Gallery")
                    .subtitle("Fundamentals")
                    .icon("swiftomniui_mark.png")
                    .barForegroundColor(.white)
                    .leadingContent {
                        Text("lead")
                    }
                    .content {
                        Text("mid")
                    }
                    .trailingContent {
                        Button("act")
                    })
        // The shapes. What they share is the Shape tier, covered once by the
        // Elements case below; each of these carries only its own.
        let case29 =             ControlCase("Rectangle", source: "Rectangle.swift",
                Rectangle()
                    .strokeBorder(.firebrick, lineWidth: 2)
                    .cornerRadius(topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0))
        let case30 =             ControlCase("Ellipse", source: "Ellipse.swift", Ellipse())
        let case31 =             ControlCase("Line", source: "Line.swift",
                Line()
                    .x1(0)
                    .y1(0)
                    .x2(240)
                    .y2(40))
        let case32 =             ControlCase("Path", source: "Path.swift",
                Path("M 0,40 L 20,0 L 40,40 Z")
                    .data("M 0,40 L 20,0 L 40,40 Z")
                    // The one transform, sent as its whole matrix: a matrix
                    // with a lean in it exercises the part only a geometry
                    // can draw.
                    .renderTransform(Self.leaned))
        var legacyPath = Node(shape: PathContract.self)
        legacyPath.write(PathContract.data, "M 0,40 L 20,0 L 40,40 Z")
        let case32b = ControlCase("PathSVG", source: "Path.swift", legacyPath)
        let case33 =             ControlCase("Polygon", source: "Polygon.swift",
                Polygon([Point(20, 0), Point(40, 40), Point(0, 40)])
                    .points([Point(20, 0), Point(40, 40), Point(0, 40)])
                    .fillRule(.nonzero))
        let case34 =             ControlCase("Polyline", source: "Polyline.swift",
                Polyline([Point(0, 30), Point(20, 5), Point(40, 25)])
                    .points([Point(0, 30), Point(20, 5), Point(40, 25)])
                    .fillRule(.evenOdd))
        // A canvas, and the instructions it draws - every one of them, since
        // the format they travel in is read in one place by a host.
        let case35 =             ControlCase("Canvas", source: "Canvas.swift",
                Canvas {
                    Draw.fillColor(.cornflowerBlue)
                    Draw.strokeColor(Color(light: .black, dark: .white))
                    Draw.strokeWidth(2)
                    Draw.foregroundStyle(.white)
                    Draw.fontSize(14)
                    Draw.alpha(0.9)

                    Draw.drawLine(x1: 0, y1: 0, x2: 40, y2: 40)
                    Draw.drawRectangle(x: 0, y: 0, width: 20, height: 10)
                    Draw.drawRoundedRectangle(x: 0, y: 0, width: 20, height: 10, cornerRadius: 4)
                    Draw.drawEllipse(x: 0, y: 0, width: 20, height: 20)
                    Draw.drawArc(
                        x: 0, y: 0, width: 20, height: 20,
                        startAngle: 0, endAngle: 90, clockwise: true, closed: false)
                    Draw.drawPath("M 0,0 L 10,10 Z")

                    Draw.fillRectangle(x: 0, y: 0, width: 20, height: 10)
                    Draw.fillRoundedRectangle(x: 0, y: 0, width: 20, height: 10, cornerRadius: 4)
                    Draw.fillEllipse(x: 0, y: 0, width: 20, height: 20)
                    Draw.fillArc(
                        x: 0, y: 0, width: 20, height: 20,
                        startAngle: 0, endAngle: 90, clockwise: true)
                    Draw.fillPath("M 0,0 L 10,10 Z")

                    // A comma in the text: the string carries its own length,
                    // so it is text and never a separator.
                    Draw.drawText(
                        "Hello, world", x: 10, y: 20, width: 80, height: 16,
                        horizontalAlignment: .center, verticalAlignment: .end)

                    Draw.saveState()
                    Draw.translate(dx: 4, dy: 4)
                    Draw.rotate(45)
                    Draw.scale(sx: 2, sy: 2)
                    Draw.restoreState()
                }
                .onPressed { _ in }
                .onDragged { _ in }
                .onReleased { _ in })
        // The protocol tiers, once, on the three controls it takes to reach all
        // of them: a stack for spacing and padding, a label for text, font and
        // alignment, and a shape for what a shape is drawn with. The grid
        // placement is on the label because that is where a placement
        // lives - on the child, not the grid.
        // The Shape tier, which all seven shapes share - so it is
        // checked here rather than in each of their cases, exactly
        // as the font tier is.
        let el0 =                     Ellipse()

                        .fill(.radialGradient([

                            GradientStop(.white, 0),

                            GradientStop(.steelBlue, 1),

                        ], center: Point(0.3, 0.3), radius: 0.8))

                        .stroke(.linearGradient([

                            GradientStop(.gold, 0),

                            GradientStop(.tomato, 1),

                        ], startPoint: Point(0, 0), endPoint: Point(1, 1)))

                        .strokeWidth(2)

                        .strokeDashPattern([4, 2])

                        .strokeDashOffset(1)

                        .strokeLineCap(.round)

                        .strokeLineJoin(.bevel)

                        .strokeMiterLimit(4)

                        .strokeBorder(.tomato, lineWidth: 3)

                        .aspect(.fill)

                        // The one transform, on the geometry: a matrix with a

                        // lean in it exercises the part only a geometry draws.

                        .renderTransform(Self.leaned)

                        // A gradient behind a view, which is what a Brush is for

                        // everywhere else.

                        .background(.solidColor(Color(light: .whiteSmoke, dark: .black)))

        let el1 =                     Text("Tiers")

                        .foregroundStyle(.firebrick)

                        .characterSpacing(1.5)

                        .textCase(.uppercase)

                        .fontSize(20)

                        .fontFamily("OpenSansRegular")

                        .fontAttributes(.bold)

                        .fontAutoScalingEnabled(false)

                        .multilineTextAlignment(.center)

                        .verticalTextAlignment(.end)

                        // What the view says about itself: a handle for a

                        // driver, and three things a screen reader says.

                        .accessibilityIdentifier("tiers")

                        .accessibilityLabel("The shared tier")

                        .accessibilityHint("Everything every view can be told")

                        .accessibilityHeadingLevel(.level2)

                        .accessibilityHidden(false)

                        .automationExcludedWithChildren(false)

                        .help("The shared tier")

                        .gridRow(1)

                        .gridColumn(2)

                        .gridRowSpan(3)

                        .gridColumnSpan(4)

                        // The other layout that asks a child where it goes.

                        // Harmless on a view in none: an area means something

                        // only to the layout that asks for it.

                        .area(.absolute(0, 0, 120, 40))

                        // A drag written into states rather than reported -

                        // the path that describes nothing.

                        .panX(followed.projectedValue)

                        .panY(followed.projectedValue)

                        .contentPadding(8, 4)

        // The input tier, which TextField, TextEditor and SearchField all
        // share - checked here rather than in each of their cases,
        // exactly as the shape tier is.
        let el2 =                     TextField("Ada")

                        .placeholder("Name")

                        .placeholderColor(.lightGray)

                        .isReadOnly(false)

                        .textContentType(.email)

                        .maximumLength(40)

                        .isSpellCheckEnabled(false)

                        .isTextPredictionEnabled(false)

                        .cursorPosition(1)

                        .selectionLength(2)

        let elv1 = VStack {
            el0

            el1

            el2

        }

                .spacing(12)
                // The safe strip is the LAYOUT tier's one property of its own;
                // the four-value form pins its full spelling in the patch.
                .ignoresSafeArea(.none, .keyboard, .container, .all)
                .clipsContent(true)
                .letsInputThrough(true)
                .hitShape(.capsule)
                .style("Card")
                .contentPadding(24, 16, 24, 16)
                .padding(4, 8, 4, 8)
                .horizontalAlignment(.center)
                .verticalAlignment(.fill)
                .hidden(!true)
                .disabled(!false)
                .allowsHitTesting(!false)
                .layoutDirection(.rightToLeft)

        let elv2 = elv1                .opacity(0.5)
                .blur(radius: 4)
                .shadow(radius: 6, y: 2)
                .transition(.blur.combined(with: .offset(y: 12)))
                .controlSize(.small)
                .scrollDisabled(false)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
                .scrollContentBackground(.hidden)
                .scrollTargetLayout()
                .scrollTargetBehavior(.paging)
                .safeAreaPadding(.vertical, 8)
                .background(.whiteSmoke)
                .frame(width: 200)
                .frame(height: 100)
                .frame(minWidth: 50)
                .frame(minHeight: 25)
                .frame(maxWidth: 400)
                .frame(maxHeight: 300)

        let ns = Namespace().wrappedValue
        let elv3 = elv2                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isSelected)
                .compositingGroup()
                .drawingGroup()
                .matchedGeometryEffect(id: "shared", in: ns)
                .matchedGeometryEffect(id: "follower", in: ns, isSource: false)
                .symbolEffect(.bounce, value: 1)
                .symbolEffect(.pulse, options: .repeating, isActive: true)
                .contentTransition(.numericText())
                .rotationEffect(15)
                .rotation3DEffect(x: 30)
                .rotation3DEffect(y: 45)
                .scaleEffect(1.5)
                .scaleEffect(x: 2)
                .scaleEffect(y: 3)
                .offset(x: 10)
                .offset(y: 20)
                .pivotX(0.25)
                .pivotY(0.75)
                .flex(0)
                .tag("shared")
                .zIndex(3)
                // Every gesture SwiftOmniUI has, on one view - which is legal, and the
                // only way to check that each recognizer is asked for on its
                // own terms.
                .onTapGesture(count: 2) {}
                .onSwiped(direction: [.left, .up], threshold: 60) { _ in }
                .onPanUpdated(touchCount: 1) { _ in }
                .onPinchUpdated { _ in }
                .onPointerEntered {}
                .onPointerExited {}
                .onPointerMoved { _ in }
                .onPointerPressed { _ in }
                .onPointerReleased { _ in }
                .draggable(text: "Alpha", canDrag: true) {}
                .onDropCompleted {}
                .onDrop { _ in }
                .onDragOver {}
                .onDragLeave {}
                .pointerStyle(.link)
                .layoutPriority(1)
                .alignmentGuide(.leading) { _ in 10 }
                .alignmentGuide(.top) { _ in 5 }
                .blendMode(.multiply)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .progressViewStyle(.linear)
        let case36 = ControlCase("Elements", sources: SourceTree.sharedTier, elv3)

        // Tiers with no control of their own, each standing in for the marker
        // its file writes: the reader's container, a layer's decoration flag
        // and the edge an inset bar's stack answers.
        let case36b = ControlCase("GeometryReader", source: "GeometryReader.swift",
                GeometryReader { _ in Text("measured") }.node.built)
        let case36c = ControlCase("Layered", source: "Layered.swift",
                Text("base").overlay { Circle() }.node.built)
        let case36d = ControlCase("SafeAreaInset", source: "View+SafeArea.swift",
                Text("body").safeAreaInset(edge: VerticalEdge.bottom) { Text("bar") }.node.built)

        let case37 = ControlCase("MenuButton", source: "MenuBar.swift",
            Menu {
                MenuItem("One")
                Divider()
                Menu("Sub") {
                    MenuItem("Three")
                }
            } label: {
                Text("Pick")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(false))

        let case38 = ControlCase("CustomLayout", source: "CustomLayout.swift",
            CaseRow {
                Text("one").layoutValue(key: CaseGap.self, value: 4)
                Text("two")
            })

        let case39 = ControlCase("Masked", source: "ClipShape.swift",
            Text("one")
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .mask { RoundedRectangle(cornerRadius: 8).fill(.tomato) })

        return [
            case0, case0b, case1, case2, case3, case4, case5, case6, case7, case8, case9, case10, case11, case12, case13, case14, case15, case16, case17, case18, case19, case20, case20a, case20b, case20c, case20d, case20e, case21, case22, case23, case24, case25, case26, case27, case28, case29, case30, case31, case32, case32b, case33, case34, case35, case36, case36b, case36c, case36d, case37, case38, case39,
        ]
    }

    /// A renderer the test attaches - the modifier writes the marker and the
    /// node keeps the object; no draw pass runs under a test.
    private struct ProbeTextRenderer: TextRenderer {}

    /// A layout tag for the CustomLayout case.
    private enum CaseGap: LayoutValueKey {
        static let defaultValue = 0.0
    }

    /// The arrangement the CustomLayout case arranges by: each child in a
    /// row, at its own size.
    private struct CaseRow: Layout {
        func sizeThatFits(
            proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
        ) -> Size {
            subviews.reduce(Size(width: 0, height: 0)) { size, subview in
                let measured = subview.sizeThatFits(proposal)
                return Size(
                    width: size.width + measured.width,
                    height: max(size.height, measured.height))
            }
        }

        func placeSubviews(
            in bounds: Rect, proposal: ProposedViewSize,
            subviews: Subviews, cache: inout Void
        ) {
            var x = bounds.x
            for subview in subviews {
                subview.place(at: Point(x: x, y: bounds.y), proposal: proposal)
                x += subview.sizeThatFits(proposal).width
            }
        }
    }

    // MARK: - What a host is handed

    /// EVERY CONTROL CARRIES ONLY WHAT ITS CONTRACT DECLARES: every case,
    /// rendered from nothing, puts on each element of its patch properties,
    /// registrations, transitions and handlers its element's contract - its
    /// own members and its tiers' - declares, and nothing a host would have to
    /// guess at.
    func testEveryControlCarriesOnlyWhatItsContractDeclares() throws {
        var checked = 0

        for control in Self.cases {
            let patch = Differ().reconcile(nil, with: control.node).patch

            for element in patch.subtree {
                // A fragment is transparent: it mounts no element and declares
                // no contract - its children stand in the parent's list.
                if element.type == .fragment {
                    continue
                }

                guard let contract = LibraryContracts.elements.first(where: { $0.nodeType == element.type }) else {
                    XCTFail("\(control.name): \(element.type.name) has no contract")
                    continue
                }

                let carried = Set(element.props.keys.map(\.name))
                    .union(element.cleared.map(\.name))
                    .union(element.driven?.bindings.keys.map(\.name) ?? [])
                    .union(element.transitions.keys.map(\.name))
                    .union(element.eventNames)

                XCTAssertEqual(
                    carried.subtracting(Self.names(wornBy: contract)).sorted(), [],
                    "\(control.name): \(element.type.name) carries what its contract does not declare")
                checked += 1
            }
        }

        XCTAssertGreaterThan(checked, 50, "the cases rendered almost nothing")
    }

    /// Every member name a contract lets its element carry: its own, and its
    /// tiers' with theirs.
    private static func names(wornBy contract: any Contract.Type) -> Set<String> {
        contract.tiers.reduce(into: Set(contract.members.map(\.name))) { names, tier in
            names.formUnion(Self.names(wornBy: tier))
        }
    }

    // MARK: - The set, kept honest

    /// A modifier that no case uses is a modifier no patch here carries, which
    /// is a modifier a host can quietly not implement.
    func testEveryModifierIsExercised() throws {
        // Written where no case can stand: `lazyRowStack` inside `LazyStacks`'
        // `producer`, which runs when a host's window asks for rows, and
        // `padding` on a `Style`, which is no element - StyleTests covers it.
        let windowed: [String: Set<String>] = [
            "LazyStacks.swift": ["lazyRowStack"], "View.swift": ["padding"],
        ]
        var covered: [String: Set<String>] = [:]

        for control in Self.cases {
            for source in control.sources {
                covered[source, default: []].formUnion(Self.propNames(in: control.node))
            }
        }

        var read = 0

        for (source, keys) in covered.sorted(by: { $0.key < $1.key }) {
            let declared = try SourceTree.propertyKeys(in: source)
            let missing = declared.subtracting(keys).subtracting(windowed[source] ?? []).sorted()

            read += declared.count

            XCTAssertTrue(missing.isEmpty, """
                \(source) declares \(missing.joined(separator: ", ")), which no \
                case in this file uses.

                A property no case carries is one a host can leave out \
                without anything failing. Add the modifier to the case for that \
                control.
                """)
        }

        XCTAssertGreaterThan(read, 110, "the scan read almost nothing")
    }

    /// The same promise for a file that has no case OF ITS OWN - a tier.
    ///
    /// The guard above groups by SOURCE FILE and then walks the files that have
    /// cases, so a file with none was never asked about at all. A tier file
    /// has no case of its own, so its modifiers are nobody's to prove unless
    /// this asks.
    ///
    /// A tier belongs to several controls, so the question it can answer is
    /// weaker and is the one the other guard's own message asks: is this
    /// property carried by SOME case, or built by some test? Proof is taken
    /// from wherever it comes, exactly as `testEveryEventModifierIsExercised`
    /// takes it. A `ToolbarItem` is the case for the second: it is not a view,
    /// so it has no case here, and PageTests is where it is built with
    /// everything it can do.
    func testEveryModifierOfATierIsExercisedSomewhere() throws {
        let withCases = Set(Self.cases.flatMap(\.sources))
        let rendered = Self.cases.reduce(into: Set<String>()) { $0.formUnion(Self.carriedNames(in: $1.node)) }
        let tests = try SourceTree.testSources().map(\.text).joined(separator: "\n")
        var missing: [String] = []
        var read = 0

        for source in try SourceTree.controlSources() where !withCases.contains(source) {
            let declared = try SourceTree.propertyKeys(in: source)

            read += declared.count

            // A test writes `.strokeWidth(`, and the anchors are what keep
            // `text` from being answered by `textColor`.
            for key in declared.sorted() where !rendered.contains(key) && !tests.contains(".\(key)(") {
                missing.append("\(source) declares \(key)")
            }
        }

        XCTAssertGreaterThan(read, 22, "the scan read almost nothing")
        XCTAssertEqual(missing, [], """
            These are declared by a file with no case of its own, and no \
            case carries them:

            \(missing.joined(separator: "\n"))

            A tier is shared, so it has no case of its own - but a property no \
            case carries is still one the renderer can leave out without \
            anything failing. Add the modifier to the case of a control that \
            conforms to the tier.
            """)
    }

    /// EVERY PROPERTY CAN BE HANDED A BINDING: for every value modifier -
    /// `fontSize(_ value: Double)`, `isVisible(_ value: Bool)`,
    /// `horizontalAlignment(_ value: Alignment)` - there is a twin taking
    /// `Binding<T>`, so a property whose value is decided somewhere else is
    /// never a reason to build the view again. Each twin stands beside its
    /// value form, and this is what keeps the two together: a value modifier
    /// added without its twin is named here.
    ///
    /// WHAT IS ALLOWED OUT is named one by one, and each for a reason the host
    /// gives: a value it cannot be handed whole (a brush, a picture, a date, a
    /// shape, a transform, a law, a run of numbers), a NAME rather than a
    /// value (a style key, a font family, a radio group), a rectangle - four
    /// lanes where a plain value is one - and the tiers no view wears: a page,
    /// a bar, a menu item, a title bar, a map's own flags.
    func testEveryValueModifierHasABindingTwin() throws {
        let allowed: Set<String> = [
            // Named rather than valued.
            "style", "fontFamily", "groupName", "source", "userAgent", "data", "content", "format",
            // A value the host cannot be handed whole.
            "background", "fill", "stroke", "icon", "icon",
            "icon", "maximumDate",
            "minimumDate", "strokeDashPattern", "points", "options", "columns",
            "rows", "shape", "renderTransform", "transformEffect", "animation", "id",
            "assign", "area",
            // Spellings over a flag set, whose driven half is the set itself.
            "underline", "strikethrough",
            // A compound over several members - no one member is its twin.
            "font",
            // Composed over the wrapping they write: a task, a clip, a fit,
            // a truncation spelling or a colour's own.
            "clipShape", "fixedSize", "task", "clipped", "truncationMode", "contentShape",
            "hitShape",
            // Style objects over the kind member they write - the driven form
            // takes the kind, as `buttonStyle(Binding<ButtonStyleKind>)`.
            "buttonStyle", "textFieldStyle", "pickerStyle", "listStyle",
            // An environment object, not a host property.
            "toggleStyle", "labelStyle",
            // Tiers no view wears.
            "barBackgroundColor", "barForegroundColor", "isScrollEnabled", "isZoomEnabled",
            "isTrafficEnabled", "showsUserLocation", "isDestructive", "title", "subtitle",
            "mapType", "ignoresSafeArea",
            // A structure the host reads whole at insert and remove, not a
            // value a state animates.
            "transition", "contentTransition",
            // A space's name - declared like `style` or `id`, not a value.
            "coordinateSpace",
            // A gesture the view answers, whose state is the gesture's own.
            "gesture",
            // A compound drawn as one, and a size the control's own keeps.
            "shadow", "controlSize",
            // Spellings that write through to a scroll view inside, whose
            // driven halves are the members' own.
            "scrollDisabled", "scrollBounceBehavior", "scrollClipDisabled",
            "scrollContentBackground", "scrollTargetLayout", "scrollTargetBehavior",
            "defaultScrollAnchor",
            // Container spellings that write through to the texts inside,
            // whose driven halves are the members' own twins.
            "fontDesign", "fontWeight", "foregroundColor", "kerning",
            "lineLimit", "lineSpacing", "multilineTextAlignment", "tracking",
            // Page chrome, lifted to the page and window records - no driven
            // half crosses that way.
            "navigationBarBackButtonHidden", "navigationDocument", "navigationSubtitle",
            "navigationTitle", "navigationSplitViewColumnWidth", "windowBackground",
            "toolbarVisibility", "toolbarBackground",
            // A spelling over another member or a flag set - the member's own
            // twin is the driven form.
            "gridColumnAlignment", "accessibilityAddTraits", "accessibilityRemoveTraits",
            "accessibilityElement",
            // Style objects over the kind member they write - the driven form
            // takes the kind, as `buttonStyle(Binding<ButtonStyleKind>)`.
            "menuStyle", "progressViewStyle",
            // Enum spellings and markers a host reads at apply, not animated
            // from a state.
            "pointerStyle", "menuIndicator", "renderingMode", "blendMode",
            // A layout quantity and a text scale the host reads at measure,
            // not driven through the value channel.
            "layoutPriority", "minimumScaleFactor",
            // A closed protocol the driven form cannot name.
            "textSelection",
            // A style the host cannot be handed whole; the colour twin is
            // `foregroundStyle(Binding<Color>)`.
            "foregroundStyle",
            // A lookup key beside its fallback, not a value to animate - the
            // driven half is the string member's own twin.
            "help", "placeholder",
            // Structural marks a host reads at apply, not values animated
            // from a state: a cell's span count and a tab's composed label.
            "gridCellColumns", "tabItem",
        ]
        var values: Set<String> = []
        var twins: Set<String> = []

        for (path, text) in try SourceTree.allSources() where path.contains("Views") {
            for raw in text.split(whereSeparator: \.isNewline) {
                var line = raw.drop(while: { $0 == " " })[...]
                // `@_spi(Host) public func` on one line counts as a public
                // func, the shape spi members were declared in before inline.
                if line.hasPrefix("@_spi(Host) ") { line = line.dropFirst("@_spi(Host) ".count) }

                // ONE VALUE AND NOTHING ELSE: a handler, a second parameter or
                // a generic is a different shape of member, and none of them is
                // a property being given a value.
                guard line.hasPrefix("public func "),
                      let open = line.firstIndex(of: "("),
                      let returns = line.range(of: ") -> "),
                      case let inside = line[line.index(after: open)..<returns.lowerBound],
                      !inside.contains(","),
                      !inside.contains("@escaping"),
                      !inside.contains("("),
                      let colon = inside.firstIndex(of: ":")
                else { continue }

                let name = String(line[line.index(line.startIndex, offsetBy: 12)..<open])
                // A default is the caller's convenience, not the type:
                // `disabled(_ disabled: Bool = true)` is a Bool either way.
                let type = inside[inside.index(after: colon)...]
                    .drop(while: { $0 == " " })
                    .components(separatedBy: " =").first.map { String($0) } ?? ""

                guard !name.contains("<") else { continue }

                if type.hasPrefix("Binding<"), type.hasSuffix(">") {
                    let bare = String(type.dropFirst("Binding<".count).dropLast())

                    twins.insert(name + ":" + bare)
                } else if !type.contains("<"), line[returns.upperBound...].hasPrefix("Modified") {
                    values.insert(name + ":" + type)
                }
            }
        }

        let missing = values
            .filter { !twins.contains($0) && !allowed.contains(String($0.split(separator: ":")[0])) }
            .sorted()

        XCTAssertGreaterThan(values.count, 120, "the scan read almost nothing")
        XCTAssertEqual(missing, [], """
            These value modifiers have no binding twin - write one beside \
            its value form, with the other twins of its type:

            \(missing.joined(separator: "\n"))
            """)
    }

    /// THE SIBLING OF THE MODIFIER GUARD, for the modifiers it cannot see.
    ///
    /// `testEveryModifierIsExercised` scans for a property being WRITTEN, so a
    /// modifier whose whole body is an `addHandler` is invisible to it: no
    /// property key, nothing to miss.
    ///
    /// Every event a `Views/` file subscribes must therefore be named by some
    /// test or carried by a case - an event is fired by a test rather than
    /// described in a message - and it is the promise that would have caught
    /// these two.
    func testEveryEventModifierIsExercised() throws {
        var subscribed: Set<String> = []

        for file in try SourceTree.controlSources() {
            subscribed.formUnion(try SourceTree.handlerKeys(in: file))
        }

        // Anywhere in the active Swift suites: an event is proved by a test
        // firing it or by a case carrying it.
        let named = try (SourceTree.testSources().map(\.text)
            + Self.cases.flatMap { Differ().reconcile(nil, with: $0.node).patch.subtree.flatMap(\.eventNames) })
            .joined(separator: "\n")

        let missing = subscribed
            .filter { !named.contains($0) }
            .sorted()

        XCTAssertGreaterThan(subscribed.count, 29, "the scan read almost nothing")
        XCTAssertEqual(missing, [], """
            These events a control subscribes are named by no test:

            \(missing.joined(separator: ", "))

            An event modifier writes no property, so the modifier guard cannot \
            see it. Fire it in a test - ChangesTests is where the reported \
            properties live - or the renderer's half of it is code nobody runs.
            """)
    }

    /// A control with no case at all, which is the same hole one modifier wide:
    /// a type a `Views/` file describes and no case ever builds.
    func testEveryControlHasACase() throws {
        let covered = Set(Self.cases.map { $0.name })
        var read = 0

        for source in try SourceTree.controlSources() {
            for type in try SourceTree.nodeTypes(in: source).sorted()
            where !SourceTree.notViews.contains(type) {
                read += 1
                XCTAssertTrue(covered.contains(type), """
                    \(source) describes \(type), which has no case in \
                    ControlTests.

                    Every control is built here with everything it can do, and \
                    its patch held to its contract. A control without one is a \
                    control nothing checks a host against.
                    """)
            }
        }

        XCTAssertGreaterThan(read, 30, "the scan read almost nothing")
    }

    /// The shared tier, deliberately covered in one place rather than in every
    /// control's case - the one chain, plus the few tier cases whose spelling
    /// no view's chain can write (a style's `padding` among them).
    func testTheSharedTierIsCoveredOnce() throws {
        let tiers = Self.cases.filter { $0.sources == SourceTree.sharedTier }
        XCTAssertFalse(tiers.isEmpty)
        let declared = try SourceTree.sharedTier.reduce(into: Set<String>()) {
            $0.formUnion(try SourceTree.propertyKeys(in: $1))
        }

        let carried = tiers.reduce(into: Set<String>()) {
            $0.formUnion(Self.propNames(in: $1.node))
        }

        // `padding` is a style's spelling - `View.swift`'s other branch, which
        // no view's chain can carry; StyleTests asserts the write itself.
        let viewless: Set<String> = ["padding"]

        // Worth stating rather than implying: this is a real number of
        // properties, and it is covered once.
        XCTAssertGreaterThan(declared.count, 30)
        XCTAssertEqual(carried.intersection(declared), declared.subtracting(viewless))
    }

    /// EVERY PROPERTY OF EVERY CONTRACT IS CARRIED, read from the contracts
    /// rather than from the sources. An element with cases carries each
    /// property of its own in them, and every property of every contract, a
    /// tier's and a structure element's included, is carried by some case,
    /// described or driven, or built by a test that reads it off the node.
    func testEveryPropertyOfEveryContractIsCarried() throws {
        let rendered = Self.cases.reduce(into: Set<String>()) { $0.formUnion(Self.carriedNames(in: $1.node)) }
        let tests = try SourceTree.testSources().map(\.text).joined(separator: "\n")
        var carried: [String: Set<String>] = [:]
        var missing: [String] = []

        for control in Self.cases {
            carried[control.node.type.name, default: []].formUnion(Self.carriedNames(in: control.node))
        }

        for contract in LibraryContracts.elements {
            guard let names = carried[contract.nodeType.name] else { continue }

            for member in contract.members where member is any PropertyMember && !names.contains(member.name) {
                missing.append("\(contract.name).\(member.name) is in no case of its element")
            }
        }

        for contract in LibraryContracts.all {
            for member in contract.members
            where member is any PropertyMember
                && !rendered.contains(member.name)
                && !Self.reads(member.name, in: tests) {
                missing.append("\(contract.name).\(member.name) is carried by no case and built by no test")
            }
        }

        XCTAssertEqual(missing, [], """
            A property no case carries is one a host can leave out without \
            anything failing. Give the element's case the modifier.
            """)
    }

    /// Whether a test builds a property or reads it off a patch: the modifier,
    /// the subscript by token or by name, or the key of the values it expects.
    private static func reads(_ name: String, in tests: String) -> Bool {
        tests.contains(".\(name)(") || tests.contains("props[.\(name)]")
            || tests.contains("props[\"\(name)\"]") || tests.contains("\"\(name)\": ")
    }

    /// Every property a tree describes and every one it drives, the root's
    /// and its children's. Materialized first, as `propNames` is.
    private static func carriedNames(in node: Node) -> Set<String> {
        var node = node
        node.materialize()

        let own = Set(node.props.keys.map(\.name)).union(node.driven.keys.map(\.name))

        return node.children.reduce(into: own) { names, child in
            names.formUnion(carriedNames(in: child))
        }
    }

    // MARK: - Two-way inputs

    /// A binding is what a two-way input IS: the state handed to the host,
    /// which writes the user's every report back onto it.
    func testATwoWayInputWritesBackWhatArrives() {
        let text = State("")
        let toggled = State(false)
        let volume = State(0.0)
        let size = State(0)
        let due = State(CalendarDate(year: 2026, month: 1, day: 1))
        let ticked = State(false)
        let chosen = State(false)
        let servings = State(0.0)
        let query = State("")
        let alarm = State(ClockTime(hour: 0, minute: 0))

        let renders = Renders()

        // Rendered for the numbers the states are issued, which is what the
        // host's writes below are addressed by.
        _ = renders.render(Node(type: "VStack", children: [
            TextField(text.projectedValue).node,
            TextEditor(text.projectedValue).id("editor").node,
            Switch(toggled.projectedValue).node,
            Slider(volume.projectedValue).node,
            Picker(["S", "M", "L"]).selectedIndex(size.projectedValue).node,
            DatePicker(due.projectedValue).node,
            CheckBox(ticked.projectedValue).id("checkBox").node,
            RadioButton("Medium").isOn(chosen.projectedValue).id("radio").node,
            Stepper(servings.projectedValue).id("stepper").node,
            SearchField(query.projectedValue).id("search").node,
            TimePicker(alarm.projectedValue).id("time").node,
        ]))

        // What the user TYPES is the HOST's own write onto the text state,
        // whole - a TextField and a TextEditor over one state are two fields the
        // same words land on.
        typed(text.number, "Ada")
        typed(text.number, "Notes")
        // A switch, a picker, a box and a radio button are the HOST's own
        // writes onto plain ties, not events.
        moved(toggled.number, to: 1)
        // A slider's and a stepper's report is the HOST's own write onto the
        // journey it walks, not an event.
        dragged(volume.number, to: 12.5)
        moved(size.number, to: 2)
        // A chosen day and a chosen time are three lanes each, landed the same way.
        moved(due.number, to: [2026, 8, 2], mask: 0b111)
        moved(ticked.number, to: 1)
        moved(chosen.number, to: 1)
        dragged(servings.number, to: 4)
        typed(query.number, "al")
        moved(alarm.number, to: [9, 30, 0], mask: 0b111)

        XCTAssertEqual(text.wrappedValue, "Notes")
        XCTAssertTrue(toggled.wrappedValue)
        XCTAssertEqual(volume.wrappedValue, 12.5)
        XCTAssertEqual(size.wrappedValue, 2)
        XCTAssertEqual(due.wrappedValue, CalendarDate(year: 2026, month: 8, day: 2))
        XCTAssertTrue(ticked.wrappedValue)
        XCTAssertTrue(chosen.wrappedValue)
        XCTAssertEqual(servings.wrappedValue, 4)
        XCTAssertEqual(query.wrappedValue, "al")
        XCTAssertEqual(alarm.wrappedValue, ClockTime(hour: 9, minute: 30))
    }

    /// A radio button hears its own CLEARING as well: a change of mind is
    /// reported from both buttons, and the host lands the false on the state
    /// the button borrows exactly as it lands the true.
    func testARadioButtonThatLosesTheGroupWritesBackFalse() {
        let chosen = State(true)

        let renders = Renders()
        renders.render(
            RadioButton("Medium")
                .isOn(chosen.projectedValue)
                .groupName("size")
                .node)

        moved(chosen.number, to: 0)

        XCTAssertFalse(chosen.wrappedValue)
    }

    /// A day READS AND WRITES its text form - year, month and day, hyphen-separated,
    /// the year at least four digits and a minus before one before the first -
    /// and what it writes it reads back.
    func testADayIsReadAndWrittenAsYearMonthDay() {
        XCTAssertEqual(CalendarDate(year: 2026, month: 8, day: 2).text, "2026-08-02")
        XCTAssertEqual(CalendarDate("2026-8-2"), CalendarDate(year: 2026, month: 8, day: 2), "leading zeros or not")
        XCTAssertEqual(CalendarDate(year: 987, month: 1, day: 5).text, "0987-01-05")
        XCTAssertEqual(CalendarDate(year: -5, month: 3, day: 1).text, "-0005-03-01", "a minus before the digits")
        XCTAssertEqual(CalendarDate("-2026-08-02")?.year, -2026)

        for day in [
            CalendarDate(year: -5, month: 3, day: 1), CalendarDate(year: 0, month: 12, day: 31),
            CalendarDate(year: 2026, month: 8, day: 2), CalendarDate(year: 12345, month: 6, day: 7),
        ] {
            XCTAssertEqual(CalendarDate(day.text), day, "\(day.text) reads back as the day it was written from")
        }
    }

    /// Text of another shape is no day - an empty part, a sign where none belongs, a letter - so a value that did
    /// not survive the trip shows where it is read.
    func testTextOfAnotherShapeIsNoDay() {
        for text in [
            "2026--08-02", "2026-08-02-", "+2026-08-02", "2026-+8-02", "--2026-08-02", "2026-08", "2026/08/02",
            "2026-08-0x", "", "-", " 2026-08-02",
        ] {
            XCTAssertNil(CalendarDate(text), text)
        }
    }

    /// A time of day READS AND WRITES its text form, which is a convenience for
    /// an author and not the form it travels in: in the patch it is its numbers,
    /// for the reason a date is - a formatter would mean ICU. The patch's rule is
    /// `testATwoWayInputWritesBackWhatArrives`, which fires `timeChanged` with
    /// three numbers, and the TimePicker case.
    func testATimeOfDayReadsAndWritesItsTextForm() {
        XCTAssertEqual(ClockTime(hour: 9, minute: 5).text, "09:05:00")
        XCTAssertEqual(ClockTime(hour: 21, minute: 5, second: 30).text, "21:05:30")

        // Read back in the full form, and in the shorter one a hand would
        // write.
        XCTAssertEqual(ClockTime("21:05:30"), ClockTime(hour: 21, minute: 5, second: 30))
        XCTAssertEqual(ClockTime("09:30"), ClockTime(hour: 9, minute: 30))

        // Nil rather than midnight, so a value that did not survive the trip is
        // visible.
        XCTAssertNil(ClockTime("half past nine"))
        XCTAssertNil(ClockTime("9"))

        XCTAssertLessThan(ClockTime(hour: 9, minute: 30), ClockTime(hour: 9, minute: 31))

        // Exactly three digits of millisecond, for text an author hands in.
        // now() answers as four numbers, not as this, and the text form drops
        // the milliseconds again on the way out.
        XCTAssertEqual(
            ClockTime("21:05:30.125"),
            ClockTime(hour: 21, minute: 5, second: 30, millisecond: 125))
        XCTAssertEqual(ClockTime(hour: 9, minute: 5, second: 1, millisecond: 500).text, "09:05:01")
        XCTAssertNil(ClockTime("21:05:30.12"), "two digits is a truncated value, not 120ms")
        XCTAssertNil(ClockTime("21:05:30.abc"))

        XCTAssertLessThan(
            ClockTime(hour: 9, minute: 30, second: 1, millisecond: 100),
            ClockTime(hour: 9, minute: 30, second: 1, millisecond: 200))
    }

    /// The rule that makes the two forms mix: a typed handler written after a
    /// binding runs BESIDE the binding's write, not instead of it.
    ///
    /// A handler that REPLACED it would stop the field reporting anything
    /// without a word - which is why the typed modifiers go through
    /// `addHandler`, and why nothing public replaces a handler at all.
    func testATypedHandlerRunsBesideTheBindingRatherThanReplacingIt() {
        let text = State("")
        var seen: [String] = []

        let renders = Renders()
        let patch = renders.render(
            TextField(text.projectedValue)
                .onTextChanged { seen.append($0) }
                .node)

        // The host lands the typed words on the state first and raises the
        // event after, which is the order a handler relies on.
        typed(text.number, "Ada")
        renders.fire(handler(patch, "textChanged"), with: [.string("Ada")])

        XCTAssertEqual(text.wrappedValue, "Ada")
        XCTAssertEqual(seen, ["Ada"])
        XCTAssertNotNil(patch.driven?[.text], "the field is driven by the state")
    }

    /// The same rule in the other order: the binding written AFTER the handler
    /// must not replace it. A binding that stored its write-back directly
    /// would kill the handler in
    /// `.onSelectedIndexChanged { } .selectedIndex($size)` without a word.
    func testABindingWrittenAfterAHandlerRunsBesideIt() {
        let size = State(0)
        var seen: [Int] = []
        var stateAsTheHandlerRan: [Int] = []

        let renders = Renders()
        let patch = renders.render(
            Picker(["S", "M", "L"])
                .onSelectedIndexChanged {
                    seen.append($0)
                    stateAsTheHandlerRan.append(size.wrappedValue)
                }
                .selectedIndex(size.projectedValue)
                .node)

        // The choice is the HOST's write onto the plain tie, landed before the
        // event it raises beside it - so the handler reads the state already
        // written, wherever it was written in the chain.
        moved(size.number, to: 2)
        renders.fire(handler(patch, "selectedIndexChanged"), with: [.number(2)])

        XCTAssertEqual(size.wrappedValue, 2)
        XCTAssertEqual(seen, [2])
        XCTAssertEqual(stateAsTheHandlerRan, [2])
    }

    /// A second handler for the same event runs beside the first - on a Button
    /// too, where the replacing primitive would run only the last one
    /// written.
    func testASecondHandlerRunsBesideTheFirst() {
        var seen: [String] = []

        let renders = Renders()
        let patch = renders.render(
            Button("Save")
                .onClicked { seen.append("first") }
                .onClicked { seen.append("second") }
                .node)

        renders.fire(handler(patch, "clicked"))

        XCTAssertEqual(seen, ["first", "second"],
            "Both handlers run, in the order they were written.")
    }

    /// The same promise on the non-view items, which each carry their typed
    /// event modifier by hand: one that ASSIGNED the handler would let a
    /// second silently replace the first while "every typed event modifier
    /// composes" stood written on Button. A ToolbarItem and a Pin
    /// stand for the family - MenuItem is the same two lines.
    func testASecondHandlerOnAnItemRunsBesideTheFirst() {
        var seen: [String] = []

        let renders = Renders()
        let bar = renders.render(
            ToolbarItem("Save")
                .onClicked { seen.append("first") }
                .onClicked { seen.append("second") }
                .node)

        renders.fire(handler(bar, "clicked"))

        XCTAssertEqual(seen, ["first", "second"])

        seen = []
        let pin = renders.render(
            Pin("Office")
                .onPinClicked { seen.append("first") }
                .onPinClicked { seen.append("second") }
                .node)

        renders.fire(handler(pin, "pinClicked"))

        XCTAssertEqual(seen, ["first", "second"])
    }

    /// A payload of the wrong KIND leaves the handler AND the binding alone -
    /// the rule every gesture follows, now on the typed value events too.
    /// Nothing is parsed anywhere: the value arrives under its tag and the
    /// typed accessor answers nil for every other arm. -1 is a real index
    /// (nothing chosen), so it cannot stand in for "unreadable" either.
    func testAPayloadOfTheWrongKindLeavesTheHandlerAlone() {
        let size = State(1)
        var seen: [Int] = []

        let renders = Renders()
        let patch = renders.render(
            Picker(["S", "M", "L"])
                .selectedIndex(size.projectedValue)
                .onSelectedIndexChanged { seen.append($0) }
                .node)

        renders.fire(handler(patch, "selectedIndexChanged"), with: [.string("not-a-number")])

        XCTAssertEqual(size.wrappedValue, 1)
        XCTAssertEqual(seen, [])
    }
    /// A two-way control handed a binding the host CANNOT carry - a part of a
    /// state, or one made from closures - keeps the described road: the value
    /// is read at build, the report is written back through the binding, and
    /// nothing is registered for the host to tie.
    func testAPartOrClosureBindingKeepsTheDescribedRoad() {
        var on = false
        let closure = Binding<Bool>(get: { on }, set: { on = $0 })
        let room = State(wrappedValue: Rect(0, 0, 3, 4))

        struct Profile { var name = "" }
        let profile = State(wrappedValue: Profile())
        var typed = ""
        let text = Binding<String>(get: { typed }, set: { typed = $0 })
        var day = CalendarDate(year: 2026, month: 1, day: 1)
        let date = Binding<CalendarDate>(get: { day }, set: { day = $0 })
        var clock = ClockTime(hour: 0, minute: 0)
        let time = Binding<ClockTime>(get: { clock }, set: { clock = $0 })

        let renders = Renders()
        let patch = renders.render(Node(type: "VStack", children: [
            Switch(closure).node,
            Picker(["S", "M", "L"]).selectedIndex(Binding(get: { Int(room.wrappedValue.width) }, set: { room.wrappedValue.width = Double($0) })).node,
            TextField(text).node,
            TextEditor(profile.projectedValue.name).id("editor").node,
            SearchField(text).id("search").node,
            DatePicker(date).id("date").node,
            TimePicker(time).id("time").node,
        ]))

        XCTAssertEqual(patch.children[0].props[.isOn], .bool(false), "described: the value is written at build")
        XCTAssertNil(patch.children[0].driven, "and nothing is tied")
        XCTAssertEqual(patch.children[1].props[.selectedIndex], .number(3))

        // The fields and the pickers take the same road over a part or a
        // closure: the value read at build, nothing tied, the report written
        // back through the binding.
        XCTAssertEqual(patch.children[2].props[.text], .string(""))
        XCTAssertNil(patch.children[2].driven)
        XCTAssertEqual(patch.child("editor")?.props[.text], .string(""))
        XCTAssertNil(patch.child("editor")?.driven)
        XCTAssertEqual(patch.child("date")?.props[.date], .numbers([2026, 1, 1]))
        XCTAssertNil(patch.child("date")?.driven)
        XCTAssertEqual(patch.child("time")?.props[.time], .numbers([0, 0, 0]))
        XCTAssertNil(patch.child("time")?.driven)

        renders.fire(handler(patch.children[0], "toggled"), with: [.bool(true)])
        renders.fire(handler(patch.children[1], "selectedIndexChanged"), with: [.number(1)])
        renders.fire(handler(patch.children[2], "textChanged"), with: [.string("Ada")])
        renders.fire(handler(patch.child("editor"), "textChanged"), with: [.string("Notes")])
        renders.fire(handler(patch.child("date"), "dateChanged"), with: [.numbers([2026, 8, 2])])
        renders.fire(handler(patch.child("time"), "timeChanged"), with: [.numbers([9, 30, 0])])

        XCTAssertTrue(on, "the report went back through the closure")
        XCTAssertEqual(room.wrappedValue.width, 1, "and through the part")
        XCTAssertEqual(typed, "Ada")
        XCTAssertEqual(profile.wrappedValue.name, "Notes")
        XCTAssertEqual(day, CalendarDate(year: 2026, month: 8, day: 2))
        XCTAssertEqual(clock, ClockTime(hour: 9, minute: 30))
    }

    /// A value the PLATFORM moves - the scroller's offset, which the platform
    /// keeps read-only - comes back into the state as the host's own write: the host
    /// writes the image by the number the state was issued, and the state reads
    /// what it wrote.
    func testAReportedPropertyWritesIntoItsBinding() {
        let scrolled = State(Point.zero)

        let renders = Renders()
        renders.render(
            ScrollView {
                Text("content")
            }
            .scrollOffset(scrolled.projectedValue)
            .node)

        slid(scrolled.number, to: Point(0, 120))

        XCTAssertEqual(scrolled.wrappedValue.y, 120)
    }

    /// A number crosses as its own bits, so no locale can garble it on the
    /// way and there is nothing here to parse. What is left to get wrong is the
    /// SHAPE: a payload that is not a number leaves the handler alone rather
    /// than landing on a zero nobody dragged to - which is why the value fired
    /// is text that LOOKS like a number under some separator.
    func testAValueOfTheWrongKindLeavesTheBindingAlone() {
        let volume = State(0.0)
        var seen: [Double] = []

        let renders = Renders()
        let patch = renders.render(
            Slider(volume.projectedValue)
                .onValueChanged { seen.append($0) }
                .node)

        renders.fire(handler(patch, "valueChanged"), with: [.string("12,5")])

        XCTAssertEqual(seen, [])
        XCTAssertEqual(volume.wrappedValue, 0)
    }

    /// A navigation that arrives with no reason still reports, because the
    /// url and the outcome beside it are perfectly good.
    ///
    /// Measured on Windows: a web view's FIRST navigation - the source it was
    /// handed before its browser existed - arrives with a reason no
    /// `WebNavigationEvent` member names, and the host has nothing to
    /// translate it onto but `.unknown`. Refusing that report would leave a
    /// page loaded on screen while the interface still said nothing had, with
    /// only a second navigation ever reporting. An unknown member degrades; a
    /// wrong SHAPE still refuses, which is the test below.
    func testANavigationWithNoReasonStillReports() {
        var seen: [WebNavigated] = []

        let renders = Renders()
        let patch = renders.render(
            WebView("https://example.com")
                .onNavigated { seen.append($0) }
                .node)

        renders.fire(handler(patch, "navigated"), with: [
            .enumeration(WebNavigationResult.success.rawValue),
            .enumeration(WebNavigationEvent.unknown.rawValue),
            .string("https://example.com/"),
        ])

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.result, .success)
        XCTAssertEqual(seen.first?.event, .unknown)
        XCTAssertEqual(seen.first?.url, "https://example.com/")

        // `.unknown` is what this platform actually reports, and it has a case
        // of its own; the RULE is wider than that one member, so a number
        // neither side declares reads as unknown too rather than taking the
        // report down with it.
        renders.fire(handler(patch, "navigated"),
            with: [.enumeration(9), .enumeration(9), .string("https://example.com/")])

        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(seen.last?.result, .unknown)
        XCTAssertEqual(seen.last?.event, .unknown)
    }

    /// The other half of the same rule: a value of the wrong KIND is a
    /// garbled payload rather than a reason the platform left unnamed, so nothing runs -
    /// a report invented from rubbish is worse than a report not made.
    func testANavigationReportOfTheWrongShapeLeavesTheHandlerAlone() {
        var seen: [WebNavigation] = []

        let renders = Renders()
        let patch = renders.render(
            WebView("https://example.com")
                .onNavigating { seen.append($0) }
                .node)

        // The reason as a plain NUMBER where a member is wanted - what a host
        // that stopped translating would send.
        renders.fire(handler(patch, "navigating"), with: [
            .number(Double(WebNavigationEvent.newPage.rawValue)),
            .string("https://example.com/"),
        ])

        XCTAssertTrue(seen.isEmpty)
    }

    // MARK: - Support

    private func handler(_ patch: HostPatch?, _ event: Event) -> Int {
        patch?.events?[event] ?? -1
    }

    /// Every property name in a tree, the case's own and its children's.
    /// The node is materialized first: a container keeps its content in a
    /// closure until it is described, and this walk reads raw trees.
    private static func propNames(in node: Node) -> Set<String> {
        var node = node
        node.materialize()

        return node.children.reduce(into: Set(node.props.keys.map(\.name))) { names, child in
            names.formUnion(propNames(in: child))
        }
    }
}

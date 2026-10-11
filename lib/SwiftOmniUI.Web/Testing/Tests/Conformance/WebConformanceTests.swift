// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIConformance
import XCTest

/// The conformance suite on the Web, in a browser (`test-web.sh --browser`): a family a contract, each one test,
/// its verdicts the Web's column of the control dictionary.
@MainActor
final class WebConformanceTests: XCTestCase {
    override func setUp() {
        WebTestLoop.started
    }

    func testActivityIndicator() { conform(ActivityIndicatorTests.self) }
    func testButton() { conform(ButtonTests.self) }
    func testCanvas() { conform(CanvasTests.self) }
    func testCheckBox() { conform(CheckBoxTests.self) }
    func testColorPicker() { conform(ColorPickerTests.self) }
    func testDatePicker() { conform(DatePickerTests.self) }
    func testCustomLayout() { conform(CustomLayoutTests.self) }
    func testMasked() { conform(MaskedTests.self) }
    func testEllipse() { conform(EllipseTests.self) }
    func testGrid() { conform(GridTests.self) }
    func testGridRow() { conform(GridRowTests.self) }
    func testHStack() { conform(HStackTests.self) }
    func testImage() { conform(ImageTests.self) }
    func testText() { conform(TextTests.self) }
    func testLine() { conform(LineTests.self) }
    func testMap() { conform(MapTests.self) }
    func testMenuButton() { conform(MenuButtonTests.self) }
    func testPath() { conform(PathTests.self) }
    func testPicker() { conform(PickerTests.self) }
    func testPolygon() { conform(PolygonTests.self) }
    func testPolyline() { conform(PolylineTests.self) }
    func testPositionIndicator() { conform(PositionIndicatorTests.self) }
    func testProgressBar() { conform(ProgressBarTests.self) }
    func testRadioButton() { conform(RadioButtonTests.self) }
    func testRectangle() { conform(RectangleTests.self) }
    func testScrollView() { conform(ScrollViewTests.self) }
    func testLazyHGrid() { conform(LazyHGridTests.self) }
    func testLazyHStack() { conform(LazyHStackTests.self) }
    func testLazyVGrid() { conform(LazyVGridTests.self) }
    func testLazyVStack() { conform(LazyVStackTests.self) }
    func testList() { conform(ListTests.self) }
    func testSearchField() { conform(SearchFieldTests.self) }
    func testSlider() { conform(SliderTests.self) }
    func testStepper() { conform(StepperTests.self) }
    func testSwitch() { conform(SwitchTests.self) }
    func testTextEditor() { conform(TextEditorTests.self) }
    func testTextField() { conform(TextFieldTests.self) }
    func testTimePicker() { conform(TimePickerTests.self) }
    func testTitleBar() { conform(TitleBarTests.self) }
    func testVStack() { conform(VStackTests.self) }
    func testWebView() { conform(WebViewTests.self) }
    func testZStack() { conform(ZStackTests.self) }
    func testApplication() { conform(ApplicationTests.self) }
    func testContent() { conform(ContentTests.self) }
    func testContextMenu() { conform(ContextMenuTests.self) }
    func testLeadingContent() { conform(LeadingContentTests.self) }
    func testMenu() { conform(MenuTests.self) }
    func testMenuBar() { conform(MenuBarTests.self) }
    func testMenuItem() { conform(MenuItemTests.self) }
    func testMenuSeparator() { conform(MenuSeparatorTests.self) }
    func testModalStack() { conform(ModalStackTests.self) }
    func testNavigationStack() { conform(NavigationStackTests.self) }
    func testOverlay() { conform(OverlayTests.self) }
    func testPopover() { conform(PopoverTests.self) }
    func testPage() { conform(PageTests.self) }
    func testPin() { conform(PinTests.self) }
    func testScene() { conform(SceneTests.self) }
    func testSpan() { conform(SpanTests.self) }
    func testSpans() { conform(SpansTests.self) }
    func testNavigationSplitView() { conform(NavigationSplitViewTests.self) }
    func testTabView() { conform(TabViewTests.self) }
    func testTitleView() { conform(TitleViewTests.self) }
    func testToolbarItem() { conform(ToolbarItemTests.self) }
    func testToolbarItems() { conform(ToolbarItemsTests.self) }
    func testToolbarSpacer() { conform(ToolbarSpacerTests.self) }
    func testTrailingContent() { conform(TrailingContentTests.self) }
    func testWindow() { conform(WindowTests.self) }
    func testPropertyContainer() { conform(PropertyContainerTests.self) }
    func testVisualElement1() { conform(VisualElementTests.self, part: Conformance.Part(1, of: 24)) }
    func testVisualElement2() { conform(VisualElementTests.self, part: Conformance.Part(2, of: 24)) }
    func testVisualElement3() { conform(VisualElementTests.self, part: Conformance.Part(3, of: 24)) }
    func testVisualElement4() { conform(VisualElementTests.self, part: Conformance.Part(4, of: 24)) }
    func testVisualElement5() { conform(VisualElementTests.self, part: Conformance.Part(5, of: 24)) }
    func testVisualElement6() { conform(VisualElementTests.self, part: Conformance.Part(6, of: 24)) }
    func testVisualElement7() { conform(VisualElementTests.self, part: Conformance.Part(7, of: 24)) }
    func testVisualElement8() { conform(VisualElementTests.self, part: Conformance.Part(8, of: 24)) }
    func testVisualElement9() { conform(VisualElementTests.self, part: Conformance.Part(9, of: 24)) }
    func testVisualElement10() { conform(VisualElementTests.self, part: Conformance.Part(10, of: 24)) }
    func testVisualElement11() { conform(VisualElementTests.self, part: Conformance.Part(11, of: 24)) }
    func testVisualElement12() { conform(VisualElementTests.self, part: Conformance.Part(12, of: 24)) }
    func testVisualElement13() { conform(VisualElementTests.self, part: Conformance.Part(13, of: 24)) }
    func testVisualElement14() { conform(VisualElementTests.self, part: Conformance.Part(14, of: 24)) }
    func testVisualElement15() { conform(VisualElementTests.self, part: Conformance.Part(15, of: 24)) }
    func testVisualElement16() { conform(VisualElementTests.self, part: Conformance.Part(16, of: 24)) }
    func testVisualElement17() { conform(VisualElementTests.self, part: Conformance.Part(17, of: 24)) }
    func testVisualElement18() { conform(VisualElementTests.self, part: Conformance.Part(18, of: 24)) }
    func testVisualElement19() { conform(VisualElementTests.self, part: Conformance.Part(19, of: 24)) }
    func testVisualElement20() { conform(VisualElementTests.self, part: Conformance.Part(20, of: 24)) }
    func testVisualElement21() { conform(VisualElementTests.self, part: Conformance.Part(21, of: 24)) }
    func testVisualElement22() { conform(VisualElementTests.self, part: Conformance.Part(22, of: 24)) }
    func testVisualElement23() { conform(VisualElementTests.self, part: Conformance.Part(23, of: 24)) }
    func testVisualElement24() { conform(VisualElementTests.self, part: Conformance.Part(24, of: 24)) }
    func testView1() { conform(ViewTests.self, part: Conformance.Part(1, of: 11)) }
    func testView2() { conform(ViewTests.self, part: Conformance.Part(2, of: 11)) }
    func testView3() { conform(ViewTests.self, part: Conformance.Part(3, of: 11)) }
    func testView4() { conform(ViewTests.self, part: Conformance.Part(4, of: 11)) }
    func testView5() { conform(ViewTests.self, part: Conformance.Part(5, of: 11)) }
    func testView6() { conform(ViewTests.self, part: Conformance.Part(6, of: 11)) }
    func testView7() { conform(ViewTests.self, part: Conformance.Part(7, of: 11)) }
    func testView8() { conform(ViewTests.self, part: Conformance.Part(8, of: 11)) }
    func testView9() { conform(ViewTests.self, part: Conformance.Part(9, of: 11)) }
    func testView10() { conform(ViewTests.self, part: Conformance.Part(10, of: 11)) }
    func testView11() { conform(ViewTests.self, part: Conformance.Part(11, of: 11)) }
    func testLayout() { conform(LayoutTests.self) }
    func testStackBase() { conform(StackBaseTests.self) }
    func testInputView() { conform(InputViewTests.self) }
    func testShape1() { conform(ShapeTests.self, part: Conformance.Part(1, of: 3)) }
    func testShape2() { conform(ShapeTests.self, part: Conformance.Part(2, of: 3)) }
    func testShape3() { conform(ShapeTests.self, part: Conformance.Part(3, of: 3)) }
    func testTextElement() { conform(TextElementTests.self) }
    func testTextStyleElement() { conform(TextStyleElementTests.self) }
    func testFontElement() { conform(FontElementTests.self) }
    func testTextAlignmentElement() { conform(TextAlignmentElementTests.self) }
    func testLineHeightElement() { conform(LineHeightElementTests.self) }
    func testDecorableTextElement() { conform(DecorableTextElementTests.self) }
    func testPaddingElement() { conform(PaddingElementTests.self) }
    func testBorderElement() { conform(BorderElementTests.self) }
    func testImageElement() { conform(ImageElementTests.self) }
    func testTintElement() { conform(TintElementTests.self) }
    func testBarElement() { conform(BarElementTests.self) }
    func testMenuItemElement() { conform(MenuItemElementTests.self) }
    func testPageElement() { conform(PageElementTests.self) }
    func testControlSizeElement() { conform(ControlSizeElementTests.self) }
    func testScrollContentElement() { conform(ScrollContentElementTests.self) }
    func testPipelineMarks() { conform(PipelineMarksTests.self) }

    /// Runs `family` - or `part` of it - on the Web, and holds its verdicts to the family's file of the Web's marks.
    /// A long family runs in parts, each a test of its own, so a part can be run alone and the parts side by side.
    private func conform(_ family: any ConformanceFamily.Type, part: Conformance.Part = .whole) {
        WebExports.conform(family, part: part)
    }
}

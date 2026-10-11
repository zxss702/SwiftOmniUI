// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@_spi(Host) import SwiftOmniUIConformance
import Foundation
import XCTest

/// The conformance suite on GTK: a family a contract, each one test, its verdicts GTK's column of the
/// control dictionary.
final class GTKConformanceTests: XCTestCase {
    /// The host with its backends, as an application registering them runs it.
    override func setUp() {
        onUIThread { GTKBackends.registered }
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
    func testPopover() { conform(PopoverTests.self) }
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
    func testVisualElement() { conform(VisualElementTests.self) }
    func testView() { conform(ViewTests.self) }
    func testLayout() { conform(LayoutTests.self) }
    func testStackBase() { conform(StackBaseTests.self) }
    func testInputView() { conform(InputViewTests.self) }
    func testShape() { conform(ShapeTests.self) }
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

    /// Runs `family` on GTK, and holds its verdicts to the family's file of GTK's marks.
    private func conform(_ family: any ConformanceFamily.Type) {
        let name = onUIThread { family.name }
        guard !GTKExports.skips(name, at: "marks/gtk/\(name).txt") else { return }
        let verdicts = onUIThread {
            Conformance.run(
                family, on: GTKDriver(), report: { XCTFail($0.message, file: $0.file, line: $0.line) })
        }
        XCTAssertNoThrow(try GTKExports.hold(
            HostVerdict.text(verdicts, revision: GTKExports.revision(of: name)),
            at: "marks/gtk/\(name).txt"))
    }
}

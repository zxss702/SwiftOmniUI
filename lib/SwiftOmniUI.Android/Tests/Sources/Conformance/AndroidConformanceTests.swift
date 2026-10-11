// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Android
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIAndroid
@_spi(Host) import SwiftOmniUIConformance
import XCTest

/// The conformance suite on Android Views: a family a contract, each one test, its verdicts Android's column of the
/// control dictionary - written into the test APK's files, where `test-android.sh` holds `exports/` to them.
final class AndroidConformanceTests: XCTestCase {
    static var allTests: [(String, (AndroidConformanceTests) -> () throws -> Void)] {
        [
            ("testActivityIndicator", testActivityIndicator),
            ("testButton", testButton),
            ("testCanvas", testCanvas),
            ("testCheckBox", testCheckBox),
            ("testColorPicker", testColorPicker),
            ("testDatePicker", testDatePicker),
            ("testCustomLayout", testCustomLayout),
            ("testMasked", testMasked),
            ("testEllipse", testEllipse),
            ("testGrid", testGrid),
            ("testGridRow", testGridRow),
            ("testHStack", testHStack),
            ("testImage", testImage),
            ("testText", testText),
            ("testLine", testLine),
            ("testMap", testMap),
            ("testMenuButton", testMenuButton),
            ("testPath", testPath),
            ("testPicker", testPicker),
            ("testPopover", testPopover),
            ("testPolygon", testPolygon),
            ("testPolyline", testPolyline),
            ("testPositionIndicator", testPositionIndicator),
            ("testProgressBar", testProgressBar),
            ("testRadioButton", testRadioButton),
            ("testRectangle", testRectangle),
            ("testScrollView", testScrollView),
            ("testLazyHGrid", testLazyHGrid),
            ("testLazyHStack", testLazyHStack),
            ("testLazyVGrid", testLazyVGrid),
            ("testLazyVStack", testLazyVStack),
            ("testList", testList),
            ("testSearchField", testSearchField),
            ("testSlider", testSlider),
            ("testStepper", testStepper),
            ("testSwitch", testSwitch),
            ("testTextEditor", testTextEditor),
            ("testTextField", testTextField),
            ("testTimePicker", testTimePicker),
            ("testTitleBar", testTitleBar),
            ("testVStack", testVStack),
            ("testWebView", testWebView),
            ("testZStack", testZStack),
            ("testApplication", testApplication),
            ("testContent", testContent),
            ("testContextMenu", testContextMenu),
            ("testLeadingContent", testLeadingContent),
            ("testMenu", testMenu),
            ("testMenuBar", testMenuBar),
            ("testMenuItem", testMenuItem),
            ("testMenuSeparator", testMenuSeparator),
            ("testModalStack", testModalStack),
            ("testNavigationStack", testNavigationStack),
            ("testOverlay", testOverlay),
            ("testPage", testPage),
            ("testPin", testPin),
            ("testScene", testScene),
            ("testSpan", testSpan),
            ("testSpans", testSpans),
            ("testNavigationSplitView", testNavigationSplitView),
            ("testTabView", testTabView),
            ("testTitleView", testTitleView),
            ("testToolbarItem", testToolbarItem),
            ("testToolbarItems", testToolbarItems),
            ("testToolbarSpacer", testToolbarSpacer),
            ("testTrailingContent", testTrailingContent),
            ("testWindow", testWindow),
            ("testPropertyContainer", testPropertyContainer),
            ("testVisualElement", testVisualElement),
            ("testView", testView),
            ("testLayout", testLayout),
            ("testStackBase", testStackBase),
            ("testInputView", testInputView),
            ("testShape", testShape),
            ("testTextElement", testTextElement),
            ("testTextStyleElement", testTextStyleElement),
            ("testFontElement", testFontElement),
            ("testTextAlignmentElement", testTextAlignmentElement),
            ("testLineHeightElement", testLineHeightElement),
            ("testDecorableTextElement", testDecorableTextElement),
            ("testPaddingElement", testPaddingElement),
            ("testBorderElement", testBorderElement),
            ("testImageElement", testImageElement),
            ("testTintElement", testTintElement),
            ("testBarElement", testBarElement),
            ("testMenuItemElement", testMenuItemElement),
            ("testPageElement", testPageElement),
            ("testControlSizeElement", testControlSizeElement),
            ("testScrollContentElement", testScrollContentElement),
            ("testPipelineMarks", testPipelineMarks),
        ]
    }

    func testActivityIndicator() throws { try conform(ActivityIndicatorTests.self) }
    func testButton() throws { try conform(ButtonTests.self) }
    func testCanvas() throws { try conform(CanvasTests.self) }
    func testCheckBox() throws { try conform(CheckBoxTests.self) }
    func testColorPicker() throws { try conform(ColorPickerTests.self) }
    func testDatePicker() throws { try conform(DatePickerTests.self) }
    func testCustomLayout() throws { try conform(CustomLayoutTests.self) }
    func testMasked() throws { try conform(MaskedTests.self) }
    func testEllipse() throws { try conform(EllipseTests.self) }
    func testGrid() throws { try conform(GridTests.self) }
    func testGridRow() throws { try conform(GridRowTests.self) }
    func testHStack() throws { try conform(HStackTests.self) }
    func testImage() throws { try conform(ImageTests.self) }
    func testText() throws { try conform(TextTests.self) }
    func testLine() throws { try conform(LineTests.self) }
    func testMap() throws { try conform(MapTests.self) }
    func testMenuButton() throws { try conform(MenuButtonTests.self) }
    func testPath() throws { try conform(PathTests.self) }
    func testPicker() throws { try conform(PickerTests.self) }
    func testPopover() throws { try conform(PopoverTests.self) }
    func testPolygon() throws { try conform(PolygonTests.self) }
    func testPolyline() throws { try conform(PolylineTests.self) }
    func testPositionIndicator() throws { try conform(PositionIndicatorTests.self) }
    func testProgressBar() throws { try conform(ProgressBarTests.self) }
    func testRadioButton() throws { try conform(RadioButtonTests.self) }
    func testRectangle() throws { try conform(RectangleTests.self) }
    func testScrollView() throws { try conform(ScrollViewTests.self) }
    func testLazyHGrid() throws { try conform(LazyHGridTests.self) }
    func testLazyHStack() throws { try conform(LazyHStackTests.self) }
    func testLazyVGrid() throws { try conform(LazyVGridTests.self) }
    func testLazyVStack() throws { try conform(LazyVStackTests.self) }
    func testList() throws { try conform(ListTests.self) }
    func testSearchField() throws { try conform(SearchFieldTests.self) }
    func testSlider() throws { try conform(SliderTests.self) }
    func testStepper() throws { try conform(StepperTests.self) }
    func testSwitch() throws { try conform(SwitchTests.self) }
    func testTextEditor() throws { try conform(TextEditorTests.self) }
    func testTextField() throws { try conform(TextFieldTests.self) }
    func testTimePicker() throws { try conform(TimePickerTests.self) }
    func testTitleBar() throws { try conform(TitleBarTests.self) }
    func testVStack() throws { try conform(VStackTests.self) }
    func testWebView() throws { try conform(WebViewTests.self) }
    func testZStack() throws { try conform(ZStackTests.self) }
    func testApplication() throws { try conform(ApplicationTests.self) }
    func testContent() throws { try conform(ContentTests.self) }
    func testContextMenu() throws { try conform(ContextMenuTests.self) }
    func testLeadingContent() throws { try conform(LeadingContentTests.self) }
    func testMenu() throws { try conform(MenuTests.self) }
    func testMenuBar() throws { try conform(MenuBarTests.self) }
    func testMenuItem() throws { try conform(MenuItemTests.self) }
    func testMenuSeparator() throws { try conform(MenuSeparatorTests.self) }
    func testModalStack() throws { try conform(ModalStackTests.self) }
    func testNavigationStack() throws { try conform(NavigationStackTests.self) }
    func testOverlay() throws { try conform(OverlayTests.self) }
    func testPage() throws { try conform(PageTests.self) }
    func testPin() throws { try conform(PinTests.self) }
    func testScene() throws { try conform(SceneTests.self) }
    func testSpan() throws { try conform(SpanTests.self) }
    func testSpans() throws { try conform(SpansTests.self) }
    func testNavigationSplitView() throws { try conform(NavigationSplitViewTests.self) }
    func testTabView() throws { try conform(TabViewTests.self) }
    func testTitleView() throws { try conform(TitleViewTests.self) }
    func testToolbarItem() throws { try conform(ToolbarItemTests.self) }
    func testToolbarItems() throws { try conform(ToolbarItemsTests.self) }
    func testToolbarSpacer() throws { try conform(ToolbarSpacerTests.self) }
    func testTrailingContent() throws { try conform(TrailingContentTests.self) }
    func testWindow() throws { try conform(WindowTests.self) }
    func testPropertyContainer() throws { try conform(PropertyContainerTests.self) }
    func testVisualElement() throws { try conform(VisualElementTests.self) }
    func testView() throws { try conform(ViewTests.self) }
    func testLayout() throws { try conform(LayoutTests.self) }
    func testStackBase() throws { try conform(StackBaseTests.self) }
    func testInputView() throws { try conform(InputViewTests.self) }
    func testShape() throws { try conform(ShapeTests.self) }
    func testTextElement() throws { try conform(TextElementTests.self) }
    func testTextStyleElement() throws { try conform(TextStyleElementTests.self) }
    func testFontElement() throws { try conform(FontElementTests.self) }
    func testTextAlignmentElement() throws { try conform(TextAlignmentElementTests.self) }
    func testLineHeightElement() throws { try conform(LineHeightElementTests.self) }
    func testDecorableTextElement() throws { try conform(DecorableTextElementTests.self) }
    func testPaddingElement() throws { try conform(PaddingElementTests.self) }
    func testBorderElement() throws { try conform(BorderElementTests.self) }
    func testImageElement() throws { try conform(ImageElementTests.self) }
    func testTintElement() throws { try conform(TintElementTests.self) }
    func testBarElement() throws { try conform(BarElementTests.self) }
    func testMenuItemElement() throws { try conform(MenuItemElementTests.self) }
    func testPageElement() throws { try conform(PageElementTests.self) }
    func testControlSizeElement() throws { try conform(ControlSizeElementTests.self) }
    func testScrollContentElement() throws { try conform(ScrollContentElementTests.self) }
    func testPipelineMarks() throws { try conform(PipelineMarksTests.self) }

    /// The verdicts of a family run in parts, gathered until its last part writes them.
    nonisolated(unsafe) private static var gathered: [String: [HostVerdict]] = [:]

    /// Runs `family` - or `part` of it - on Android Views, and writes its verdicts to its file of Android's marks once
    /// its last part has run. The runner runs a long family in parts, each in a message of the UI thread of its own.
    /// Design: docs/design/platforms/android/conformance.md#a-message-an-item
    func conform(_ family: any ConformanceFamily.Type, part: Conformance.Part = .whole) throws {
        try onMainActor {
            let driver = AndroidDriver()
            let verdicts = Conformance.run(
                family, part: part, on: driver, report: { XCTFail($0.message, file: $0.file, line: $0.line) })
            driver.finish()
            let all = (Self.gathered.removeValue(forKey: family.name) ?? []) + verdicts
            guard part.number == part.count else { return Self.gathered[family.name] = all }
            try TestFiles.write(HostVerdict.text(HostVerdict.merged(all)), to: "marks/android/\(family.name).txt")
        }
    }
}

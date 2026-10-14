// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

@MainActor final class WinUIStartupTests: XCTestCase {
    func testHresultThrowerNeverReceivesAnErrorMessageAsItsSourceLocation() throws {
        // throw_hresult's second argument is slim_source_location. Messages
        // belong to hresult_error; check all relay call sites even on hosts
        // where the Windows projection is unavailable to the compiler.
        let invalid = try NSRegularExpression(
            pattern: #"winrt::throw_hresult\s*\([^;\n]*,\s*(?:L|u8|u|U)?\x22"#)
        for folder in ["lib/SwiftOmniUI.WinUI/Sources/CSwiftOmniUIWinUI", "lib/Backends/WebView.WinUI/Relay"] {
            let root = SourceTree.repository.appendingPathComponent(folder)
            let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "cpp" {
                let source = try String(contentsOf: file, encoding: .utf8)
                XCTAssertEqual(invalid.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)), 0,
                               "\(file.lastPathComponent): use hresult_error when supplying an error message")
            }
        }
    }

    func testServicingAndXamlConfigurationPrecedeBothStartupPaths() throws {
        let source = try String(contentsOf: SourceTree.repository.appendingPathComponent(
            "lib/SwiftOmniUI.WinUI/Sources/CSwiftOmniUIWinUI/Application.cpp"), encoding: .utf8)
        let runStart = try XCTUnwrap(source.range(of: "extern \"C\" int32_t swiftomniui_winui_run_single_instance("))
        let embedStart = try XCTUnwrap(source.range(of: "extern \"C\" int32_t swiftomniui_winui_embed("))
        let embedEnd = try XCTUnwrap(source.range(of: "extern \"C\" void swiftomniui_winui_pump("))
        let run = String(source[runStart.lowerBound..<embedStart.lowerBound])
        let embed = String(source[embedStart.lowerBound..<embedEnd.lowerBound])

        // This ordering is an API requirement: XAML and AppLifecycle lock
        // process-wide configuration. A successful property assignment on a
        // later control cannot prove the startup selected the optimizations.
        try assertOrder(["loadRuntime();", "configureRuntimeCompatibility();",
                         "lifecycle::AppInstance::GetCurrent()", "selectPrimary(",
                         "configureXaml();", "xaml::Application::Start("], in: run)
        try assertOrder(["loadRuntime();", "configureRuntimeCompatibility();", "configureXaml();",
                         "winrt::make<SwiftOmniUIApplication>", "InitializeForCurrentThread()"], in: embed)
    }

    func testProjectionCacheIncludesTheSdkReleaseAndNewRuntimeHeaders() throws {
        let source = try String(contentsOf: SourceTree.repository.appendingPathComponent(
            ".scripts/WinUI/tools.ps1"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "function Initialize-SwiftOmniUIProjection"))
        let end = try XCTUnwrap(source.range(of: "# What SwiftPM is told to build"))
        let projection = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(projection.contains("windowsappsdk $SwiftOmniUIWindowsAppSDKVersion"),
                      "aggregate servicing changes must invalidate projections even when components stay the same")
        try assertOrder(["SwiftOmniUIWinUIVersion.h", "Test-Path $stamp",
                         "winrt\\Microsoft.UI.Xaml.Settings.h", "winrt\\Microsoft.Windows.ApplicationModel.WindowsAppRuntime.h",
                         "generating the C++/WinRT projection",
                         "Set-Content -Path (Join-Path $projection $versionHeader)", "Set-Content -Path $stamp"], in: projection)
    }

    private func assertOrder(_ parts: [String], in source: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        var remaining = source.startIndex..<source.endIndex
        for part in parts {
            let found = try XCTUnwrap(source.range(of: part, range: remaining),
                                     "missing or out of order: \(part)", file: file, line: line)
            remaining = found.upperBound..<source.endIndex
        }
    }
}

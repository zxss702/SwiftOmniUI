// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// Temporary diagnostics for the startup layout cycle. Formatting and file I/O
/// never query native geometry, measure a control, or request another pass.
@MainActor
enum WinUILayoutDiagnostics {
    private struct Phase {
        let token: UInt64
        let kind: String
        let view: Int64
    }
    private static var sequence: UInt64 = 0
    private static var phases: [Phase] = []

    static func begin(_ kind: String, view: WinUIView, _ details: String) -> UInt64 {
        sequence &+= 1
        let token = sequence
        record("\(kind).begin", view: view, "call=\(token) \(details)")
        phases.append(Phase(token: token, kind: kind, view: view.number))
        return token
    }

    static func end(_ token: UInt64, view: WinUIView, _ details: String = "") {
        let kind = phases.last?.kind ?? "unknown"
        record("\(kind).end", view: view, "call=\(token) \(details)")
        if phases.last?.token == token { phases.removeLast() }
    }

    static func record(_ event: String, view: WinUIView? = nil, _ details: String = "",
                       file: StaticString = #fileID, line: UInt = #line) {
        let scope = phases.last.map { "\($0.kind)#\($0.token):\($0.view)" } ?? "idle"
        var identity = ""
        if let view {
            let element = view.sourceElement.map { String(describing: $0.type) } ?? "none"
            let parent = view.placingLayout?.number ?? 0
            let owner = view.nativeLayoutOwner?.number ?? 0
            let bar = (view.nativeSafeBarOwner as? WinUIView)?.number ?? 0
            identity = " view=\(view.number):\(type(of: view)) element=\(element)"
                + " parent=\(parent) nativeOwner=\(owner) barOwner=\(bar) root=\(view.rootSafeAreaContext != nil)"
                + " rev=\(view.measurementRevision) hierarchy=\(view.hierarchyRevision)"
        }
        let message = "\(event) scope=\(scope) depth=\(phases.count)"
            + " M=\(WinUIView.measuring) A=\(WinUIView.arranging) Q=\(WinUILayoutView.queryingSize)"
            + identity + " \(details) at=\(file):\(line)"
        message.withCString { swiftomniui_winui_layout_trace($0) }
    }

    static func proposal(width: Double?, height: Double?) -> String {
        "\(width.map { String($0) } ?? "nil")x\(height.map { String($0) } ?? "nil")"
    }

    static func size(_ value: LayoutSize) -> String { "\(value.width)x\(value.height)" }

    static func rect(_ value: Rect) -> String { "(\(value.x),\(value.y),\(value.width),\(value.height))" }
}

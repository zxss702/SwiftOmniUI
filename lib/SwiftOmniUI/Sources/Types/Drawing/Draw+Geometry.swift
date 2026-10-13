// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension Draw {
    static func drawGeometry(_ path: Path) -> DrawCommand {
        DrawCommand(.drawGeometry, [.numbers(path.geometry.numbers)])
    }
    static func fillGeometry(_ path: Path) -> DrawCommand {
        DrawCommand(.fillGeometry, [.numbers(path.geometry.numbers)])
    }
    static func completeStrokeStyle(_ style: StrokeStyle) -> DrawCommand {
        DrawCommand(.completeStrokeStyle, [
            .number(style.lineWidth), .enumeration(style.lineCap.rawValue), .enumeration(style.lineJoin.rawValue),
            .number(style.miterLimit), .numbers(style.dash), .number(style.dashPhase),
        ])
    }
}

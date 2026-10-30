// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// What a host moves frame by frame: the properties its views present and whose values travel, and nothing else.
final class TransitionSurfaceTests: XCTestCase {
    /// A colour box's colour, size and corners travel, as a view's opacity, a page's padding, a line's transform, a
    /// window's place and a title bar's colours do; a turn about a flat view's axis, a stepper's value, an indicator's
    /// opacity and a property no host knows arrive at once.
    func testTheSurfaceIsClosedAroundWhatAViewPresents() {
        for property: Prop in [.color, .width, .height, .cornerRadius] {
            XCTAssertTrue(TransitionSurface.presents(property, on: .colorPicker), "\(property)")
        }
        XCTAssertTrue(TransitionSurface.presents(.opacity, on: .text))
        XCTAssertTrue(TransitionSurface.presents(.contentPadding, on: .page))
        XCTAssertTrue(TransitionSurface.presents(.renderTransform, on: .line))
        XCTAssertTrue(TransitionSurface.presents(.x, on: .windowScene))
        XCTAssertTrue(TransitionSurface.presents(.background, on: .titleBar))
        XCTAssertTrue(TransitionSurface.presents(.barForegroundColor, on: .titleBar))

        XCTAssertFalse(TransitionSurface.presents(.rotationX, on: .text))
        XCTAssertFalse(TransitionSurface.presents(.value, on: .stepper))
        XCTAssertFalse(TransitionSurface.presents(.opacity, on: .positionIndicator))
        XCTAssertFalse(TransitionSurface.presents(Prop("custom"), on: .text))
    }

    /// What a host's toolkit paints only at rest arrives at once on that host, and the rest of the surface travels.
    func testWhatAToolkitPaintsAtRestArrivesAtOnce() {
        let atRest: [NodeType: Set<Prop>] = [.text: [.contentPadding, .background]]

        XCTAssertFalse(TransitionSurface.presents(.contentPadding, on: .text, atRest: atRest))
        XCTAssertFalse(TransitionSurface.presents(.background, on: .text, atRest: atRest))
        XCTAssertTrue(TransitionSurface.presents(.foregroundStyle, on: .text, atRest: atRest))
        XCTAssertTrue(TransitionSurface.presents(.contentPadding, on: .vStack, atRest: atRest))
    }
}

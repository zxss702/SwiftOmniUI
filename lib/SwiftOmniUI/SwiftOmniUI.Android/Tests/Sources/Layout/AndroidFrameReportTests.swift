// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIAndroid
import SwiftOmniUIConformance
import XCTest

/// Where a view stands, as its handler hears it. The test's root stands in no window, so each layout is told as the
/// window's layout listener tells it.
final class AndroidFrameReportTests: XCTestCase {
    static var allTests: [(String, (AndroidFrameReportTests) -> () throws -> Void)] {
        [
            ("testAViewSaysNothingBeforeItIsLaidOut", testAViewSaysNothingBeforeItIsLaidOut),
            ("testAViewThatJoinsSaysNothingBeforeItIsLaidOut", testAViewThatJoinsSaysNothingBeforeItIsLaidOut),
        ]
    }

    /// A view says nothing of where it stands before a layout places it: the first report its handler hears is
    /// where it is laid out.
    func testAViewSaysNothingBeforeItIsLaidOut() {
        onMainActor {
            let heard = Received<[Double]>()
            let host = AndroidRenderer.running {
                VStack {
                    ColorPicker(.steelBlue).frame(width: 120).frame(height: 60)
                        .onEvent(ViewContract.frameChanged) { heard.values.append($0) }
                }
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            host.runtime.frames.laidOut()
            host.frame()
            host.layOut()
            host.runtime.frames.laidOut()
            host.frame()
            host.settle { !heard.values.isEmpty }

            XCTAssertEqual(heard.values.first.map { Array($0.prefix(4)) }, [0, 0, 120, 60])
        }
    }

    /// A view that joins a shown page says nothing before its layout either: a display frame comes before the
    /// layout pass that places it.
    func testAViewThatJoinsSaysNothingBeforeItIsLaidOut() {
        onMainActor {
            let heard = Received<[Double]>()
            let shown = State(wrappedValue: false)
            let host = AndroidRenderer.running {
                VStack {
                    Text("above").frame(height: 20)
                    if shown.wrappedValue {
                        ColorPicker(.steelBlue).frame(width: 120).frame(height: 60)
                            .onEvent(ViewContract.frameChanged) { heard.values.append($0) }
                    }
                }
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            host.layOut()
            shown.wrappedValue = true
            host.runtime.pump.turn()
            host.runtime.frames.laidOut()
            host.frame()
            host.layOut()
            host.runtime.frames.laidOut()
            host.frame()
            host.settle { heard.values.count >= 2 || heard.values.first?[2] == 120 }

            XCTAssertEqual(heard.values.first.map { Array($0.prefix(4)) }, [0, 20, 120, 60])
        }
    }
}

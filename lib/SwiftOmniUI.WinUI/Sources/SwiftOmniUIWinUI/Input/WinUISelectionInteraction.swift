// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

extension WinUIView {
    func updateSelectionInteraction(active: Bool, point: [Double], send: @escaping (Event, [PropValue]) -> Void) {
        selectionInput = { code, point in
            switch code {
            case 0: send(.windowPointerPressed, [])
            case 1: send(.copyRequested, [])
            case 2: send(.selectAllRequested, [])
            default: send(.dragScrolled, [point.propValue])
            }
        }
        swiftomniui_winui_selection_interaction(handle, number, active, point.count == 2,
            point.first ?? 0, point.last ?? 0) { number, code, x, y in
                MainActor.assumeIsolated {
                    WinUIView.find(number)?.selectionInput?(code, Point(x, y))
                }
            }
    }
}

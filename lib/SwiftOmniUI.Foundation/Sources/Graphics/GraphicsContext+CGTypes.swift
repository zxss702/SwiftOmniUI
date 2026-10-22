// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftOmniUICore
public extension GraphicsContext {
    mutating func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(text, at: Point(point), anchor: anchor)
    }
    mutating func draw(_ text: Text, in rect: CGRect) {
        draw(text, in: Rect(rect))
    }
}

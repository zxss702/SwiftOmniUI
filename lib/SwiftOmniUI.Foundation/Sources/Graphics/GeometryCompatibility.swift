// SPDX-License-Identifier: Apache-2.0
import Foundation
@_spi(Host) import SwiftOmniUICore
public extension CGRect { init(_ rect: Rect) { self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height) } }
public extension CGPoint { init(_ point: Point) { self.init(x: point.x, y: point.y) } }
public extension Path {
    init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) {
        self.init(roundedRect: Rect(Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)), cornerRadius: Double(cornerRadius), style: style)
    }
}

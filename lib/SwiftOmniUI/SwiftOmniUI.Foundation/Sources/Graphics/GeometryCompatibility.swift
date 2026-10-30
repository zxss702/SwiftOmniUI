// SPDX-License-Identifier: Apache-2.0
import Foundation
@_spi(Host) import SwiftOmniUICore
public extension CGRect { init(_ rect: Rect) { self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height) } }
public extension CGPoint { init(_ point: Point) { self.init(x: point.x, y: point.y) } }

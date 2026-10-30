// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A brush as the relay takes it, read from a colour or a brush as it crosses.
/// Design: docs/design/types/brushes.md#as-a-host-is-handed-it
struct WinUIBrush: Equatable {
    /// 0 none, 1 solid, 2 linear, 3 radial.
    var kind: Int32 = 0

    /// A line's two points, or a centre and a radius, in fractions of the painted box.
    var geometry: [Double] = [0, 0, 0, 0]

    /// Whether how it paints follows the size of what it paints: a radial gradient's circle does.
    var followsSize: Bool { kind == 3 }
    var colors: [UInt32] = []
    var offsets: [Double] = []

    /// Transparent decorations need no native drawing object. Gradients still
    /// paint if any stop has coverage, including partially transparent ones.
    var drawsInk: Bool { kind != 0 && colors.contains { $0 >> 24 != 0 } }

    /// Nothing painted.
    static let none = WinUIBrush()

    init() {}

    /// The brush the tree's `value` describes, read by the host layer's rule (`HostBrush`), in ARGB.
    init(_ value: HostValue?) {
        switch HostBrush(value) {
        case .none: self.init()
        case .solid(let color): self.init(kind: 1, geometry: [0, 0, 0, 0], [(0, color.argb ?? 0)])
        case .linear(let from, let to, let stops):
            self.init(kind: 2, geometry: [from.x, from.y, to.x, to.y], stops.compactMap(Self.stop))
        case .radial(let center, let radius, let stops):
            self.init(kind: 3, geometry: [center.x, center.y, radius, 0], stops.compactMap(Self.stop))
        case .material(let kind):
            self.init(kind: 1, geometry: [0, 0, 0, 0], [(0, Self.materialArgb(kind))])
        }
    }

    /// What a material paints as where no frosted backing is drawn: a grey as
    /// translucent as `Material.Kind` is thin, in ARGB.
    private static func materialArgb(_ kind: Int32) -> UInt32 {
        let alpha: UInt32 = switch kind {
        case 1: 51    // ultraThin, 0.2
        case 2: 89    // thin, 0.35
        case 3: 128   // regular, 0.5
        case 4: 166   // thick, 0.65
        case 5: 204   // ultraThick, 0.8
        default: 128  // bar, and anything else
        }
        return (alpha << 24) | (128 << 16) | (128 << 8) | 140
    }

    private init(kind: Int32, geometry: [Double], _ stops: [(offset: Double, argb: UInt32)]) {
        self.kind = kind
        self.geometry = geometry
        colors = stops.map(\.argb)
        offsets = stops.map(\.offset)
    }

    private static func stop(_ stop: HostBrush.Stop) -> (offset: Double, argb: UInt32)? {
        stop.color.argb.map { (stop.offset, $0) }
    }

    /// Runs `body` with the brush as the relay's struct for a box of `size`, its stops held for the call: a radial
    /// gradient's radius per axis, one circle's reach (`HostBrush.reach`) in fractions of each side.
    /// Design: docs/design/platforms/winui/drawing.md#a-box-and-its-brush
    func withRelayBrush<Result>(over size: LayoutSize, _ body: (SwiftOmniUIBrush) -> Result) -> Result {
        colors.withUnsafeBufferPointer { colors in
            offsets.withUnsafeBufferPointer { offsets in
                var g = geometry
                if followsSize {
                    let reach = HostBrush.reach(of: g[2], width: size.width, height: size.height)
                    (g[2], g[3]) = (size.width > 0 ? reach / size.width : g[2], size.height > 0 ? reach / size.height : g[2])
                }
                return body(SwiftOmniUIBrush(
                    kind: kind, geometry: (g[0], g[1], g[2], g[3]), count: Int32(colors.count),
                    colors: colors.baseAddress, offsets: offsets.baseAddress))
            }
        }
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension HostPath {
    /// Stable geometry records. Kinds 0...4 agree with HostCurveCommand;
    /// kind 5 retains an elliptical arc until the native boundary.
    public var numbers: [Double] {
        commands.flatMap { command -> [Double] in
            switch command {
            case .move(let p): return [0, p.x, p.y]
            case .line(let p): return [1, p.x, p.y]
            case .cubic(let a, let b, let p): return [2, a.x, a.y, b.x, b.y, p.x, p.y]
            case .quadratic(let a, let p): return [3, a.x, a.y, p.x, p.y]
            case .close: return [4]
            case .arc(let x, let y, let rotation, let large, let sweep, let p):
                return [5, x, y, rotation, large ? 1 : 0, sweep ? 1 : 0, p.x, p.y]
            }
        }
    }

    /// Reject malformed records as a whole, just like SVG input.
    public init?(numbers: [Double]) {
        guard numbers.allSatisfy(\.isFinite) else { return nil }
        var commands: [HostPathCommand] = []
        var offset = 0
        var hasStart = false
        while offset < numbers.count {
            let kind = numbers[offset]
            let count: Int
            switch kind {
            case 0, 1: count = 3
            case 2: count = 7
            case 3: count = 5
            case 4: count = 1
            case 5: count = 8
            default: return nil
            }
            guard offset + count <= numbers.count, kind == 0 || hasStart else { return nil }
            func point(_ at: Int) -> Point { Point(numbers[offset + at], numbers[offset + at + 1]) }
            switch kind {
            case 0: commands.append(.move(point(1))); hasStart = true
            case 1: commands.append(.line(point(1)))
            case 2: commands.append(.cubic(control1: point(1), control2: point(3), end: point(5)))
            case 3: commands.append(.quadratic(control: point(1), end: point(3)))
            case 4: commands.append(.close)
            default:
                guard [0.0, 1.0].contains(numbers[offset + 4]),
                      [0.0, 1.0].contains(numbers[offset + 5]) else { return nil }
                commands.append(.arc(radiusX: numbers[offset + 1], radiusY: numbers[offset + 2],
                    rotation: numbers[offset + 3], largeArc: numbers[offset + 4] == 1,
                    sweep: numbers[offset + 5] == 1, end: point(6)))
            }
            offset += count
        }
        self.init(commands: commands)
    }

    /// SVG is an interchange/description format, generated only when asked.
    public var svg: String {
        func point(_ p: Point) -> String { "\(p.x),\(p.y)" }
        return commands.map { command in
            switch command {
            case .move(let p): "M \(point(p))"
            case .line(let p): "L \(point(p))"
            case .cubic(let a, let b, let p): "C \(point(a)) \(point(b)) \(point(p))"
            case .quadratic(let a, let p): "Q \(point(a)) \(point(p))"
            case .close: "Z"
            case .arc(let x, let y, let rotation, let large, let sweep, let p):
                "A \(x),\(y) \(rotation) \(large ? 1 : 0) \(sweep ? 1 : 0) \(point(p))"
            }
        }.joined(separator: " ")
    }
}

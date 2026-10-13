// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension Rectangle {
    public func path(in rect: Rect) -> Path {
        let radius = node.controlContent.props[RectangleContract.cornerRadius.token].flatMap(CornerRadius.init(propValue:)) ?? .uniform(0)
        switch radius {
        case .uniform(let r): return Path(roundedRect: rect, cornerRadius: r)
        case .corners(let a, let b, let c, let d):
            return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
                topLeading: a, topTrailing: b, bottomLeading: c, bottomTrailing: d))
        }
    }
}
extension Ellipse {
    public func path(in rect: Rect) -> Path { Path(ellipseIn: rect) }
}
extension RoundedRectangle {
    public func path(in rect: Rect) -> Path { Path(roundedRect: rect, cornerRadius: cornerRadius) }
}
extension UnevenRoundedRectangle {
    public func path(in rect: Rect) -> Path { Path(roundedRect: rect, cornerRadii: cornerRadii) }
}
extension Capsule {
    public func path(in rect: Rect) -> Path { Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2) }
}
extension Circle {
    public func path(in rect: Rect) -> Path {
        let side = min(rect.width, rect.height)
        return Path(ellipseIn: Rect(rect.x + (rect.width - side) / 2, rect.y + (rect.height - side) / 2, side, side))
    }
}
extension Line {
    public func path(in rect: Rect) -> Path {
        Path {
            $0.move(to: Point(node.controlContent.props[LineContract.x1.token]?.number ?? 0, node.controlContent.props[LineContract.y1.token]?.number ?? 0))
            $0.addLine(to: Point(node.controlContent.props[LineContract.x2.token]?.number ?? 0, node.controlContent.props[LineContract.y2.token]?.number ?? 0))
        }
    }
}
extension Polygon {
    public func path(in rect: Rect) -> Path {
        var path = Path()
        let points = node.controlContent.props[PolygonContract.points.token].flatMap([Point].init(propValue:)) ?? []
        if let first = points.first { path.move(to: first); path.addLines(Array(points.dropFirst())); path.closeSubpath() }
        return path
    }
}
extension Polyline {
    public func path(in rect: Rect) -> Path {
        var path = Path()
        let points = node.controlContent.props[PolylineContract.points.token].flatMap([Point].init(propValue:)) ?? []
        if let first = points.first { path.move(to: first); path.addLines(Array(points.dropFirst())) }
        return path
    }
}

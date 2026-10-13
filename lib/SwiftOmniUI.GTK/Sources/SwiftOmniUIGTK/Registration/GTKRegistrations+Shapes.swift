// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension GTKRegistrations {
    /// The six shapes: a rectangle and an ellipse filling their room, and a line, a path, a polygon and a polyline
    /// drawn from their own geometry - each filled, outlined and placed as the shape tier says.
    static func shapes(_ registry: Registry<GTKView>) {
        registry.add(RectangleContract.self, create: { _ in GTKShapeView() }) { shape in
            shape.applies(shapeMembers + [RectangleContract.cornerRadius]) { view, values in
                paint(view, values)
                view.draw(.rectangle(BoxArithmetic.clockwise(values[RectangleContract.cornerRadius])))
            }
        }
        registry.add(EllipseContract.self, create: { _ in GTKShapeView() }) { shape in
            shape.applies(shapeMembers) { view, values in
                paint(view, values)
                view.draw(.ellipse)
            }
        }
        registry.add(LineContract.self, create: { _ in GTKShapeView() }) { shape in
            shape.applies(shapeMembers + [LineContract.x1, LineContract.y1, LineContract.x2, LineContract.y2]) {
                view, values in
                paint(view, values)
                let from = [values[LineContract.x1] ?? 0, values[LineContract.y1] ?? 0]
                let to = [values[LineContract.x2] ?? 0, values[LineContract.y2] ?? 0]
                view.draw(authored([0] + from + [1] + to, evenOdd: false, values))
            }
        }
        registry.add(PathContract.self, create: { _ in GTKShapeView() }) { shape in
            shape.applies(shapeMembers + [PathContract.data, PathContract.commands]) { view, values in
                paint(view, values)
                let geometry: HostPath?
                if let data = values[PathContract.data] { geometry = HostPath(svg: data) }
                else { geometry = values[PathContract.commands].flatMap { HostPath(numbers: $0) } }
                let curves = geometry?.arcsAsCubics ?? []
                view.draw(authored(curves.flatMap(\.numbers), evenOdd: (values[ShapeContract.fillRule] ?? .nonzero) == .evenOdd, values, local: true))
            }
        }
        registry.add(PolygonContract.self, create: { _ in GTKShapeView() }) { shape in
            shape.applies(shapeMembers + [PolygonContract.points]) { view, values in
                paint(view, values)
                view.draw(authored(
                    ShapeArithmetic.curves(through: values[PolygonContract.points] ?? [], closed: true).flatMap(\.numbers),
                    evenOdd: (values[PolygonContract.fillRule] ?? .evenOdd) == .evenOdd, values))
            }
        }
        registry.add(PolylineContract.self, create: { _ in GTKShapeView() }) { shape in
            shape.applies(shapeMembers + [PolylineContract.points]) { view, values in
                paint(view, values)
                view.draw(authored(
                    ShapeArithmetic.curves(through: values[PolylineContract.points] ?? [], closed: false).flatMap(\.numbers),
                    evenOdd: (values[PolylineContract.fillRule] ?? .evenOdd) == .evenOdd, values))
            }
        }
    }

    /// The surface an application draws on, and the press it answers. The drawing is ONE value that replaces the
    /// one before it, so the canvas takes it whole rather than instruction by instruction; the three reports carry
    /// where the press was, in the canvas's own coordinates - the ones the instructions use.
    static func drawing(_ registry: Registry<GTKView>) {
        registry.add(CanvasContract.self, create: { reports in
            let canvas = GTKCanvasView()
            canvas.onPressed = { reports.raise(CanvasContract.pressed, $0) }
            canvas.onDragged = { reports.raise(CanvasContract.dragged, $0) }
            canvas.onReleased = { reports.raise(CanvasContract.released, $0) }
            return canvas
        }, members: { canvas in
            canvas.property(CanvasContract.drawable) { view, drawing in
                view.apply(drawing)
            }
            canvas.raises(CanvasContract.pressed)
            canvas.raises(CanvasContract.dragged)
            canvas.raises(CanvasContract.released)
        })
    }

    /// What every shape takes whole.
    private static let shapeMembers: [any ContractMember] = [
        ShapeContract.fill, ShapeContract.stroke, ShapeContract.strokeWidth,
        ShapeContract.strokeDashPattern, ShapeContract.strokeDashOffset,
        ShapeContract.strokeLineCap, ShapeContract.strokeLineJoin, ShapeContract.strokeMiterLimit,
        ShapeContract.aspect, ShapeContract.renderTransform, ShapeContract.fillRule, ShapeContract.strokeDashInPathUnits, ShapeContract.strokePhaseInPathUnits,
    ]

    private static func paint<Realized: ElementContract>(_ view: GTKShapeView, _ values: ElementValues<Realized>) {
        view.paint(
            fill: GTKBrush(values[ShapeContract.fill]?.propValue),
            stroke: GTKBrush(values[ShapeContract.stroke]?.propValue),
            width: values[ShapeContract.strokeWidth] ?? 1,
            dashes: (values[ShapeContract.strokeDashPattern] ?? []).map {
                values[ShapeContract.strokeDashInPathUnits] == true ? $0 / max(0.000001, values[ShapeContract.strokeWidth] ?? 1) : $0
            },
            dashOffset: (values[ShapeContract.strokeDashOffset] ?? 0)
                / (values[ShapeContract.strokePhaseInPathUnits] == true ? max(0.000001, values[ShapeContract.strokeWidth] ?? 1) : 1),
            cap: values[ShapeContract.strokeLineCap] ?? .flat,
            join: values[ShapeContract.strokeLineJoin] ?? .miter,
            miter: values[ShapeContract.strokeMiterLimit] ?? 10)
    }

    /// A geometry of the shape's own, placed by its aspect and moved by its transform.
    private static func authored<Realized: ElementContract>(
        _ commands: [Double], evenOdd: Bool, _ values: ElementValues<Realized>, local: Bool = false
    ) -> GTKShapeView.Geometry {
        let transform = values[ShapeContract.renderTransform]?.propValue.values?.compactMap(\.number)
        return .authored(
            commands, evenOdd: evenOdd, aspect: values[ShapeContract.aspect] ?? (local ? nil : .fit),
            transform: transform.flatMap { $0.count == 6 && $0.allSatisfy(\.isFinite) ? $0 : nil })
    }

}

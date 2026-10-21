// SPDX-License-Identifier: Apache-2.0
// The CoreText/CoreGraphics subset used by portable clients. Native font files,
// native glyph geometry and native bitmap rendering provide the implementation.
import Foundation
@_spi(Host) import SwiftOmniUICore

public typealias CGGlyph = UInt16
public typealias UTF32Char = UInt32
public typealias CFAttributedString = NSAttributedString
public typealias CFString = String
public let kCTFontAttributeName = NSAttributedString.Key("SOUIFont")
public let kCTKernAttributeName = NSAttributedString.Key("SOUIKern")
public let kCTForegroundColorAttributeName = NSAttributedString.Key("SOUIColor")
public let CGPointZero = CGPoint.zero
public func CGPointMake(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
public func CGSizeMake(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
public func CGRectMake(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
public func CGRectGetMaxX(_ rect: CGRect) -> CGFloat { rect.maxX }
public func CGRectGetMaxY(_ rect: CGRect) -> CGFloat { rect.maxY }
public func CGRectGetMinY(_ rect: CGRect) -> CGFloat { rect.minY }
public func CFRangeMake(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }

@MainActor public final class CGDataProvider {
    let path: String
    public init?(filename: String) {
        guard FileManager.default.fileExists(atPath: filename) else { return nil }
        path = filename
    }
}
@MainActor public final class CGFont {
    let face: FontFace
    private let names: OpenTypeGlyphNames
    public init?(_ provider: CGDataProvider) {
        guard let face = FontFace(path: provider.path) else { return nil }
        self.face = face; self.names = OpenTypeGlyphNames(face: face)
    }
    public func name(for glyph: CGGlyph) -> String? {
        names.names.indices.contains(Int(glyph)) ? names.names[Int(glyph)] : nil
    }
    public func getGlyphWithGlyphName(name: String) -> CGGlyph { names.indices[name] ?? 0 }
}
@MainActor public final class CTFont {
    let font: CGFont
    let size: CGFloat
    init(font: CGFont, size: CGFloat) { self.font = font; self.size = size }
    var scale: CGFloat { size / CGFloat(font.face.unitsPerEm) }
    func glyph(_ scalar: Unicode.Scalar) -> CGGlyph { font.face.glyph(for: scalar.value) }
    func advance(_ glyph: CGGlyph) -> CGFloat { CGFloat(font.face.metrics(for: glyph)[0]) * scale }
    func bounds(_ glyph: CGGlyph) -> CGRect {
        let m = font.face.metrics(for: glyph)
        return CGRect(x: CGFloat(m[1]) * scale, y: CGFloat(m[2]) * scale,
                      width: CGFloat(m[3]) * scale, height: CGFloat(m[4]) * scale)
    }
    func path(_ glyph: CGGlyph) -> Path { font.face.path(for: glyph) }
}
@MainActor public func CTFontCreateWithGraphicsFont(_ font: CGFont, _ size: CGFloat, _ matrix: UnsafeRawPointer?, _ attributes: UnsafeRawPointer?) -> CTFont {
    CTFont(font: font, size: size)
}
@MainActor public func CTFontGetSize(_ font: CTFont) -> CGFloat { font.size }
public enum CTFontOrientation { case horizontal }
@MainActor public func CTFontGetUnitsPerEm(_ font: CTFont) -> UInt32 { UInt32(font.font.face.unitsPerEm) }

@discardableResult
@MainActor public func CTFontGetAdvancesForGlyphs(_ font: CTFont, _ orientation: CTFontOrientation,
                              _ glyphs: UnsafePointer<CGGlyph>, _ sizes: UnsafeMutablePointer<CGSize>?, _ count: Int) -> Double {
    var total: CGFloat = 0
    for index in 0..<count {
        let width = font.advance(glyphs[index])
        sizes?[index] = CGSize(width: width, height: 0)
        total += width
    }
    return Double(total)
}
@discardableResult
@MainActor public func CTFontGetBoundingRectsForGlyphs(_ font: CTFont, _ orientation: CTFontOrientation,
                                   _ glyphs: UnsafePointer<CGGlyph>, _ boxes: UnsafeMutablePointer<CGRect>?, _ count: Int) -> CGRect {
    var result = CGRect.null
    for index in 0..<count {
        let box = font.bounds(glyphs[index])
        boxes?[index] = box
        result = result.union(box)
    }
    return result.isNull ? .zero : result
}
@MainActor public func CTFontGetGlyphsForCharacters(_ font: CTFont, _ characters: UnsafePointer<UInt16>,
                                _ glyphs: UnsafeMutablePointer<CGGlyph>, _ count: Int) -> Bool {
    var index = 0, found = true
    while index < count {
        let first = UInt32(characters[index])
        var code = first, width = 1
        if (0xD800...0xDBFF).contains(first), index + 1 < count {
            let second = UInt32(characters[index + 1])
            if (0xDC00...0xDFFF).contains(second) {
                code = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
                width = 2
            }
        }
        let glyph = Unicode.Scalar(code).map(font.glyph) ?? 0
        glyphs[index] = glyph
        if width == 2 { glyphs[index + 1] = 0 }
        found = found && glyph != 0
        index += width
    }
    return found
}


public final class CGImage: @unchecked Sendable, Hashable {
    public let bitmap: BitmapImage
    public var width: Int { bitmap.pixels.width }
    public var height: Int { bitmap.pixels.height }
    public var size: CGSize { CGSize(width: bitmap.size.width, height: bitmap.size.height) }
    public init(bitmap: BitmapImage) { self.bitmap = bitmap }
    public static func == (lhs: CGImage, rhs: CGImage) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    public func resized(to size: CGSize) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        // Resizing changes logical dimensions; native image scaling retains the original pixels.
        guard size.width.isFinite, size.height.isFinite else { return nil }
        let image = bitmap.withLogicalSize(Size(Double(size.width), Double(size.height)))
        return CGImage(bitmap: image)
    }
}
public extension Image {
    init(decorative image: CGImage, scale: Double = 1, orientation: Image.Orientation = .up) {
        let logical = Size(Double(image.width) / scale, Double(image.height) / scale)
        self.init(ImageSource(bitmap: image.bitmap.withLogicalSize(logical)))
    }
    enum Orientation: Sendable { case up }
}
@MainActor public final class CTLine: NSObject {
    struct Glyph {
        let id: CGGlyph
        let font: CTFont
        let x: CGFloat
        let y: CGFloat
        let advance: CGFloat
        let cluster: Range<Int>
        let isVisible: Bool
        let color: Color?
    }
    let glyphs: [Glyph]
    let width: Double
    let bounds: CGRect
    let lineBreaks: [FontFace.LineBreak]
    let clusterAdvances: [(range: Range<Int>, width: Double)]
    init(_ text: NSAttributedString) {
        var glyphs: [Glyph] = []
        var x: CGFloat = 0, bounds = CGRect.null
        var segments: [(range: NSRange, font: CTFont)] = []
        var offset = 0
        while offset < text.length {
            var range = NSRange()
            let attributes = text.attributes(at: offset, effectiveRange: &range)
            if let font = attributes[kCTFontAttributeName] as? CTFont {
                if let previous = segments.last, previous.font === font, NSMaxRange(previous.range) == offset {
                    segments[segments.count - 1].range.length = NSMaxRange(range) - previous.range.location
                } else {
                    segments.append((NSRange(location: offset, length: NSMaxRange(range) - offset), font))
                }
            }
            offset = NSMaxRange(range)
        }
        var breaks: [FontFace.LineBreak] = []
        var clusterWidths: [Range<Int>: Double] = [:]
        for segment in segments {
            let font = segment.font
            let source = text.attributedSubstring(from: segment.range).string
            guard let shaped = font.font.face.shape(source) else { continue }
            if segment.range.location == 0, segment.range.length == text.length { breaks = shaped.lineBreaks }
            // Native shaping runs are independent of colours and explicit
            // mathematical spacing. Neither can split a ligature or combining
            // sequence into separately measured scalar glyphs.
            let clusters = Dictionary(grouping: shaped.glyphs, by: \.cluster)
            let visual = clusters.keys.sorted {
                let left = clusters[$0]?.map(\.position.x).min() ?? 0
                let right = clusters[$1]?.map(\.position.x).min() ?? 0
                return left == right ? $0.lowerBound < $1.lowerBound : left < right
            }
            var tracking: [Range<Int>: CGFloat] = [:]
            var extra: CGFloat = 0
            for cluster in visual {
                tracking[cluster] = extra
                let global = (segment.range.location + cluster.lowerBound)..<(segment.range.location + cluster.upperBound)
                let attributes = text.attributes(at: global.upperBound - 1, effectiveRange: nil)
                let kern = global.upperBound < text.length
                    ? (attributes[kCTKernAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0 : 0
                extra += kern
                clusterWidths[global, default: 0] += Double(kern)
            }
            for native in shaped.glyphs {
                let cluster = (segment.range.location + native.cluster.lowerBound)..<(segment.range.location + native.cluster.upperBound)
                let attributes = text.attributes(at: cluster.lowerBound, effectiveRange: nil)
                let px = x + CGFloat(native.position.x) * font.scale + (tracking[native.cluster] ?? 0)
                let py = CGFloat(native.position.y) * font.scale
                let advance = CGFloat(native.advance) * font.scale
                glyphs.append(Glyph(id: native.id, font: font, x: px, y: py,
                    advance: advance, cluster: cluster, isVisible: native.isVisible,
                    color: attributes[kCTForegroundColorAttributeName] as? Color))
                if native.isVisible { bounds = bounds.union(font.bounds(native.id).offsetBy(dx: px, dy: py)) }
                clusterWidths[cluster, default: 0] += Double(advance)
            }
            x += CGFloat(shaped.width) * font.scale + extra
        }
        if segments.count > 1, let font = segments.first?.font {
            // Breaking is a property of the full Unicode text, not of a font or
            // colour attribute boundary. Ask the native analyzer once across it.
            breaks = font.font.face.shape(text.string)?.lineBreaks ?? []
        }
        self.glyphs = glyphs
        self.width = Double(x)
        self.bounds = bounds.isNull ? .zero : bounds
        self.lineBreaks = breaks
        self.clusterAdvances = clusterWidths.map { (range: $0.key, width: $0.value) }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
public typealias CTRun = CTLine
public typealias CTTypesetter = NSAttributedString
public nonisolated struct CTLineBoundsOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let useGlyphPathBounds = Self(rawValue: 1)
}
@MainActor public func CTLineCreateWithAttributedString(_ text: NSAttributedString) -> CTLine { CTLine(text) }
@MainActor public func CTLineGetBoundsWithOptions(_ line: CTLine, _ options: CTLineBoundsOptions) -> CGRect { line.bounds }
@MainActor public func CTLineGetTypographicBounds(_ line: CTLine, _ ascent: UnsafeMutablePointer<CGFloat>?,
                               _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    ascent?.pointee = max(0, line.bounds.maxY)
    descent?.pointee = max(0, -line.bounds.minY)
    leading?.pointee = 0
    return line.width
}
@MainActor public func CTLineGetGlyphRuns(_ line: CTLine) -> [CTRun] { [line] }
@MainActor public func CTRunGetGlyphCount(_ run: CTRun) -> Int { run.glyphs.count }
@MainActor public func CTRunGetGlyphs(_ run: CTRun, _ range: NSRange, _ output: UnsafeMutablePointer<CGGlyph>) {
    for index in 0..<range.length { output[index] = run.glyphs[range.location + index].id }
}
@MainActor public func CTTypesetterCreateWithAttributedString(_ text: NSAttributedString) -> CTTypesetter { text }
@MainActor public func CTTypesetterSuggestLineBreak(_ text: CTTypesetter, _ start: Int, _ width: Double) -> Int {
    guard start >= 0, start < text.length, !width.isNaN, width >= 0 else { return 0 }
    let remainder = text.attributedSubstring(from: NSRange(location: start, length: text.length - start))
    let line = CTLine(remainder)
    let opportunities = Dictionary(uniqueKeysWithValues: line.lineBreaks.map { ($0.offset, $0.mandatory) })
    var occupied = 0.0, consumed = 0, lastAllowed = 0
    for cluster in line.clusterAdvances {
        occupied += cluster.width
        if occupied > width { return lastAllowed > 0 ? lastAllowed : consumed }
        consumed = cluster.range.upperBound
        if let mandatory = opportunities[consumed] {
            if mandatory { return consumed }
            lastAllowed = consumed
        }
    }
    return remainder.length
}

/// Records CoreGraphics-style baseline coordinates as native Canvas paths.
/// Each operation keeps its state so cached drawings can be replayed safely.
@MainActor public final class CGContext {
    struct State {
        var sx: Double = 1, sy: Double = 1, x: Double = 0, y: Double = 0
        public var fill: Color = .primary, stroke: Color = .primary
        var textPosition = CGPoint.zero
    }
    struct Mark {
        let path: Path
        let state: State
        var line: StrokeStyle? = nil
    }
    public static var current: CGContext?
    private let imageSize: CGSize
    private let imageScale: Double
    public init(size: CGSize, scale: Double = 1) {
        self.imageSize = size; self.imageScale = scale
    }
    public func withCurrent<T>(_ body: () throws -> T) rethrows -> T {
        let previous = Self.current; Self.current = self
        defer { Self.current = previous }
        return try body()
    }
    public func makeImage() -> CGImage? {
        var context = GraphicsContext()
        replay(into: &context, ascent: imageSize.height)
        guard let bitmap = context.makeImage(size: Size(Double(imageSize.width), Double(imageSize.height)), scale: imageScale) else { return nil }
        return CGImage(bitmap: bitmap)
    }
    private var state = State()
    private var stack: [State] = []
    private(set) var marks: [Mark] = []
    public var textPosition: CGPoint {
        get { state.textPosition }
        set { state.textPosition = newValue }
    }
    public func saveGState() { stack.append(state) }
    public func restoreGState() { if let saved = stack.popLast() { state = saved } }
    public func translateBy(x: CGFloat, y: CGFloat) { state.x += state.sx * Double(x); state.y += state.sy * Double(y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.sx *= Double(x); state.sy *= Double(y) }
    public func setFillColor(_ color: Color) { state.fill = color }
    public func setStrokeColor(_ color: Color) { state.stroke = color }
    public func setBlendMode(_ mode: BlendMode) {}
    public func fill(_ rect: CGRect) { marks.append(Mark(path: Path(Rect(rect.minX, rect.minY, rect.width, rect.height)), state: state)) }
    func stroke(_ path: Path, width: CGFloat, cap: LineCap) {
        marks.append(Mark(path: path, state: state, line: StrokeStyle(lineWidth: Double(width), lineCap: cap)))
    }
    func glyph(_ glyph: CGGlyph, font: CTFont, at point: CGPoint) {
        saveGState()
        translateBy(x: point.x, y: point.y)
        scaleBy(x: font.scale, y: font.scale)
        marks.append(Mark(path: font.path(glyph), state: state))
        restoreGState()
    }
    private func replay(into context: inout GraphicsContext, ascent: CGFloat) {
        context.drawLayer { context in
            context.translateBy(x: 0, y: Double(ascent))
            context.scaleBy(x: 1, y: -1)
            for mark in marks {
                context.drawLayer { context in
                    context.translateBy(x: mark.state.x, y: mark.state.y)
                    context.scaleBy(x: mark.state.sx, y: mark.state.sy)
                    if let line = mark.line { context.stroke(mark.path, with: .color(mark.state.stroke), style: line) }
                    else { context.fill(mark.path, with: .color(mark.state.fill)) }
                }
            }
        }
    }
}
@MainActor public func CTFontDrawGlyphs(_ font: CTFont, _ glyphs: UnsafePointer<CGGlyph>, _ positions: UnsafePointer<CGPoint>,
                     _ count: Int, _ context: CGContext) {
    for index in 0..<count { context.glyph(glyphs[index], font: font, at: positions[index]) }
}
@MainActor public func CTLineDraw(_ line: CTLine, _ context: CGContext) {
    for glyph in line.glyphs {
        guard glyph.isVisible else { continue }
        context.saveGState()
        if let color = glyph.color { context.setFillColor(color) }
        context.glyph(glyph.id, font: glyph.font,
            at: CGPoint(x: context.textPosition.x + glyph.x, y: context.textPosition.y + glyph.y))
        context.restoreGState()
    }
}
@MainActor public final class GraphicsBezierPath {
    private var path = Path()
    public var lineWidth: CGFloat = 1
    public var lineCapStyle: LineCap = .flat
    public init() {}
    public func move(to point: CGPoint) { path.move(to: Point(point.x, point.y)) }
    public func addLine(to point: CGPoint) { path.addLine(to: Point(point.x, point.y)) }
    public func stroke() { CGContext.current?.stroke(path, width: lineWidth, cap: lineCapStyle) }
}
public extension Color {
    init(_ color: Color) { self = color }
    var cgColor: Color { self }
    @MainActor func setFill() { CGContext.current?.setFillColor(self) }
    @MainActor func setStroke() { CGContext.current?.setStrokeColor(self) }
    init?(fromHexString string: String) {
        let hex = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        self.init(hex)
    }
}

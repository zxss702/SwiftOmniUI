// SPDX-License-Identifier: Apache-2.0
// A process-private font face opened from the exact font file supplied by the caller.

@MainActor public final class FontFace {
    /// One native shaped glyph, in font design units with a Y-up baseline.
    /// `cluster` addresses UTF-16 code units in the original string; ligatures
    /// and combining sequences can therefore share a range across several glyphs.
    public struct ShapedGlyph: Sendable {
        public let id: UInt16
        public let position: Point
        public let advance: Double
        public let cluster: Range<Int>
        public let isVisible: Bool
        public init(id: UInt16, position: Point, advance: Double, cluster: Range<Int>, isVisible: Bool = true) {
            self.id = id; self.position = position; self.advance = advance; self.cluster = cluster; self.isVisible = isVisible
        }
    }
    public struct LineBreak: Sendable {
        public let offset: Int
        public let mandatory: Bool
        public init(offset: Int, mandatory: Bool) { self.offset = offset; self.mandatory = mandatory }
    }
    public struct ShapedText: Sendable {
        public let glyphs: [ShapedGlyph]
        public let width: Double
        public let lineBreaks: [LineBreak]
        public init(glyphs: [ShapedGlyph], width: Double, lineBreaks: [LineBreak]) {
            self.glyphs = glyphs; self.width = width; self.lineBreaks = lineBreaks
        }
    }
    @_spi(Host) public struct Operations {
        public let unitsPerEm: Double
        public let glyph: (UInt32) -> UInt16
        public let metrics: (UInt16) -> [Double]
        public let outline: (UInt16) -> String
        public let table: (String) -> [UInt8]
        public let shape: ([UInt16]) -> ShapedText?
        public let close: () -> Void
        public init(unitsPerEm: Double, glyph: @escaping (UInt32) -> UInt16,
                    metrics: @escaping (UInt16) -> [Double], outline: @escaping (UInt16) -> String,
                    table: @escaping (String) -> [UInt8], shape: @escaping ([UInt16]) -> ShapedText?,
                    close: @escaping () -> Void) {
            self.unitsPerEm = unitsPerEm; self.glyph = glyph; self.metrics = metrics
            self.outline = outline; self.table = table; self.shape = shape; self.close = close
        }
    }
    /// Installed during desktop-host startup; native operations are consumed on
    /// the main actor by this face's initializer and methods.
    @_spi(Host) public nonisolated(unsafe) static var open: ((String) -> Operations?)?
    private let operations: Operations
    private var metricsCache: [UInt16: [Double]] = [:]
    private var pathCache: [UInt16: Path] = [:]
    public var unitsPerEm: Double { operations.unitsPerEm }
    public init?(path: String) {
        guard let operations = Self.open?(path) else { return nil }
        guard operations.unitsPerEm.isFinite, operations.unitsPerEm > 0 else { operations.close(); return nil }
        self.operations = operations
    }
    isolated deinit { operations.close() }
    public func glyph(for scalar: UInt32) -> UInt16 { operations.glyph(scalar) }
    /// Advance, minX, minY, width and height, in unhinted design units.
    public func metrics(for glyph: UInt16) -> [Double] {
        if let metrics = metricsCache[glyph] { return metrics }
        let metrics = operations.metrics(glyph)
        metricsCache[glyph] = metrics
        return metrics
    }
    public func path(for glyph: UInt16) -> Path {
        if let path = pathCache[glyph] { return path }
        let path = Path(operations.outline(glyph))
        pathCache[glyph] = path
        return path
    }
    public func table(_ tag: String) -> [UInt8] { operations.table(tag) }
    /// Native OpenType shaping and Unicode line-break opportunities for the exact
    /// loaded font file. No platform font-family lookup substitutes another face.
    public func shape(_ text: String) -> ShapedText? { operations.shape(Array(text.utf16)) }
}

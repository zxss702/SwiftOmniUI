// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Measuring what a layout decided: `.onFrameChanged` on any view, and
// `GeometryReader`, a composed view whose content is built from its frame.
// Design: docs/design/views/measured-layouts.md#frame-reports

/// Which coordinates a measurement is answered in.
public enum CoordinateSpace: Sendable {
    /// The frame as the parent placed it: `x` and `y` are offsets inside the
    /// parent. The default.
    case parent

    /// The same rectangle with its origin converted to the window, ancestor
    /// offsets and scroll positions accounted for.
    case global

    /// Measured from where content can safely sit - past the status bar, the
    /// notch and any bar drawn above the page - so a view at the very top of
    /// its page's content reads zero on every platform. With no platform, in a
    /// test, it agrees with `.global`.
    case safeArea

    /// The view's own bounds: zero origin, its own size.
    case local

    /// The space an ancestor declared with `.coordinateSpace(.named(name))`:
    /// the frame measured from that ancestor's top left.
    case named(String)
}

extension View {
    /// Reports this view's own frame as layout settles it - the first layout
    /// included - and again when an ancestor's frame or a scroll moves it.
    ///
    ///     VStack {
    ///         …
    ///     }
    ///     .onFrameChanged { frame in height = frame.height }
    ///     .onFrameChanged(in: .global) { frame in anchor = frame }
    ///
    /// Each handler hears only changes in its own space. A transform -
    /// `.translationX`, `.rotation`, `.scale` - moves what is drawn and not the
    /// frame, so it reports nothing; an animated `.width` reports every step.
    ///
    /// - Parameters:
    ///   - space: Which coordinates to answer in - the parent's unless said.
    ///   - handler: What to run with each settled frame.
    @_spi(Host) public func onFrameChanged(
        in space: CoordinateSpace = .parent,
        _ handler: @escaping ValueEventHandler<Rect>
    ) -> ModifiedContent {
        // One report serves every space; each handler stays quiet while its
        // own answer is unchanged.
        let last = LastFrame()

        nonisolated(nonsending) func report() async throws {
            guard var report = last.report else { return }
            report.named = last.named

            let frame = report.frame(in: space)
            guard frame != last.rect else { return }

            last.rect = frame
            try await handler(frame)
        }

        return hearing(ViewContract.frameChanged) { numbers in
            guard let arrived = FrameReport(numbers) else { return }
            last.report = arrived
            try await report()
        }
        .hearing(ViewContract.namedFramesChanged) { frames in
            last.named = frames
            try await report()
        }
    }
}

/// What a frame handler last handed over, remembered across reports; a
/// rebuilt view starts it afresh, costing one repeated report.
private final class LastFrame: @unchecked Sendable {
    /// The last numbers report.
    var report: FrameReport?

    /// The named spaces the last report travelled with.
    var named: [NamedSpaceFrame] = []

    /// The rectangle the handler last ran with.
    var rect: Rect?
}

/// What an `onGeometryChange` handler last answered with - the same book as
/// `LastFrame`, on the transformed value rather than on the rectangle.
private final class LastGeometry<T: Equatable>: @unchecked Sendable {
    /// The last numbers report.
    var report: FrameReport?

    /// The named spaces the last report travelled with.
    var named: [NamedSpaceFrame] = []
    var insets: EdgeInsets?

    /// The value the handler last ran with.
    var value: T?
}

extension View {
    /// Runs `action` with a value drawn from this view's geometry every time
    /// that value settles somewhere new, the first layout included - the
    /// SwiftUI spelling.
    ///
    ///     .onGeometryChange(for: Rect.self) { proxy in
    ///         proxy.frame(in: .global)
    ///     } action: { frame in
    ///         anchor = frame
    ///     }
    ///
    /// - Parameters:
    ///   - type: what `transform` answers.
    ///   - transform: the part of the proxy to watch - the view's size, or its
    ///     frame in a coordinate space.
    ///   - action: run with each new settled value.
    public func onGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (GeometryProxy) -> T,
        action: @escaping (T) -> Void
    ) -> ModifiedContent {
        let last = LastGeometry<T>()

        nonisolated(nonsending) func report() async throws {
            guard var report = last.report else { return }
            report.named = last.named
            report.reportedInsets = last.insets
            let value = transform(GeometryProxy(report: report))
            guard value != last.value else { return }
            last.value = value
            action(value)
        }

        return hearing(ViewContract.frameChanged) { numbers in
            guard let arrived = FrameReport(numbers) else { return }
            last.report = arrived
            try await report()
        }
        .hearing(ViewContract.namedFramesChanged) { frames in
            last.named = frames
            try await report()
        }
        .hearing(ViewContract.safeAreaInsetsChanged) { insets in
            last.insets = insets
            // The host follows this environment with the matching frame,
            // even when only the insets changed. Transform one coherent pair.
        }
    }
}

/// What a `GeometryReader` hands its content: the view's size, where the safe
/// area cuts into it, and its frame in the space asked for.
public struct GeometryProxy: Sendable {
    /// The report this proxy reads.
    let report: FrameReport

    /// The size the view was laid out at.
    public var size: Size { Size(report.frame.width, report.frame.height) }

    /// The container's remaining safe-area contributions. A safe allocation
    /// can exclude these strips from `size` while still observing them here;
    /// a scroll document consumes them before reporting its inner geometry.
    public var safeAreaInsets: EdgeInsets { report.safeAreaInsets }

    /// The view's frame in the space named - `.local` for its own bounds,
    /// `.global` for the window, `.parent` where the parent placed it,
    /// `.safeArea` inside what is not covered, `.named(name)` measured from
    /// the ancestor `.coordinateSpace(.named(name))` declared, `.zero` for a
    /// name nobody declared.
    public func frame(in space: CoordinateSpace) -> Rect {
        report.frame(in: space)
    }
}

/// A container whose content is built from the space it was given.
///
///     GeometryReader { proxy in
///         Text("half of \(Int(proxy.size.width)) is \(Int(proxy.size.width / 2))")
///             .frame(width: proxy.size.width / 2)
///     }
///
/// The closure runs when the host has allocated the reader, and again whenever
/// its frame settles somewhere new. Several views stack from the leading top
/// corner. Content does not determine the reader's natural size. To report a frame rather than build from it, write
/// `.onFrameChanged` on the view.
public struct GeometryReader: View {
    /// The closure cannot lay out from an invented zero proposal. The empty
    /// reader still accepts space and reports it, before mounting its content.
    @State private var report: FrameReport? = nil

    /// The named spaces the last report travelled with.
    @State private var named: [NamedSpaceFrame] = []
    @State private var insets: EdgeInsets? = nil

    /// What to show, given the space it will live in.
    private let build: (GeometryProxy) -> any View

    /// A reader handing its content closure a proxy of the last report,
    /// rebuilt whenever any space's answer moves.
    ///
    /// - Parameter content: What to show, built again as each measurement
    ///   settles.
    public init(@ViewBuilder _ content: @escaping (GeometryProxy) -> any View) {
        self.build = content
    }

    /// The content, in a Grid that fills the offered space and writes each
    /// report into the state this body reads.
    public var body: some View { AnyView(content) }

    private var content: any View {
        let proxy = report.map { report in
            var report = report
            report.named = named
            report.reportedInsets = insets
            return GeometryProxy(report: report)
        }
        var container = Grid {
            if let proxy { build(proxy) }
        }
        container.node.props[.isGeometryReader] = true.propValue
        return container
        .flex(0)
        .hearing(ViewContract.namedFramesChanged) { frames in
            guard frames != self.named else { return }
            var transaction = Transaction()
            transaction.isGeometryFeedback = true
            withTransaction(transaction) { self.named = frames }
        }
        .hearing(ViewContract.safeAreaInsetsChanged) { insets in
            guard insets != self.insets else { return }
            var transaction = Transaction()
            transaction.isGeometryFeedback = true
            withTransaction(transaction) { self.insets = insets }
        }
        .hearing(ViewContract.frameChanged) { numbers in
            guard let report = FrameReport(numbers), report != self.report else { return }
            var transaction = Transaction()
            transaction.isGeometryFeedback = true
            withTransaction(transaction) { self.report = report }
        }
    }
}

/// One measurement as the host sends it: place, corner and safe area in ten
/// numbers, and the named spaces enclosing the view.
struct FrameReport: Equatable, Sendable {
    /// The frame in the parent's coordinates.
    let frame: Rect

    /// The same rectangle with its origin in the window's.
    let global: Rect

    /// The window's safe area, in the window's coordinates.
    var safeAreaRect: Rect

    /// The named spaces enclosing the view, innermost first, each in window
    /// coordinates; carried by `namedFramesChanged`, which travels with a
    /// report rather than inside its numbers.
    var named: [NamedSpaceFrame] = []
    /// Optional context supplied by hosts that distinguish the allocated
    /// safe proposal from the viewport extending outside it. Legacy hosts
    /// still derive the value from the physical rectangle below.
    var reportedInsets: EdgeInsets?

    /// A report of nothing, before the host's first answer.
    static let zero = FrameReport(
        frame: Rect(0, 0, 0, 0), global: Rect(0, 0, 0, 0), safeAreaRect: Rect(0, 0, 0, 0))

    /// The view's frame measured from the safe area's top left.
    var safeArea: Rect {
        Rect(global.x - safeAreaRect.x, global.y - safeAreaRect.y, frame.width, frame.height)
    }

    /// Where the safe area still covers the view's bounds: positive on each
    /// side the view reaches past it.
    var safeAreaInsets: EdgeInsets {
        if let reportedInsets { return reportedInsets }
        return EdgeInsets(
            top: min(frame.height, max(0, safeAreaRect.y - global.y)),
            leading: min(frame.width, max(0, safeAreaRect.x - global.x)),
            bottom: min(frame.height, max(0, global.y + frame.height - safeAreaRect.y - safeAreaRect.height)),
            trailing: min(frame.width, max(0, global.x + frame.width - safeAreaRect.x - safeAreaRect.width)))
    }

    /// Reads the ten numbers of one report - x, y, width, height, windowX,
    /// windowY, safeX, safeY, safeWidth, safeHeight; any other count is nil.
    init?(_ numbers: [Double]) {
        guard numbers.count == 10 else { return nil }
        frame = Rect(numbers[0], numbers[1], numbers[2], numbers[3])
        global = Rect(numbers[4], numbers[5], numbers[2], numbers[3])
        safeAreaRect = Rect(numbers[6], numbers[7], numbers[8], numbers[9])
    }

    /// Assembles a report from its parts - tests and the empty state.
    init(frame: Rect, global: Rect, safeAreaRect: Rect) {
        self.frame = frame
        self.global = global
        self.safeAreaRect = safeAreaRect
    }

    /// The rectangle a space means.
    func frame(in space: CoordinateSpace) -> Rect {
        switch space {
        case .parent: return frame
        case .global: return global
        case .safeArea: return safeArea
        case .local: return Rect(0, 0, frame.width, frame.height)
        case .named(let name):
            guard let space = named.first(where: { $0.name == name }) else { return Rect(0, 0, 0, 0) }
            return Rect(global.x - space.frame.x, global.y - space.frame.y, frame.width, frame.height)
        }
    }
}

/// One named space enclosing a view: the name an ancestor declared and that
/// ancestor's frame in window coordinates.
public struct NamedSpaceFrame: Equatable, Sendable {
    /// The name `.coordinateSpace` declared.
    public let name: String

    /// The declaring view's frame in window coordinates.
    public let frame: Rect

    /// A space of `name` standing at `frame` in its window.
    public init(name: String, frame: Rect) {
        self.name = name
        self.frame = frame
    }
}

extension NamedSpaceFrame: HostRepresentable {
    /// A name and a frame cross as a string and four numbers.
    public var propValue: PropValue {
        .values([.string(name), .numbers([frame.x, frame.y, frame.width, frame.height])])
    }

    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let values = propValue.values, values.count == 2,
              let name = values[0].string, let numbers = values[1].numbers, numbers.count == 4
        else { return nil }

        self.init(name: name, frame: Rect(numbers[0], numbers[1], numbers[2], numbers[3]))
    }
}

extension View {
    /// Declares this view a named coordinate space: measurements inside it can
    /// ask for their frame in `.named(name)` and read it from here.
    ///
    ///     ScrollView { … }
    ///         .coordinateSpace(.named("CodeEditCoordinateSpace"))
    ///
    ///     GeometryReader { proxy in
    ///         … proxy.frame(in: .named("CodeEditCoordinateSpace")) …
    ///     }
    ///
    /// Only `.named` declares a space; the fixed spaces need no declaring.
    ///
    /// - Parameter space: The space to declare.
    public func coordinateSpace(_ space: CoordinateSpace) -> ModifiedContent {
        guard case .named(let name) = space else {
            return revised { _ in }
        }
        return setting(ViewContract.coordinateSpaceName, name)
    }

    /// Declares this view a named coordinate space under `name` - the older
    /// spelling of `.coordinateSpace(.named(name))`.
    ///
    /// - Parameter name: The space's name.
    public func coordinateSpace(name: String) -> ModifiedContent {
        coordinateSpace(.named(name))
    }
}

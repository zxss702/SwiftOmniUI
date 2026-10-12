// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

/// What a runtime writes out for whoever reads its log rather than its screen: the running tally
/// (`SWIFTOMNIUI_TALLY=1`) and every inspected pass as text (`SWIFTOMNIUI_INSPECT=1`).
/// Design: docs/design/host/patches.md#what-a-runtime-writes-out
@_spi(Host) public struct DiagnosticText {
    /// Whether the running tally is written after a message worth a line.
    public let tallies: Bool

    /// Whether every pass the inspector records is written as text.
    public let inspects: Bool

    /// How many of its own views the host holds alive, written beside the elements alive; nil where it counts none.
    public var views: (() -> Int)?

    private let output: (String) -> Void
    private let timings: DiagnosticTimings?
    private var applies = 0
    private var nodes = 0
    private var made = 0
    private var applyMicros = 0.0
    private var longestMicros = 0.0
    private var printedAt = -Double.infinity
    private var appliedAt = -Double.infinity

    /// Text for the switches given, handed to `write`.
    public init(tallies: Bool, inspects: Bool, write: @escaping (String) -> Void) {
        self.tallies = tallies
        self.inspects = inspects
        self.output = write
        timings = tallies ? DiagnosticTimings(write: write) : nil
    }

    /// The switches this process's environment sets, written to its standard error.
    public static var environment: DiagnosticText {
        DiagnosticText(
            tallies: switched("SWIFTOMNIUI_TALLY"), inspects: switched("SWIFTOMNIUI_INSPECT"), write: HostLog.writeStandardError)
    }

    /// Times a synchronous phase only when the tally is enabled. Copies of the
    /// diagnostic text share these totals, including native work between renders.
    @MainActor public func measure<Result>(_ phase: String, _ body: () -> Result) -> Result {
        guard let timings else { return body() }
        return timings.measure(phase, body)
    }

    /// Writes accumulated phase costs at most every tenth of a second. Times in
    /// different phases can overlap; recursive calls within one phase are timed once.
    @MainActor public func writeTimings(now: Double) {
        timings?.write(now: now)
    }

    /// One message applied, which began at `began` milliseconds on the runtime's clock.
    mutating func applied(_ tally: RenderTally, began: Double, core: CoreLink) {
        if inspects {
            let passes = core.takeInspectionLog()
            if !passes.isEmpty { output(passes) }
        }
        guard tallies else { return }

        let micros = RenderTally.micros(ContinuousClock.now - tally.began)
        applies += 1
        nodes += tally.nodes
        made += tally.made
        applyMicros += micros
        longestMicros = max(longestMicros, micros)

        let quiet = began - appliedAt
        appliedAt = began
        guard began - printedAt >= 100 || quiet >= 333 else { return }
        printedAt = began
        output(line(core.tally))
    }

    /// The running totals, as one line.
    private func line(_ core: HostTally) -> String {
        "SwiftOmniUI tally: applies \(applies)  nodes \(nodes)  made \(made)  kept \(nodes - made)  "
            + "renders \(core.renders)  empty \(core.empty)  refused \(core.refused)  alive \(core.alive)  "
            + (views.map { "views \($0())  " } ?? "")
            + "apply \(Self.milliseconds(applyMicros / Double(applies))) ms avg / "
            + "\(Self.milliseconds(longestMicros)) ms worst / \(Self.milliseconds(applyMicros)) ms total\n"
    }

    /// Microseconds as milliseconds with two decimals.
    fileprivate static func milliseconds(_ micros: Double) -> String {
        let hundredths = Int((micros / 10).rounded())
        let fraction = hundredths % 100
        return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    private static func switched(_ name: String) -> Bool {
        #if os(Windows)
        var value: UnsafeMutablePointer<CChar>?
        var count = 0
        guard _dupenv_s(&value, &count, name) == 0, let value else { return false }
        defer { free(value) }
        return String(cString: value) == "1"
        #else
        return getenv(name).map { String(cString: $0) == "1" } ?? false
        #endif
    }
}

/// Phase totals are kept apart from patch costs: XAML can do most of its work
/// after a patch and its window presentation have returned.
final class DiagnosticTimings {
    private struct Sample {
        var calls = 0
        var roots = 0
        var micros = 0.0
        var worst = 0.0
    }

    private var samples: [String: Sample] = [:]
    private var active: Set<String> = []
    private var printedAt = -Double.infinity
    private var changed = false
    private let output: (String) -> Void

    init(write: @escaping (String) -> Void) { output = write }

    func measure<Result>(_ phase: String, _ body: () -> Result) -> Result {
        samples[phase, default: Sample()].calls += 1
        // A native Measure recursively calls Measure on its children. Count all
        // calls, but charge elapsed time only to the outer call of this phase.
        guard active.insert(phase).inserted else { return body() }
        let began = ContinuousClock.now
        defer {
            active.remove(phase)
            let micros = RenderTally.micros(ContinuousClock.now - began)
            var sample = samples[phase] ?? Sample()
            sample.roots += 1
            sample.micros += micros
            sample.worst = max(sample.worst, micros)
            samples[phase] = sample
            changed = true
        }
        return body()
    }

    func write(now: Double) {
        guard changed, now - printedAt >= 100 else { return }
        printedAt = now
        changed = false
        let phases = samples.keys.sorted().compactMap { phase -> String? in
            guard let sample = samples[phase], sample.roots > 0 else { return nil }
            return "\(phase) calls \(sample.calls) roots \(sample.roots) "
                + "\(DiagnosticText.milliseconds(sample.micros / Double(sample.roots))) ms avg / "
                + "\(DiagnosticText.milliseconds(sample.worst)) ms worst / "
                + "\(DiagnosticText.milliseconds(sample.micros)) ms total"
        }
        output("SwiftOmniUI timings: " + phases.joined(separator: " | ") + "\n")
    }
}

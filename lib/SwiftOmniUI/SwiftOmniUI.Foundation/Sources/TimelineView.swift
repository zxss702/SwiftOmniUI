// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `TimelineView`: content rebuilt on a schedule's tick, handed the current
// date. Foundation-free SwiftOmniUI carries the ticker; the `Date` it is read as
// lives here where Foundation stands.

import Foundation
@_spi(Host) import SwiftOmniUICore

/// When a `TimelineView` rebuilds. A value type carrying the interval - the
/// one spelling SCE needs - rather than SwiftUI's protocol of schedules.
public struct TimelineSchedule: Equatable, Sendable {
    /// How long between updates, or nil to run only when told.
    let minimumInterval: Duration?

    /// Whether ticks pause for now.
    let paused: Bool

    /// Updates at the display's pace - `minimumInterval` apart - pausing
    /// while `paused` holds.
    public static func animation(
        minimumInterval: Double? = nil,
        paused: Bool = false
    ) -> TimelineSchedule {
        TimelineSchedule(
            minimumInterval: minimumInterval.map { .seconds($0) },
            paused: paused)
    }
}

/// A `TimelineView` rebuild's moment - hoisted out of the generic, whose
/// `Context` as a nested type would block the content's inference.
public struct TimelineViewContext: Sendable {
    /// When this build stands.
    public var date: Date
}

/// A view rebuilt on a schedule, each rebuild handed the current date:
///
///     TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
///         Circle().opacity(pulse(at: context.date))
///     }
public struct TimelineView<Content: View>: View {
    /// A rebuild's moment - `context.date`, as SwiftUI spells it.
    public typealias Context = TimelineViewContext

    /// The schedule the ticks follow.
    let schedule: TimelineSchedule

    /// What each rebuild draws with its moment.
    let content: (Context) -> Content

    /// The clock - kept across rebuilds, started while the view stands.
    @State private var ticker = Ticker(every: .seconds(1))

    public init(
        _ schedule: TimelineSchedule,
        @ViewBuilder content: @escaping (Context) -> Content
    ) {
        self.schedule = schedule
        self.content = content
    }

    public var body: some View {
        // Reading the count binds the build to the ticker's pulse.
        _ = ticker.ticks

        if let interval = schedule.minimumInterval, ticker.interval != interval {
            ticker.interval = interval
        }
        if schedule.paused {
            if ticker.isRunning { ticker.stop() }
        } else if schedule.minimumInterval != nil, !ticker.isRunning {
            ticker.start()
        }

        return content(Context(date: Date()))
            .onDisappear { ticker.stop() }
    }
}

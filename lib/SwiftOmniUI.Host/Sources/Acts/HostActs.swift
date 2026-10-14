// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The acts every host performs itself - the application calls them and no control of its own stands behind them -
/// and how the ones that ask the time are read and answered, the same on every host.
/// Design: docs/design/host/runtime.md#acts
@_spi(Host) public enum HostActs {
    /// The acts every host performs: the focus, the questions for the user and a word to a screen reader, the time
    /// and the zones, the on-screen keyboard, a kept value, and a handler's failure told.
    public static let performed: [any ContractMember] = [
        VisualElementContract.focus, VisualElementContract.unfocus,
        AppContract.alert, AppContract.announce, AppContract.chooseAction,
        AppContract.confirm, AppContract.copyText, AppContract.currentTime, AppContract.currentTimeZone,
        AppContract.handlerFailed, AppContract.hideOnScreenKeyboard, AppContract.localizedString,
        AppContract.persistValue, AppContract.prompt, AppContract.utcOffset,
    ]

    /// The acts a host with a `FileToolkit` performs: the files the user opens and saves, read, and what the system
    /// launches.
    public static let files: [any ContractMember] = [
        AppContract.openFiles, AppContract.openFolders, AppContract.saveFile, AppContract.readFile,
        AppContract.launchFile, AppContract.launchLink, AppContract.revealFile,
    ]

    /// The answer to `currentTime`: the hour, the minute, the second and the millisecond of the local time.
    public static func currentTime(hour: Int, minute: Int, second: Int, millisecond: Int) -> [HostValue] {
        [[Double(hour), Double(minute), Double(second), Double(millisecond)].propValue]
    }

    /// What `utcOffset` asks of: a zone by its name - nil for the local one - on a day - nil for today.
    public static func utcOffsetQuestion(_ call: HostActCall) -> (zone: String?, day: CalendarDate?) {
        (call.arguments.value(0)?.string, call.arguments.value(1).flatMap { CalendarDate(propValue: $0) })
    }

    /// The answer to `utcOffset`: how far the zone is from UTC, in minutes.
    public static func utcOffset(minutes: Int) -> [HostValue] {
        [.number(Double(minutes))]
    }

    /// Why `utcOffset` fails for a zone the platform does not know.
    public static func unknownZone(_ name: String?) -> ActFailure {
        ActFailure("no time zone '\(name ?? "")' is known")
    }
}

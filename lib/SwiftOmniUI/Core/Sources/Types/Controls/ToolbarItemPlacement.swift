// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Where a toolbar item goes in the platform's native action surface.
public enum ToolbarItemPlacement: Int32, Sendable {
    /// Wherever the platform normally puts an item.
    case automatic = 0

    /// On the bar itself, where it can be chosen straight away.
    case bar = 1

    /// Behind the native overflow menu.
    case overflow = 2

    /// The action the page exists for - `Button("Done")` in a sheet's
    /// `.confirmationAction` stands beside it.
    case primaryAction = 3

    /// The confirming action - a sheet's "Done".
    case confirmationAction = 4

    /// The cancelling action - a sheet's "Cancel", at the bar's leading side.
    case cancellationAction = 5

    /// Navigational furniture - the undo of `ToolbarItemGroup(placement: .navigation)` -
    /// at the bar's leading side.
    case navigation = 6

    /// The item the bar centres on, where the platform centres one.
    case principal = 7

    /// A status readout, where the bar keeps one.
    case status = 8

    /// The destructive action - a sheet's "Delete".
    case destructiveAction = 9

    /// The search field installed by `searchable`, after the page's actions
    /// at the toolbar's trailing edge.
    case search = 10
}

extension ToolbarItemPlacement: HostRepresentable {}

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.

/// How a `ToolbarSpacer` takes room - what `ToolbarSpacer(_:placement:)` takes.
public enum ToolbarSpacerVariant: Int32, Sendable {
    /// All the room between the items it separates, pushing them apart.
    case flexible = 0

    /// The platform's ordinary gap between two items.
    case fixed = 1
}

extension ToolbarSpacerVariant: HostRepresentable {}

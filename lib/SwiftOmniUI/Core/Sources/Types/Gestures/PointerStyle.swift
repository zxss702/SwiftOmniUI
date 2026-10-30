// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// The pointer's look while it is over the view - what `.pointerStyle` takes
/// on a platform with a pointer at all:
///
///     Text("Resize")
///         .pointerStyle(.rowResize)
public enum PointerStyle: Int32, Sendable {
    /// Whatever the platform shows - the arrow.
    case `default` = 0

    /// The I-beam of text that selects.
    case text = 1

    /// The I-beam of text running down the page.
    case verticalText = 2

    /// The I-beam of text running across it.
    case horizontalText = 3

    /// The pointing hand of a link.
    case link = 4

    /// The open hand over what can be grabbed.
    case grabIdle = 5

    /// The closed hand while it is grabbed.
    case grabActive = 6

    /// The arrow with a copy badge while a drag offers one.
    case dragCopy = 7

    /// The arrow with a link badge while a drag offers one.
    case dragLink = 8

    /// The slashed circle where a drag cannot land.
    case operationNotAllowed = 9

    /// The cross of a rectangle being dragged out.
    case rectangleSelection = 10

    /// The I-beam over text that only reads.
    case alertText = 11

    /// The two-way arrow over a column's edge.
    case columnResize = 12

    /// The two-way arrow over a row's edge.
    case rowResize = 13

    /// The two-way arrow over a frame's edge - the corner or side it grabs is
    /// the platform's, `inward` says which way the frame grows.
    case frameResize = 14
}

extension PointerStyle: HostRepresentable {}
extension PointerStyle: StateChoice {}

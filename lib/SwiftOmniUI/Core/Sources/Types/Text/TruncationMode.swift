// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Where a line that will not fit is cut, with an ellipsis at the cut -
/// `.truncationMode`'s choice, a `LineBreak` said the SwiftUI way.
public enum TruncationMode: Sendable {
    /// The line keeps its end; the ellipsis stands at its start - a file
    /// path's tail, where the name outlives the folders.
    case head

    /// The line keeps its start; the ellipsis stands at its end.
    case tail

    /// The line keeps both ends; the ellipsis stands in its middle.
    case middle

    /// The `LineBreak` the same cut goes by.
    var lineBreak: LineBreak {
        switch self {
        case .head: .headTruncation
        case .tail: .tailTruncation
        case .middle: .middleTruncation
        }
    }
}

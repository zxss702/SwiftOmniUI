// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A scroll view's geometry: content offset, content size, content insets, and container size.
public struct ScrollGeometry: Equatable, Sendable {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize

    public init(
        contentOffset: CGPoint = .zero,
        contentSize: CGSize = .zero,
        contentInsets: EdgeInsets = EdgeInsets(0),
        containerSize: CGSize = .zero
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }

    public var visibleRect: CGRect {
        CGRect(origin: contentOffset, size: containerSize)
    }

    public var bounds: CGRect {
        CGRect(
            x: -contentInsets.left,
            y: -contentInsets.top,
            width: contentSize.width + contentInsets.left + contentInsets.right,
            height: contentSize.height + contentInsets.top + contentInsets.bottom
        )
    }

    init?(numbers: [Double]) {
        guard numbers.count == 10 else { return nil }
        var insets = EdgeInsets(0)
        insets.top = numbers[4]
        insets.left = numbers[5]
        insets.bottom = numbers[6]
        insets.right = numbers[7]
        self.init(
            contentOffset: CGPoint(x: numbers[0], y: numbers[1]),
            contentSize: CGSize(width: numbers[2], height: numbers[3]),
            contentInsets: insets,
            containerSize: CGSize(width: numbers[8], height: numbers[9])
        )
    }
}

/// The phase of a scroll interaction on a scrollable view.
public enum ScrollPhase: Hashable, Sendable {
    case idle
    case tracking
    case interacting
    case decelerating
    case animating

    public var isScrolling: Bool {
        self != .idle
    }
}

/// Context provided when a scroll view's phase changes.
public struct ScrollPhaseChangeContext: Sendable {
    public let geometry: ScrollGeometry
    public let velocity: CGSize?

    public init(geometry: ScrollGeometry = ScrollGeometry(), velocity: CGSize? = nil) {
        self.geometry = geometry
        self.velocity = velocity
    }
}

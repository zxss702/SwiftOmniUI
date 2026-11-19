// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The arithmetic of a container with one child - a page, a pane: the child within its padding.
/// Design: docs/design/host/layout.md#one-child
@_spi(Host) public enum SingleChildArithmetic {
    /// The room the child and the padding take for the width offered; the padding alone without a shown child.
    @MainActor
    public static func size<Child: LayoutChild>(
        of item: Child?, padding: EdgeInsets, width offered: Double?, height: Double? = nil
    ) -> LayoutSize {
        guard let item, item.isShown else {
            return LayoutSize(width: padding.left + padding.right, height: padding.top + padding.bottom)
        }

        let margin = item.values.margin
        let width = offered.map { max(0, $0 - padding.left - padding.right - margin.left - margin.right) }
        let size = if let height {
            item.size(offered: ProposedViewSize(
                width: width, height: max(0, height - padding.top - padding.bottom - margin.top - margin.bottom)))
        } else {
            item.size(offered: width)
        }
        return LayoutSize(
            width: padding.left + padding.right + margin.left + margin.right + size.width,
            height: padding.top + padding.bottom + margin.top + margin.bottom + size.height)
    }

    /// Where the child stands in `room`, within `padding`; right to left, turned about the room's middle.
    @MainActor
    public static func place<Child: LayoutChild>(
        of item: Child, in room: Rect, padding: EdgeInsets, direction: LayoutDirection
    ) -> Rect {
        direction.places(leftToRight(of: item, in: room, padding: padding), in: room)
    }

    /// The place as a layout written left to right has it.
    @MainActor
    private static func leftToRight<Child: LayoutChild>(of item: Child, in room: Rect, padding: EdgeInsets) -> Rect {
        let content = room.inset(padding)
        let values = item.values
        let margin = values.margin
        let availableWidth = max(0, content.width - margin.left - margin.right)
        let availableHeight = max(0, content.height - margin.top - margin.bottom)
        let expandsAcross = values.flex != nil || values.expandingAxes == .horizontal || values.expandingAxes == .both
        let expandsDown = values.flex != nil || values.expandingAxes == .vertical || values.expandingAxes == .both
        let frame = values.isFrameContent
        let needsNatural = (!expandsAcross && values.horizontal != 3 && values.width == nil)
            || (!expandsDown && values.vertical != 3 && values.height == nil)
        let natural = if !needsNatural {
            LayoutSize.zero
        } else if frame {
            item.size(offered: ProposedViewSize(width: availableWidth, height: availableHeight))
        } else {
            item.size(offered: availableWidth)
        }
        let width = Extent.of(
            option: expandsAcross ? 3 : values.horizontal, stated: values.width, natural: natural.width,
            available: availableWidth, minimum: values.minimumWidth, maximum: values.maximumWidth, allowsOverflow: frame)
        let height = Extent.of(
            option: expandsDown ? 3 : values.vertical, stated: values.height, natural: natural.height,
            available: availableHeight, minimum: values.minimumHeight, maximum: values.maximumHeight, allowsOverflow: frame)

        return Rect(
            x: Extent.start(option: values.horizontal, extent: width, start: content.x + margin.left,
                            available: availableWidth, allowsOverflow: frame),
            y: Extent.start(option: values.vertical, extent: height, start: content.y + margin.top,
                            available: availableHeight, allowsOverflow: frame),
            width: width,
            height: height)
    }
}

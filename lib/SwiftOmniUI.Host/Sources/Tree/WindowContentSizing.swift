// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Content constraints combined with the window's explicit constraints, in DIPs.
@_spi(Host) @MainActor public struct WindowContentSizing {
    public var bounds: WindowBounds

    /// The window's bounds as the content's measures read them: its natural
    /// size, the smallest it still reads at, and what it declares, each held
    /// against what the window already allows.
    public init(
        of window: MountedElement, content: MountedElement?,
        measure: (MountedElement, Double?) -> LayoutSize?
    ) {
        bounds = WindowBounds(of: window)
        let requested = window.value(.resizability)?.enumeration ?? WindowResizability.automatic.rawValue
        let mode = requested == WindowResizability.automatic.rawValue ? WindowResizability.contentMinSize.rawValue : requested
        guard mode == WindowResizability.contentSize.rawValue || mode == WindowResizability.contentMinSize.rawValue,
              let content, let natural = measure(content, nil) else { return }
        let small = measure(content, 0) ?? natural
        let minimum = LayoutSize(width: min(natural.width, small.width), height: min(natural.height, small.height))
        let declared = Self.declared(content, natural: natural, measure: measure)
        bounds.minimumWidth = max(bounds.minimumWidth ?? 0, declared.minimumWidth ?? minimum.width)
        bounds.minimumHeight = max(bounds.minimumHeight ?? 0, declared.minimumHeight ?? minimum.height)
        let sized = mode == WindowResizability.contentSize.rawValue
        bounds.maximumWidth = Self.upper(bounds.maximumWidth, sized ? declared.maximumWidth : nil, bounds.minimumWidth)
        bounds.maximumHeight = Self.upper(bounds.maximumHeight, sized ? declared.maximumHeight : nil, bounds.minimumHeight)
    }

    /// Whether any size but the one bounds holds is still open.
    public var isResizable: Bool {
        bounds.minimumWidth != bounds.maximumWidth || bounds.minimumWidth == nil
            || bounds.minimumHeight != bounds.maximumHeight || bounds.minimumHeight == nil
    }

    private static func declared(
        _ content: MountedElement, natural: LayoutSize,
        measure: (MountedElement, Double?) -> LayoutSize?
    ) -> WindowBounds {
        var result = WindowBounds()
        var node: MountedElement? = content
        var widthSaid = false
        var heightSaid = false
        while let current = node, let size = measure(current, nil) {
            let values = current.layoutValues
            let across = values.margin.left + values.margin.right + max(0, natural.width - size.width)
            let down = values.margin.top + values.margin.bottom + max(0, natural.height - size.height)
            if !widthSaid, values.width != nil || current.value(.minimumWidth) != nil || current.value(.maximumWidth) != nil {
                let range = axis(values.width, values.minimumWidth, values.maximumWidth, outside: across)
                result.minimumWidth = range.0
                result.maximumWidth = range.1
                widthSaid = true
            }
            if !heightSaid, values.height != nil || current.value(.minimumHeight) != nil || current.value(.maximumHeight) != nil {
                let range = axis(values.height, values.minimumHeight, values.maximumHeight, outside: down)
                result.minimumHeight = range.0
                result.maximumHeight = range.1
                heightSaid = true
            }
            let compressible = values.flex != nil
                || (current.type == .image && current.value(ImageContract.isResizable.token)?.bool == true)
            if !widthSaid, compressible || values.scrollAxes == .horizontal || values.scrollAxes == .both {
                result.minimumWidth = across
                widthSaid = true
            }
            if !heightSaid, compressible || values.scrollAxes == .vertical || values.scrollAxes == .both {
                result.minimumHeight = down
                heightSaid = true
            }
            if widthSaid && heightSaid { break }
            let children = current.arrangedChildren.filter { $0.standsShown && !$0.isDeparting }
            let occupying = children.filter {
                guard let size = measure($0, nil) else { return false }
                return size.width > 0 || size.height > 0
            }
            node = children.count == 1 ? children.first : (occupying.count == 1 ? occupying.first : nil)
        }
        return result
    }

    private static func axis(_ fixed: Double?, _ minimum: Double?, _ maximum: Double?, outside: Double) -> (Double?, Double?) {
        if let fixed {
            let size = Extent.bounded(fixed, minimum: minimum, maximum: maximum) + outside
            return (size, size)
        }
        return ((minimum ?? 0) + outside, maximum.flatMap { $0.isFinite ? $0 + outside : nil })
    }

    private static func upper(_ explicit: Double?, _ content: Double?, _ minimum: Double?) -> Double? {
        [explicit, content].compactMap { $0 }.min().map { max($0, minimum ?? 0) }
    }

    /// A measured size held to the bounds: the frame's delta is the part the
    /// bounds refused.
    public func constrain(_ size: LayoutSize) -> WindowFrame {
        let width = Extent.bounded(size.width, minimum: bounds.minimumWidth, maximum: bounds.maximumWidth)
        let height = Extent.bounded(size.height, minimum: bounds.minimumHeight, maximum: bounds.maximumHeight)
        return WindowFrame(width: width != size.width ? width : nil, height: height != size.height ? height : nil)
    }
}

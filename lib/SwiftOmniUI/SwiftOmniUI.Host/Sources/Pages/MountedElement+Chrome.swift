// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What a page gives the chrome it stands under, the same on every host - a window's one chrome, or a header bar of
/// its own: its actions, and the colours of its bar.
/// Design: docs/design/host/pages.md#the-windows-chrome
extension MountedElement {
    /// This page's actions for its chrome: the leading group - navigation and
    /// the cancelling action - the bar's own items, and those placed behind
    /// the overflow. Each group is by priority, then in the order written;
    /// none where the page hides its bar.
    ///
    /// The entries are the page's `toolbarItems` slot's, and those every
    /// `.toolbar { … }` under it wrote - a slot under a nested arrangement is
    /// that arrangement's own.
    public var chromeActions: (leading: [MountedElement], primary: [MountedElement], overflow: [MountedElement]) {
        guard pageValue(.hasNavigationBar)?.bool != false else { return ([], [], []) }

        var items: [MountedElement] = []
        gatherToolbarItems(under: self, into: &items)
        guard !items.isEmpty else { return ([], [], []) }

        let ordered = items.enumerated().sorted {
            let left = $0.element.value(.priority)?.number ?? 0
            let right = $1.element.value(.priority)?.number ?? 0
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)

        var leading: [MountedElement] = []
        var primary: [MountedElement] = []
        var search: [MountedElement] = []
        var overflow: [MountedElement] = []
        for item in ordered {
            switch ToolbarItemPlacement(rawValue: item.value(.placement)?.enumeration ?? 0) ?? .automatic {
            case .navigation, .cancellationAction:
                leading.append(item)
            case .overflow:
                overflow.append(item)
            case .search:
                search.append(item)
            default:
                primary.append(item)
            }
        }
        return (leading, primary + search, overflow)
    }

    /// The toolbar entries under `element` - its `toolbarItems` slots'
    /// children, in tree order, not reaching into a nested arrangement's own.
    private func gatherToolbarItems(under element: MountedElement, into items: inout [MountedElement]) {
        for child in element.children where !child.isDeparting {
            if child.type == .toolbarItems {
                items.append(contentsOf: child.children.filter {
                    !$0.isDeparting && ($0.type == .toolbarItem || $0.type == .toolbarSpacer)
                })
            } else if !NodeType.pageTypes.contains(child.type) {
                gatherToolbarItems(under: child, into: &items)
            }
        }
    }

    /// The colours this element's bar is painted in: the nearest stack's or tabbed view's around it, itself included,
    /// and what stands on the bar in, the nearest stack's - else its window's title bar's.
    public var barColors: (background: HostValue?, foreground: HostValue?) {
        var background: HostValue?
        var foreground: HostValue?
        var each: MountedElement? = self
        while let element = each, background == nil || foreground == nil {
            switch element.type {
            case .navigationStack:
                background = background ?? element.value(.barBackgroundColor)
                foreground = foreground ?? element.value(.barForegroundColor)
            case .tabView:
                background = background ?? element.value(.barBackgroundColor)
            case .windowScene:
                let titleBar = element.children.first { $0.type == .titleBar }
                background = background ?? titleBar?.value(.background)
                foreground = foreground ?? titleBar?.value(.barForegroundColor)
            default:
                break
            }
            each = element.parent
        }
        return (background, foreground)
    }
}

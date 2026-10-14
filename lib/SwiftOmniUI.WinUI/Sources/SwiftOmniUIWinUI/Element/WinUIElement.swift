// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The WinUI half of a mounted element: its native element and everything hung on it.
/// Design: docs/design/host/tree.md#the-native-half
@MainActor
final class WinUIElement: NativeElement {
    /// The element of the mounted tree this is the WinUI half of; it owns this half.
    unowned let element: MountedElement

    /// The element's view; nil for an element drawn by its parent's, or none.
    private(set) var view: WinUIView?

    weak var host: WinUIRenderer?

    /// Whether a label shows its spans' runs in place of its own words.
    var hasRuns = false

    /// Whether the view was last given a context menu, and whether its menu changed in this patch.
    var hadContextMenu = false
    var contextMenuChanged = false

    init(_ element: MountedElement, host: WinUIRenderer) {
        self.element = element
        self.host = host
        view = makeView()
        view?.sourceElement = element
        if element.value(.blur) != nil || element.driven[.blur] != nil
            || element.transition?.insertion.blur != nil || element.transition?.removal.blur != nil {
            view?.prepareBlur()
        }
    }

    // MARK: - The element's tree, read through its mounted element

    var type: NodeType { element.type }
    var parent: WinUIElement? { element.parent?.winUI }
    var children: [WinUIElement] { element.children.map(\.winUI) }
    func value(_ property: Prop) -> HostValue? { element.value(property) }

    // MARK: - The native half's part in a patch

    var presentsView: Bool { view != nil }

    func standingValue(_ property: Prop) -> HostValue? {
        switch (type, property) {
        case (_, .opacity): view.map { .number($0.opacity) }
        case (_, .blur): view.map { .number($0.blur) }
        case (.slider, .value): (view as? WinUISliderView).map { .number($0.value) }
        default: nil
        }
    }

    func animates(_ property: Prop) -> Bool {
        (presentsView && (property == .blur || TransitionSurface.presentsDrawing(property)))
            || TransitionSurface.presents(property, on: type)
    }

    func applied(changed: Set<Prop>, wasDescribed: Bool) {
        if wasDescribed, changed.contains(.isVisible) { crossVisibility() }
        applyProperties(changed: changed)
        if let view, let host { element.applyDrawnChildren(to: view, through: WinUIRegistrations.registry, in: host.runtime) }
        configureGestures()
        view?.setFocusChanged(element.handler(.isFocusedChanged) == nil ? nil : { [weak self] focused in
            self?.send(.isFocusedChanged, [.bool(focused)])
        })
        configureLayoutMotion()
        arrangeChildren()
        arrangePages(changed: changed)
        if changed.contains(.preferredColumnWidth) || (element.childrenChanged && parent?.type == .navigationSplitView),
           let split = element.parent?.enclosing(type: .navigationSplitView)?.winUI {
            split.arrangeChildren()
        }
        var declared = element.enclosing(type: .contextMenu)
        while let owner = declared?.parent?.winUI {
            owner.contextMenuChanged = true
            declared = owner.element.parent?.enclosing(type: .contextMenu)
        }
        refreshContextMenu()
        if let view { host?.runtime.frames.follow(self, order: view.number, reads: readsFrame) }
    }

    func presentFrame(_ changed: Set<Prop>) {
        applyProperties(changed: changed)
    }

    func departureChanged() {
        view?.setIgnoresInput(element.isDeparting || element.value(.ignoresInput)?.bool == true)
    }

    func leave() {
        if let view { host?.runtime.frames.follow(self, order: view.number, reads: false) }
        view?.detach()
    }
}

extension MountedElement {
    /// This element's WinUI half.
    var winUI: WinUIElement { native as! WinUIElement }
}

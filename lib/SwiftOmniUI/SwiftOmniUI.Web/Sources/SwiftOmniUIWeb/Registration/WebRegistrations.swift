// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The contracts this host realizes through the core's registry: how each element's view is made, which of its
/// members the view takes, and what it reports.
@MainActor
enum WebRegistrations {
    /// The registry, built once.
    static let registry: Registry<WebDOMView> = {
        let registry = Registry<WebDOMView>()

        words(registry)
        toggles(registry)
        values(registry)
        indicators(registry)
        pickers(registry)
        dates(registry)
        shapes(registry)
        canvas(registry)
        items(registry)
        web(registry)
        fields(registry)
        layouts(registry)
        pictures(registry)
        shared(registry)

        return registry
    }()

    /// What `WebElement` puts on every view wearing each member's contract, and what the host layer's rules realize on
    /// every element the page shows: its place, its drawing over it, its words for assistive technology, the way its
    /// words run, where it stands, and the user's taps, presses, pinches and swipes and the pointer over it.
    static func shared(_ registry: Registry<WebDOMView>) {
        registry.everyElementRealizes(VisualElementContract.opacity)
        registry.everyElementRealizes(VisualElementContract.isVisible)
        registry.everyElementRealizes(VisualElementContract.isEnabled)
        registry.everyElementRaises(VisualElementContract.isFocusedChanged)
        registry.everyElementRealizes(VisualElementContract.background)
        registry.everyElementRealizes(VisualElementContract.ignoresInput)
        registry.everyElementRealizes(VisualElementContract.layoutDirection)
        registry.everyElementTakesItsPlace()
        registry.everyElementIsDrawnOverItsPlace()
        registry.everyElementMeetsAssistiveTechnology(identifying: true)
        registry.everyElementHearsTheUser()
        registry.everyElementDragsAndDrops()
    }
}

extension Registry {
    /// Every element's view is dragged between views and takes what is dropped on it - words or files - by this
    /// host's own rules (`WebElement.listenForTheUser` reads `dragOffer`, `hearDrop` says what came); the host
    /// layer keeps no `DragAndDrop` for this boundary, so the members stand here.
    /// Design: docs/design/host/runtime.md#a-drag-between-views
    func everyElementDragsAndDrops() {
        everyElementRealizes(ViewContract.canDrag)
        everyElementRealizes(ViewContract.dragText)
        everyElementRealizes(ViewContract.allowDrop)
        everyElementRaises(ViewContract.dragStarting)
        everyElementRaises(ViewContract.dropCompleted)
        everyElementRaises(ViewContract.dragOver)
        everyElementRaises(ViewContract.dragLeave)
        everyElementRaises(ViewContract.drop)
        everyElementRaises(ViewContract.dropPaths)
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The contracts this host realizes through the core's registry: how each element's view is made, which of its
/// members the view takes, and what it reports.
@MainActor
enum GTKRegistrations {
    /// The registry, built once.
    static let registry: Registry<GTKView> = {
        let registry = Registry<GTKView>()

        text(registry)
        buttons(registry)
        toggles(registry)
        values(registry)
        indicators(registry)
        pickers(registry)
        dates(registry)
        fields(registry)
        layouts(registry)
        pictures(registry)
        shapes(registry)
        drawing(registry)
        items(registry)
        popovers(registry)
        shared(registry)

        return registry
    }()

    /// What `GTKElement` puts on every view wearing each member's contract, and what the host layer's rules realize
    /// on every element GTK shows.
    static func shared(_ registry: Registry<GTKView>) {
        registry.everyElementRealizes(VisualElementContract.opacity)
        registry.everyElementRealizes(VisualElementContract.isVisible)
        registry.everyElementRealizes(VisualElementContract.transition)
        registry.everyElementRealizes(VisualElementContract.isEnabled)
        // GTK 4.14 gives an accessible no identifier of its own: it is met by its role, its label and its place.
        registry.everyElementMeetsAssistiveTechnology(identifying: false)
        registry.everyElementTakesItsPlace()
        registry.everyElementIsDrawnOverItsPlace()
        registry.everyElementHearsTheUser()
        registry.everyElementRaises(VisualElementContract.isFocusedChanged)
    }

    /// The acts `GTKActPerformer` performs.
    static let acts: [any ContractMember] = [
        VisualElementContract.focus, VisualElementContract.unfocus,
        AppContract.alert, AppContract.announce, AppContract.chooseAction,
        AppContract.chooseFiles, AppContract.copyText, AppContract.openFolders,
        AppContract.revealFile, AppContract.launchFile, AppContract.launchLink,
        AppContract.confirm, AppContract.currentTime, AppContract.currentTimeZone,
        AppContract.handlerFailed, AppContract.hideOnScreenKeyboard, AppContract.persistValue,
        AppContract.prompt, AppContract.utcOffset, CanvasContract.measureText,
        ListContract.scrollTo, ScrollViewContract.scrollToDescendant,
    ]

}

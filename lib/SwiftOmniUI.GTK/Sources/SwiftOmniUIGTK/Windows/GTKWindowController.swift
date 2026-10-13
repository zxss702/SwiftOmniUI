// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// One window element shown in a GTK window: what the host layer says it shows - its arrangement of pages, its
/// sheets, its overlay, the window it belongs to and its chrome - turned into GTK's, in step with the element as
/// the tree changes.
/// Design: docs/design/platforms/gtk/runtime.md#the-window
@MainActor
final class GTKWindowController {
    /// The window element shown.
    private(set) weak var element: MountedElement?

    /// The GTK window it is shown in.
    let window: GTKWindow

    /// What the window shows, by the host layer's rule.
    private let presentation = WindowPresentation()

    /// A sheet for each page the window's modal stack presents, the last on top.
    private(set) var sheets: [(element: MountedElement, sheet: GTKSheet)] = []

    /// The header currently hosting commands, including one in a tab that may become inactive.
    private weak var commandsFrame: GTKPageFrame?

    /// The arrangement of pages the window shows.
    var arrangement: MountedElement? { presentation.arrangement }

    init(_ element: MountedElement, application: UnsafeMutablePointer<GtkApplication>) {
        self.element = element
        window = GTKWindow(application: application)
    }

    /// Shows what the element asks for now, the window it belongs to found by `windowOf`.
    func present(_ element: MountedElement, in runtime: HostRuntime, windowOf: (MountedElement) -> GTKWindow?) {
        self.element = element

        let changes = presentation.show(element, in: runtime.lifecycle)
        if let owner = changes.owner { window.setOwner(owner.flatMap(windowOf)) }
        if let hidden = changes.hidden { window.setHidden(hidden) }
        let arrangement = presentation.arrangement
        if let arrangement {
            let shown = Self.shownArrangement(arrangement)
            if GTKElement.framedTypes.contains(shown.type) {
                window.show(page: arrangement.gtk.view)
            } else {
                window.show(arrangement.gtk.view)
            }
        } else {
            window.show(nil)
        }
        if let overlay = changes.overlay { window.showOverlay(overlay?.gtk.view) }
        if let pages = changes.sheets { showSheets(pages, in: runtime) }
        refreshChrome()
        let sizing = WindowContentSizing(of: element, content: presentation.arrangement) { node, width in
            guard let item = node.gtk.layoutItem else { return nil }
            return SingleChildArithmetic.size(of: item, padding: EdgeInsets(0), width: width)
        }
        window.apply(sizing)
        window.setSize(width: element.value(.width)?.number, height: element.value(.height)?.number)
        window.presentContent()
    }

    /// Takes the window down - the tree no longer holds it: its sheets first, then the window.
    func close() {
        for entry in sheets.reversed() { entry.sheet.close() }
        sheets = []
        window.destroy()
    }

    /// Keeps a sheet for each page presented, in its order: a sheet gone closes, the last first, and one new is
    /// shown over those before it.
    /// Design: docs/design/platforms/gtk/pages.md#sheets
    private func showSheets(_ pages: [MountedElement], in runtime: HostRuntime) {
        let kept = sheets.filter { entry in
            pages.contains { $0 === entry.element && $0.gtk.view === entry.sheet.page }
        }
        for entry in sheets.reversed() where !kept.contains(where: { $0.sheet === entry.sheet }) { entry.sheet.close() }
        sheets = pages.compactMap { page in
            if let entry = kept.first(where: { $0.element === page }) { return entry }
            let shown = Self.shownArrangement(page)
            guard let view = page.gtk.view else { return nil }
            let sheet = GTKSheet(page: view, framed: GTKElement.framedTypes.contains(shown.type))
            sheet.onClosedByUser = { [weak self, weak runtime] in
                guard let runtime else { return }
                self?.dismissTopSheet(in: runtime)
            }
            sheet.present(over: window)
            return (page, sheet)
        }
    }

    /// The user took the top sheet away - Escape, its close button: the modal stack is told how many remain.
    private func dismissTopSheet(in runtime: HostRuntime) {
        guard let element, !presentation.sheets.isEmpty else { return }
        runtime.goBack(.dismissSheet(remaining: presentation.sheets.count - 1), in: element)
    }

    /// Writes every shown page's chrome on its header bar, and names the window after the page the user sees.
    /// Design: docs/design/platforms/gtk/pages.md#the-chrome
    func refreshChrome() {
        guard let element else { return }

        if let arrangement = presentation.arrangement {
            let shown = Self.shownArrangement(arrangement)
            let framed = GTKElement.framedTypes.contains(shown.type)
            let rootChrome = shown.gtk.chrome
            let commandFrame = framed && rootChrome.showsBar
                ? window.pageFrame : shown.gtk.leadingHeaderFrame
            if let previous = commandsFrame, previous !== commandFrame {
                var chrome = previous.chrome
                chrome.appMenu = []
                previous.show(chrome)
            }
            commandsFrame = commandFrame
            let entries = GTKElement.appMenuEntries(of: element)
            // Commands belong to a window, not to the page that supplies its title. Resolve their host from
            // the actual native frames, and write them once while composing every bar (including inactive ones).
            let show: @MainActor @Sendable (GTKPageFrame, GTKPageChrome) -> Void = { frame, chrome in
                var chrome = chrome
                chrome.appMenu = frame === commandFrame ? entries : []
                frame.show(chrome)
            }
            if framed, let frame = window.pageFrame {
                show(frame, rootChrome)
            }
            shown.gtk.composeChrome(show: show)
        }
        adaptSplitViews()
        for (page, sheet) in sheets {
            let shown = Self.shownArrangement(page)
            let chrome = shown.gtk.chrome
            sheet.frame?.show(chrome)
            sheet.setTitle(shown.navigationValue(.title)?.string ?? chrome.title)
            shown.gtk.composeChrome()
        }
        let chrome = WindowChrome(window: element, arrangement: presentation.arrangement)
        window.setTitle(chrome.title ?? element.value(.title)?.string)
        window.setBackground(chrome.windowBackground)
        window.showToolbarlessChrome(chrome.toolbarVisibility?.enumeration == Visibility.hidden.rawValue)
    }

    /// The element the window's bar belongs to: a page that wraps only an
    /// arrangement stands in no frame of its own - the arrangement inside it
    /// carries the bars, or the frame around it does.
    private static func shownArrangement(_ element: MountedElement) -> MountedElement {
        var shown = element
        while shown.type == .page, let inner = shown.contentArrangement {
            shown = inner
        }
        return shown
    }

    /// Collapses the window's split view where the window is narrow.
    private func adaptSplitViews() {
        guard let split = presentation.arrangement?.visibleSplitView?.gtk,
              let view = split.view as? GTKSplitView
        else { return }

        view.adapt(in: window.widget)
    }

    /// Goes the way back the window offers (`WindowPresentation.wayBack`), as the user does: a stack's top page
    /// going in GTK first, the path then told; a sheet going through the host layer. Whether there was one.
    /// Design: docs/design/host/pages.md#the-way-back
    func goBack(in runtime: HostRuntime) -> Bool {
        guard let element, let way = presentation.wayBack else { return false }
        switch way {
        case .pop(let stack):
            return stack.gtk.goBack()
        case .dismissSheet:
            runtime.goBack(way, in: element)
            return true
        }
    }
}

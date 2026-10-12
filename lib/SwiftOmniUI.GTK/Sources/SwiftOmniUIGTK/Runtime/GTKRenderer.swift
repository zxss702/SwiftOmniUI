// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// The GTK runtime: the mounted tree over GTK widgets, the window around it, and the turn.
/// Design: docs/design/platforms/gtk/runtime.md#the-gtk-runtime
@MainActor
final class GTKRenderer {
    /// The one runtime of the process, made when the application is activated.
    static var shared: GTKRenderer?

    /// What the host says for whoever reads its log: standard error, or wherever a test listens.
    static var log = HostLog(host: "GTK")

    let frameClock: GTKFrameClock

    /// Whether the user asked for less animation: every animation arrives at once.
    private let reducesMotion: () -> Bool

    /// The application the windows belong to.
    let application: UnsafeMutablePointer<GtkApplication>

    /// The parts every host holds alike - the core's link, the motions, the display cycle, the mounted tree and
    /// the turn - each element's GTK half a `GTKElement`.
    private(set) lazy var runtime = HostRuntime(
        clock: frameClock, reducesMotion: reducesMotion,
        makeNative: { [unowned self] element in GTKElement(element, host: self) }, log: { GTKRenderer.log.error($0) },
        localization: { key in GTKStrings.resolve(key) },
        views: { GTKView.liveCount })

    /// What performs the acts the application calls, and answers them.
    private(set) lazy var acts = GTKActPerformer(core: runtime.core)

    /// The application's ID, which the desktop knows it by.
    var applicationID: String {
        g_application_get_application_id(application.of(GApplication.self)).map { String(cString: $0) } ?? ""
    }

    /// The windows the tree holds, in the tree's order - a window gone from it closes, the last first, so a
    /// window closes before the one it belongs to.
    private let roster = WindowRoster<GTKWindowController>()

    /// The controller of the window in front - the window element activated last, else the first the tree holds.
    private var frontController: GTKWindowController? {
        let front = runtime.lifecycle.activatedLast(among: roster.windows.map(\.element))
        return front.flatMap { roster.controller(of: $0) } ?? roster.controllers.first
    }

    /// The window in front; nil before the tree says there is one. Where a question, a file's choosing and the
    /// keyboard stand.
    var window: GTKWindow? { frontController?.window }

    /// A sheet for each page the front window's modal stack presents, the last on top.
    var sheets: [(element: MountedElement, sheet: GTKSheet)] { frontController?.sheets ?? [] }

    /// Every window the roster holds, in the tree's order - teardown takes them down together.
    var windows: [GTKWindow] { roster.controllers.map(\.window) }

    /// The page the window in front shows the user, whose menus its main menu is.
    var windowPage: MountedElement? { frontController?.arrangement?.visiblePage }

    /// Whether the screen the first window stands on has been told.
    private var reportedDisplay = false
    private var holdsWithoutWindows = false

    /// A runtime whose windows belong to `application`, on GLib's monotonic clock or on `clock`, with the animation
    /// `reducesMotion` allows.
    init(
        application: UnsafeMutablePointer<GtkApplication>,
        clock: (() -> Double)? = nil,
        reducesMotion: @escaping () -> Bool = { MainActor.assumeIsolated { GTKEnvironment.reducesMotion } }
    ) {
        self.application = application
        let frameClock = clock.map { GTKFrameClock(now: $0, ticksWithGTK: false) } ?? GTKFrameClock()
        self.frameClock = frameClock
        self.reducesMotion = reducesMotion
        runtime.displayCycle.presenter = self
        runtime.pump.presenter = self
    }

    /// The application was activated on GLib's thread: the first time, the first drain makes it MainActor's and
    /// the host starts; after that, a second launch brings the window forward.
    /// Design: docs/design/platforms/gtk/runtime.md#starting
    nonisolated static func activated(_ application: UnsafeMutablePointer<GtkApplication>) {
        let core = CoreLink()
        _ = core.needsRender
        _ = core.runJobs()
        nonisolated(unsafe) let application = application

        MainActor.assumeIsolated {
            if let window = shared?.window {
                window.present()
            } else {
                start(application: application)
            }
        }
    }

    /// The platform handed the application files to open - a launch under `HANDLES_OPEN` emits `open` instead of
    /// `activate`, so the host starts here where it never did; then every `onOpenURL` listener hears each URL.
    nonisolated static func opened(_ application: UnsafeMutablePointer<GtkApplication>, urls: [String]) {
        nonisolated(unsafe) let application = application
        MainActor.assumeIsolated {
            if shared == nil { start(application: application) }
            guard let runtime = shared?.runtime else { return }
            for url in urls {
                runtime.core.raise(AppContract.urlOpened, url)
            }
            runtime.pump.turn()
        }
    }

    /// Starts the host: the application rendered whole, then the doorbell for everything after.
    @discardableResult
    static func start(application: UnsafeMutablePointer<GtkApplication>) -> GTKRenderer {
        shared?.runtime.tree.root?.leave()

        let renderer = GTKRenderer(application: application)
        shared = renderer
        renderer.runtime.core.setRealization(GTKRegistrations.registry.realization, unrealized: GTKRealization.unmade)
        renderer.show()
        GTKDoorbell.install()
        return renderer
    }

    /// Renders the application whole, connecting its scene first, told what the host stands on.
    func show() {
        GTKEnvironment.report(to: runtime.core, applicationID: applicationID)
        GTKKeptValues.restore(into: runtime.core, applicationID: applicationID)
        GTKEnvironment.watch { [weak self] in self?.environmentChanged() }
        runtime.core.connectScene()
        runtime.pump.turn()
    }

    /// The desktop's style turned dark or light: the core hears it, and renders what it changed.
    func environmentChanged() {
        GTKEnvironment.reportChanging(to: runtime.core)
        runtime.pump.turn()
    }

    /// Shows every window element in a GTK window of its own, in the tree's order - a window the tree no longer
    /// holds closes - and tells each, once, in its turn, that it was made.
    /// Design: docs/design/platforms/gtk/runtime.md#the-window
    private func showWindows() {
        let needsHold = runtime.tree.root?.windows.isEmpty == true
            && runtime.tree.root?.children.isEmpty == false
        if needsHold, !holdsWithoutWindows {
            g_application_hold(application.of(GApplication.self))
            holdsWithoutWindows = true
        }
        roster.update(
            root: runtime.tree.root,
            make: { element in
                let controller = GTKWindowController(element, application: application)
                controller.window.onClosedByUser = { [weak self, weak element] in
                    guard let self, let element else { return }
                    windowClosed(element)
                }
                controller.window.onActiveChanged = { [weak self, weak element] active in
                    guard let self, let element else { return }
                    runtime.windowStateChanged(element, minimized: false, activated: active)
                }
                return controller
            },
            close: { $0.close() })
        if !needsHold, holdsWithoutWindows {
            g_application_release(application.of(GApplication.self))
            holdsWithoutWindows = false
        }
        // Frames tick only in a window GTK shows: a window closed or hidden stops ticking, and every animation
        // would wait for the next event - the clock moves to a window still shown.
        let widgets = roster.controllers.map(\.window.widget)
        let ticks = frameClock.widget.map { widgets.contains($0) && gtk_widget_get_mapped($0) != 0 } ?? false
        if !ticks { frameClock.widget = widgets.first { gtk_widget_get_mapped($0) != 0 } ?? widgets.first }
        if !reportedDisplay, let widget = roster.controllers.first?.window.widget,
           gtk_widget_get_realized(widget) != 0 {
            reportedDisplay = true
            GTKEnvironment.reportDisplay(to: runtime.core, window: widget)
        }
        for (element, controller) in roster.windows {
            controller.present(element, in: runtime, windowOf: { [roster] in roster.controller(of: $0)?.window })
        }
    }

    /// The user asked a window closed - its close button, the desktop's: what that tells runs in order, each
    /// rendered before the next.
    private func windowClosed(_ element: MountedElement) {
        runtime.userClosed(element)
    }

    /// Writes every window's shown pages' chrome on their header bars, naming each after the page its user sees.
    /// Design: docs/design/platforms/gtk/pages.md#the-chrome
    func refreshChrome() {
        for controller in roster.controllers { controller.refreshChrome() }
    }

    /// Goes the way back the window in front offers, as the user does. Whether there was one.
    /// Design: docs/design/host/pages.md#the-way-back
    func goBack() -> Bool {
        frontController?.goBack(in: runtime) ?? false
    }
}

extension GTKRenderer: TurnPresenter {
    func presentRendered() {
        showWindows()
    }

    func perform(_ call: HostActCall) {
        acts.perform(call, in: runtime.tree, window: window, applicationID: applicationID)
    }
}

extension GTKRenderer: FramePresenter {
    var wantsFrames: Bool {
        runtime.frames.wantsFrames
    }

    func commitUserReports(now: Double) {
        runtime.frames.commit(now: now)
    }

    func present(states: [Int32: HostStateValue], properties: [UInt64: Set<Prop>]) {
        let impact = runtime.tree.present(states: states, properties: properties)
        if impact.windowChrome { showWindows() }
    }

    func renderIfNeeded() {
        if runtime.core.needsRender { runtime.pump.turn() }
    }
}

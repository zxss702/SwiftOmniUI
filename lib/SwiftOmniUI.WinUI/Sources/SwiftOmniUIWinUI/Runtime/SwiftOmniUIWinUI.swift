// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// Runs a SwiftOmniUI application as native WinUI 3 controls in the application's own process.
///
/// An application's WinUI head names the application to the host and hands it
/// the thread:
///
///     import HelloWorldUI
///     import SwiftOmniUIWinUI
///
///     SwiftOmniUIWinUI.run(applicationID: "com.swiftomniui.helloworld") {
///         swiftomniui_app_register()
///     }
///
/// `.scripts/WinUI/run-app.ps1` builds the head and lays the Windows App SDK
/// beside it. A control this host does not present yet shows its name in red
/// where it belongs.
public enum SwiftOmniUIWinUI {
    nonisolated(unsafe) private static var initialization: (@MainActor @Sendable () -> Void)?

    /// Runs after the native entry has selected this process as the primary instance.
    @MainActor static func initializeApplication() {
        let initialize = initialization
        initialization = nil
        initialize?()
    }

    /// Starts WinUI on this thread and runs the application until its last window closes.
    ///
    /// - Parameters:
    ///   - applicationID: the single-instance key; nil uses the executable's full path.
    ///     A repeated plain launch activates or reopens the first declared main window.
    ///   - initialize: registers the application and its controls on the UI thread, once in the primary process.
    ///     A secondary process forwards its activation and returns without invoking this closure.
    /// - Returns: the process's exit code - 0, or the failure WinUI started with.
    @discardableResult
    public static func run(
        applicationID: String? = nil, initializing initialize: @escaping @MainActor @Sendable () -> Void = {}
    ) -> Int32 {
        initialization = initialize
        defer { initialization = nil }
        PicturePixels.read = { name in
            let files = PictureArithmetic.files(for: name)
            var size = [Int32](repeating: 0, count: 2)
            var answered = WinUIStrings.withCStrings(files) { names in
                swiftomniui_winui_picture_pixels(names, Int32(files.count), &size, nil, 0)
            }
            guard answered, size[0] > 0, size[1] > 0 else { return nil }
            var rgba = [UInt8](repeating: 0, count: Int(size[0]) * Int(size[1]) * 4)
            answered = rgba.withUnsafeMutableBufferPointer { buffer in
                WinUIStrings.withCStrings(files) { names in
                    swiftomniui_winui_picture_pixels(
                        names, Int32(files.count), &size, buffer.baseAddress, Int64(buffer.count))
                }
            }
            return answered ? PicturePixels(width: Int(size[0]), height: Int(size[1]), rgba: rgba) : nil
        }
        Fonts.add = { path in swiftomniui_winui_register_font(path) > 0 }
        for path in Fonts.pending { _ = Fonts.add?(path) }
        Fonts.pending.removeAll()
        var callbacks = WinUICallbacks.table
        if let applicationID {
            return applicationID.withCString { swiftomniui_winui_run_single_instance(&callbacks, $0) }
        }
        return swiftomniui_winui_run_single_instance(&callbacks, nil)
    }
}

/// What the relay calls on the UI thread, each forwarded to the host by the view's number.
/// Design: docs/design/platforms/winui/relay.md#the-callbacks
enum WinUICallbacks {
    static var table: SwiftOmniUIWinUICallbacks {
        SwiftOmniUIWinUICallbacks(
            launched: { WinUIRenderer.launch() },
            turn: { MainActor.assumeIsolated { WinUIDoorbell.turn() } },
            frame: { MainActor.assumeIsolated { WinUIFrameClock.current?.frame() } },
            measure: { view, width, height, size in
                // The relay's own out-parameter, written on the thread that handed it over.
                nonisolated(unsafe) let size = size
                MainActor.assumeIsolated {
                    guard let layout = WinUIView.find(view) as? WinUILayoutView, let size else { return }
                    let measured = layout.measure(width: width, height: height)
                    size[0] = measured.width
                    size[1] = measured.height
                }
            },
            arrange: { view, width, height in
                MainActor.assumeIsolated {
                    (WinUIView.find(view) as? WinUILayoutView)?.arrange(width: width, height: height)
                    WinUIRenderer.shared?.runtime.frames.laidOut()
                }
            },
            viewportChanged: { view, x, y, width, height, _, _ in
                MainActor.assumeIsolated {
                    (WinUIView.find(view) as? WinUILazyView)?.viewportReported(
                        Rect(x: x, y: y, width: width, height: height))
                }
            },
            clicked: { view in
                MainActor.assumeIsolated { WinUIView.find(view)?.clicked() }
            },
            toggled: { view, on in
                MainActor.assumeIsolated { WinUIView.find(view)?.toggled(on) }
            },
            valueChanged: { view, value in
                MainActor.assumeIsolated { (WinUIView.find(view) as? WinUIValueView)?.onValueChanged?(value) }
            },
            textChanged: { view, utf8 in
                let text = utf8.map { String(cString: $0) } ?? ""
                MainActor.assumeIsolated { (WinUIView.find(view) as? WinUIInputView)?.typed(text) }
            },
            submitted: { view in
                MainActor.assumeIsolated { (WinUIView.find(view) as? WinUIInputView)?.onSubmitted?() }
            },
            scrolling: { view, x, y, fx, fy in
                MainActor.assumeIsolated {
                    guard let scroller = WinUIView.find(view) as? WinUIScrollerView else { return }
                    scroller.nextOffset = Point(x: x, y: y)
                    scroller.finalOffset = Point(x: fx, y: fy)
                    scroller.ears.removeAll { $0.owner == nil }
                    for ear in scroller.ears { ear.moved() }
                }
            },
            scrolled: { view, x, y in
                MainActor.assumeIsolated {
                    guard let scroller = WinUIView.find(view) as? WinUIScrollerView else { return }
                    scroller.nextOffset = nil
                    scroller.finalOffset = nil
                    scroller.ears.removeAll { $0.owner == nil }
                    for ear in scroller.ears { ear.moved() }
                    scroller.onScrolled?(Point(x: x, y: y))
                    WinUIRenderer.shared?.runtime.frames.laidOut()
                }
            },
            held: { view, holding in
                MainActor.assumeIsolated {
                    WinUIView.find(view)?.held(holding)
                }
            },
            chosen: { view, index in
                MainActor.assumeIsolated { WinUIView.find(view)?.chose(Int(index)) }
            },
            presented: { view, open in
                MainActor.assumeIsolated { WinUIView.find(view)?.presented(open) }
            },
            environmentChanged: {
                MainActor.assumeIsolated { WinUIRenderer.shared?.environmentChanged() }
            },
            heard: { view, what, phase, x, y, scale in
                if what == SwiftOmniUIHeardPress {
                    return MainActor.assumeIsolated { WinUIView.find(view)?.heardPress(phase: phase, at: Point(x: x, y: y)) }
                }
                guard let heard = HeardInput(what, phase: phase, x: x, y: y, scale: scale) else { return }
                MainActor.assumeIsolated { WinUIView.find(view)?.heard(heard) }
            },
            answered: { ticket, accepted, utf8 in
                let words = utf8.map { String(cString: $0) }
                MainActor.assumeIsolated { WinUIRenderer.shared?.answered(ticket: ticket, accepted: accepted, words: words) }
            },
            filesChosen: { ticket, count, paths, names, failure in
                let files = (0..<Int(count)).compactMap { index -> ChosenFile? in
                    guard let path = paths?[index], let name = names?[index] else { return nil }
                    return ChosenFile(address: String(cString: path), name: String(cString: name))
                }
                let why = failure.map { String(cString: $0) }
                MainActor.assumeIsolated { WinUIRenderer.shared?.fileToolkit.chose(ticket: ticket, files: files, failure: why) }
            },
            fileRead: { ticket, bytes, length, failure in
                let read = bytes.map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? []
                let why = failure.map { String(cString: $0) }
                MainActor.assumeIsolated { WinUIRenderer.shared?.fileToolkit.read(ticket: ticket, bytes: read, failure: why) }
            },
            launchAnswered: { ticket, taken in
                MainActor.assumeIsolated { WinUIRenderer.shared?.fileToolkit.launched(ticket: ticket, taken: taken) }
            },
            canvasPressed: { view, phase, x, y in
                MainActor.assumeIsolated {
                    (WinUIView.find(view) as? WinUICanvasView)?.pressed(phase: phase, at: Point(x: x, y: y))
                }
            },
            picked: { view, first, second, third in
                MainActor.assumeIsolated { WinUIView.find(view)?.picked(first, second, third) }
            },
            menuChosen: { view, index in
                MainActor.assumeIsolated { WinUIView.find(view)?.menuChosen(Int(index)) }
            },
            focused: { view, focused in
                MainActor.assumeIsolated { WinUIView.find(view)?.focusChanged(focused) }
            },
            windowStateChanged: { window, minimized, activated in
                MainActor.assumeIsolated {
                    WinUIRenderer.shared?.windowStateChanged(number: window, minimized: minimized, activated: activated)
                }
            },
            windowClosed: { window in
                MainActor.assumeIsolated { WinUIRenderer.shared?.windowClosed(number: window) }
            },
            itemCell: { view, kind, cell in
                // The relay's own out-parameter, and the panel it takes a reference of.
                nonisolated(unsafe) let cell = cell
                nonisolated(unsafe) var panel: SwiftOmniUIObjectRef?
                MainActor.assumeIsolated {
                    guard let made = WinUIItemsList.owner(of: view)?.makeCell(item: kind == 0) else { return }
                    cell?.pointee = made.number
                    panel = made.handle
                }
                return panel
            },
            itemHeld: { view, cell, utf8 in
                let identity = utf8.map { String(cString: $0) } ?? ""
                MainActor.assumeIsolated { WinUIItemsList.owner(of: view)?.held(identity, in: cell) }
            },
            itemLetGo: { view, cell in
                MainActor.assumeIsolated { WinUIItemsList.owner(of: view)?.letGo(cell) }
            },
            itemsChose: { view, utf8 in
                let joined = utf8.map { String(cString: $0) } ?? ""
                MainActor.assumeIsolated {
                    WinUIItemsList.owner(of: view)?.chose(joined.split(separator: "\n").map(String.init))
                }
            },
            itemInvoked: { view, utf8 in
                let identity = utf8.map { String(cString: $0) } ?? ""
                MainActor.assumeIsolated { WinUIItemsList.owner(of: view)?.invoked(identity) }
            },
            itemsShowing: { view, first, last in
                MainActor.assumeIsolated { WinUIItemsList.owner(of: view)?.showing(Int(first)...Int(last)) }
            },
            urlOpened: { utf8 in
                guard let url = utf8.map({ String(cString: $0) }) else { return }
                MainActor.assumeIsolated { WinUIRenderer.shared?.urlOpened(url) }
            },
            activated: {
                MainActor.assumeIsolated { WinUIRenderer.shared?.activateInitialWindow() }
            },
            menuContentRequested: { view, mount in
                MainActor.assumeIsolated {
                    guard let host = WinUIRenderer.shared,
                          let source = WinUIView.find(view)?.sourceElement ?? host.runtime.tree.root else { return }
                    source.requestMenuContent(mount: mount == 0 ? nil : mount, in: host.runtime)
                }
            })
    }
}

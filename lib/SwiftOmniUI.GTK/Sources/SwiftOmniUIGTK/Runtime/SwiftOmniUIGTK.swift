// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// Runs a SwiftOmniUI application as native GTK 4 and libadwaita widgets in the application's own process.
///
/// An application's GTK head names the application to the host and hands it
/// the thread:
///
///     import HelloWorldUI
///     import SwiftOmniUIGTK
///
///     SwiftOmniUIGTK.run(applicationID: "com.swiftomniui.helloworld") {
///         swiftomniui_app_register()
///     }
///
/// `.scripts/GTK/run-app.sh` builds the head and starts it. A control this
/// host does not present yet shows its name in red where it belongs.
public enum SwiftOmniUIGTK {
    nonisolated(unsafe) private static var initialization: (@MainActor @Sendable () -> Void)?

    /// Runs only in the primary instance, after GTK has dispatched its first activation on the UI thread.
    @MainActor static func initializeApplication() {
        let initialize = initialization
        initialization = nil
        initialize?()
    }

    /// Starts GTK on this thread and runs the application until its last window closes.
    ///
    /// - Parameters:
    ///   - applicationID: the application's reverse-DNS name, which the desktop knows it by - its entry and
    ///     its icon are named by it. A repeated plain launch activates or reopens the first declared main window.
    ///   - initialize: registers the application and its controls on the UI thread, once in the primary process.
    ///     A secondary process forwards its activation and returns without invoking this closure.
    /// - Returns: the process's exit code.
    @discardableResult
    public static func run(
        applicationID: String, initializing initialize: @escaping @MainActor @Sendable () -> Void = {}
    ) -> Int32 {
        initialization = initialize
        defer { initialization = nil }
        PicturePixels.read = { name in MainActor.assumeIsolated { GTKPictures.pixels(of: name) } }
        BitmapImage.decode = { bytes in MainActor.assumeIsolated { GTKImageCodec.decode(bytes) } }
        BitmapImage.encodePNG = { pixels in MainActor.assumeIsolated { GTKImageCodec.encode(pixels) } }
        BitmapImage.rasterize = { size, scale, drawing in MainActor.assumeIsolated { GTKCanvasView.bitmap(size: size, scale: scale, drawing: drawing) } }
        FontFace.open = { path in GTKFontFaces.open(path) }
        FontMetrics.read = { descriptor in GTKSystemFontMetrics.read(descriptor) }
        Fonts.add = { path in MainActor.assumeIsolated { GTKFonts.register(path) } }
        for path in Fonts.pending { _ = Fonts.add?(path) }
        Fonts.pending.removeAll()
        if let displayName = DesktopApplicationInfo.displayName { g_set_application_name(displayName) }
        let application = adw_application_new(
            applicationID, GApplicationFlags(G_APPLICATION_HANDLES_OPEN.rawValue))!
        gtk_window_set_default_icon_name(applicationID)
        connectSignal(UnsafeMutableRawPointer(application), "activate", number: 0) { application, _ in
            GTKRenderer.activated(application!.assumingMemoryBound(to: GtkApplication.self))
        }
        connectSignal(UnsafeMutableRawPointer(application), "open", number: 0) { application, files, count, _, _ in
            guard let files else { return }
            var urls: [String] = []
            for place in 0 ..< Int(count) {
                if let file = files[place], let uri = g_file_get_uri(OpaquePointer(file)) {
                    urls.append(String(cString: uri))
                    g_free(uri)
                }
            }
            GTKRenderer.opened(application!.assumingMemoryBound(to: GtkApplication.self), urls: urls)
        }
        let status = g_application_run(application.of(GApplication.self), CommandLine.argc, CommandLine.unsafeArgv)
        g_object_unref(UnsafeMutableRawPointer(application))
        return status
    }
}

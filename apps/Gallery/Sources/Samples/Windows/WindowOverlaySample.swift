import SwiftOmniUI

extension OverlayKey {
    /// The sample's notice.
    static let notice = OverlayKey("notice")
}

/// A notice the window lays over every page, which stays while the pages change under it.
struct WindowOverlaySample: SampleContent, ExampleContent {
    @Environment private var window: WindowSession

    @State private var shown = false

    static let id = "windowOverlay"
    static let title = "WindowScene overlay"
    static let summary = "Lay a notice over the window, then open another page."

    static let code = """
        extension OverlayKey {
            static let notice = OverlayKey("notice")
        }

        @Environment private var window: WindowSession
        @State private var shown = false

        Toggle(isOn: $shown).onChange(of: shown) {
            window.overlays[.notice] = shown ? WindowNotice() : nil
        }

        struct WindowNotice: View {
            @Environment private var window: WindowSession

            var body: some View {
                HStack {
                    Text("Over every page")
                    Button("Dismiss", action: { window.overlays[.notice] = nil })
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        """

    var notes: (any View)? { nil }

    var body: some View {
        HStack {
            Toggle(isOn: $shown)
                .accessibilityIdentifier("window.overlay")
                .accessibilityLabel("Notice over the window")
            Text("Notice over the window")
        }
        .spacing(8)
        .onChange(of: shown) {
            guard shown != (window.overlays[.notice] != nil) else { return }
            window.overlays[.notice] = shown ? WindowNotice() : nil
        }
        // The switch follows the notice, which its own button takes away.
        .onChange(of: window.overlays[.notice] != nil) { shown = window.overlays[.notice] != nil }
        .onAppear { shown = window.overlays[.notice] != nil }
    }
}

/// What the sample lays over the window: a line at the top, with its own way out.
private struct WindowNotice: View {
    @Environment private var window: WindowSession

    var body: some View {
        HStack {
            Text("Over every page")
                .foregroundStyle(.white)
            Button("Dismiss", action: { window.overlays[.notice] = nil })
                .accessibilityIdentifier("window.overlay.dismiss")
                
        }
        .spacing(12)
        .padding(EdgeInsets(16, 8))
        .background(Palette.accent)
        .shape(.roundedRectangle(10))
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

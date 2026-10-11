import SwiftOmniUI

/// The native window lifecycle recorded through `WindowSession.phase`.
struct LifecycleSample: SampleContent, ExampleContent {
    /// The window's log, kept with the gallery. It is written by `MainWindow`,
    /// which watches its window's phase - see Gallery/MainWindow.swift - and
    /// this sample only reads it.
    let log: WindowLog

    static let id = "lifecycle"
    static let title = "WindowScene lifecycle"
    static let summary = "Watch the native window lifecycle as state."

    static let code = """
        final class WindowLog {
            @State var events: [String] = []
            @State private(set) var count = 0

            func note(_ name: String) {
                count += 1
                events = Array((events + ["\\(count) · \\(name)"]).suffix(6))
            }
        }

        struct MainWindow: WindowScene {
            @Environment private var window: WindowSession
            @State private var menuOpen = false
            let log: WindowLog

            var page: any Page {
                NavigationSplitView($menuOpen) { MenuPage() } detail: { HomePage() }
                    .onAppear { log.note("created") }
                    .onChange(of: window.phase) { log.note("\\(window.phase)") }
            }
        }

        VStack {

            ForEach(log.events) { row in
                Text(row)
            }
        }
        """

    var notes: (any View)? { nil }

    var body: some View {
        VStack {
            Text("What the window has said so far, newest last:")
                .font(.system(size: 14))
                .foregroundStyle(Palette.subtle)

            VStack {

                if log.events.isEmpty {
                    Text("nothing yet - switch away and back")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.subtle)
                }

                ForEach(log.events) { row in
                    Text(row)
                        .font(.system(size: 15))
                }
            }
            .spacing(4)
        }
        .spacing(12)
    }

}

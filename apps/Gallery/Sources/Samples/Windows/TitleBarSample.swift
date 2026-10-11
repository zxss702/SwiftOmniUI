import SwiftOmniUI

/// Values changed by the sample and presented by the gallery window.
final class TitleBarState {
    /// The second line in the native title area.
    @State var subtitle = ""

    /// Whether the trailing title-area slot presents an action.
    @State var showsSurprise = false
}

/// Native window chrome described by a `TitleBar` value and its three slots.
struct TitleBarSample: SampleContent, ExampleContent {
    /// The values shared with this gallery's main window.
    let bar: TitleBarState

    static let id = "titleBar"
    static let title = "TitleBar"
    static let summary = "Title, color, and interactive content in native window chrome."
    static let formFactors: Set<FormFactor> = [.desktop]

    static let code = """
        final class TitleBarState {
            @State var subtitle = ""
            @State var showsAction = false
        }

        struct MainWindow: WindowScene {
            let titleBar: TitleBarState
            @Environment private var window: WindowSession

            var page: any Page {
                HomePage()
                    .onAppear { window.titleBar = chrome }
                    .onChange(of: titleBar.subtitle) {
                        window.titleBar = chrome
                    }
            }

            var chrome: TitleBar {
                TitleBar("SwiftOmniUI")
                    .subtitle(titleBar.subtitle)
                    .icon("swiftomniui_mark.png")
                    .barForegroundColor(.white)
                    .background(.cornflowerBlue)
                    .leadingContent { Button("Sidebar") }
                    .content { SearchField("Search") }
                    .trailingContent {
                        TitleBarAction(state: titleBar)
                    }
            }
        }

        struct TitleBarAction: View {
            let state: TitleBarState

            var body: some View {
                HStack {
                    if state.showsAction {
                        Button("Surprise me")
                    }
                }
            }
        }

        struct TitleBarSample: View {
            let state: TitleBarState

            var body: some View {
                VStack {
                    DebugInfoLabel()
                    TextField(state.$subtitle).placeholder("WindowScene subtitle")
                    Toggle(isOn: state.$showsAction)
                }
            }
        }
        """

    var notes: (any View)? { nil }

    var body: some View {
        VStack {
            DebugInfoLabel()

            TextField(bar.$subtitle)
                .accessibilityIdentifier("titleBar.subtitle")
                .accessibilityLabel("Subtitle for the window")
                .placeholder("WindowScene subtitle")

            HStack {
                Toggle(isOn: bar.$showsSurprise)
                    .accessibilityIdentifier("titleBar.surprise")
                    .accessibilityLabel("Show a title bar action")

                Text("Show a trailing action")
                    .verticalAlignment(.center)
            }
            .spacing(8)
        }
        .spacing(12)
    }
}

import SwiftOmniUI

/// Native window identity, geometry, constraints, operations and translucency.
struct WindowSample: SampleContent, ExampleContent {
    @Environment private var window: WindowSession

    @State private var renames = 0
    @State private var maximizable = true
    @State private var minimizable = true
    @State private var translucent = false
    @State private var width = 0.0
    @State private var height = 0.0

    static let id = "window"
    static let title = "WindowScene"
    static let summary = "Change the native window while it stays on screen."

    static let code = """
        struct MainWindow: WindowScene {
            @Environment private var window: WindowSession

            var page: any Page {
                HomePage()
                    .onAppear {
                        window.title = "Notes"
                        window.width = 1100
                        window.height = 800
                        window.minimumWidth = 700
                        window.minimumHeight = 500
                        window.maximumWidth = 1600
                        window.maximumHeight = 1200
                        window.isMaximizable = true
                        window.isMinimizable = true
                    }
            }
        }

        @Environment private var window: WindowSession
        @State private var maximizable = true
        @State private var minimizable = true
        @State private var translucent = false

        DebugInfoLabel()

        Button("Move to 80, 80", action: {
            window.x = 80
            window.y = 80
        })

        Button("900 × 650", action: {
            window.width = 900
            window.height = 650
        })

        Toggle(isOn: $maximizable).onChange(of: maximizable) {
            window.isMaximizable = maximizable
        }

        Toggle(isOn: $minimizable).onChange(of: minimizable) {
            window.isMinimizable = minimizable
        }

        Toggle(isOn: $translucent)
            .onChange(of: translucent) {
                window.isTranslucent = translucent
            }
            .onAppear { translucent = window.isTranslucent == true }
        """

    var notes: (any View)? { nil }

    var body: some View {
        VStack {
            DebugInfoLabel()

            Text(window.title ?? "Platform title")
                .font(.system(size: 15))
                .bold()

            HStack {
                action("Rename") {
                    renames += 1
                    window.title = "Gallery \(renames)"
                }
                .accessibilityIdentifier("window.rename")

                action("Move to 80, 80") {
                    window.x = 80
                    window.y = 80
                }
                .accessibilityIdentifier("window.move")
            }
            .spacing(10)

            HStack {
                action("900 × 650") {
                    window.width = 900
                    window.height = 650
                }
                .accessibilityIdentifier("window.compact")

                action("1100 × 800") {
                    window.width = 1100
                    window.height = 800
                }
                .accessibilityIdentifier("window.regular")
            }
            .spacing(10)

            option("Maximize", id: "window.maximize", value: $maximizable)
                .onChange(of: maximizable) {
                    window.isMaximizable = maximizable
                }

            option("Minimize", id: "window.minimize", value: $minimizable)
                .onChange(of: minimizable) {
                    window.isMinimizable = minimizable
                }

            option("Translucent", id: "window.translucent", value: $translucent)
                .onChange(of: translucent) {
                    window.isTranslucent = translucent
                }

            Text("Sample frame: \(Int(width)) × \(Int(height))")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
        }
        .spacing(12)
        .onFrameChanged(in: .global) { frame in
            width = frame.width
            height = frame.height
        }
        // The switch starts where the window stands - on, where the gallery's
        // window opens translucent.
        .onAppear { translucent = window.isTranslucent == true }
    }

    /// An action that writes the surrounding window session.
    private func action(_ title: String, _ write: @escaping () -> Void) -> any View {
        Button(title, action: { write() })
            .font(.system(size: 13))
            .padding(EdgeInsets(16, 6))
            
    }

    /// A native boolean window capability.
    private func option(_ title: String, id: String, value: Binding<Bool>) -> any View {
        HStack {
            Toggle(isOn: value)
                .accessibilityIdentifier(id)
                .accessibilityLabel(title)
            Text(title).verticalAlignment(.center)
        }
        .spacing(8)
    }
}

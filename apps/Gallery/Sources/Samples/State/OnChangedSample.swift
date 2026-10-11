import SwiftOmniUI

/// Running something when a value is not what it was last render.
struct OnChangedSample: SampleContent, ExampleContent {
    @State private var celsius = 20.0
    @State private var log: [String] = []
    @State private var fired = 0

    static let id = "onChanged"
    static let title = "Reacting to change"
    static let summary = "A handler that runs when a value moves - with the old value and the new one."

    static let code = """
        @State private var celsius = 20.0
        @State private var log: [String] = []
        @State private var fired = 0

        VStack {
            // THIS closure reads `celsius`, so every report from the slider
            // builds it again - which is what a get on a dragged value costs.
            DebugInfoLabel()

            Text("\\(Int(celsius)) °C")

            Slider($celsius, in: -10...40)

            // Watches ROUNDED degrees, so dragging fires once per whole
            // degree rather than once per pixel. It does not fire when the
            // page appears - a view arriving is not a value changing.
            VStack {
                ForEach(log.reversed()) { line in
                    Text(line).id(line)
                }
            }
            .animation(nil)
            .onChange(of: Int(celsius)) { old, new in
                fired += 1
                let arrow = new > old ? "warmer" : "colder"
                log.append("\\(old) -> \\(new) °C, \\(arrow) (#\\(fired))")
                if log.count > 6 { log.removeFirst() }
            }
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            Text("\(Int(celsius)) °C")
                .font(.system(size: 34))
                .bold()
                .horizontalAlignment(.center)

            Slider($celsius, in: -10...40)
                .accessibilityIdentifier("onChanged.celsius")
                .accessibilityLabel("Celsius")

            // Watches ROUNDED degrees, so dragging fires once per whole degree
            // rather than once per pixel. It does not fire when the page
            // appears - a view arriving is not a value changing.
            VStack {
                ForEach(log.reversed()) { line in
                    Text(line)
                        .font(.system(size: 13))
                        .id(line)
                }
            }
            .spacing(4)
            .animation(nil)
            .onChange(of: Int(celsius)) { old, new in
                fired += 1
                let arrow = new > old ? "warmer" : "colder"
                log.append("\(old) -> \(new) °C, \(arrow) (#\(fired))")
                if log.count > 6 { log.removeFirst() }
            }

        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`.onChanged` compares against what this view carried last render, on "
                + "the Swift side alone - nothing about it crosses to the host. The "
                + "two-argument form is handed the old value and the new one; the short "
                + "form takes no arguments at all.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("It watches rounded degrees here, so dragging fires once per whole "
                + "degree rather than once per pixel. It does not fire when the page "
                + "appears: a view arriving is not a value changing.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}

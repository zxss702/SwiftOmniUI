// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftOmniUIFoundation
import SwiftOmniUICore

struct FoundationSurfaceTests {
    /// An attributed string's runs land as spans, one per run, in order.
    @Test func attributedTextBecomesSpans() throws {
        var words = AttributedString("hello ")
        var styled = AttributedString("world")
        styled[TextRunStyleAttributeKey.self] = TextRunStyle(fontAttributes: .bold)
        words.append(styled)

        let node = Text(words).node
        let spans = try #require(node.children.first { $0.type == "Spans" })

        #expect(spans.children.count == 2, "two attributes, two runs")
    }

    /// A timeline view stands as a composed node.
    @Test func timelineViewBuilds() {
        let view = TimelineView(.animation(minimumInterval: 1.0 / 30)) { context -> TupleView in
            Text("\(context.date.timeIntervalSince1970 > 0)")
        }
        _ = view.node
    }

    /// `.onOpenURL` writes the SwiftUI spelling onto a view.
    @Test func openURLModifierApplies() {
        struct Page: View {
            var body: some View {
                Text("page")
                    .onOpenURL { url in _ = url.isFileURL }
            }
        }

        _ = Page().node
    }
}

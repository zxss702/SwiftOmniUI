// The Swift behind an example.

import SwiftOmniUI

/// The code that produced an example, in a box of its own.
///
/// A block scrolls only horizontally. Its page keeps ownership of vertical
/// scrolling when the pointer is over the listing.
struct CodeBlock: View {
    private let code: String

    /// - Parameter code: The snippet, as a reader would write it.
    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        ScrollView(.horizontal) {
            snippet
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .background(Palette.raised)
        .stroke(Palette.outline)
        .shape(.roundedRectangle(8))
        // Code reads left to right in every language, from its first column.
        .layoutDirection(.leftToRight)
    }

    /// How large the code is drawn, in points.
    private let size: Double = 13

    /// The code itself, coloured run by run.
    ///
    /// The label, its spans and the highlight scan are all built inside this
    /// container's closure - which runs when the block is described, and a
    /// block built with the same code is carried whole, so the scan runs once
    /// per block rather than once per render.
    private var snippet: any View {
        VStack {
            // One run per token, gathered into a single Text with `+` - the
            // block is built once when described and carried whole after
            // that, so the scan runs once per block rather than once per
            // render.
            CodeHighlight.runs(in: code).map { run in
                // The size goes on every run rather than on the Text. A run
                // carries font properties of its own, and what an unset one
                // falls back to is the platform's business - one property
                // per run costs nothing and leaves nothing to it.
                Text(run.text)
                    .foregroundStyle(run.colour)
                    .font(.system(size: size))
            }
            .reduce(Text(""), +)
            .padding(14)
        }
    }
}

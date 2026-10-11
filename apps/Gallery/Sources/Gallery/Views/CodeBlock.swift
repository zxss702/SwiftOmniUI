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
        .strokeWidth(1)
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
            Text()
                .spans {
                    // Identified by OFFSET: two runs may be the same words
                    // in the same colour, and the snippet never changes, so
                    // the offsets never move.
                    ForEach(
                        Array(CodeHighlight.runs(in: code).enumerated()),
                        id: \.offset
                    ) { run in
                        // The size goes on every run rather than on the
                        // Text. A span carries font properties of its own,
                        // and what an unset one falls back to is the
                        // platform's business - one property per run costs
                        // nothing and leaves nothing to it.
                        TextSpan(run.element.text)
                            .foregroundStyle(run.element.colour)
                            .font(.system(size: size))
                    }
                }
                .padding(14)
        }
    }
}

import SwiftOmniUI

/// A `SearchField` on the navigation bar in place of the title, and the rows it filters.
struct SearchSample: SampleContent, ExampleContent {
    /// Where the gallery is: choosing a suggestion pushes a page.
    let nav: Navigation

    /// What there is to search. A constant: the sample is about the box, and
    /// nothing here edits the list.
    private let items = ["Alpha", "Beta", "Gamma", "Delta"]

    @State private var query = ""

    /// The page this sample is on, whose bar the box goes on.
    @Environment private var page: PageSession

    static let id = "search"
    static let title = "Search"
    static let summary = "A view on the navigation bar in place of the title, and the matches under it."

    static let code = """
        let nav: Navigation
        private let items = ["Alpha", "Beta", "Gamma", "Delta"]

        @State private var query = ""

        @Environment private var page: PageSession

        var body: some View {
            VStack {
                // The query and the matches are read here, so every keystroke
                // in the bar builds this closure.

                ForEach(matches, id: \\.self) { item in
                    MenuRow(item) { nav.push(.item(item)) }
                }

                Button("Clear the box", action: { query = "" })
                    .disabled(query.isEmpty)
                    
            }
            // The title view belongs to the page session, like toolbar items.
            .onAppear {
                page.titleView = SearchField($query)
                    .accessibilityLabel("Search the list")
                    .background(Palette.surface)
                    .frame(height: 38)
            }
        }

        /// What the query matches - everything when there is no query: these
        /// rows are the page's content, and an empty page under an empty box
        /// would read as a mistake.
        private var matches: [String] {
            query.isEmpty
                ? items
                : items.filter { $0.lowercased().hasPrefix(query.lowercased()) }
        }
        """

    var body: some View {
        VStack {

            Text("Type in the box on the navigation bar; these rows follow it.")
                .font(.system(size: 14))

            VStack {
                ForEach(matches, id: \.self) { item in
                    // A row that opens a page: the chosen item rides as a VALUE
                    // of the route - `.item("Alpha")`.
                    MenuRow(item) { nav.push(.item(item)) }
                }
            }
            .spacing(2)

            Text(matches.isEmpty
                ? "Nothing matches \"\(query)\""
                : "\(matches.count) of \(items.count) shown")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Button("Clear the box", action: { query = "" })
                .disabled(query.isEmpty)
                .padding(EdgeInsets(20, 10))
                
        }
        .spacing(12)
        // The box goes in the page's title slot. It is an ordinary view in the
        // tree, handed the same `@State` the content reads.
        .onAppear {
            page.titleView = SearchField($query)
                .accessibilityIdentifier("search.query")
                .accessibilityLabel("Search the list")
                .foregroundStyle(Palette.text)
                .background(Palette.surface)
                .frame(height: 38)
        }
    }

    var notes: (any View)? {
        VStack {
            Text("The box is a `SearchField` written into `page.titleView`, the bar's title "
                + "slot, so it sits where this page's title would; the page a match pushes "
                + "wears its own. The rows under it are drawn by this page from its own "
                + "state, so they look like the app and do whatever choosing one should do.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A title view replaces the title while this page is showing, so use "
                + "the slot only when the view has a job there.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`OnScreenKeyboard.hide()` takes the focus off whatever holds it - the box on "
                + "the bar included. Where the host lets a focused search box take over "
                + "the bar, unfocusing it gives the bar back.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }

    /// What the query matches - everything when there is no query: these rows
    /// are the page's content, and an empty page under an empty box would read
    /// as a mistake.
    ///
    /// `hasPrefix` rather than `contains`, which is a choice about the RESULT
    /// and not about what compiles: matching from the start makes a short list
    /// of names narrow predictably as the user types, where a substring
    /// match keeps rows whose beginning bears no relation to the query.
    private var matches: [String] {
        query.isEmpty
            ? items
            : items.filter { $0.lowercased().hasPrefix(query.lowercased()) }
    }
}

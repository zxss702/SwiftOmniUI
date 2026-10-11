import SwiftOmniUI

/// Page-owned native toolbar and menu items.
struct ToolbarSample: SampleContent, ExampleContent {
    @State private var saved = 0
    @State private var recent = ["notes.txt", "budget.csv"]

    /// How many files Add has made, so each gets a name of its own - a menu
    /// row is identified by the file it names, and two rows may not claim the
    /// same identity.
    @State private var added = 0

    /// The page this sample is on, whose bar and menus these are.
    @Environment private var page: PageSession

    /// What the page's bar held before this sample added to it - the
    /// gallery's own buttons, which stay after the sample's.
    @State private var chrome: [ToolbarItem] = []

    static let id = "toolbar"
    static let title = "Toolbar and menus"
    static let summary = "Buttons in the navigation bar, and the desktop menu bar above it."

    static let code = """
        @State private var saved = 0
        @State private var recent = ["notes.txt", "budget.csv"]
        @State private var added = 0

        @Environment private var page: PageSession
        @State private var chrome: [ToolbarItem] = []

        // Both belong to the PAGE, so they are written into its session -
        // and written again when what they say moves.
        private var items: [ToolbarItem] {
            [
                ToolbarItem("Save") { saved += 1 }
                    .id("save"),

                ToolbarItem("Add") {
                        added += 1
                        recent.append("file\\(added).txt")
                    }
                    .id("add"),

                ToolbarItem("Clear", placement: .overflow) { saved = 0 }
                    .id("clear")
                    .disabled(saved <= 0),
            ]
        }

        private var menus: [Menu] {
            [
                Menu("File") {
                    MenuItem("Save") { saved += 1 }
                        .id("save")

                    Divider()
                        .id("line")

                    Menu("Recent") {
                        ForEach(recent) { file in
                            MenuItem(file) { recent.removeAll { $0 == file } }
                                .id(file)
                        }
                    }
                    .id("recent")
                    .disabled(recent.isEmpty)
                }
                .id("file"),
            ]
        }

        var body: some View {
            VStack {
                // The counts are read here, so every toolbar item that acts
                // builds this closure.

                Text("Saved \\(saved) time(s)")
                Text(recent.isEmpty ? "No recent files" : recent.joined(separator: ", "))

            }
            .onAppear {
                chrome = page.toolbarItems      // what the page put there first
                page.toolbarItems = items + chrome
                page.menuBar = menus
            }
            .onChange(of: saved) { page.toolbarItems = items + chrome }
            .onChange(of: recent) { page.menuBar = menus }
        }
        """

    /// The buttons this sample puts on the page's bar, before the gallery's
    /// own.
    private var items: [ToolbarItem] {
        [
            ToolbarItem("Save") { saved += 1 }
                .id("save"),

            ToolbarItem("Add") {
                    added += 1
                    recent.append("file\(added).txt")
                }
                .id("add"),

            ToolbarItem("Clear", placement: .overflow) { saved = 0 }
                .id("clear")
                .disabled(saved <= 0),
        ]
    }

    /// And the desktop menu bar's File menu.
    private var menus: [Menu] {
        [
            Menu("File") {
                MenuItem("Save") { saved += 1 }
                    .id("save")

                Divider()
                    .id("line")

                Menu("Recent") {
                    ForEach(recent) { file in
                        MenuItem(file) { recent.removeAll { $0 == file } }
                            .id(file)
                    }
                }
                .id("recent")
                .disabled(recent.isEmpty)
            }
            .id("file"),
        ]
    }

    var body: some View {
        VStack {

            Text("Saved \(saved) time(s)")
                .font(.system(size: 17))

            Text(recent.isEmpty ? "No recent files" : recent.joined(separator: ", "))
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)

            Text("Press Save and Add on the bar; Clear is in its overflow.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

        }
        .spacing(12)
        // The bar and the menus are the PAGE's, so this sample writes them
        // into the page's session - its buttons before the gallery's own,
        // which the page wrote a moment earlier, being further out.
        .onAppear {
            chrome = page.toolbarItems
            page.toolbarItems = items + chrome
            page.menuBar = menus
        }
        // What they say follows the state, so they are written again when it
        // moves: `saved` decides whether Clear can be pressed, `recent` the
        // submenu.
        .onChange(of: saved) { page.toolbarItems = items + chrome }
        .onChange(of: recent) { page.menuBar = menus }
    }

    var notes: (any View)? {
        VStack {
            Text("Save and Add are on the page's bar. Clear sits in the "
                + "native overflow, enabled once something is saved.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Recent files live in the desktop File menu: Add puts one there, "
                + "choosing one removes it, and an empty submenu disables itself.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The bar and the menus belong to the page, so they are written into "
                + "its `PageSession` - and written again whenever the state they show "
                + "moves.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}

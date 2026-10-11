// The menu that slides in from the side.

import SwiftOmniUI

/// The gallery's sidebar - and it is an ordinary page.
///
/// That is the whole point of it. A view with a gradient at the top,
/// some rows in the middle and a line at the bottom - and a row is a view with
/// a tap on it that writes state. There is no menu vocabulary to learn: what
/// can go in the pane is whatever can go on a page, and what a row does is
/// whatever a handler can do.
///
/// Its title names the pane on hosts whose navigation chrome exposes that name.
struct MenuPage: View {
    /// Everything the gallery shows - the rows are one per group.
    let catalog: Catalog

    /// Where the gallery is, so a row can move it and know whether it is the
    /// row the user is on.
    let nav: Navigation

    /// What the window has said about its life - written by `WindowPhaseLog`
    /// at the foot of this page as the window's phase moves.
    let log: WindowLog

    /// Whether the row that is hidden by default is listed - the Split view sample
    /// writes it, and here it is an `if` around the row.
    let listsHiddenRow: Bool

    /// The device's facts, for the line at the bottom.
    @Environment private var device: DeviceInfo

    /// The page itself.
    @Environment private var page: PageSession

    /// The window the menu stands in - whether the desktop shows through it.
    @Environment private var window: WindowSession

    var body: some View {
        Grid {
            header

            ScrollView {
                rows
            }
            .gridRow(1)

            footer

            WindowPhaseLog(log: log)
        }
        // Three rows: the header and the footer keep their height, and the
        // rows take what is left and scroll between them.
        //
        // The header is outside the scroller so its background owns the page's
        // top edge while only the rows participate in scrolling.
        .rows(.auto, .fill, .auto)
        // EDGE TO EDGE, so the gradient runs behind the status bar the way the
        // navigation bar beside it does. Every LAYOUT insets itself, so the
        // header says it too.
        .ignoresSafeArea(.none)
        .onAppear {
            page.title = "SwiftOmniUI"

            // The image hosts use for the pane's navigation affordance.
            page.icon = "nav_menu_dark.png"
            page.background = surface
        }
        // A window the desktop shows through shows it through the menu as well.
        .onChange(of: window.isTranslucent) { page.background = surface }
    }

    /// What the menu is drawn on: the gallery's surface - and nothing of its own
    /// where the window shows the desktop, the sidebar's glass showing it in
    /// the tint the window's bars lay over it.
    private var surface: Color? {
        window.isTranslucent == true ? nil : Palette.surface
    }

    /// The mark, the name and what this is - on the gradient the home page opens
    /// with, so the menu and the page behind it are plainly one application. A
    /// phone leaves the mark out: its rows need the room to scroll.
    private var header: any View {
        VStack {
            if device.formFactor != .phone {
                Image("swiftomniui_mark.png")
                    .frame(width: 51)
                    .frame(height: 51)
                    .horizontalAlignment(.start)
            }

            Text("SwiftOmniUI")
                .font(.system(size: 24))
                .bold()
                .tracking(-0.5)
                .foregroundStyle(Palette.onBrand)

            Text("Native interfaces, written in Swift")
                .font(.system(size: 12))
                .foregroundStyle(Palette.onBrand)
                .opacity(0.85)
        }
        .spacing(6)
        // Edge to edge, and padded down by hand. A layout that insets its
        // children below a status bar at ARRANGE time while its MEASURED
        // height knows nothing of it leaves a header's bottom clipped by
        // exactly the inset - so the padding is the app's own, and the
        // gradient was always meant to run behind the status bar anyway.
        .ignoresSafeArea(.none)
        .padding(EdgeInsets(20, 40, 20, 22))
        .background(Palette.identity)
    }

    /// Home, one row per group, the row that is not always listed, and the one
    /// row that performs an act rather than going anywhere.
    private var rows: any View {
        VStack {
            MenuRow("Home") { nav.open(.home) }
                .icon(ImageSource(light: "nav_home.png", dark: "nav_home_dark.png"))
                .chosen(nav.showing(.home))

            // One row per group, built from the catalog - so a new group is a
            // line there rather than a change here.
            ForEach(catalog.groups, id: \.route) { group in
                MenuRow(group.title) { nav.openGroup(group.route) }
                    .icon(group.icon)
                    .chosen(nav.showingGroup(group.route))
            }

            // A row the menu lists only when it is told to. The page behind it
            // is reachable either way - `nav.open(.hidden)` is a value, and a
            // value nobody drew a row for is still a value. The list being a
            // view, the answer is an `if`.
            if listsHiddenRow {
                MenuRow("Not in the list") { nav.open(.hidden) }
                    .icon(ImageSource(light: "nav_hidden.png", dark: "nav_hidden_dark.png"))
                    .chosen(nav.showing(.hidden))
            }

            // A row that DOES something rather than going somewhere. It needs
            // no type of its own: the same view, with a different handler.
            MenuRow("Surprise me") { nav.surprise(from: catalog, on: device.formFactor) }
                .icon(ImageSource(light: "nav_surprise.png", dark: "nav_surprise_dark.png"))
        }
    }

    /// What is underneath: the platform compiled in, and the formFactor the host
    /// answered before the first render.
    private var footer: any View {
        Text("native: \(stateUIPlatform()) · \(device.formFactor)")
            .font(.system(size: 11))
            .foregroundStyle(Palette.subtle)
            .multilineTextAlignment(.center)
            // Room under it for the home indicator, the content being edge to
            // edge: a phone with no home button draws a bar across the bottom
            // of the screen, and this line would otherwise sit under it.
            .padding(EdgeInsets(16, 16, 16, 30))
            // The footer's own row, written on the footer.
            .gridRow(2)
    }
}

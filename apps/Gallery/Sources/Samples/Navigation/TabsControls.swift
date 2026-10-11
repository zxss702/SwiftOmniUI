import SwiftOmniUI

/// The panel every tab of the demonstration carries: what the tab list is, what
/// the selection sends the host, and the buttons that change that list while a
/// tab is showing.
///
/// It is on EVERY tab page rather than on one of them, because what is being
/// watched is which tab the platform leaves showing - so wherever it lands, the
/// same readings are under it.
struct TabsControls: View {
    /// Where the gallery is, and the moves that change the tab list.
    let nav: Navigation

    /// The tab this copy of the panel is on, which is what lets it say whether
    /// the binding and the screen agree.
    let thisTab: DemoTab

    var body: some View {
        VStack {
            SectionTitle("The tab bar, as Swift describes it")

            VStack {
                ForEach(Array(nav.tabs.enumerated()), id: \.offset) { pair in
                    row(index: pair.offset, tab: pair.element)
                }
            }
            .spacing(4)

            Text("currentPage sent to the host · \(sentToTheHost)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.accent)

            if agrees {
                Text(verdict)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtle)
            } else {
                HStack {
                    WarningMark()

                    Text(verdict)
                        .font(.system(size: 12))
                        .bold()
                        .foregroundStyle(Palette.accent)
                }
                .spacing(6)
            }

            SectionTitle("Change the list while it is showing")

            move("Add a tab at the end") { nav.addTab(showing: thisTab) }

            move("Insert a tab before this one") {
                nav.insertTab(before: thisTab, showing: thisTab)
            }

            move("Reverse the tabs") { nav.reverseTabs(showing: thisTab) }

            move("Reset") { nav.resetTabs() }

            Text("last move · \(nav.tabsNote)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(10)
    }

    /// One row of the printed list: its index, its caption, whether it is the
    /// one selected, and a way to close it.
    ///
    /// The last row keeps no close button: a tab bar with nothing in it draws no
    /// page, so there would be nothing left to press.
    private func row(index: Int, tab: DemoTab) -> any View {
        HStack {
            Text("\(index)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.subtle)
                .frame(width: 24)

            Text(tab.caption)
                .font(.system(size: 13))
                .foregroundStyle(tab == nav.tab ? Palette.accent : Palette.text)
                .frame(width: 90)

            Text(tab == nav.tab ? "◀ selected" : " ")
                .font(.system(size: 12))
                .foregroundStyle(Palette.accent)
                .frame(width: 80)

            if nav.tabs.count > 1 {
                Button("close", action: { nav.closeTab(tab, showing: thisTab) })
                    .font(.system(size: 12))
                    .padding(EdgeInsets(10, 2))
                    
            }
        }
        .spacing(8)
    }

    /// One of the buttons, all of which look the same.
    private func move(_ caption: String, _ act: @escaping EventHandler) -> Button {
        Button(caption, action: act)
            .font(.system(size: 13))
            .padding(EdgeInsets(16, 6))
            .horizontalAlignment(.start)
            
    }

    /// The index `TabView.selection` sends the host for this selection -
    /// the same line the library runs, repeated here so that the number is on
    /// screen.
    ///
    /// A property is sent only when its VALUE changed, so a move that leaves
    /// this number alone sends nothing at all and the tab bar is rebuilt
    /// underneath a selection nobody restated. That is the case `Reverse the
    /// tabs` makes, from the middle of three.
    private var sentToTheHost: String {
        guard let index = nav.tabs.firstIndex(of: nav.tab) else {
            return "nothing - the selection names no tab"
        }

        return "\(index)"
    }

    /// Whether the binding and the tab actually on screen are the same tab.
    private var agrees: Bool {
        nav.tab == thisTab
    }

    /// What that comparison says, in words.
    private var verdict: String {
        agrees
            ? "The binding says \(thisTab.caption), and \(thisTab.caption) is what you are looking at."
            : "THE BINDING SAYS \(nav.tab.caption) - YOU ARE LOOKING AT \(thisTab.caption)."
    }
}

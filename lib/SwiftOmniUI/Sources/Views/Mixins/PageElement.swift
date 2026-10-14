// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The title and icon of an arrangement - a `NavigationStack`, a `TabView`
/// or a `NavigationSplitView` - read where it is shown as an item of something else,
/// such as a tab:
///
///     TabView(Tab.allCases) { tab in
///         switch tab {
///         case .home:
///             NavigationStack($homePath) {
///                 HomePage()
///             } destination: { … }
///             .title("Home")                    // the tab's caption
///             .icon("house.png")                // and its picture
///
///         case .settings:
///             SettingsPage()                    // a written page sets
///         }                                     // `page.title` instead
///     }
///
/// A page the author writes says the same through its `PageSession`.
@preconcurrency @MainActor public protocol PageElement: PropertyContainer {}

extension PageElement {
    /// What the page is called: a tab's caption, and the window's title where
    /// a platform takes one from the page.
    ///
    /// Not the text on a navigation bar, which belongs to the page on top of
    /// the stack; a title on the `NavigationStack` itself names the whole stack.
    @_spi(Host) public func title(_ value: String) -> Modified {
        setValue(PageElementContract.title, value)
    }

    /// The picture that stands for the page: a tab's icon. A page not shown as
    /// an item of something else has nowhere to draw it.
    @_spi(Host) public func icon(_ value: ImageSource) -> Modified {
        setValue(PageElementContract.icon, value)
    }

    /// The mark the item wears on its icon - a count or a short word, drawn as
    /// the container draws one:
    ///
    ///     NavigationStack($path) { MailPage() }
    ///         .title("Mail")
    ///         .badge("3")
    public func badge(_ value: String) -> Modified {
        setValue(PageElementContract.badge, value)
    }

    /// `badge` from a state, `$x`: the host writes each new mark, and no view
    /// is rebuilt for it.
    public func badge(_ state: Binding<String>) -> Modified {
        words(PageElementContract.badge, by: state)
    }

}

extension View {
    /// The title the page holding this view shows - on its navigation bar,
    /// and on a tab or the window where the platform takes one from the page:
    ///
    ///     Form { … }
    ///         .navigationTitle("Settings")
    ///
    /// Written on a page's root view it names the page itself, as `page.title`
    /// does from inside.
    @_disfavoredOverload public func navigationTitle<S: StringProtocol>(_ value: S) -> ModifiedContent {
        setting(PageElementContract.title, String(value))
    }

    /// The title the page holding this view shows, looked up - the key beside
    /// its `displayString` fallback, which the host's answer stands in for:
    ///
    ///     Form { … }
    ///         .navigationTitle("Settings")
    public func navigationTitle(_ key: LocalizedStringKey) -> ModifiedContent {
        setting(PageElementContract.title, key.displayString)
            .setting(PageElementContract.titleKey, key)
    }

    /// `navigationTitle` from a state, `$x`: the host writes each new title,
    /// and no view is rebuilt for it.
    @_disfavoredOverload
    public func navigationTitle(_ state: Binding<String>) -> ModifiedContent {
        revised { $0.driveWords(PageElementContract.title, by: state) }
    }

    /// The item the page holding this view is tabbed under - caption and
    /// icon as the label states them:
    ///
    ///     StackPage()
    ///         .tabItem(Label("Stack", image: "tab_bar.png"))
    ///
    /// Written on a page's root view it names the page's tab, as `page.icon`
    /// does from inside. A label composed of custom views rather than the
    /// `Label(_:image:)` and `Label(_:systemImage:)` initializers keeps its
    /// look inside the page and names no item.
    public func tabItem(_ label: Label) -> ModifiedContent {
        var made = label.semanticParts.icon.map { setting(PageElementContract.icon, $0) }
            ?? revised { _ in }
        if let title = label.semanticParts.title {
            made = made
                .setting(PageElementContract.title, title.display)
                .setting(PageElementContract.titleKey, title.key)
        }
        return made
    }
}

extension View {
    /// The heights the sheet holding this view may stand at, first the one
    /// preferred:
    ///
    ///     SheetForm()
    ///         .presentationDetents([.height(220), .large])
    ///
    /// Written on a presented page's root. A platform without detents takes
    /// the largest it can as the sheet's own size.
    public func presentationDetents(_ detents: [PresentationDetent]) -> ModifiedContent {
        setting(PageElementContract.presentationDetents, detents)
    }

    /// `presentationDetents` from a state, `$x`: each new list is written as
    /// the state renders this view again.
    @_disfavoredOverload
    public func presentationDetents(_ state: Binding<[PresentationDetent]>) -> ModifiedContent {
        setting(PageElementContract.presentationDetents, state.wrappedValue)
    }

    /// Whether the sheet holding this view shows its drag handle:
    ///
    ///     SheetForm()
    ///         .presentationDragIndicator(.hidden)
    ///
    /// Written on a presented page's root.
    public func presentationDragIndicator(_ visibility: Visibility) -> ModifiedContent {
        setting(PageElementContract.presentationDragIndicator, visibility)
    }

    /// `presentationDragIndicator` from a state, `$x`: the host writes each
    /// new visibility, and no view is rebuilt for it.
    @_disfavoredOverload
    public func presentationDragIndicator(_ state: Binding<Visibility>) -> ModifiedContent {
        revised { $0.drivePlain(PageElementContract.presentationDragIndicator, by: state) }
    }

    /// Whether the user may not dismiss the sheet holding this view - its
    /// gestures, close button and backdrop press all off:
    ///
    ///     CloningSheet()
    ///         .interactiveDismissDisabled(cloning)
    ///
    /// Written on a presented page's root. `true` where the argument is left
    /// out, as SwiftUI's no-argument form is.
    public func interactiveDismissDisabled(_ disabled: Bool = true) -> ModifiedContent {
        setting(PageElementContract.interactiveDismissDisabled, disabled)
    }

    /// `interactiveDismissDisabled` from a state, `$x`: the host writes each
    /// new answer, and no view is rebuilt for it.
    @_disfavoredOverload
    public func interactiveDismissDisabled(_ state: Binding<Bool>) -> ModifiedContent {
        revised { $0.drivePlain(PageElementContract.interactiveDismissDisabled, by: state) }
    }

    /// The title the page holding this view shows, from a `Text` - its words,
    /// its styling left with the page's own conventions:
    ///
    ///     Form { … }
    ///         .navigationTitle(Text(name))
    ///
    /// Written on a page's root view it names the page itself, as `page.title`
    /// does from inside.
    public func navigationTitle(_ title: Text) -> ModifiedContent {
        var written = setting(PageElementContract.title, title.words)
        if let key = title.wordsKey {
            written = written.setting(PageElementContract.titleKey, key)
        }
        return written
    }

    /// The secondary text the page's title area shows, beside or below the title
    /// according to the platform's own title bar:
    ///
    ///     ContentView()
    ///         .navigationSubtitle("New conversation")
    ///
    /// Written on a page's root view it names the page itself.
    @_disfavoredOverload public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> ModifiedContent {
        setting(PageElementContract.subtitle, String(subtitle))
    }

    /// The same, looked up - the key beside its `displayString` fallback.
    public func navigationSubtitle(_ key: LocalizedStringKey) -> ModifiedContent {
        setting(PageElementContract.subtitle, key.displayString)
            .setting(PageElementContract.subtitleKey, key)
    }

    /// `navigationSubtitle` from a `Text` - its words, its styling left with
    /// the page's own conventions.
    public func navigationSubtitle(_ subtitle: Text) -> ModifiedContent {
        var written = setting(PageElementContract.subtitle, subtitle.words)
        if let key = subtitle.wordsKey {
            written = written.setting(PageElementContract.subtitleKey, key)
        }
        return written
    }

    /// The document the page stands for, as its path - where a platform shows
    /// one in the window's chrome, as a macOS window's proxy icon and path do:
    ///
    ///     EditorView()
    ///         .navigationDocument(documentPath)
    ///
    /// Written on a page's root view it names the page itself.
    public func navigationDocument(_ documentPath: String) -> ModifiedContent {
        setting(PageElementContract.document, documentPath)
    }

    /// Whether the page's way back - the navigation stack's back button -
    /// shows over it. `true` where the argument is left out, as SwiftUI's
    /// no-argument form is:
    ///
    ///     PushedPage()
    ///         .navigationBarBackButtonHidden()
    ///
    /// Written on a page's root view it speaks for the page itself.
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> ModifiedContent {
        setting(PageContract.hasBackButton, !hidesBackButton)
    }

    /// The width the split-view column this view leads asks for - its least,
    /// its ideal, and its most:
    ///
    ///     SidebarView()
    ///         .navigationSplitViewColumnWidth(min: 256, ideal: 280, max: 400)
    ///
    /// Written on a column's root view it speaks for the column itself; a
    /// platform that fixes its columns takes the ideal where it can.
    public func navigationSplitViewColumnWidth(
        min: Double? = nil, ideal: Double? = nil, max: Double? = nil
    ) -> ModifiedContent {
        setting(PageElementContract.preferredColumnWidth, [min ?? -1, ideal ?? -1, max ?? -1])
    }

    /// A fixed width for the split-view column this view leads.
    public func navigationSplitViewColumnWidth(_ width: Double) -> ModifiedContent {
        navigationSplitViewColumnWidth(min: width, ideal: width, max: width)
    }

    /// Whether the window's own toolbar shows over the page holding this
    /// view:
    ///
    ///     ContentView()
    ///         .toolbarVisibility(.hidden, for: .windowToolbar)
    ///
    /// Written on a page's root view it speaks for the page itself. A
    /// placement other than `.windowToolbar` has no bar of its own yet and is
    /// left to the platform.
    public func toolbarVisibility(
        _ visibility: Visibility, for bars: ToolbarPlacement = .automatic
    ) -> ModifiedContent {
        revised {
            if bars.contains(.windowToolbar) || bars == .automatic {
                $0.write(PageElementContract.toolbarVisibility, visibility)
            }
        }
    }

    /// Whether the window's own toolbar paints its background over the page
    /// holding this view:
    ///
    ///     ContentView()
    ///         .toolbarBackground(.hidden, for: .windowToolbar)
    ///
    /// Written on a page's root view it speaks for the page itself.
    public func toolbarBackground(
        _ visibility: Visibility, for bars: ToolbarPlacement = .automatic
    ) -> ModifiedContent {
        revised {
            if bars.contains(.windowToolbar) || bars == .automatic {
                $0.write(PageElementContract.toolbarBackground, visibility)
            }
        }
    }

    /// The colour the window paints behind the page's own background - a
    /// material colour reaching the window itself:
    ///
    ///     Color.clear.windowBackground(.windowBackground)
    ///
    /// Written on a page's root view it speaks for the window the page stands
    /// in.
    public func windowBackground(_ background: Color) -> ModifiedContent {
        setting(PageElementContract.windowBackground, background)
    }
}

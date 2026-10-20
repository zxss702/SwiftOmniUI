// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// What this host realizes beyond its registry, whose export says the rest - the GTK 4 column of the control
/// dictionary; a member is recorded once a test of this package covers it.
/// Design: docs/design/contracts/dictionary.md#marks
enum GTKRealization {
    /// The entries this host realizes none of: those it shows as unsupported, and the parts of one.
    static let unrealized: Set<String> = [
        "Content", "GridRow", "LeadingContent", "Map",
        "Pin", "PositionIndicator", "TrailingContent",
    ]

    /// The entries a backend realizes on this host - a package of its own, for a library GTK does not ship - which
    /// the application's head registers: WebKitGTK's web view. Realized none of until it is registered.
    static let backends: Set<String> = ["WebView"]

    /// What the running host realizes none of: what it never makes, and each backend no one registered.
    @MainActor static var unmade: Set<String> {
        unrealized.union(backends.subtracting(GTKRegistrations.registry.realization.elements))
    }

    /// The entries this host presents with no view of their own - a title bar is the window's, a span a run of its
    /// label's words - so no tier's record reaches them: only a member the entry's own records name is realized.
    static let viewless: Set<String> = ["Span", "TitleBar"]

    /// The entries GTK will not have; none.
    static let notPlanned: [String: String] = [:]

    /// Every record, the tiers' first.
    static let records: [HostRecord] = [
        // MARK: Tiers - a member every wearer realizes alike
        .complete("Menu", "isEnabled"),
        .complete("Menu", "text"),
        .complete("MenuItemElement", "clicked"),
        .complete("MenuItemElement", "icon"),
        .complete("MenuItemElement", "isEnabled"),
        .complete("MenuItemElement", "text"),
        .notPlanned("MenuItem", "icon", reason: "GNOME's menus show words alone, no picture beside them."),
        .notPlanned("MenuItem", "isDestructive", reason: "GNOME's menus mark no entry as destroying something."),
        .complete("PageElement", "badge"),
        .notPlanned("PageElement", "document",
            reason: "GTK 4 names a window for a document in its title alone."),
        .notPlanned("PageElement", "interactiveDismissDisabled",
            reason: "A GTK sheet is libadwaita's dialog: Escape and its close always take it."),
        .notPlanned("PageElement", "presentationDetents",
            reason: "A GTK sheet is libadwaita's dialog, sized by what it shows - detents are not its to take."),
        .notPlanned("PageElement", "presentationDragIndicator",
            reason: "A GTK sheet is libadwaita's dialog, which draws no grabber of its own."),
        .partial("PageElement", "preferredColumnWidth",
            missing: "An ideal width has no home in AdwOverlaySplitView; only the bounds bind it."),
        .complete("PageElement", "subtitle"),
        .complete("PageElement", "title"),
        .partial("PageElement", "toolbarVisibility",
            missing: "A tabbed view's shared header retains its own visibility."),
        .partial("PageElement", "toolbarBackground",
            missing: "A tabbed view's shared header retains its own background."),
        .partial("PageElement", "windowBackground",
            missing: "A brush fills the window with its first colour alone."),
        .notPlanned("VisualElement", "accessibilityChildBehavior",
            reason: "GTK's accessibility bridge answers no child behaviour yet."),
        .notPlanned("VisualElement", "accessibilityTraits",
            reason: "GTK's accessibility bridge answers no traits yet."),
        .notPlanned("VisualElement", "contentTransition",
            reason: "GTK swaps a label's words with no transition yet."),
        .notPlanned("VisualElement", "matchedGeometry",
            reason: "GTK's layout motion flies no matched child into place yet."),
        .notPlanned("VisualElement", "matchedGeometrySource",
            reason: "GTK's layout motion flies no matched child into place yet."),
        .notPlanned("VisualElement", "symbolEffect",
            reason: "GTK's pictures are painted, not animated as symbols."),
        .notPlanned("VisualElement", "symbolEffectActive",
            reason: "GTK's pictures are painted, not animated as symbols."),
        .notPlanned("VisualElement", "symbolEffectOptions",
            reason: "GTK's pictures are painted, not animated as symbols."),
        .notPlanned("VisualElement", "symbolEffectValue",
            reason: "GTK's pictures are painted, not animated as symbols."),
        .notPlanned("VisualElement", "blendMode",
            reason: "GTK composites every view normally; a blend pass over its own content draws nothing yet."),
        .complete("View", "layoutPriority"),
        .partial("View", "horizontalGuide",
            missing: "GTK's items name no text baseline: the baseline guides land on edges; the rest align."),
        .partial("View", "verticalGuide",
            missing: "GTK's items name no text baseline: the baseline guides land on edges; the rest align."),
        .notPlanned("View", "pointerStyle",
            reason: "GTK sets a widget's cursor only through the frame's display, which the element layer does not own yet."),
        .complete("VisualElement", "hint"),
        .complete("VisualElement", "layoutDirection"),
        .complete("VisualElement", "style"),

        // MARK: Entries - a control's or a part's own
        .partial("DatePicker", "format", missing: "GTK writes \"D\" and \"d\" in the user's own way, and any other pattern as \"d\"."),
        .partial("DatePicker", "maximumDate",
                 missing: "GtkCalendar offers every day: one the user picks past the range stands at its end."),
        .partial("DatePicker", "minimumDate",
                 missing: "GtkCalendar offers every day: one the user picks past the range stands at its end."),
        .partial("TimePicker", "format",
                 missing: "GTK writes hours and minutes in the user's own clock, whatever the format asks: no seconds, no pattern."),
        .unrealized("List", "style", why: "No style can name an List: a style names its control by an "
            + "initializer that sets nothing, which a list of some items has not."),
        .unrealized("MenuButton", "style", why: "No style can name a MenuButton: the `Menu` view makes one, "
            + "and no `Menu()` means anything; its closed style vocabulary crosses as `.menuStyle`."),
        .partial("Text", "background", missing: "A brush fills the box with its first colour alone."),
        .notPlanned("Text", "minimumScaleFactor",
            reason: "Pango gives a label no shrink-to-fit factor; the text truncates by its lineBreak instead."),
        .partial("Text", "textRenderer",
            missing: "A native label draws the words itself: a renderer watching layout degrades to the default draw pass; its own draw never runs."),
        .complete("MenuButton", "isEnabled"),
        .complete("MenuButton", "menuIndicator"),
        .complete("MenuButton", "menuStyle"),
        .partial("ProgressBar", "progressStyle",
            missing: "The bar GTK draws is linear; `circular` falls back to it rather than the spinner."),
        .partial("Image", "renderingMode",
            missing: "GTK paints the picture as loaded; `template` does not retint it against the theme."),
        .complete("Page", "appearing"),
        .complete("Page", "disappearing"),
        .complete("Page", "hasNavigationBar"),
        .complete("Page", "navigatedFrom"),
        .complete("Page", "navigatedTo"),
        .complete("Page", "navigatingFrom"),
        .complete("RadioButton", "groupName"),
        .notPlanned("Slider", "dragCompleted", reason: "GTK's scale tells no one it is held: its range claims the "
            + "press, and GTK denies every other gesture on it."),
        .notPlanned("Slider", "dragStarted", reason: "GTK's scale tells no one it is held: its range claims the "
            + "press, and GTK denies every other gesture on it."),
        .complete("Span", "background"),
        .complete("Span", "fontAttributes"),
        .complete("Span", "fontSize"),
        .complete("Span", "text"),
        .complete("Span", "foregroundStyle"),
        .complete("Span", "textDecorations"),
        .complete("NavigationSplitView", "isSidebarVisible"),
        .complete("NavigationSplitView", "columnVisibility"),
        .complete("NavigationSplitView", "columnVisibilityChanged"),
        .complete("TabView", "currentPage"),
        .complete("TitleBar", "background"),
        .complete("TitleBar", "barForegroundColor"),
        .complete("ToolbarItem", "placement"),
        .complete("ToolbarItem", "priority"),
        .complete("ToolbarSpacer", "placement"),
        .complete("ToolbarSpacer", "variant"),
        .complete("WindowScene", "allowsRestoration"),
        .partial("WindowScene", "resizability",
            missing: "A content minimum names the window element's own minimum instead of measuring content."),
        .unrealized("WindowScene", "defaultPosition",
            why: "GTK keeps no window-positioning request: where a window opens is the compositor's."),
    ]

    /// What GTK's registry says it realizes: the export's content.
    @MainActor static var declaration: HostDeclaration {
        let registry = GTKRegistrations.registry
        return HostDeclaration(
            realization: registry.realization, shared: registry.sharedNames, acts: GTKRegistrations.acts.map(\.name))
    }

    /// What GTK realizes, member by member: these records before what its registry says. A backend's entry is
    /// unrealized only while no application registered it.
    @MainActor static var register: HostRegister {
        HostRegister(
            records: records,
            unrealized: unrealized.union(backends.subtracting(GTKRegistrations.registry.realization.elements)),
            viewless: viewless, notPlanned: notPlanned
        ).and(declaration)
    }
}

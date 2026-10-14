# Pages on WinUI

How the WinUI host presents a window's arrangement of pages - a navigation
stack, a split view, a set of tabs - as a Windows desktop application
presents its own: one chrome across the top of the window, WinUI's own
navigation pane, and the way back the mouse and the keyboard offer. SwiftOmniUI
keeps every page, the path and the selection; WinUI is given no second
navigation model to reconcile with them.

## Page-level safe bars

Top inset surfaces occupy a native Grid/StackPanel overlay in the existing
content row, directly beneath TitleBar, menus and tabs. They do not create an
auto row or shrink the ScrollView viewport. The common surface takes the
TitleBar background and uses a native theme brush for the lower scroll edge;
sheets and authored window overlays remain above it. Explicit bar backgrounds
stay on their original views.

The overlay's origin and width follow the visible page's native allocation,
including the NavigationSplitView detail column. Its page-sized proposal must
match the source inset's logical proposal: measuring a detail bar at full
window width would both cover the sidebar and alternate layout proposals.
Source placement queues a coalesced geometry update; unchanged geometry
does not write XAML layout properties again.

Only the uninterrupted page-root modifier chain is promoted. Local layouts,
finite frames, clipping, side boundaries and negative spacing retain ordinary
local hosting. The mounted source keeps geometry, animation and coordinate
ancestry while native ownership changes are coalesced after layout. Old hosts
release their children before new ones attach them; weak queued callbacks do
nothing after release or window teardown.

## The window's chrome

The visible page's `windowBackground` paints the native root behind the entire
client area; removing it restores the system backdrop. A composed page can
supply that colour around its navigation arrangement.

Hiding `.windowToolbar` removes the XAML title bar and its layout row. Content
then reaches the window's top edge, beneath Windows' native caption buttons,
whose resting backgrounds are transparent. The default caption drag strip is
cleared so it does not intercept controls along that edge. Showing the toolbar
again reattaches the same native title bar and restores its height.

A window has one chrome: WinUI's `TitleBar`, across the top of a window
whose content extends under its title bar, over a Mica backdrop, as
Windows' own applications stand. The renderer composes it again from what
the window shows after every render, and after every change the user makes
that the application may not render for - a tab chosen, the sidebar shown:

- the title of the page that names the window, on the chrome and to the
  system - the visible page, but tabs on a stack name it by their own title,
  else by the page beneath ([the window's chrome](../../host/pages.md#the-windows-chrome));
- the resolved `navigationSubtitle` is written to the same native
  `TitleBar.Subtitle` property, and cleared when it becomes empty or absent.
  WinUI owns its placement and compact-mode visibility;
- the way back is the chrome's own back button, while the visible stack's
  top page can go back;
- a split view adds the chrome's pane toggle, which shows and hides its
  sidebar;
- the visible page's actions stand on a command bar at the chrome's trailing
  side, in their priority's order, those it places in overflow behind the
  bar's own "more"; an action with a picture shows the picture alone - the
  first of the files its name stands for that the application's pictures
  hold ([pictures](controls.md#pictures)), or the Fluent glyph its name is -
  its words naming it to Narrator and in its tip. A `Button` an item carries
  with a picture or words - a `Toggle` of `.button` style is one - is the
  bar's own `AppBarToggleButton`, momentary until it wears `isOn`: the
  picture in its icon slot, the words its label, or its tip when it has a
  picture, WinUI's own look throughout. A view of the author's stands in an
  `AppBarElementContainer`, a `Menu` as the view's menu button with the menu
  as its flyout;
- the page's title view stands at the chrome's centre, where an application
  puts its search;
- an authored `TitleBar` adds its leading, centre and trailing content, and
  the bars' colours paint the chrome; with no colour written for what stands
  on it, the chrome takes the dark color scheme on a dark band and the light one on
  a light band ([words on a painted
  band](../../host/layout.md#words-on-a-painted-band)), its title, its
  buttons and its commands alike - the window's own caption buttons keep
  Windows' colours;
- the visible page's menus stand on a menu bar beneath the chrome
  ([menus](#menus)).

A page that hides its navigation bar puts neither the way back nor its
actions on the chrome.

WinUI's `TitleBar` keeps a column at each edge for the window's own buttons,
as wide as the window's insets - which it takes in pixels as though they were
DIPs (microsoft-ui-xaml #10344): at 200% the actions stand a caption's width
short of the bar's end. The relay caps each column at the inset over the
window's scale, whenever the bar is loaded or changes size; a column WinUI
sizes right stays as it is. The drag column WinUI keeps beside the buttons
stays too.

## A navigation stack

A navigation stack shows its top page across its whole frame; the pages below
are kept by their elements and held by no view, so each keeps what it showed
for when the user comes back to it. Its bar is the window's chrome.

The layout panel holds a native `Frame`. Its `Navigate` call creates a stock
`Page` shell whose content is the retained Swift view: forward navigation uses
`SlideNavigationTransitionInfo` with `FromRight`, return uses `FromLeft`.
The first presentation and reduced-motion navigation suppress transitions.
`IsNavigationStackEnabled` is false and page caching is disabled; Swift's path
remains the only navigation history. A view still held by an old page during a
rapid return is released from that page before attachment to the new one.
The panel continues to supply Swift layout and safe-area context, while the
Frame measures and arranges its native shells and owns the transition timing.

## The way back

The way back is the chrome's back button, the mouse's back button, Alt+Left
and the Back key - each the window's, as Windows applications offer it - and
it pops the visible stack's top page.

## A split view

A split view uses WinUI's `SplitView`, with the sidebar in its leading pane.
From 1008 DIPs it stands inline; below that it overlays the content and the
native light-dismiss interaction closes it. There is no NavigationView item
rail or template row to replace: each column receives the full finite height.

A three-column split nests a trailing `SplitView` inside the outer content.
Its pane holds the auxiliary detail; its content holds the flexible middle
column. The trailing split stays inline. A detail width of zero removes that
native column, and `.detailOnly` hides the middle column so detail takes the
remaining room. Page identities and business navigation state stay in Swift.

Both pane boundaries use native `Thumb` drag capture. Minimum/ideal/maximum
bounds choose the initial pane width and constrain resizing; unchanged bounds
do not overwrite the user's width. Content minimum/maximum constrain the
remaining column. Native owners release their children before a page moves
between the two-column and three-column forms. Native column configuration
is coalesced outside MeasureOverride/ArrangeOverride.

Whether the sidebar shows follows the binding and native pane events. The
first wide room opens it once; after that the user and the application decide.
The shared page path includes every visible column for appearance/disappearance.

## A native arrangement

Native SplitViews measure their own columns at the finite room supplied by the
parent. Swift measures the outer split before arrangement and reports that
result; it never measures a content page at the whole window width or calls
Measure from Arrange. Changes of content or column width invalidate the native
measurement without rebuilding page trees.

## Tabs

A tabbed view's tabs are a `SelectorBar`. The first tabbed view down the
visible page path - through stacks and split views' details - gives its tabs
to the window: they stand across the window beneath its chrome, or across a
split view's detail, beside the sidebar and never over it. Any other tabbed
view - in a sidebar, in a tab of another, inside content - shows its tabs in a
row of its own above its page. Choosing a tab is the user choosing it: the
pages hear it, then the selection's state, and the chrome follows at once.

## A page's phases

A page hears its phases as the host layer tells them ([a page's
phases](../../host/pages.md#a-pages-phases)); WinUI supplies the tab the user
chose and whether the navigation view's pane shows, which the layer reads to
know what an arrangement shows.

## The modal stack

The pages a window's modal stack presents stand over everything the window
shows, as WinUI presents a dialog: each on a card over a veil across the
whole window - the chrome and the tabs too - the last on top. The card is a
dialog's own - its background, outline and corners, no wider than a dialog
and clear of the window's edges - with the presented page's title above the
page, and it enters as a dialog enters. The veil takes every click meant for
what is beneath, and the keyboard goes round inside the top card.

What the user sees is the top sheet, else the window's arrangement: when that
changes, the page that stops showing hears it and then the one that starts,
as a move. Escape takes the top sheet away, and so does the window's way back
while a sheet shows, once the sheet's own stack has no page to go back to;
the window is told how many sheets remain.

## The window's overlay

What a window lays over everything it shows - the inspector docked in it -
stands where the page stands, beneath the chrome, over the page and over
every sheet, whichever came first. It has no background of its own, so a
click beside what it holds goes on to the page or the sheet under it. It and
the sheets are layers of the window, not the content of a row: the chrome and
the menu bar standing again, as a page's menus come and go, leave both where
they are. The window takes the overlay out when it no longer describes it.

## Menus

The visible page's menus stand on WinUI's `MenuBar` in a row of the window
beneath its chrome, above the window's tabs - each menu one of the bar's,
its entries within it - while the page has any; a page with none leaves no
row. The bar is written again only when what it draws changes: a render that
changes nothing on it leaves the bar, and a menu open on it, as they are.

A view's context menu is WinUI's `MenuFlyout` on the view: a right click and a
long press open it where the user asked, and on a view that holds the
keyboard, the menu key and Shift+F10 too. Its items
are `MenuFlyoutItem`s, its separators `MenuFlyoutSeparator`s and its submenus
`MenuFlyoutSubItem`s, one level inside another as the tree nests them; an
entry that cannot be chosen is shown dimmed. The host hands the relay the
menu flat - an item, a separator, a submenu opening and closing, each with its
caption - and hears a choice by the item's place among the items, submenus'
included; the item's own handler runs. A bar's menus are written the same
way. Any entry the tree changes, adds or
removes gives the view its menu again, and a menu with no entries is none.

A view-labeled Menu requests its root content through the native flyout's
Opening event. MenuFlyoutSubItem has no separate public Opening event; WinUI
creates its submenu presenter during expansion. The disabled Text placeholder's
native Loaded event requests that visible level, including keyboard and UI
Automation expansion. Initial focus in the main menu does not request unopened
descendants. Each request mounts only that level, and repeated requests keep its existing state.
Updates reuse the MenuFlyout and match submenu controls by mounted element
number, retaining an expanded parent while its contents arrive. The relay
receives these numbers alongside the existing flat menu entries.

`.buttonStyle(.plain)` reaches Menu triggers directly or through a container.
It clears the native background, border and padding and supplies transparent
hover, pressed and disabled resources; switching to automatic restores the
native menu-style choice.

A stack with a menu is hit across its bounds, as a listening one is
([listening](input.md#listening)): a right click anywhere across it opens the
menu, not only on its children.

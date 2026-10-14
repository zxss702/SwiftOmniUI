# Pages on GTK

How the GTK host presents a window's pages as GNOME's own applications do:
each page under a header bar of its own, which slides with it.

## A page and its header bar

A page GTK shows stands in a frame: an `AdwToolbarView` whose top bar is the
page's own `AdwHeaderBar`, over the page's view. A tabbed view stands in one
too. A page shown by itself is the window's content in such a frame, its
header bar the window's title bar; a page of a stack is one in its navigation
page; a split view's pane is one where it is a page. A stack and a split view
stand in none: their pages carry their own. The frame holds its bar's title
itself, since a title view takes its place in the bar and the bar lets go of
what it no longer shows. The frame lets go of nothing in
it as it goes: a page popped still slides away in it, and GTK lets the whole
of it go once the slide is over.

Page-level top inset surfaces are added after the native header and tabs in
the same `AdwToolbarView`. Content extends to its top edge, while the placement
context reserves only the native header/tabs there; each source inset reserves
its own extent once. The native toolbar owns the combined backdrop. Since
extend-content disables libadwaita's flat undershoot, page scrollers drive the
native raised bar style while scrolled; its shadow lands below the complete
top region. Only their displaced top scroller effects are suppressed. Bottom,
side and local insets remain transparent layouts, with independent edge effects.

A promoted authored widget has one native parent. Its logical source and
placing layout remain unchanged, retaining ancestor animation matrices,
opacity, hit-testing scope, named spaces and parent-coordinate reports. Native
hosting releases it before returning it to the logical panel. On frame
teardown, content extension is reset and the bar returns to local placement,
so a departing navigation page can remain owned by GTK through its slide.

## The chrome

The visible page's `windowBackground` paints the native application window,
including when a composed page supplies it around a navigation arrangement.
Removing the colour restores GTK's background.

Hiding `.windowToolbar` removes the header's reserved height. A native
`GtkWindowControls` with only the close action stands over the top-right corner
of the content, without contributing to its measurement or safe area. The
page's content stands in a `GtkWindowHandle`: GTK's bubbling gestures leave
native controls their input and let the window manager move the window from
unclaimed content, including blank space inside a scroller. Window overlays
and the close controls stand outside that handle. Showing the toolbar again
unwraps the same content, hides the floating controls and restores the header.

The chrome is composed by one function from what the window shows, after
every render, and written on the header bar of each page shown:

- the page's title, at the middle of its bar, or its title view in its place,
  where an application puts its search;
- the resolved `navigationSubtitle` beneath it, through the same
  `AdwWindowTitle`; enclosing navigation metadata is inherited for the main
  content column and changes in place with the title;
- the page's actions, at the bar's end in their priority's order, those it
  places in overflow behind the bar's menu. An action with a picture stands
  on the bar as an icon, the way a header bar's buttons stand, its title its
  tooltip and its name to assistive technology; one whose picture the
  application does not hold shows its title, and the overflow's menu shows
  titles. So the bar's own buttons never read as one more choice of a
  tabbed view's switcher beside them;
- the way back, the bar's own back button, which libadwaita shows while the
  page has one below it and the page does not refuse it;
- no bar at all, for a page that hides its navigation bar;
- a split view's sidebar toggle, at the start of the bar of the page the user
  sees in its detail, pressed in while the sidebar shows;
- for a tabbed view, its switcher in the middle, over the chosen tab's page's
  actions;
- the bar's colours: a page's header bar is painted in the bar colour of the
  nearest stack or tabbed view around it, and what stands on it - the title,
  the way back, the toggles and the switcher's captions - in the nearest
  stack's foreground, as a class of the host's style sheet
  ([a widget's own box](drawing.md#a-widgets-own-box)). The window's title
  bar has no place of its own on a desktop of header bars: its colours paint
  every header bar no arrangement colours - a split view's sidebar among
  them - and a bar neither colours keeps the platform's.

The page the user sees names the window, for the desktop's switcher and dock;
a page with no title leaves the window's own.

## A navigation stack

A navigation stack is libadwaita's `AdwNavigationView`, each page in a
navigation page holding its frame. A path one page longer pushes the page, one
shorter pops to where it now ends, any other change replaces the stack - each
as the program's move, whose `popped` is its echo. The user's back - the back
button, the swipe, Alt+Left, the mouse's back button - pops in GTK first, and
the stack's `popped` then tells the path how many pages remain; a path that
does not follow is put back by the next render. A page is pushed named as the
tree names it, or after the application until it does: libadwaita asks every
page for a title.

## A split view

Wide split views use native `GtkPaned` boundaries: the sidebar at the leading
edge, flexible main content in the middle, and an optional detail at the
trailing edge. Each pane retains its user's width, starting at the modifier's
ideal and clamped to the minimum/maximum and the neighboring column's room.
GtkPaned owns pointer capture and keyboard resizing. Width requests are placed
on native slot wrappers, leaving the authored page's requests intact.

A detail width of zero removes the auxiliary pane. Column visibility also
controls the middle column and every visible column's appearance lifecycle.
Frames follow their page when columns change, and native owners release each
widget before it is assigned another parent.

Below the window's 400sp breakpoint, libadwaita's `AdwOverlaySplitView` hosts
the sidebar over the same content. Its light-dismiss and swipe interactions
update the binding; wide windows return the sidebar to the draggable layout.
Parent changes and constrained positions are committed outside GTK allocation.
The first wide room opens the sidebar once, as the shared adaptation specifies.

## Tabs

A tabbed view is a `GtkStack` of its tabs, each named by its page's title,
and its `GtkStackSwitcher` - the captions joined in one control - stands at
the start of a bar of its own beneath the header bar of the frame the tabbed
view stands in, painted as the header bar is. The header bar keeps its room
for the title - the host layer's: tabs on a stack name it by their own
title, else by the page beneath - the chosen tab's actions and the window's buttons,
and the tabs' bar scrolls them across where the page is narrower than they
are. The
switcher's choice is the user's: the pages hear it, then the selection's
state, and the header bar follows the chosen tab whether or not the
application renders again.

## Menus

A menu is GTK's model of one: the host layer's walk of its entries
([menus](../../host/pages.md#menus)) as a `GMenu` - the entries between two
separators a section, a submenu a link - each item an action of a group the
menu hands the widget it stands on, which GTK runs only while it is enabled;
a submenu out of reach is one whose tracking action is not. GNOME's menus
show words alone: no picture beside them, no entry marked as destroying
something.

A view's context menu is a `GtkPopoverMenu` on the view's widget, opened
where the user clicks with the secondary button or holds a finger, at that
point; a panel presents it as it lays out. A menu of no entries is none.

A desktop of header bars has no menu bar: the menus a page declares stand in
the main menu at the very end of its header bar - GNOME's
`open-menu-symbolic` button - each a submenu holding its entries, joined by
the host layer's rule. A page that declares none shows no main menu.

Scene commands use a separate native menu button at the start of one visible
header. A `CommandGroup(replacing: .appInfo)` contributes its entries there;
a `CommandMenu` contributes a submenu. The window controller chooses the
actual frame carrying the header, rather than comparing it with the page
that supplies the window title: the window's own frame, the top navigation
frame, or the leading visible split column. Page wrappers and tab selection
do not drop commands, and hiding a split column moves the menu to the next
visible header. Hidden and inactive frames carry no duplicate command menu.
Unchanged entries keep their native model and actions; updates compare nested
contents and target element identities as well as captions and enabled state.

## The window's overlay

What a window lays over everything it shows - the inspector docked in it, an
application's own layers - is an overlay of the `GtkOverlay` the window's
content stands in: over the whole window, header bars included, which the
inspector's own layout leaves free where it docks at a side. It holds a
layout that lets input through, so a click beside what it holds goes on to
the page under it ([listening](input.md#listening)). The window takes the
overlay out when it no longer describes it.

## A page's phases

A page hears its phases as the host layer tells them ([a page's
phases](../../host/pages.md#a-pages-phases)); GTK supplies the tab the user
chose and whether the sidebar shows, which the layer reads to know what an
arrangement shows.
## Sheets

A page a window's modal stack presents is a sheet: libadwaita's `AdwDialog`
over the window, each over those before it, the last on top - a page in a
frame of its own, whose header bar holds the dialog's close button, or an
arrangement whose pages carry theirs. A sheet asks for 560 by 480, which
libadwaita fits to the window, rising from its bottom where the window is
narrow. The user's close - Escape, the close button - takes the top sheet
away through the host layer's way back, the modal stack told how many remain;
a sheet the program takes away closes and tells nothing. A sheet starts a path
of its own ([the visible path](../../host/pages.md#the-visible-path)): it
wears no bar of what stands around it, and names the dialog by its page's
title.


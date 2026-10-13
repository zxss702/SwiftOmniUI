# Safe-area placement on GTK and WinUI

The SwiftUI-shaped public inset overloads share one internal placement model.
The source tree still contains a base and a decorative bar, but an inset is
an ordered safe-region boundary, not generic ZStack overlay arithmetic.

`SafeAreaContext` carries proposal bounds, the allocated local layout rectangle,
container and keyboard rectangles,
and consumed avoidance. A child touching a safe edge retains the associated
unsafe strip for a ScrollView viewport or `ignoresSafeArea`; a local child
inside the region cannot inherit a window-wide viewport. The bar receives its
incoming edge proposal without its own contribution. Only the base receives
the reduced safe region. Scrollers retain a viewport spanning the unsafe
strips. Readers accept the safe allocation and keep the unconsumed safe-area
environment; transparent wrappers forward those responsibilities. Ordinary
content placed safely consumes the excluded strips.
Hidden bars reserve no extent or spacing; retained removal
branches are excluded from current layout.

The usable region is the intersection of the inherited container/keyboard
rectangles **and the child's proposal bounds**. Keeping only the inherited
intersection would give a 320-point tutorial column the entire page's width
when it places a local bar. Ordinary children retain their own bounds while
edge-touching descendants can retain the corresponding unsafe strips.

GeometryReader accepts its allocated room independently of its closure. A
finite native allocation supplies its size; an unspecified axis has ideal
extent ten. Content starts at the leading top corner. The frame-report wire
format remains `[x, y, width, height, windowX, windowY, safeX, safeY, safeWidth,
safeHeight]`. Actual size and coordinate conversion still come from that
physical report. An accompanying `safeAreaInsetsChanged` event carries the
remaining environment independently of the allocated size, for both
GeometryReader and onGeometryChange. Hosts without that context retain the
ten-number fallback. A scroll document consumes its enclosing
contribution and gives content a clean context; its moving origin cannot
reintroduce an outer inset. New local insets can reserve space again.

For the original FOPage structure, the outer top inset changes the safe region
while GeometryReader accepts the remaining allocation and observes the
unconsumed heading inset. Allocated size is not forced to equal the native
viewport. If the incoming height is H and the total top contribution is T,
the reader's height is H-T and its remaining top inset is T. The existing
`geometry.size.height - geometry.safeAreaInsets.top` expression therefore
requests H-2T. ScrollView keeps the full native viewport, resolves
the region to document/indicator margins, and then passes a clean context into
the document. With top margin T, that frame's centre is T+(H-2T)/2 = H/2,
matching the user's macOS reference. The previous full-proposal model instead
centred it at (H+T)/2. The size and remaining environment must not be collapsed
into a single intersection rectangle. The
application needs no compensating frame expression or offset. This does not
assert that every reader has the window's size: an enclosing fixed frame or
padding can propose a smaller container.

WinUI's native title/menu/tab rows already sit outside the page allocation.
Those outside strips remain in the window root's safe environment rather than
being silently consumed by the native row layout. Their committed metrics are
read without measuring during arrangement. Native chrome draws above any
extended viewport. With native chrome C outside the page's allocated height P
and an authored top bar B, the reader receives P-B and observes C+B; the
unchanged FO expression centres its short content at (P+C)/2 in window
coordinates. This prevents a residual half-titlebar displacement.

GTK page roots join the existing AdwToolbarView after header/tabs, enabling
content extension. Libadwaita explicitly disables its flat undershoot when
content extends to the top edge. The owning page scrollers therefore drive
the native raised top-bar surface while scrolled, with the shadow below the
complete merged region. A scoped CSS class suppresses only those scrollers'
displaced top effects; nested scrollers and bottom effects keep their native
behaviour. Weak listeners are removed when a page or promoted bar goes away.
WinUI uses the existing
TitleBar and content Grid row with a native bar overlay and a lower scroll
edge. Neither host promotes local bars or reuses a control in two parents.
Authored bar views retain logical parent reports and ancestor drawing matrices;
opacity/offset changes propagate even without a new layout pass. Bar metric
changes, margin invalidations and WinUI ownership updates are committed after
layout. Scrollbar searches are restricted to the owning scroller's template
and preserve native margins across repeated updates and template replacement.

Native promotion is conservative: finite local frames, clipping, safe padding,
ignore boundaries, side boundaries and negative spacing retain local placement
when they would change the native bar's proposal. Bottom and side bars add no
implicit backdrop. The context has independent keyboard storage; these desktop
paths do not fabricate a software-keyboard inset when none is supplied.

The pasted Windows stack identifies an unhandled XAML/fail-fast path, but does
not establish a unique cause. This change removes visible measurement-time
margin mutations and synchronous native scroller measurement during arrange,
and adds HRESULT/message logging without marking the exception handled.
Source ownership, navigation return/re-entry, frame changes and modifier order
were reviewed statically. **Not compiled; no tests run; no test files added.**
Windows crash resolution, native edge appearance, platform API compatibility
and live layout convergence remain unverified at the user's request.

The follow-up screenshots exposed a missing WinUI source-element connection:
each created native view must retain a weak link to its mounted element, or
the GeometryReader and ordered-inset branches cannot run. Both hosts now
resolve scroll-document padding when the placed context changes, before the
native viewport/presenter reads the document. Native writes remain deferred.
GTK invalidates the placing parents' arithmetic caches when lazy extents change,
including the document/scroller boundary. Its document reports the full natural
extent as its minimum on scrolling axes, and lazy realization uses the actual
native viewport dimensions rather than the reduced source ScrollView frame.
WinUI panels measured directly by a native presenter retain their root frame's
bounds, and the label's inner TextBlock uses the same DIP rounding policy as
its outer Border. A native label's Loaded notification invalidates its initial
measurement once attached to the real XAML tree. Deferred measurement changes
are coalesced at the owning placed root; affected ancestor caches are cleared,
and native measure/arrange is requested asynchronously. XAML supplies the new
proposal; the root is not speculatively measured with an unbounded height.
There is no input-triggered refresh or synchronous UpdateLayout in Measure or
Arrange. These are source corrections; the screenshots' missing
captions, continuation visibility and platform appearance have not been
confirmed with a running application.

The next static audit also corrected shared HStack measurement: finite widths
are distributed before cross-axis heights are measured, and placement uses
those same wrapped sizes. Declared minima survive compression. WinUI arithmetic
does not cache results that encountered a missing native proposal during
arrangement. Measurement invalidations, arrange invalidations and native child
attachment are coalesced outside MeasureOverride/ArrangeOverride. Current
allocation bounds, rather than a previous ActualSize, propagate child contexts.
Split views use finite current proposals and compare page layout values as well
as identity. Lazy viewport processing includes measurement revisions, so an
unchanged viewport cannot suppress pending remeasurement.
LazyVStack/LazyVGrid use the current finite width before the previous `standsAt`.
An old zero allocation must not replace a new 560-point proposal and turn text
wrapping into a large committed row height. Unbounded proposals fall back to
the last allocation, and changed widths reset the corresponding row measures.

GeometryReader mounts its closure only after a real report, rather than first
building a zero-size content tree. Unloaded WinUI pages do not publish geometry;
a temporarily empty reader attachment does not overwrite its retained report.
Native Image/Viewbox content is prepared at its intrinsic dimensions, instead
of 0x0. These changes address concrete initialization and retention risks;
the missing sidebar icons, blank return page and tutorial spacing remain
runtime-unverified. No application-specific offset, title or font workaround
was added. No tests were added or run, and no platform was compiled.

The semantic references are Apple's [GeometryReader](https://developer.apple.com/documentation/swiftui/geometryreader),
[safeAreaInset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:))
and [scroll-view discussion in WWDC23](https://developer.apple.com/videos/play/wwdc2023/10159/).
Apple defines [size](https://developer.apple.com/documentation/swiftui/geometryproxy/size)
as the container size and [safeAreaInsets](https://developer.apple.com/documentation/swiftui/geometryproxy/safeareainsets)
as that container's safe insets; geometry reports do not add a bar's height to
an already smaller native allocation.
Native surface behaviour follows [AdwToolbarView](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/class.ToolbarView.html).
GTK document allocation follows the native [GtkViewport implementation](https://github.com/GNOME/gtk/blob/main/gtk/gtkviewport.c).
XAML logging uses [UnhandledExceptionEventArgs](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.unhandledexceptioneventargs?view=windows-app-sdk-1.8).
Native text attachment and asynchronous placement follow [Loaded](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.frameworkelement.loaded?view=windows-app-sdk-1.8)
and [InvalidateArrange](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.uielement.invalidatearrange).

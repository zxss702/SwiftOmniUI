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
the reduced region. Hidden bars reserve no extent or spacing; retained removal
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
safeHeight]`. All geometry reads use the placed context, with insets bounded
by the actual native dimensions. A scroll document consumes its enclosing
contribution and gives content a clean context; its moving origin cannot
reintroduce an outer inset. New local insets can reserve space again.

For the original FOPage structure, the outer top inset reserves the heading
before placing GeometryReader. The reader reports that remaining allocation
and zero inset for the heading it has already avoided. Its existing
`geometry.size.height - geometry.safeAreaInsets.top` expression therefore
uses that remaining height. ScrollView extends its native viewport under the
heading and reserves the extension in document margins. The application needs
no compensating frame expression or offset.

GTK page roots join the existing AdwToolbarView after header/tabs, enabling
content extension and a common native undershoot edge. WinUI uses the existing
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
its outer Border. These are source corrections; the screenshots' missing
captions, continuation visibility and platform appearance have not been
confirmed with a running application.

The semantic references are Apple's [GeometryReader](https://developer.apple.com/documentation/swiftui/geometryreader),
[safeAreaInset](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:))
and [scroll-view discussion in WWDC23](https://developer.apple.com/videos/play/wwdc2023/10159/).
Native surface behaviour follows [AdwToolbarView](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/class.ToolbarView.html).
GTK document allocation follows the native [GtkViewport implementation](https://github.com/GNOME/gtk/blob/main/gtk/gtkviewport.c).
XAML logging uses [UnhandledExceptionEventArgs](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.unhandledexceptioneventargs?view=windows-app-sdk-1.8).

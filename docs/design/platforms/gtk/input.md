# Input on GTK

How the GTK host hears what the user does to an element with a finger, a pen
or the mouse - a tap, the pointer, a press dragged, a pinch - and reports it
as the element's events ([a user's change](../../host/runtime.md#a-users-change)).
A control's own input - a button's click, a switch turned - is the control's,
and stays there ([controls](controls.md)).

## Listening

A view listens only for what its element's handlers and channels ask: taps
for a tap handler, the pointer for a pointer handler, a press dragged for a
pan, a swipe or a state a pan carries, a pinch for a pinch handler. Each kind
is a GTK event controller on the view's widget, added when the view starts
listening for it and removed when it stops, and every controller's signals
name the view by its number. A view that leaves the tree stops listening
first, so its widget holds none of them.

GTK hits a widget across its bounds, whatever it draws: a panel with nothing
between its children still takes a click there, so a row answers past its
words as well as on them. GTK tries a widget's children before the widget
itself, so a layout that lets input through - a panel whose own test of a
point holds none - passes a click beside its children on to what is under
it, while its children still take theirs. A view that ignores input takes
none, nor does anything in it.

A panel's `contentShape` can use a fixed native outline or a local path from
any Shape. GSK tests the latter with the requested winding/even-odd fill rule;
an empty path accepts no point on the panel. Geometry is retained until its
commands change and released with the panel. Descendants retain GTK's native
picking order. This input region does not alter the snapshot's drawing clip.

## Taps

A tap is `GtkGestureClick`'s release of the primary button, or of a finger,
over the view, of a press that has not moved past GTK's drag threshold. GTK
counts a quick run itself - the release's place in it - by the desktop's
double-click time and distance; a view asking for `count` taps answers each
time the run reaches a multiple of it.

GTK stops counting a press as a click when it moves past the drag threshold,
and also when it is held past the double-click time, and it still tells the
release after either. The host takes the stop as a move only where the press
now stands past the threshold from where it went down, so a slow click is
still a tap.

The tap claims its press, and GTK denies it to every view around the one
tapped: a tappable row inside another answers alone.

## Pressed by assistive technology

A panel carries one action, `panel.click`, enabled only while it listens for
taps. GTK offers a widget's enabled actions to assistive technology through
AT-SPI, and pressing it runs the tap handler once, whatever count the view
asks for - as a screen reader's press, and a test's, do.

## The pointer

The pointer's entering, moving and leaving are `GtkEventControllerMotion`'s,
in the view's coordinates. Its press and its release are a drag gesture of
any button, followed to its end however far it goes: pressed where it went
down, released where it was let go. That gesture stands in one group with a
pan's on the same view, so the pan claiming the press does not end the
pointer's.

## A popup over the pointer

A popup standing over the pointer - a context menu, a menu button's menu, a
popover's card, a picker's list - does not take the hover of what it covers:
the pointer did not leave the view it was on, so the view is not told it did.
GTK takes the pointer to the popover's own surface all the same, so the views
under it are told the pointer left and are told nothing when the popup goes,
since the pointer never moved. The host layer's rule
([what the user does with a
finger](../../host/runtime.md#what-the-user-does-with-a-finger)) withholds the
exit such a popup caused while any popup stands, and the last one going takes
the truth again from where the pointer stands then: what the pointer is still
on keeps its hover, and what it has left is handed the exit it was owed
(`GTKHoverHold`).

A popup is counted where it is made - the popover a page shows, a context
menu's, a picker's face, the popover a menu button makes of the menu model it
is handed, the list a drop-down holds of GTK's own - and uncounted where GTK
says it left the screen: the popover's own `visible` where the host took it
away, or the unmapping of one whose widget went without being told to hide, so
no count outlives what it counted. Only a view the motion controller told an
exit is ever held, so no walk of the element tree is needed, and a popup's own
relatedness to what it covers is never asked.

## A press dragged

A press of the primary button, or a finger, becomes a drag by the host
layer's rule ([a press dragged](../../host/runtime.md#a-press-dragged)) once
it has moved past GTK's drag threshold along either axis - the distance
GTK's own click stops at, which also tells a press that moved from a tap. From there
the drag claims its press: GTK denies it to the tap on the same press and to
every view around the one dragged, so a view dragged inside another drags
alone. It is measured on the window, from each event's own position, where
the view it moves does not move the measure. A drag says its phases - began,
moved by how far since it began, ended or cancelled - and a pan's states move
by that from where they stood as it began. It ended when the last event it
followed let go of the press; otherwise it was cancelled. Ended, it is a
swipe by the host layer's rule ([a swipe](../../host/runtime.md#a-swipe)). A
pan that asks for more than one pointer is not recognized.

## A pinch

A view that listens for a pinch takes `GtkGestureZoom` - two fingers on a
touch screen, or a touchpad's pinch - and says each step's scale since the
last, and where, as shares of its size. The pinch claims its fingers as it
begins, which keeps a scroller around the view from panning with them.
## The keyboard's focus

A view whose element hears its focus change takes `GtkEventControllerFocus`,
and reports its `enter` as the keyboard coming and its `leave` as the
keyboard going. Both name the focus within the widget or any part of it: a
field's inner text widget taking the keyboard is the field taking it, and
the keyboard moving between a control's own parts tells nothing. A widget
GTK gives no keyboard focus - a label, a box, a picture - never takes it,
whoever asks, so its element hears nothing; the act that puts the keyboard
on it answers that it did not.

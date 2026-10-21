// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The relay's C surface: what the WinUI host calls, and the callbacks the relay
// makes on the UI thread. Plain C, so Swift imports it as a C module. A handle is
// an AddRef'd WinRT interface pointer the host lets go of with
// swiftomniui_winui_release; a view is the number the host gave the element.
// Design: docs/design/platforms/winui/relay.md#the-c-surface
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SwiftOmniUIObject *SwiftOmniUIObjectRef;

/// A brush as the host hands it: its kind - 0 none, 1 solid, 2 linear, 3 radial - its geometry in fractions of
/// the painted box (a line's two points, or a centre and its radii across and down), then a colour and an offset
/// for each stop.
typedef struct {
    int32_t kind;
    double geometry[4];
    int32_t count;
    uint32_t const *colors;
    double const *offsets;
} SwiftOmniUIBrush;

/// An outline: 0 a rectangle, 1 one rounded by `radius` DIPs, 2 an ellipse, 3 a
/// capsule, 4 a circle in the middle.
typedef enum {
    SwiftOmniUIOutlineRectangle,
    SwiftOmniUIOutlineRounded,
    SwiftOmniUIOutlineEllipse,
    SwiftOmniUIOutlineCapsule,
    SwiftOmniUIOutlineCircle
} SwiftOmniUIOutline;

/// What of the user's input a view listens for, each a bit: taps; the pointer entering, leaving, moving, and its
/// button going down and up; a press dragged; two fingers pinching.
typedef enum {
    SwiftOmniUIHearingTaps = 1,
    SwiftOmniUIHearingPointer = 2,
    SwiftOmniUIHearingDrags = 4,
    SwiftOmniUIHearingPinches = 8,
} SwiftOmniUIHearing;

/// What a view heard: a tap, its place in a quick run of taps from 1, 0 for a press assistive technology made; the
/// pointer at (x, y) DIPs of the view; a pinch's phase, its scale since the last, at (x, y) as shares of the view's
/// size; a press a drag may become - 0 down, 1 moved, 2 let go, 3 taken away - at (x, y) DIPs of the window's content,
/// which the host's rule makes a drag.
typedef enum {
    SwiftOmniUIHeardTap,
    SwiftOmniUIHeardPointerEntered,
    SwiftOmniUIHeardPointerExited,
    SwiftOmniUIHeardPointerMoved,
    SwiftOmniUIHeardPointerPressed,
    SwiftOmniUIHeardPointerReleased,
    SwiftOmniUIHeardPinch,
    SwiftOmniUIHeardPress,
} SwiftOmniUIHeard;

/// A question for the user: `kind` 0 an alert, 1 a confirmation, 2 a choice of actions, 3 a prompt; its title
/// and message; the captions that accept and cancel; for a choice, the dangerous one and the choices; for a
/// prompt, the field's placeholder, its most characters (0 for any), whether its words are spell checked and
/// predicted, its input scope (`WinUIInputScope`) and what it starts holding. Null for a caption there is none of.
typedef struct {
    int32_t kind;
    char const *title;
    char const *message;
    char const *accept;
    char const *cancel;
    char const *destruction;
    char const *const *choices;
    int32_t choiceCount;
    char const *placeholder;
    int32_t maximumLength;
    bool spellChecked;
    bool predicted;
    int32_t scope;
    char const *initial;
} SwiftOmniUIQuestion;

/// A file dialog: `kind` 0 one file to open, 1 several, 2 a place to save; the kinds of file it offers, `typeCount`
/// captions, each with the count of its extensions - bare, without the dot - in `extensions` in turn; a save's name
/// and the `length` bytes it writes.
typedef struct {
    int32_t kind;
    int32_t typeCount;
    char const *const *captions;
    int32_t const *extensionCounts;
    char const *const *extensions;
    char const *name;
    uint8_t const *contents;
    int64_t length;
} SwiftOmniUIFileDialog;

/// What the relay calls on the UI thread. Every one is set: the relay calls them unchecked.
typedef struct {
    /// WinUI stands on the thread: the host's first render.
    void (*launched)(void);

    /// A turn the doorbell posted to the UI thread's queue.
    void (*turn)(void);

    /// A frame WinUI composes, while the host holds the frame clock.
    void (*frame)(void);

    /// A panel's MeasureOverride: `size` takes the width and height the view needs.
    void (*measure)(int64_t view, double width, double height, double *size);

    /// A panel's ArrangeOverride: the view places its children in the size given.
    void (*arrange)(int64_t view, double width, double height);

    /// A virtualizing panel's effective viewport, including independent touch scrolling and ancestor clipping.
    void (*viewportChanged)(int64_t view, double x, double y, double width, double height,
                            double bringX, double bringY);

    /// A button's Click.
    void (*clicked)(int64_t view);

    /// A switch, a check box or a radio button the user turned on or off.
    void (*toggled)(int64_t view, bool on);

    /// A slider's or a stepper's value moved.
    void (*valueChanged)(int64_t view, double value);

    /// A field's words changed, all of them handed over in UTF-8.
    void (*textChanged)(int64_t view, char const *utf8);

    /// A single-line field's Enter.
    void (*submitted)(int64_t view);

    /// The next view WinUI is about to display (x, y), and the one it finally lands on (fx, fy), before its
    /// ViewChanged notification.
    void (*scrolling)(int64_t view, double x, double y, double fx, double fy);

    /// A scroller's view changed: where it stands now, in DIPs.
    void (*scrolled)(int64_t view, double x, double y);

    /// The user holds a view down or lets it go: a scroller taken hold of, a button held by a pointer or a key.
    void (*held)(int64_t view, bool holding);

    /// The user chose an entry by its place: an action of a window's chrome, or its way back (-1) or sidebar toggle
    /// (-2); a tab.
    void (*chosen)(int64_t view, int32_t index);

    /// What stands over the pointer opened or closed of WinUI's accord: a split view's sidebar, a picker's list, a
    /// date picker's calendar, a context menu, a menu button's menu, a popover's card.
    void (*presented)(int64_t view, bool open);

    /// Something the environment reports changed: the theme, the power, the network.
    void (*environmentChanged)(void);

    /// What a view heard of the user's input, as `SwiftOmniUIHeard` says: `phase` a tap's place or a gesture's phase.
    void (*heard)(int64_t view, SwiftOmniUIHeard what, int32_t phase, double x, double y, double scale);

    /// The user answered the question asked under `ticket`: whether it was accepted, and the words chosen or
    /// typed, in UTF-8; null for none.
    void (*answered)(int64_t ticket, bool accepted, char const *utf8);

    /// The file dialog shown under `ticket` closed: the `count` files chosen - a save's once its contents stand
    /// written - their paths and names in UTF-8, none for a cancel; or why it failed, in UTF-8, null where it did not.
    void (*filesChosen)(int64_t ticket, int32_t count, char const *const *paths, char const *const *names,
                        char const *failure);

    /// The file read under `ticket`: its `length` bytes; or why it could not be read, in UTF-8, null where it was.
    void (*fileRead)(int64_t ticket, uint8_t const *bytes, int64_t length, char const *failure);

    /// What was launched under `ticket`: whether an application took it.
    void (*launchAnswered)(int64_t ticket, bool taken);

    /// A press on a canvas, followed from down to up: `phase` 0 pressed, 1 dragged, 2 released, at (x, y) DIPs of it.
    void (*canvasPressed)(int64_t view, int32_t phase, double x, double y);

    /// The user picked a day - its year, month and day - or a time of day - its hour, minute and 0.
    void (*picked)(int64_t view, int32_t first, int32_t second, int32_t third);

    /// The user chose an item of a view's menu: its place among the menu's items, from 0.
    void (*menuChosen)(int64_t view, int32_t index);

    /// The keyboard came into a view - to it or to what stands in it - or left it.
    void (*focused)(int64_t view, bool focused);

    /// The window `window` names was activated or deactivated, or minimized: whether it stands minimized, and
    /// whether it is activated.
    void (*windowStateChanged)(int64_t window, bool minimized, bool activated);

    /// The window `window` names closed - the user's click, or the program's.
    void (*windowClosed)(int64_t window);

    /// An ItemsView needs a cell - an item's (0), or a header's or a footer's (1): the host answers the panel that
    /// holds an entry, and its number in `cell`; the relay stands it in an ItemContainer kept for the list's life.
    SwiftOmniUIObjectRef (*itemCell)(int64_t view, int32_t kind, int64_t *cell);

    /// An ItemsView stood the cell of the panel `cell` names for the entry of `identity`, in UTF-8.
    void (*itemHeld)(int64_t view, int64_t cell, char const *identity);

    /// An ItemsView put the cell of the panel `cell` names aside.
    void (*itemLetGo)(int64_t view, int64_t cell);

    /// The user changed an ItemsView's choice: every item chosen now, their identities joined by newlines.
    void (*itemsChose)(int64_t view, char const *identities);

    /// The user invoked an ItemsView's item.
    void (*itemInvoked)(int64_t view, char const *identity);

    /// An ItemsView's view changed: the places of the first and the last entry in it.
    void (*itemsShowing)(int64_t view, int32_t first, int32_t last);

    /// The platform activated the application with a URL to open - a file's association, a protocol's link - the
    /// URL in UTF-8.
    void (*urlOpened)(char const *utf8);

    /// A plain launch or reactivation: show the first declared window, reusing it where it is open.
    void (*activated)(void);
    /// One native menu level is requested; mount 0 is the trigger's root level.
    void (*menuContentRequested)(int64_t view, uint64_t mount);

    /// A native split column changed width, invalidating its owner's size calculation.
    void (*paneWidthChanged)(int64_t view);
    /// Classifies a synchronous native change before its asynchronous notification.
    bool (*isProgramWriting)(void);
} SwiftOmniUIWinUICallbacks;

/// What the environment is, in groups, each read at once.
typedef enum {
    SwiftOmniUIFactsDevice,
    SwiftOmniUIFactsApplication,
    SwiftOmniUIFactsLocale,
    SwiftOmniUIFactsBattery,
    SwiftOmniUIFactsConnectivity,
    SwiftOmniUIFactsTheme,
    SwiftOmniUIFactsDisplay,
} SwiftOmniUIFacts;

/// Starts the single-instance application and runs its loop until the last window closes.
int32_t swiftomniui_winui_run(SwiftOmniUIWinUICallbacks const *callbacks);

/// As above, with an explicit instance key; null uses the executable's path.
int32_t swiftomniui_winui_run_single_instance(SwiftOmniUIWinUICallbacks const *callbacks, char const *applicationID);

/// Makes this thread hold WinUI elements with no loop of WinUI's running - a test process's thread.
int32_t swiftomniui_winui_embed(SwiftOmniUIWinUICallbacks const *callbacks);

/// Runs this thread's messages for `seconds` - the loop an embedded thread lacks.
void swiftomniui_winui_pump(double seconds);

/// Posts one turn to the UI thread's queue; any thread.
void swiftomniui_winui_post_turn(void);

/// Keeps the loop alive while windows exist; false schedules shutdown after queued activations.
void swiftomniui_winui_keep_scene_alive(bool alive);

/// Subscribes to CompositionTarget.Rendering, or lets go of it.
void swiftomniui_winui_hold_frames(bool hold);
/// Whether WinUI's frames are subscribed to now. What a test reads.
bool swiftomniui_winui_holds_frames(void);

/// Takes a reference of the host's own to a handle, which the host lets go of as it lets go of its own; the handle.
SwiftOmniUIObjectRef swiftomniui_winui_retain(SwiftOmniUIObjectRef object);

/// Lets go of a handle.
void swiftomniui_winui_release(SwiftOmniUIObjectRef object);

/// A window, its activation and its minimizing told through `phaseChanged` under the number `window`.
SwiftOmniUIObjectRef swiftomniui_winui_window_make(int64_t window);
void swiftomniui_winui_window_set_title(SwiftOmniUIObjectRef window, char const *title);
/// A solid colour on the complete client root; false restores the system backdrop.
void swiftomniui_winui_window_set_background(SwiftOmniUIObjectRef window, bool hasBackground, uint32_t background);
/// The native root's solid fill, where one is set. What a test reads.
bool swiftomniui_winui_window_background(SwiftOmniUIObjectRef window, uint32_t *background);
void swiftomniui_winui_window_set_content(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef content);
/// A native overlay in the existing content row, below TitleBar and above its
/// ScrollView. It never creates another auto row or reduces the viewport.
void swiftomniui_winui_window_set_safe_area_bars(SwiftOmniUIObjectRef window,
    SwiftOmniUIObjectRef const *bars, int32_t count, bool hasBackground, uint32_t background);
/// Place the merged surface in its owning page's coordinates within the existing content row.
void swiftomniui_winui_window_set_safe_area_bar_frame(SwiftOmniUIObjectRef window, double x, double y, double width);

/// The window's chrome across its top, its menu bar and the row of tabs beneath it; null for none. The first chrome
/// given also takes the window's way back: the mouse's back button, Alt+Left and the Back key choose its way back
/// (-1).
void swiftomniui_winui_window_set_chrome(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef titleBar, SwiftOmniUIObjectRef menuBar,
                                     SwiftOmniUIObjectRef tabs);
/// Restores and shows the window, then requests native foreground activation, including redirected launches.
void swiftomniui_winui_window_activate(SwiftOmniUIObjectRef window);
void swiftomniui_winui_window_close(SwiftOmniUIObjectRef window);
/// Hides the window, or shows it again without activating it.
void swiftomniui_winui_window_set_shown(SwiftOmniUIObjectRef window, bool shown);
/// Minimizes or restores the window as its buttons do: `ShowWindow` with `command`. What a test does.
void swiftomniui_winui_window_show_as_user(SwiftOmniUIObjectRef window, int32_t command);
/// Makes `owner` the window's owner - it stands above it, is hidden with it, and leaves the switchers - or, for
/// null, a window of its own again.
void swiftomniui_winui_window_set_owner(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef owner);
/// Whether `owner` owns the window and the switchers leave it out. What a test reads.
bool swiftomniui_winui_window_belongs_to(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef owner);

/// Moves or sizes the window where `has` says, each alone: `values` are x and y from the corner of the screen's work
/// area and the width and height of its content, in DIPs.
void swiftomniui_winui_window_set_frame(SwiftOmniUIObjectRef window, bool const *has, double const *values);

/// Places the window by an anchor: the point `anchor` fractions across and down it lands at the point the same
/// fractions across and down the screen's work area - `.center` of both, the window centered.
void swiftomniui_winui_window_set_anchor(SwiftOmniUIObjectRef window, double const *anchor);

/// The least and the greatest size of the window's content in DIPs: least width, least height, greatest width,
/// greatest height, 0 for none.
void swiftomniui_winui_window_set_limits(SwiftOmniUIObjectRef window, double const *limits);

/// The system title bar's height in DIPs, including before XAML finishes loading its template.
double swiftomniui_winui_window_title_bar_height(SwiftOmniUIObjectRef window);

/// What the window is: whether the user may maximize, minimize and resize it, whether its backdrop is translucent
/// (acrylic) or of the desktop's tint (Mica), and whether it floats over the application's other windows.
void swiftomniui_winui_window_set_traits(SwiftOmniUIObjectRef window, bool maximizable, bool minimizable, bool resizable,
                                     bool translucent, bool floats);

/// What a test reads of a window, into 13 values: x, y, width, height, the four limits in the order they are set,
/// maximizable, minimizable, translucent, floating and shown as 1 or 0.
void swiftomniui_winui_window_frame(SwiftOmniUIObjectRef window, double *values);

/// The client width and height in DIPs, without reading the window's position, limits or traits.
void swiftomniui_winui_window_client_size(SwiftOmniUIObjectRef window, double *size);

/// The window's name the system shows - the taskbar's, Alt+Tab's - in UTF-8, as far as `capacity` goes; answers its
/// length.
int32_t swiftomniui_winui_window_system_title(SwiftOmniUIObjectRef window, char *utf8, int32_t capacity);

/// Makes the element fill whatever place it is arranged in, whatever its style aligns it to: a SwiftOmniUI layout
/// decides its place.
void swiftomniui_winui_fill_place(SwiftOmniUIObjectRef element);

/// Every element: measured and placed by its parent's panel, shown or collapsed, drawn how opaque.
void swiftomniui_winui_measure(SwiftOmniUIObjectRef element, double width, double height, double *size);
/// What the element last measured at - reading it marks nothing, unlike measuring again.
void swiftomniui_winui_desired_size(SwiftOmniUIObjectRef element, double *size);
void swiftomniui_winui_arrange(SwiftOmniUIObjectRef element, double x, double y, double width, double height);
void swiftomniui_winui_invalidate_measure(SwiftOmniUIObjectRef element);
void swiftomniui_winui_set_shown(SwiftOmniUIObjectRef element, bool shown);
void swiftomniui_winui_set_opacity(SwiftOmniUIObjectRef element, double opacity);

/// The tip shown under the pointer resting on the element - a `.help` text,
/// or NULL for none.
void swiftomniui_winui_set_tooltip(SwiftOmniUIObjectRef element, char const *utf8);

/// Where `element`'s top left corner stands in its window's content, in DIPs, into `origin` (x, y).
void swiftomniui_winui_origin(SwiftOmniUIObjectRef element, double *origin);

/// Arrange offsets relative to an actual visual ancestor, excluding presentation transforms.
/// Returns false if the element has not been attached beneath that ancestor.
bool swiftomniui_winui_layout_offset(SwiftOmniUIObjectRef element, SwiftOmniUIObjectRef ancestor, double *offset);

/// Where WinUI laid the element out in its parent: x, y, width, height, in DIPs.
void swiftomniui_winui_frame(SwiftOmniUIObjectRef element, double *frame);
/// Whether the element is loaded in a live XAML tree; detached pages report no geometry.
bool swiftomniui_winui_is_attached(SwiftOmniUIObjectRef element);

/// A control's IsEnabled.
void swiftomniui_winui_set_enabled(SwiftOmniUIObjectRef control, bool enabled);

/// Cuts what the element shows to `outline` over `width` by `height` DIPs; `cuts` false shows it whole.
void swiftomniui_winui_set_clip(SwiftOmniUIObjectRef element, bool cuts, SwiftOmniUIOutline outline, double radius,
                            double width, double height);

/// Retained Composition clip, updated in place from local curve commands.
SwiftOmniUIObjectRef swiftomniui_winui_path_clip_make(SwiftOmniUIObjectRef element);
void swiftomniui_winui_path_clip_update(SwiftOmniUIObjectRef clip, double const *commands, int32_t count, bool evenOdd);
void swiftomniui_winui_path_clip_attach(SwiftOmniUIObjectRef element, SwiftOmniUIObjectRef clip);

/// Whether the element takes clicks and touches; one that does not lets them through to what is behind it.
void swiftomniui_winui_set_hit_testable(SwiftOmniUIObjectRef element, bool testable);

/// Where the element is drawn among its panel's children: a higher one over a lower, equal ones in order.
void swiftomniui_winui_set_z_index(SwiftOmniUIObjectRef element, int32_t z);

/// The direction the element lays itself out and writes in, which what stands in it inherits: right to left, or
/// left to right.
void swiftomniui_winui_set_flow_direction(SwiftOmniUIObjectRef element, bool rightToLeft);

/// Tips the element as it is drawn after its transform: `matrix` the sixteen numbers of a 4 x 4 matrix, row by
/// row, applied to a point (x, y, 0, 1) of the element and divided by the fourth; null for no tip.
void swiftomniui_winui_set_projection(SwiftOmniUIObjectRef element, const double *matrix);

/// The tip the element is drawn with, its matrix's sixteen numbers into `matrix`; false where it has none.
bool swiftomniui_winui_projection(SwiftOmniUIObjectRef element, double *matrix);

/// Asks WinUI to arrange the element again - a place in the air lands only in a pass.
void swiftomniui_winui_invalidate_arrange(SwiftOmniUIObjectRef element);

/// Reports committed native size changes, without measuring or flushing layout.
void swiftomniui_winui_on_size_changed(SwiftOmniUIObjectRef element, int64_t view, void (*changed)(int64_t, double, double));

/// Reports a changed committed native height, without measuring or flushing layout.
void swiftomniui_winui_on_height_changed(SwiftOmniUIObjectRef element, int64_t view, void (*changed)(int64_t));

/// Runs WinUI's layout pass over the element's tree now, as its next frame would.
void swiftomniui_winui_update_layout(SwiftOmniUIObjectRef element);

/// Listens for a lazy panel's native effective viewport; ordinary panels do not subscribe.
void swiftomniui_winui_panel_watch_viewport(SwiftOmniUIObjectRef panel, bool enabled);

/// Moves, turns and scales the element where its layout put it: DIPs and degrees, about the point
/// (`centerX`, `centerY`) of it, in DIPs.
void swiftomniui_winui_set_transform(SwiftOmniUIObjectRef element, double translationX, double translationY,
                                 double rotation, double scaleX, double scaleY, double centerX, double centerY);

/// The transform as WinUI holds it, in `set_transform`'s order: seven values.
void swiftomniui_winui_transform(SwiftOmniUIObjectRef element, double *values);

/// The element's Opacity as WinUI holds it.
double swiftomniui_winui_opacity(SwiftOmniUIObjectRef element);

/// Whether the element shows: its Visibility, as WinUI holds it.
bool swiftomniui_winui_is_shown(SwiftOmniUIObjectRef element);

/// A control's IsEnabled as WinUI holds it; true for an element that is no control.
bool swiftomniui_winui_is_enabled(SwiftOmniUIObjectRef element);

/// Whether the user leaves Windows' animations on.
bool swiftomniui_winui_animations_enabled(void);

/// The words a text block or a button's caption shows, in UTF-8; the length they need, their end not counted.
int32_t swiftomniui_winui_text(SwiftOmniUIObjectRef element, char *utf8, int32_t capacity);

SwiftOmniUIObjectRef swiftomniui_winui_panel_make(int64_t view);
/// A layout panel whose native Frame owns page transitions; Swift owns the path.
SwiftOmniUIObjectRef swiftomniui_winui_navigation_make(int64_t view);
void swiftomniui_winui_navigation_set(
    SwiftOmniUIObjectRef panel, SwiftOmniUIObjectRef background, SwiftOmniUIObjectRef content,
    bool animated, bool back
);
void swiftomniui_winui_navigation_clear(SwiftOmniUIObjectRef panel);
void swiftomniui_winui_panel_set_children(SwiftOmniUIObjectRef panel, SwiftOmniUIObjectRef const *children, int32_t count);

/// A panel that redirects its live XAML source and mask through CompositionMaskBrush.
SwiftOmniUIObjectRef swiftomniui_winui_masked_panel_make(int64_t view);
/// Commits the children and their alpha-source role together, keeping intersecting controls attached.
void swiftomniui_winui_masked_panel_set_children(
    SwiftOmniUIObjectRef panel, SwiftOmniUIObjectRef const *children, int32_t count, SwiftOmniUIObjectRef mask
);
/// Disconnects the composition surfaces when the panel leaves or is disposed.
void swiftomniui_winui_masked_panel_clear(SwiftOmniUIObjectRef panel);

/// A drawing-only presentation boundary retaining the original native control.
SwiftOmniUIObjectRef swiftomniui_winui_blur_make(SwiftOmniUIObjectRef element);
/// Updates a retained live Composition Gaussian-blur brush, in logical pixels.
bool swiftomniui_winui_blur_set(SwiftOmniUIObjectRef presenter, double radius, double reserveRadius);
void swiftomniui_winui_blur_clear(SwiftOmniUIObjectRef presenter);

/// How words look on a text block or any control showing them: the font - a size of 0 or less and an empty
/// family are the platform's - the colour as 0xAARRGGBB, `has` false putting back the platform's, and the room
/// around them in DIPs.
void swiftomniui_winui_set_font(SwiftOmniUIObjectRef element, double size, bool bold, bool italic, char const *family,
                               int32_t textStyle, double weight);

/// Native text-style readers created; repeated rows reuse these rather than making temporary controls.
uint64_t swiftomniui_winui_font_probes(void);
void swiftomniui_winui_set_foreground(SwiftOmniUIObjectRef element, bool has, uint32_t argb);
void swiftomniui_winui_set_padding(SwiftOmniUIObjectRef element, double left, double top, double right, double bottom);

/// How words look, as WinUI holds it: the size, the weight, the most lines, the alignment and the colour as
/// 0xAARRGGBB - five values; what a test reads back.
void swiftomniui_winui_text_style(SwiftOmniUIObjectRef element, double *style);

SwiftOmniUIObjectRef swiftomniui_winui_text_make(void);
void swiftomniui_winui_set_pointer_style(SwiftOmniUIObjectRef element, int32_t style);
void swiftomniui_winui_text_set_selectable(SwiftOmniUIObjectRef element, bool selectable);
int32_t swiftomniui_winui_text_character_rects(SwiftOmniUIObjectRef element, double *rectangles, int32_t capacity);

/// Native attachment completes the label's pre-attachment measurement. The
/// callback names the live view; no native handler retains a Swift object.
void swiftomniui_winui_text_on_loaded(SwiftOmniUIObjectRef handle, int64_t view, void (*ready)(int64_t));
/// What a label is drawn over: a colour, a gradient, or none - still hit across its bounds.
void swiftomniui_winui_text_set_background(SwiftOmniUIObjectRef label, SwiftOmniUIBrush background);

/// Where a label's words stand across its height: at its top (0), in its middle (1), at its bottom (2).
void swiftomniui_winui_text_set_vertical(SwiftOmniUIObjectRef label, int32_t vertical);

void swiftomniui_winui_text_set_text(SwiftOmniUIObjectRef text, char const *utf8);

/// One run of a label's words, and how it differs from the label's: its colour and its background where it has
/// them, as 0xAARRGGBB; its size in DIPs, 0 for the label's; bold, italic, and lines under or through it; its font
/// family, empty for the label's; the space between its letters in thousandths of an em of its size; how far its
/// baseline rises in DIPs; the '\n'-joined candidate files it draws as a glyph in the line, empty for none; and a
/// Fluent glyph where it is a symbol, empty for none.
typedef struct {
    char const *text;
    uint32_t color;
    uint32_t background;
    double size;
    bool hasColor;
    bool hasBackground;
    bool bold;
    bool italic;
    bool underline;
    bool strikethrough;
    char const *family;
    int32_t spacing;
    double baseline;
    char const *image;
    char const *glyph;
} SwiftOmniUIWordsRun;

/// Shows `runs`, in order, as the text block's words, each as it says, in place of its words.
void swiftomniui_winui_text_set_runs(SwiftOmniUIObjectRef text, SwiftOmniUIWordsRun const *runs, int32_t count);
/// Repaints ordinary runs without changing their text or typography; false requests a full update.
bool swiftomniui_winui_text_recolor_runs(SwiftOmniUIObjectRef text, SwiftOmniUIWordsRun const *runs, int32_t count);

/// The runs a text block shows, six values each - its colour as 0xAARRGGBB or 0, its size or 0, its weight, 1 for
/// italic, its lines (1 under, 2 through), its background or 0 - into `values` as far as `capacity` goes; answers
/// how many runs it shows. What a test reads back.
int32_t swiftomniui_winui_text_runs(SwiftOmniUIObjectRef text, double *values, int32_t capacity);

/// A label's lines - whether the words wrap, the most lines, 0 for any, and whether words that do not fit are cut
/// with an ellipsis - its words' alignment across it - start, centre, end - the space between its letters in
/// thousandths of an em, the height of a line in DIPs, 0 for the font's, and the lines under or through its words.
void swiftomniui_winui_text_set_lines(SwiftOmniUIObjectRef text, bool wraps, int32_t lines, bool trims);
void swiftomniui_winui_text_set_alignment(SwiftOmniUIObjectRef text, int32_t horizontal);
void swiftomniui_winui_text_set_spacing(SwiftOmniUIObjectRef text, int32_t characterSpacing, double lineHeight);
double swiftomniui_winui_text_natural_line_height(SwiftOmniUIObjectRef text);
void swiftomniui_winui_text_set_decorations(SwiftOmniUIObjectRef text, bool underline, bool strikethrough);

SwiftOmniUIObjectRef swiftomniui_winui_button_make(int64_t view);

/// A toolbar's own button - WinUI's AppBarToggleButton, momentary until `button_set_on` has it keep a state.
SwiftOmniUIObjectRef swiftomniui_winui_toolbar_button_make(int64_t view);

/// The picture in a toolbar button's icon slot: the first of the newline-separated `icons` files the pictures
/// hold, else the Fluent glyph `symbol` is; both empty for none. Pictured, its words move to its tip.
void swiftomniui_winui_toolbar_button_set_icon(SwiftOmniUIObjectRef button, char const *symbol, char const *icons);

/// The words a button or a radio button shows.
void swiftomniui_winui_set_caption(SwiftOmniUIObjectRef control, char const *utf8);

/// A button's look: what fills it - the platform's for none, kept `underPointer` and `pressed` of its opacity under
/// the pointer and pressed - its outline `strokeWidth` DIPs wide, and its corners' radius, less than 0 for the
/// platform's.
void swiftomniui_winui_button_set_look(SwiftOmniUIObjectRef button, SwiftOmniUIBrush background, SwiftOmniUIBrush stroke,
                                   double strokeWidth, double cornerRadius, double underPointer, double pressed);

/// A button's logical style kind: 2 accents it, 3 and 4 make it text, the rest the platform's own look.
void swiftomniui_winui_button_set_style(SwiftOmniUIObjectRef button, int kind);
void swiftomniui_winui_button_set_face(SwiftOmniUIObjectRef button, SwiftOmniUIObjectRef content);

/// The app menu's trigger on the bar: transparent at rest, with the system's subtle hover and pressed fills.
void swiftomniui_winui_toolbar_button_set_look(SwiftOmniUIObjectRef button);

/// A button's keyboard shortcut: a `VirtualKey` number, `VirtualKeyModifiers` flags in the same order - 0 for none.
void swiftomniui_winui_button_set_shortcut(SwiftOmniUIObjectRef button, int64_t view, int32_t key, int32_t modifiers);
/// A Unicode character to VirtualKey in the active keyboard layout; merges its required modifiers.
int32_t swiftomniui_winui_shortcut_key(uint32_t scalar, int32_t *modifiers);
/// Window-scoped menu commands, dispatched by their menuChosen index, including while the menu is closed.
void swiftomniui_winui_menu_set_shortcuts(SwiftOmniUIObjectRef owner, int64_t view, int32_t const *keys,
                                        int32_t const *modifiers, int32_t const *items, int32_t count);

/// Whether a button keeps its pressed look and whether it is down: `toggleable` wears `isOn` at all, `on` its state.
void swiftomniui_winui_button_set_on(SwiftOmniUIObjectRef button, int32_t toggleable, int32_t on);

/// Presses a button as UI Automation does, which raises its Click.
void swiftomniui_winui_button_invoke(SwiftOmniUIObjectRef button);

/// A control's one accent colour, `argb`, where `tinted`, and the platform's accent otherwise: a check box's tick,
/// a switch's track while it is on, a slider's thumb and the track behind it, a picker's chosen choice in its list, a
/// progress bar and a spinner - kept `underPointer` and `pressed` of its opacity under the pointer and pressed.
void swiftomniui_winui_set_tint(SwiftOmniUIObjectRef control, uint32_t argb, bool tinted, double underPointer,
                            double pressed);

/// A sheet: a card over a veil across its window, holding a presented page under its title; a window's sheets, the
/// last on top. Escape takes the top one away, chosen on the window's chrome as -3.
SwiftOmniUIObjectRef swiftomniui_winui_sheet_make(void);
void swiftomniui_winui_sheet_set(SwiftOmniUIObjectRef sheet, char const *title, SwiftOmniUIObjectRef page);
/// How tall the sheet's card stands once shown: `height` over 0 in points, under 0 -height of the window's height, 0
/// the content's own. Kept on the sheet; measured where it lands, so a parent that changes size keeps the share.
void swiftomniui_winui_sheet_set_height(SwiftOmniUIObjectRef sheet, double height);
void swiftomniui_winui_window_set_sheets(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef const *sheets, int32_t count);

/// Lays `overlay` over the window's page and its sheets, where the page stands; a click beside what it holds goes on
/// to them. Null takes it away.
void swiftomniui_winui_window_set_overlay(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef overlay);

/// How many sheets a window shows - what a test reads.
int32_t swiftomniui_winui_window_sheets(SwiftOmniUIObjectRef window);

/// A popover: a `Flyout` whose content is the element `content` - the popover's own layout, sized as it says. Its
/// closing, of the user's accord or the host's, told through `presented` as false under the number `view`.
SwiftOmniUIObjectRef swiftomniui_winui_popover_make(int64_t view, SwiftOmniUIObjectRef content);
/// Opens the popover beside `anchor`, on the edge `edge` names - `Edge`'s raw values - where there is room; an
/// anchor not yet in its window, once it is.
void swiftomniui_winui_popover_show(SwiftOmniUIObjectRef popover, SwiftOmniUIObjectRef anchor, int32_t edge);
void swiftomniui_winui_popover_hide(SwiftOmniUIObjectRef popover);
/// Whether the popover shows - what a test reads.
bool swiftomniui_winui_popover_is_open(SwiftOmniUIObjectRef popover);

/// A view's context menu: `count` entries, each `kinds`' 0 an item, 1 a separator, 2 a submenu opening, 3 it closing,
/// with its caption, whether it can be chosen and the identifier automation finds it by (empty for none); an item's
/// choice told through `menuChosen` by its place among the items. None takes the menu away.
void swiftomniui_winui_set_context_menu(SwiftOmniUIObjectRef element, int64_t view, int32_t const *kinds,
                                    char const *const *titles, bool const *enabled, char const *const *identifiers,
                                    uint64_t const *mounts, int32_t count);

/// A menu living in the view: a `Button` whose `Flyout` a press opens, its face a row - the label child before a
/// chevron the indicator setting shows or hides.
SwiftOmniUIObjectRef swiftomniui_winui_menu_button_make(int64_t view);

/// A menu on a toolbar: the view's own menu button dressed as the bar's, whose flyout `menu_button_set_menu` writes.
SwiftOmniUIObjectRef swiftomniui_winui_toolbar_menu_button_make(int64_t view);

/// The label child's element the button's face shows before its chevron; none for the chevron alone.
void swiftomniui_winui_menu_button_set_face(SwiftOmniUIObjectRef button, SwiftOmniUIObjectRef content);

/// Whether the button's face draws the chevron that says it opens a menu.
void swiftomniui_winui_menu_button_set_indicator(SwiftOmniUIObjectRef button, int32_t shown);

/// Whether the button draws the platform's frameless look - `.borderlessButton`'s.
void swiftomniui_winui_menu_button_set_borderless(SwiftOmniUIObjectRef button, int32_t borderless);

/// Native menu interaction and identity used by regression tests.
void swiftomniui_winui_menu_open_for_testing(SwiftOmniUIObjectRef button);

/// Closes the menu a menu button opens, as the user's Escape does - what a test does.
void swiftomniui_winui_menu_close_for_testing(SwiftOmniUIObjectRef button);
uint64_t swiftomniui_winui_menu_identity_for_testing(SwiftOmniUIObjectRef button);
bool swiftomniui_winui_menu_open_submenu_for_testing(SwiftOmniUIObjectRef button, uint64_t mount);

/// The entries the press opens, written as a context menu's are, the flyout the button's `Flyout`. None takes it
/// away.
void swiftomniui_winui_menu_button_set_menu(SwiftOmniUIObjectRef button, int64_t view, int32_t const *kinds,
                                        char const *const *titles, bool const *enabled,
                                        char const *const *identifiers, uint64_t const *mounts, int32_t count);

/// The scene's commands' button at the title bar's leading edge: a `Button` whose face is the platform's
/// navigation glyph and whose `Flyout` - `menu_button_set_menu` writes it - the press opens.
SwiftOmniUIObjectRef swiftomniui_winui_app_menu_make(int64_t view);

/// A window's menu bar: WinUI's MenuBar, written as a context menu is, each menu at the top one of the bar's own.
SwiftOmniUIObjectRef swiftomniui_winui_menu_bar_make(int64_t view);
void swiftomniui_winui_menu_bar_set(SwiftOmniUIObjectRef bar, int64_t view, int32_t const *kinds, char const *const *titles,
                                bool const *enabled, char const *const *identifiers, uint64_t const *mounts, int32_t count);

/// A view's context menu, or a bar's menus, as a test reads them: items by caption, "!" before one that cannot be
/// chosen, "-" a separator, a submenu's entries - and a bar's menu's - in brackets after its caption, ";" between -
/// in UTF-8; the length it needs.
int32_t swiftomniui_winui_menus(SwiftOmniUIObjectRef element, char *utf8, int32_t capacity);

/// Chooses the item at `index` among those menus' items, submenus' included, as assistive technology does.
void swiftomniui_winui_menus_choose(SwiftOmniUIObjectRef element, int32_t index);

/// The identifiers of those menus' items, submenus' included, in their order, ";" between, in UTF-8 - what a test
/// reads; the length it needs.
int32_t swiftomniui_winui_menus_identifiers(SwiftOmniUIObjectRef element, char *utf8, int32_t capacity);

/// A picker: WinUI's ComboBox - its choices, the one chosen (-1 for none, written only where `writeSelected`) told
/// through `chosen`, its placeholder while none is, its choices across it (SwiftOmniUI's `TextAlignment`), and its list
/// opening and closing told through `presented`.
SwiftOmniUIObjectRef swiftomniui_winui_picker_make(int64_t view);
void swiftomniui_winui_picker_set_options(SwiftOmniUIObjectRef picker, char const *const *options, int32_t count);
void swiftomniui_winui_picker_set(SwiftOmniUIObjectRef picker, int32_t selected, bool writeSelected, char const *title);
void swiftomniui_winui_picker_set_alignment(SwiftOmniUIObjectRef picker, int32_t alignment);
void swiftomniui_winui_picker_set_open(SwiftOmniUIObjectRef picker, bool open);

/// How the picker's box presents: a `PickerStyleKind` - 5 (`inline`) is chrome-less, the rest the platform's own.
void swiftomniui_winui_picker_set_style(SwiftOmniUIObjectRef picker, int32_t kind);
bool swiftomniui_winui_picker_is_open(SwiftOmniUIObjectRef picker);
int32_t swiftomniui_winui_picker_selected(SwiftOmniUIObjectRef picker);

/// The choices the picker holds, in UTF-8, each on a line of its own, as far as `capacity` goes; the length they need.
int32_t swiftomniui_winui_picker_choices(SwiftOmniUIObjectRef picker, char *utf8, int32_t capacity);

/// Opens or closes the list as UI Automation does, and chooses as the user does, outside the program's write - what
/// a test does.
void swiftomniui_winui_picker_open_as_user(SwiftOmniUIObjectRef picker, bool open);
void swiftomniui_winui_picker_choose_as_user(SwiftOmniUIObjectRef picker, int32_t index);

/// A day: WinUI's CalendarDatePicker, its day (none where not `hasDate`), its bounds (null for WinUI's own), its day
/// written short or long in the user's own way, and its calendar, whose opening and closing are told through
/// `presented`; the user's day told through `picked`.
SwiftOmniUIObjectRef swiftomniui_winui_date_make(int64_t view);
void swiftomniui_winui_date_set(SwiftOmniUIObjectRef picker, bool hasDate, int32_t year, int32_t month, int32_t day);
void swiftomniui_winui_date_set_range(SwiftOmniUIObjectRef picker, int32_t const *earliest, int32_t const *latest);
void swiftomniui_winui_date_set_format(SwiftOmniUIObjectRef picker, bool longForm);
void swiftomniui_winui_date_set_open(SwiftOmniUIObjectRef picker, bool open);
bool swiftomniui_winui_date_is_open(SwiftOmniUIObjectRef picker);

/// The day it shows, as year, month and day; whether it shows one.
bool swiftomniui_winui_date(SwiftOmniUIObjectRef picker, int32_t *parts);

/// A time of day: WinUI's TimePicker in the user's clock, its time (none where not `hasTime`); the user's time told
/// through `picked`.
SwiftOmniUIObjectRef swiftomniui_winui_time_make(int64_t view);
void swiftomniui_winui_time_set(SwiftOmniUIObjectRef picker, bool hasTime, int32_t hour, int32_t minute);

/// The time it shows, as hour and minute; whether it shows one.
bool swiftomniui_winui_time(SwiftOmniUIObjectRef picker, int32_t *parts);

/// Picks as the user does, outside the program's write - what a test does.
void swiftomniui_winui_date_pick_as_user(SwiftOmniUIObjectRef picker, int32_t year, int32_t month, int32_t day);
void swiftomniui_winui_time_pick_as_user(SwiftOmniUIObjectRef picker, int32_t hour, int32_t minute);

/// What shows work: a progress bar, how far along from 0 to 1 as the host keeps it, and a spinner, turning while its
/// work runs.
SwiftOmniUIObjectRef swiftomniui_winui_progress_bar_make(void);
void swiftomniui_winui_progress_bar_set(SwiftOmniUIObjectRef bar, double progress);
double swiftomniui_winui_progress_bar_value(SwiftOmniUIObjectRef bar);
SwiftOmniUIObjectRef swiftomniui_winui_progress_ring_make(void);
void swiftomniui_winui_progress_ring_set_running(SwiftOmniUIObjectRef ring, bool running);
bool swiftomniui_winui_progress_ring_running(SwiftOmniUIObjectRef ring);

/// The controls that are on or off - a switch, a check box with no caption, and a radio button in a group of its
/// own - each telling its turn through `toggled`.
SwiftOmniUIObjectRef swiftomniui_winui_switch_make(int64_t view);
SwiftOmniUIObjectRef swiftomniui_winui_check_box_make(int64_t view);
SwiftOmniUIObjectRef swiftomniui_winui_radio_make(int64_t view);
void swiftomniui_winui_toggle_set_on(SwiftOmniUIObjectRef toggle, bool on);

/// What a switch, a check box or a radio button is drawn over, in every state it can be in; none for WinUI's own.
void swiftomniui_winui_toggle_set_background(SwiftOmniUIObjectRef toggle, SwiftOmniUIBrush background);
bool swiftomniui_winui_toggle_is_on(SwiftOmniUIObjectRef toggle);

/// Turns a control as UI Automation does, which the user's turn is: a switch or a check box toggled, a radio
/// button chosen.
void swiftomniui_winui_toggle_press(SwiftOmniUIObjectRef toggle);

SwiftOmniUIObjectRef swiftomniui_winui_slider_make(int64_t view);

/// The range from `lower` to `upper` and its steps - an arrow key's, Page Up's and the one a drag lands on - then the
/// value, kept inside the range.
void swiftomniui_winui_slider_set(SwiftOmniUIObjectRef slider, double value, double lower, double upper, double key,
                              double page, double drag);
double swiftomniui_winui_slider_value(SwiftOmniUIObjectRef slider);

/// The slider's steps as WinUI holds them - an arrow key's, Page Up's and a drag's: three values.
void swiftomniui_winui_slider_steps(SwiftOmniUIObjectRef slider, double *steps);

/// A stepper: WinUI's NumberBox, its spin buttons beside its number; the range from `lower` to `upper`, the value
/// kept inside it, a step a spin button's and an arrow key's, and `fractionDigits` decimals written in the user's
/// own way.
SwiftOmniUIObjectRef swiftomniui_winui_stepper_make(int64_t view);
void swiftomniui_winui_stepper_set(SwiftOmniUIObjectRef stepper, double value, double lower, double upper, double step,
                               int32_t fractionDigits);
double swiftomniui_winui_stepper_value(SwiftOmniUIObjectRef stepper);

/// Presses a stepper's spin button, up or down, as UI Automation does - what a test does.
void swiftomniui_winui_stepper_step_as_user(SwiftOmniUIObjectRef stepper, bool up);

/// Enters `utf8` in a stepper's box as the user does, the box reading them as Enter has it - what a test does.
void swiftomniui_winui_stepper_enter_as_user(SwiftOmniUIObjectRef stepper, char const *utf8);

/// Moves a slider's or a stepper's value as UI Automation does, which the user's move is.
void swiftomniui_winui_value_move(SwiftOmniUIObjectRef control, double value);

/// The words the user types, each change told through `textChanged`: a field on one line, whose Enter is
/// `submitted`; an editor of several lines, whose Enter starts a new one; a search box, whose query is `submitted`.
SwiftOmniUIObjectRef swiftomniui_winui_field_make(int64_t view);

/// A field's logical style kind: 1 takes the chrome away, 3 unrounds it, the rest the platform's own look.
void swiftomniui_winui_field_set_style(SwiftOmniUIObjectRef field, int kind);
SwiftOmniUIObjectRef swiftomniui_winui_editor_make(int64_t view);
/// Allocation boundary for the retained TextBox; intrinsic size belongs to SOUI.
SwiftOmniUIObjectRef swiftomniui_winui_editor_allocation_make(SwiftOmniUIObjectRef editor);
/// The effective native Height; NaN means XAML still owns automatic sizing.
double swiftomniui_winui_editor_allocated_height(SwiftOmniUIObjectRef editor);

/// One line in the editor's native font, including its padding, border and minimum height.
/// Writes height only on success; false reports a native measurement failure.
bool swiftomniui_winui_editor_intrinsic_height(SwiftOmniUIObjectRef editor, double *height);

/// Queries a separate TextBlock with the editor's font and optional wrapped
/// content; never measures or changes the live TextBox. Two size values.
bool swiftomniui_winui_editor_content_size(SwiftOmniUIObjectRef editor, double width, bool growing, double *size);

/// Hides an editor's native canvas in every visual state; false restores its theme's background, without chrome.
void swiftomniui_winui_editor_set_background_hidden(SwiftOmniUIObjectRef editor, bool hidden);

SwiftOmniUIObjectRef swiftomniui_winui_search_make(int64_t view);
void swiftomniui_winui_field_set_text(SwiftOmniUIObjectRef field, char const *utf8);
void swiftomniui_winui_field_set_placeholder(SwiftOmniUIObjectRef field, char const *utf8);

/// How a field or an editor takes words: read only, spell checked, predicting the next word, and its input scope
/// (`WinUIInputScope`, the relay's numbering of WinUI's scopes), which picks the keyboard a screen offers.
void swiftomniui_winui_field_set_behaviour(SwiftOmniUIObjectRef field, bool readOnly, bool spellChecked, bool predicted,
                                       int32_t scope);

/// The case a field's or an editor's typing takes (SwiftOmniUI's `TextCase`).
void swiftomniui_winui_field_set_casing(SwiftOmniUIObjectRef field, int32_t textCase);

/// How a search box takes words: read only, and the case its typing takes (SwiftOmniUI's `TextCase`).
void swiftomniui_winui_search_set_box(SwiftOmniUIObjectRef search, bool readOnly, int32_t textCase);

/// Its words across it (SwiftOmniUI's `TextAlignment`) and its placeholder's colour, the platform's where not
/// `placeholderColored`.
void swiftomniui_winui_field_set_look(SwiftOmniUIObjectRef field, int32_t alignment, uint32_t placeholderArgb,
                                  bool placeholderColored);

/// Puts the caret `start` characters in and selects `length` from it, both kept inside the words.
void swiftomniui_winui_field_select(SwiftOmniUIObjectRef field, int32_t start, int32_t length);

/// What a test reads of a field, an editor or a search box's text box: read only, spell checked, predicting, its input scope's first name
/// (-1 for none), its words' alignment, its selection's start and length, whether its placeholder is coloured,
/// whether Enter starts a new line - nine values.
void swiftomniui_winui_field_facts(SwiftOmniUIObjectRef field, int32_t *facts);

/// Types in a search box as the user does, into the text box its template holds - what a test does.
void swiftomniui_winui_search_type(SwiftOmniUIObjectRef search, char const *utf8);

/// Submits a search box's query as UI Automation does, its own button's way - what a test does.
void swiftomniui_winui_search_submit_as_user(SwiftOmniUIObjectRef search);

/// A shape drawn behind a layout's children: a rectangle, rounded or not, or an ellipse, filled and outlined.
SwiftOmniUIObjectRef swiftomniui_winui_shape_make(SwiftOmniUIOutline outline);
void swiftomniui_winui_shape_set(SwiftOmniUIObjectRef shape, double radius, SwiftOmniUIBrush fill, SwiftOmniUIBrush stroke,
                             double strokeWidth);

/// A content divider: a native rectangle filled by the live DividerStrokeColorDefaultBrush ThemeResource.
SwiftOmniUIObjectRef swiftomniui_winui_divider_make(void);

/// A shape: a zero-intrinsic-size XAML node drawing a Composition vector path.
/// Geometry and paint updates never invalidate native Measure.
SwiftOmniUIObjectRef swiftomniui_winui_path_make(int64_t view);

/// Paints a shape: its fill and outline, the outline's width, its dashes and their offset in outline widths, its ends
/// (SwiftOmniUI's LineCap), its joins (LineJoin) and how far a mitred join may reach.
void swiftomniui_winui_path_paint(SwiftOmniUIObjectRef path, SwiftOmniUIBrush fill, SwiftOmniUIBrush stroke, double width,
                              double const *dashes, int32_t dashCount, double dashOffset, int32_t cap, int32_t join,
                              double miter);

/// The bounds of the geometry `commands` draw, as `swiftomniui_winui_path_draw` takes them, as WinUI measures it: its
/// x, y, width and height into `bounds`, all 0 for a geometry that draws nothing.
void swiftomniui_winui_path_bounds(double const *commands, int32_t count, double *bounds);

/// Draws a shape in a room `width` by `height` DIPs: `kind` 0 a rectangle, its corners' `radii` clockwise from the
/// top left, or 1 an ellipse, both drawn `inset` from the room's edges; 2 the geometry `commands` draw - flat, 0 move
/// x y, 1 line x y, 2 cubic x1 y1 x2 y2 x y, 3 quadratic x1 y1 x y, 4 close - filled by `evenOdd`'s rule. Each is
/// moved by `placement` (a b c d tx ty) where one is given: a figure's places it in the room, a rectangle's and an
/// ellipse's is their transform.
void swiftomniui_winui_path_draw(SwiftOmniUIObjectRef path, int32_t kind, double const *radii, double const *commands,
                             int32_t count, bool evenOdd, double const *placement, double width, double height,
                             double inset);

/// A canvas: a panel its drawing is replayed on, again for each size and scale it is shown at; a press on it is
/// told through `canvasPressed` for the view `view`.
SwiftOmniUIObjectRef swiftomniui_winui_canvas_make(int64_t view);

/// The canvas's drawing, as SwiftOmniUI's `HostDrawing` lays it out: each instruction's kind and whole numbers in
/// `ints`, its numbers in `numbers`, and its text in `words`, `wordCount` UTF-8 runs of `lengths` bytes end to end.
void swiftomniui_winui_canvas_draw(SwiftOmniUIObjectRef canvas, int32_t const *ints, int32_t intCount, double const *numbers,
                               int32_t numberCount, char const *words, int32_t const *lengths, int32_t wordCount);

/// The room `text` takes drawn in the font named - `family` or the canvas's own where empty, `size` DIPs or the
/// body's where not positive, `weight` on the 100-900 scale or regular where not positive, slanted where
/// `italic` - wrapped at `width` DIPs where positive. Writes width and height into `out`; 0 where it could not
/// be measured.
int32_t swiftomniui_winui_measure_text(char const *text, char const *family, double size, int32_t weight,
                                   int32_t italic, double width, double *out);

/// A ColorBox: a Border filled with one colour, its corners rounded in DIPs - top left, top right, bottom right,
/// bottom left.
SwiftOmniUIObjectRef swiftomniui_winui_color_box_make(int64_t view);
void swiftomniui_winui_color_box_set(SwiftOmniUIObjectRef box, uint32_t argb, double const *corners);

/// Renders the element and reads the colour, as ARGB, at each of `count` points given as x and y in DIPs of it -
/// what a test reads of the screen; whether it rendered.
bool swiftomniui_winui_pixels(SwiftOmniUIObjectRef element, double const *points, int32_t count, uint32_t *argb);

/// Samples actual presented RGB pixels, including Composition visuals; for visible, unobscured test windows.
bool swiftomniui_winui_presented_pixels(
    SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef element, double const *points, int32_t count, uint32_t *argb
);

/// A ScrollView's scroller: a ScrollViewer around `content`, scrolling down (0), across (1), both ways (2) or not at
/// all (3); each bar shown as WinUI decides (0), always (1) or never (2).
SwiftOmniUIObjectRef swiftomniui_winui_scroller_make(int64_t view);
void swiftomniui_winui_scroller_set(SwiftOmniUIObjectRef scroller, SwiftOmniUIObjectRef content, int32_t orientation,
                                int32_t verticalBar, int32_t horizontalBar);

/// Whether each axis moves: WinUI's own `ScrollMode` - disabled (0), enabled (1) or only where the content is big
/// enough to move (2). `scrollBounceBehavior`'s `.basedOnSize` is the last.
void swiftomniui_winui_scroller_modes(SwiftOmniUIObjectRef scroller, int32_t verticalMode, int32_t horizontalMode);

/// Marks the scroller's presenter to measure and arrange again: its anchor is chosen before the document moves.
void swiftomniui_winui_scroller_invalidate_presenter(SwiftOmniUIObjectRef scroller);

/// Native vertical and horizontal ScrollMode values, in that order.
void swiftomniui_winui_scroller_read_modes(SwiftOmniUIObjectRef scroller, int32_t *modes);

/// Moves the scroller's view to `x`, `y` DIPs at once; the scroller keeps it within what it can reach, and says where
/// it stands through `scrolled` once it has moved.
void swiftomniui_winui_scroller_move(SwiftOmniUIObjectRef scroller, double x, double y, bool animated);
/// Commits the displayed document offset after its virtualized window has been arranged.
void swiftomniui_winui_scroller_anchor(SwiftOmniUIObjectRef element, bool enabled);

/// Where the scroller's view would stand for `descendant` where the anchors say, in DIPs, read into `place`: the
/// fraction of each across the child and the room, `NAN` for "only where it is not wholly in view". `found` says
/// whether the descendant lies inside the scroller's document.
void swiftomniui_winui_scroller_place_for(SwiftOmniUIObjectRef scroller, SwiftOmniUIObjectRef descendant,
                                      double anchorX, double anchorY, int32_t *found, double *place);

/// Where the scroller's view stands, then the farthest it reaches across and down, in DIPs: four values.
void swiftomniui_winui_scroller_offset(SwiftOmniUIObjectRef scroller, double *offset);

/// Six DIPs: the visible viewport x, y, width, height in the descendant's coordinates, intersected with
/// ancestor scroll presenters and clipping bounds, then its displayed x, y relative to the native presenter.
/// Only Ready writes values; an offscreen intersection can be empty. NotReady retains a weak request,
/// resumed by native attachment/layout. Failed reports a native error and registers no pending request.
typedef enum {
    SwiftOmniUIViewportFailed = -1,
    SwiftOmniUIViewportNotReady = 0,
    SwiftOmniUIViewportReady = 1
} SwiftOmniUIViewportStatus;
SwiftOmniUIViewportStatus swiftomniui_winui_scroller_viewport(
    SwiftOmniUIObjectRef scroller, SwiftOmniUIObjectRef descendant, double *viewport);

/// The room the bars floating over the scroller keep from its indicators, in DIPs: each indicator's track is
/// inset past a bar's extent on its own edge, the document's room untouched.
void swiftomniui_winui_scroller_insets(SwiftOmniUIObjectRef scroller, double top, double right, double bottom, double left);

/// An ItemsView: WinUI's ItemsView over the identities the host gives it; the cell of each entry is the host's
/// (`itemCell`, `itemHeld`, `itemLetGo`), and what stands in view, the user's choice and an item invoked are told.
SwiftOmniUIObjectRef swiftomniui_winui_items_make(int64_t view);

/// The identities, each an item (0) or a header or a footer (1), and the changes from the ones before: runs of places
/// removed, last first, then runs inserted, first first, each a start and a count. Asked while the list lays its
/// cells out, the relay applies them once it is done, in order.
void swiftomniui_winui_items_set_entries(SwiftOmniUIObjectRef items, char const *const *identities, int32_t const *kinds,
                                     int32_t count, int32_t const *removed, int32_t removedCount,
                                     int32_t const *inserted, int32_t insertedCount);

/// How the entries stand: down (0), across (1), or in columns at least `minimumItemWidth` DIPs wide (2); `spacing`
/// DIPs apart.
void swiftomniui_winui_items_set_layout(SwiftOmniUIObjectRef items, int32_t shape, double spacing, double minimumItemWidth);

/// How the items' surface presents: a `ListStyleKind` - 1 (`plain`) on no ground, 2 (`sidebar`) on the platform's
/// muted layer, the rest the platform's own.
void swiftomniui_winui_items_set_style(SwiftOmniUIObjectRef items, int32_t kind);

/// How many items the user may choose - none (0), one (1), many (2) - the identities chosen, and whether an item is
/// invoked.
void swiftomniui_winui_items_set_choice(SwiftOmniUIObjectRef items, int32_t mode, char const *const *chosen, int32_t count,
                                    bool invokable);

/// Brings the entry at `index` into view: at the start (0), the centre (1), the end (2), or the nearest edge (3).
void swiftomniui_winui_items_scroll_to(SwiftOmniUIObjectRef items, int32_t index, int32_t anchor, bool animated);

/// The ItemsView left: nothing waits, and every cell is let go.
void swiftomniui_winui_items_release(SwiftOmniUIObjectRef items);

/// What a test reads: the identities the list holds chosen, joined by newlines; the length it needs.
int32_t swiftomniui_winui_items_chosen(SwiftOmniUIObjectRef items, char *utf8, int32_t capacity);

/// What a test reads: how many items the user may choose, as `set_choice` numbers it.
int32_t swiftomniui_winui_items_mode(SwiftOmniUIObjectRef items);

/// What a test does as the user's click on the entry at `index`: where many may be chosen it takes the item or lets it
/// go, else it takes it alone; the choice is told as the user's.
void swiftomniui_winui_items_choose_as_user(SwiftOmniUIObjectRef items, int32_t index);

/// What a test does as the user opens the item a cell holds: its container's Invoke, as Narrator's; false where there
/// is none.
bool swiftomniui_winui_items_invoke_as_user(SwiftOmniUIObjectRef cell);

/// What a test does as the user scrolls the list to `x`, `y` DIPs, unanimated: the list's view stands there once
/// WinUI's compositor has moved it, a moment later.
void swiftomniui_winui_items_scroll_as_user(SwiftOmniUIObjectRef items, double x, double y);

/// Where the list's view stands, then the farthest it reaches across and down, in DIPs: four values.
void swiftomniui_winui_items_offset(SwiftOmniUIObjectRef items, double *offset);

/// Names the row holding the cell numbered `cell` `words`: what Narrator reads of it, which reads no further.
void swiftomniui_winui_items_name(SwiftOmniUIObjectRef items, int64_t cell, char const *words);

/// What a test reads: what Narrator calls the row holding the cell numbered `cell`; the length it needs.
int32_t swiftomniui_winui_items_row_name(SwiftOmniUIObjectRef items, int64_t cell, char *utf8, int32_t capacity);

/// A window's chrome: WinUI's TitleBar, its way back and its sidebar's toggle, the title, the page's actions on it or
/// in its overflow, and three slots - leading, centre, trailing. The way back is chosen as -1, the toggle as -2, an
/// action by its place.
SwiftOmniUIObjectRef swiftomniui_winui_title_bar_make(int64_t view);

/// The native template's declared row height in DIPs, available before activation or layout.
double swiftomniui_winui_title_bar_layout_height(SwiftOmniUIObjectRef bar);

/// `words` stand light (1) or dark (2) on a bar the tree paints, the bar's buttons and commands with them; 0 for
/// the theme's own.
void swiftomniui_winui_title_bar_set(SwiftOmniUIObjectRef bar, char const *title, bool back, bool paneToggle,
                                 bool hasBackground, uint32_t background, bool hasForeground, uint32_t foreground,
                                 int32_t words);

/// The native title bar's subtitle; an empty string clears the previous value.
void swiftomniui_winui_title_bar_set_subtitle(SwiftOmniUIObjectRef bar, char const *subtitle);

/// The page's actions on a window's chrome: each one's words, the identifier automation finds it by (empty for
/// none), the files its picture may stand in - each ended by a line feed, empty for none - the Segoe Fluent glyph
/// it shows where its picture is a symbol (empty for none), whether it stands in the overflow, and whether it can be
/// chosen; `kinds` says what each entry is - 0 a button, 1 a fixed gap, 2 a
/// flexible one - and `contents` the view an entry shows in the button's place, null for a button.
void swiftomniui_winui_title_bar_set_actions(SwiftOmniUIObjectRef bar, char const *const *texts,
                                         char const *const *identifiers, char const *const *icons,
                                         char const *const *symbols, bool const *overflows, bool const *enabled,
                                         SwiftOmniUIObjectRef const *contents, int32_t const *kinds,
                                         int32_t count, int32_t leadingCount);

/// What a test reads: whether a title bar's words stand light (1), dark (2), or as the theme has them (0).
int32_t swiftomniui_winui_title_bar_words(SwiftOmniUIObjectRef bar);

/// What a test reads: the room a title bar keeps at its trailing edge, and the room the window's own buttons there
/// take, both in DIPs; -1 kept where the bar stands in no window.
void swiftomniui_winui_title_bar_caption_room(SwiftOmniUIObjectRef bar, double *kept, double *room);
void swiftomniui_winui_title_bar_set_slots(SwiftOmniUIObjectRef bar, SwiftOmniUIObjectRef leading, SwiftOmniUIObjectRef center,
                                       SwiftOmniUIObjectRef trailing);

/// The scene's commands' button at the bar's leading edge, ahead of the authored leading content; null takes it
/// away.
void swiftomniui_winui_title_bar_set_app_menu(SwiftOmniUIObjectRef bar, SwiftOmniUIObjectRef button);

/// A native SplitView; a trailing pane holds an auxiliary detail column. A zero breakpoint keeps it inline.
SwiftOmniUIObjectRef swiftomniui_winui_split_make(int64_t view, double expandsAt, bool trailing);
/// Selects the initial display mode from a known client allocation before activation.
void swiftomniui_winui_split_prepare_room(SwiftOmniUIObjectRef split, double width);
void swiftomniui_winui_split_clear(SwiftOmniUIObjectRef split);
/// Releases one changed slot while leaving the other columns attached.
void swiftomniui_winui_split_remove(SwiftOmniUIObjectRef split, SwiftOmniUIObjectRef child);
double swiftomniui_winui_split_minimum_width(SwiftOmniUIObjectRef split);

/// Width bounds apply to the pane and remaining content. The native drag handle retains the user's width.
void swiftomniui_winui_split_set(SwiftOmniUIObjectRef split, SwiftOmniUIObjectRef pane, SwiftOmniUIObjectRef content,
                             SwiftOmniUIObjectRef row, bool open, double minimum, double ideal, double maximum,
                             bool contentShown, double contentMinimum, double contentMaximum);

/// A tabbed view's row of tabs: a SelectorBar, `selected` chosen.
SwiftOmniUIObjectRef swiftomniui_winui_tabs_make(int64_t view);
void swiftomniui_winui_tabs_set(SwiftOmniUIObjectRef tabs, char const *const *titles, int32_t count, int32_t selected);
/// Chooses the tab at `index` as the user's click does - what a test does.
void swiftomniui_winui_tabs_choose_as_user(SwiftOmniUIObjectRef tabs, int32_t index);

/// A group of the environment's facts, in UTF-8, each ended by the unit separator (0x1F); the display's are the
/// screen `window` stands on. Answers the length the facts need, their end not counted.
int32_t swiftomniui_winui_facts(SwiftOmniUIFacts kind, SwiftOmniUIObjectRef window, char *utf8, int32_t capacity);

/// Watches the theme, the power and the network, `environmentChanged` called in the UI thread's turn after each
/// change; once.
void swiftomniui_winui_watch_environment(void);

/// Listens on `element`, which the view `view` shows, for what `hearing` names, each heard through `heard`; 0
/// stops. A panel that listens is hit where it draws nothing, and one that hears taps assistive technology presses.
void swiftomniui_winui_hear(SwiftOmniUIObjectRef element, int64_t view, uint32_t hearing);

/// The host says the press the view `view` heard is a drag: the view holds the pointer from the move it heard it in.
void swiftomniui_winui_press_dragged(int64_t view);
bool swiftomniui_winui_point_from_root(SwiftOmniUIObjectRef view, double x, double y, double *local);

/// The system's drag distance, across and down, in DIPs.
void swiftomniui_winui_drag_distance(double *distance);

/// Presses `element` as assistive technology does, through its automation peer; whether it could be pressed.
bool swiftomniui_winui_press(SwiftOmniUIObjectRef element);

/// Whether a click at (x, y) DIPs of `element` would reach the element itself.
bool swiftomniui_winui_hits(SwiftOmniUIObjectRef element, double x, double y);

/// Whether a click at (x, y) DIPs of `element` would reach it, or what stands in it, through everything its window
/// shows over it - what a test reads.
bool swiftomniui_winui_reaches(SwiftOmniUIObjectRef element, double x, double y);

/// Whether a place in the window's content, in DIPs, reaches `element` or what stands in it - the pointer's own
/// place asked the same way when a popup that stood over it goes.
bool swiftomniui_winui_content_reaches(SwiftOmniUIObjectRef element, double x, double y);

/// The pointer's place in the window's content, in DIPs; false where it stands outside the window, or its own place
/// cannot be read.
bool swiftomniui_winui_pointer_place(SwiftOmniUIObjectRef element, double *place);

/// Tells `focused` whenever the keyboard comes into the element or leaves it, while `hearing`; false stops.
void swiftomniui_winui_hear_focus(SwiftOmniUIObjectRef element, int64_t view, bool hearing);


/// How many views listen for the user's input - what a test counts to see every one stop.
int32_t swiftomniui_winui_listeners(void);

/// How many sets of input handlers hang on elements - a view that stopped listening keeps its set until the event
/// running is over - what a test counts.
int32_t swiftomniui_winui_hung_handlers(void);

/// What assistive technology meets of the element: its automation id, name and help text - null for the control's
/// own - its heading level (0 none, 1 to 9), and `presence`: 0 as the control is of itself, 1 met, 2 skipped, 3
/// skipped with every part its template draws.
void swiftomniui_winui_set_accessibility(SwiftOmniUIObjectRef element, char const *identifier, char const *label,
                                     char const *hint, int32_t heading, int32_t presence);

/// Whether assistive technology meets none of what stands in a panel.
void swiftomniui_winui_panel_hide_children(SwiftOmniUIObjectRef panel, bool hidden);

/// What assistive technology meets of the element, as its automation peer says it - what a test reads: `what` 0 its
/// name, 1 its help text, 2 its automation id, in UTF-8; the length they need, their end not counted.
int32_t swiftomniui_winui_automation_words(SwiftOmniUIObjectRef element, int32_t what, char *utf8, int32_t capacity);

/// Its heading level, whether it is a control element and a content element, and how many children it has: four
/// values.
void swiftomniui_winui_automation_facts(SwiftOmniUIObjectRef element, int32_t *facts);

/// How many canvases WinUI holds - what a test counts to see every one let go.
int32_t swiftomniui_winui_canvases(void);
/// Successful surface submissions for regression checks; no logging or switches.
uint64_t swiftomniui_winui_canvas_paints(SwiftOmniUIObjectRef canvas);

/// The local time of day: hour, minute, second and millisecond, into `time`.
void swiftomniui_winui_clock(int32_t *time);

/// The IANA identifier of the local time zone, in UTF-8, as far as `capacity` goes; answers its whole length.
int32_t swiftomniui_winui_time_zone(char *utf8, int32_t capacity);

/// How far `zone` - an IANA identifier, the local zone for null - stands from UTC on a day, in minutes; year 0
/// for today. Answers false for a zone ICU does not know.
bool swiftomniui_winui_utc_offset(char const *zone, int32_t year, int32_t month, int32_t day, int32_t *minutes);

/// Says `utf8` to a screen reader, from `element`, cutting off what it was saying.
void swiftomniui_winui_announce(SwiftOmniUIObjectRef element, char const *utf8);

/// Puts `utf8` on the clipboard, replacing what it held.
void swiftomniui_winui_copy_text(char const *utf8);

/// Puts the keyboard's focus on `element`, or the first control in it that takes it, answering whether one did;
/// or takes it off whatever holds it inside `element`, answering whether anything did.
bool swiftomniui_winui_focus(SwiftOmniUIObjectRef element, bool focus);

/// Whether `element`, or something inside it, holds the keyboard's focus.
bool swiftomniui_winui_focused(SwiftOmniUIObjectRef element);

/// Takes the focus off a field typed into in `element`'s window, so the on-screen keyboard goes; whether one was.
bool swiftomniui_winui_hide_keyboard(SwiftOmniUIObjectRef element);

/// Puts `question` to the user in WinUI's dialog over `element`'s window, at once - the host asks one at a time;
/// the answer comes back through `answered`, under `ticket`.
void swiftomniui_winui_ask(SwiftOmniUIObjectRef element, int64_t ticket, SwiftOmniUIQuestion const *question);

/// Answers the dialog showing over `element`'s window as the user would: `button` 0 accepts, 1 cancels, 2 and on
/// press the choices in order; a prompt's field first holding `words` where they are given. Whether a dialog
/// was showing and had that button. What a test does.
bool swiftomniui_winui_answer(SwiftOmniUIObjectRef element, int32_t button, char const *words);

/// Shows `dialog` in Windows' own file dialog over `window` (a `Window`); a save writes its contents where the user
/// said, beside the UI thread. The answer comes back through `filesChosen`, under `ticket`, on the UI thread.
void swiftomniui_winui_show_file_dialog(SwiftOmniUIObjectRef window, int64_t ticket, SwiftOmniUIFileDialog const *dialog);

/// Reads the file at `path`, in UTF-8, whole, beside the UI thread; its bytes come back through `fileRead`, under
/// `ticket`, on the UI thread.
void swiftomniui_winui_read_file(int64_t ticket, char const *path);

/// Hands the file at the path `target`, or the address `target`, to Windows to open in the application it gives it;
/// whether one took it comes back through `launchAnswered`, under `ticket`, on the UI thread.
void swiftomniui_winui_launch(int64_t ticket, char const *target, bool file);
void swiftomniui_winui_reveal(int64_t ticket, char const *path);

/// What a test does: while `held`, a launch is answered as taken and Windows is asked nothing.
void swiftomniui_winui_hold_launches(bool held);

/// What a test does: a dialog that saves opens in `folder`, in UTF-8, so what a test saves stays there.
void swiftomniui_winui_keep_test_files_in(char const *folder);

/// What a test does: answers the file dialog `dialog` - the one showing in the process where 0 - as the user would,
/// by the `count` files of `paths`, in UTF-8: typed whole, several each in quotes, and taken once its field holds
/// them; none cancels it. The dialog answered, 0 where it no longer shows: a dialog shown a moment ago may not take
/// its answer yet, so a test answers it again until it is gone.
int64_t swiftomniui_winui_answer_file_dialog(int64_t dialog, char const *const *paths, int32_t count);

/// The folder the host's stores stand in, in UTF-8; empty for the application's own in the user's local data.
void swiftomniui_winui_set_store(char const *utf8);

/// The store in the file `name` as it stands, in UTF-8, as far as `capacity` goes; answers its whole length.
int32_t swiftomniui_winui_stored(char const *name, char *utf8, int32_t capacity);

/// Writes the whole store in the file `name`, in UTF-8, in place of the old one; whether it was written.
bool swiftomniui_winui_store(char const *name, char const *utf8);

/// The font file at `path`, in UTF-8, loaded privately for this process - Windows' own process-private font
/// registration - so a family it carries may be named to `Font.custom`. How far the registration reaches, whether
/// XAML's `FontFamily` resolves a family it holds, is Windows' to say; a family it does not resolve falls back as
/// it did. The number of faces Windows took, 0 where none was.
int32_t swiftomniui_winui_register_font(char const *path);

/// The folder the application's pictures are read from, in UTF-8; empty for `Images` beside the executable.
void swiftomniui_winui_set_pictures(char const *folder);

/// An Image showing the first of the `count` files `names` lists that the pictures hold, filling its room as
/// SwiftOmniUI's Aspect says: fit, fill, stretch, centre. Answers whether a picture was found, or none was named;
/// `size` takes the size an SVG declares, in DIPs, and zero for a bitmap, whose size WinUI knows once it has read
/// it.
SwiftOmniUIObjectRef swiftomniui_winui_image_make(int64_t view);
bool swiftomniui_winui_image_set(SwiftOmniUIObjectRef image, char const *const *names, int32_t count, int32_t aspect,
                             double *size);

/// A symbol in place of the picture: `glyph` is the Segoe Fluent Icons glyph the symbol is shown as, in UTF-8 -
/// the Fluent font is the platform's own symbol set, which is why the glyph and not a name crosses. Answers false
/// for a missing element or an empty glyph.
bool swiftomniui_winui_image_set_symbol(SwiftOmniUIObjectRef image, char const *glyph, int32_t aspect,
                                       double fontSize, double fontWeight, int32_t textStyle, double *size);
/// Tint the native system glyph, or clear the local foreground to follow the theme.
void swiftomniui_winui_image_set_tint(SwiftOmniUIObjectRef image, bool has, uint32_t argb);

/// The synchronously decoded bitmap size, or an SVG's declared intrinsic size, in DIPs.
void swiftomniui_winui_image_size(SwiftOmniUIObjectRef image, double *size);

/// Places the picture or symbol at its rendered size, centred in the image's layout frame.
void swiftomniui_winui_image_place(SwiftOmniUIObjectRef image, double width, double height);

/// Draws an SVG `image` shows at `width` by `height` DIPs, at the display's scale; nothing for a bitmap.
void swiftomniui_winui_image_draw(SwiftOmniUIObjectRef image, double width, double height);

/// Changes when the application's picture folder changes, including back to its default.
uint64_t swiftomniui_winui_pictures_revision(void);

/// Whether two native Images hold the same ready, decoded source.
bool swiftomniui_winui_images_share_source(SwiftOmniUIObjectRef left, SwiftOmniUIObjectRef right);

/// An Image's decoded premultiplied RGBA pixels, available before the first XAML frame.
bool swiftomniui_winui_image_decoded_pixels(SwiftOmniUIObjectRef image, int32_t *size, uint8_t *rgba, int64_t capacity);

/// The pixels of the first of the `count` files `names` lists that the pictures hold, as premultiplied RGBA rows:
/// `size` takes the picture's width and height in pixels, and `rgba` - where it holds `capacity` bytes of at
/// least `width * height * 4` - the pixels themselves. Answers whether a picture answered, so a call with no
/// `rgba` asks the size, and one with it takes a copy. SVGs use their synchronously rendered intrinsic viewport;
/// a name no picture bears answers false.
bool swiftomniui_winui_picture_pixels(char const *const *names, int32_t count, int32_t *size, uint8_t *rgba,
                                      int64_t capacity);

/// What WinUI holds of `element`'s property named `what`, in UTF-8, as far as `capacity` goes - a colour as #AARRGGBB,
/// a number, 0 or 1, words, sides and corners as four numbers - answering its whole length; -1 for a property the
/// element has none of. What a test reads.
int32_t swiftomniui_winui_read(SwiftOmniUIObjectRef element, char const *what, char *utf8, int32_t capacity);
/// Requests a native element theme (0 system, 1 light, 2 dark), without a Swift tree update. What a test does.
void swiftomniui_winui_set_theme_for_testing(SwiftOmniUIObjectRef element, int32_t theme);
/// Writes UIElement.Scale directly, reporting whether XAML permits the facade. What a test does.
bool swiftomniui_winui_set_scale_for_testing(SwiftOmniUIObjectRef element, double x, double y);
/// Authored XAML rectangle and transform, as native SplitView templates use.
void swiftomniui_winui_set_native_clip_for_testing(
    SwiftOmniUIObjectRef element, bool enabled, double x, double y, double width, double height, double dx, double dy);

/// The question showing over `element`'s window, in UTF-8, as far as `capacity` goes: its title, message, accepting
/// and cancelling captions, its field's words (0x01 for none) and its choices, each ended by the unit separator
/// (0x1F) but the last; -1 for none showing. What a test reads.
int32_t swiftomniui_winui_question(SwiftOmniUIObjectRef element, char *utf8, int32_t capacity);

/// What the screen reader was told since the relay started, in UTF-8, each ended by the unit separator (0x1F) but
/// the last, as far as `capacity` goes; its whole length. What a test reads.
int32_t swiftomniui_winui_announced(char *utf8, int32_t capacity);

/// The file dialog showing in the process: 0 one that opens, 1 one that saves, -1 none. What a test reads.
int32_t swiftomniui_winui_file_dialog(void);

/// What was launched since the relay started - a file by its path, an address as written - in UTF-8, each ended by
/// the unit separator (0x1F) but the last, as far as `capacity` goes; its whole length. What a test reads.
int32_t swiftomniui_winui_launched(char *utf8, int32_t capacity);

#ifdef __cplusplus
}
#endif

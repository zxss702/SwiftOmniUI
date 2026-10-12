# Drawing on GTK

What the GTK host draws itself: a layout's box, a colour box, and a child
placed by an engine's run. Each is a `SwiftOmniUIPanel` whose snapshot the host
answers ([the C API](c-api.md#a-subclass-from-swift)).

## A layout's box

A layout draws its own box in its snapshot, before its children: the fill -
a colour, or a linear or radial gradient over the box in fractions of its
size, a radial one a circle reaching as far across as down
([brushes](../../types/brushes.md#geometry-in-fractions)) - inside the
outline, then the outline's stroke inside its edge, so the
stroke never spills over the place the layout was given. The outline is a
rectangle, a rectangle with rounded corners, or an ellipse, each GSK's
rounded rectangle. A stroke is drawn in one colour: a gradient's first stop.

A layout that clips cuts what it holds to its outline as it draws it, and
takes `overflow: hidden`, so a child cut away also takes no click. A layout
that does not clip cuts nothing.

A colour box is a panel of one colour, its corners rounded each by its own
radius; it takes the room its layout gives it and asks for none.

## A widget's own box

GTK sizes and draws a widget's own box - the room between its edge and its
content - from CSS alone. The host keeps one style sheet for the whole
display, and a rule in it for each value asked for, a class named for what
it says - `swiftomniui-padding-24-8-12-4`, a header bar's colours
`swiftomniui-bar-b512BD4FF-fFFFFFFFF` - which a widget wears to take it and takes
off to give it up. The sheet stands above the color scheme, so its rule wins over
the color scheme's own for the same widget. A rule is written the first time its value is
asked for and stays, the sheet written again in the rules' order; a value
that moves every frame has its own road, never a rule a frame.

## The application's pictures

The application's pictures stand in an `Images` folder beside its
executable, which the run script fills from the application's
`Resources/Images`, and the tree names each by its file. Where the tree asks
for a PNG the folder holds as an SVG, the SVG is shown: the application's
pictures are written once, as SVGs, for every host.

A picture shown as an icon is a `GtkImage` of the file's icon, a given number
of logical pixels across: GTK reads the file - an SVG through gdk-pixbuf's
loader - at that size times the display's scale, and again when the scale
changes.

`PicturePixels(named:)` answers through `GTKPictures.pixels`: the file read
by `GdkPixbuf`, whose bytes are RGB, plus a straight alpha where it has one,
premultiplied on the way into the RGBA rows it hands back - or nil where no
loader reads the file.

## The application's fonts

The fonts an application carries are registered, as `Fonts.register` names
them, through `GTKFonts.register`: the file is added to the current
fontconfig's application fonts - the list every `pango_attr_family_new`
resolves its name against - so a `Font.custom` family finds it without the
font being installed. A `PangoFcFontMap` lists the families it had when it
was made, so the default font map is told the configuration changed, that a
file registered late is still found. The files are handed to fontconfig as
the host starts, before it makes a font context; `register` keeps them for
it before then.

## The shapes

Each of the six shapes is a panel drawing its geometry with GSK's own paths
in its snapshot, for the room its layout gives it, again whenever that room
changes. A rectangle and an ellipse fill the room, drawn half their outline in
from its edges so the outline stays inside; a rectangle's corners are each
its own radius, an ellipse a rounded rectangle whose corners meet. A line, a
path, a polygon and a polyline draw a geometry of their own - a path's data
read by the core's parser, its arcs as curves - placed in the room by the host
layer's rule ([a shape's own geometry](../../host/layout.md#a-shapes-own-geometry))
from the bounds GSK measures. The fill and the outline are the shape's
brushes painted through the path - a gradient runs across the shape it fills;
dashes, gaps and their offset are outline widths in SwiftOmniUI and lengths in
GSK, so they are multiplied by the width. A shape has no size of its own: it
takes the room its layout gives it.

## A canvas

A canvas is a panel that replays its drawing's records in its snapshot,
each against the pen the host layer keeps for it
([settings hold until changed](../../types/drawing.md#settings-hold-until-changed)):
a path the records name is built with GSK's builder - its arcs arriving as
cubic curves already - and pushed as a fill or a stroke, the stroke's cap and
join GSK's own; a fill's rule is GSK's fill rule. A transform multiplies the
snapshot's, and `saveState` and `restoreState` are the snapshot's own, so a
turned shape turns nothing after it. Text is a Pango layout, its pixel size
measured so the two alignments can place it in its box, which clips it.

A press on the canvas is followed by a drag gesture of the view's own, so a
down, a move and a lift arrive as the canvas's `pressed`, `dragged` and
`released` - the point in the canvas's own coordinates, which is where the
drawing's numbers mean.

## A placed child

A ZStack whose places a state drives stands each child where the run says, and
draws it as the run says - moved, turned, tipped in depth and scaled, and as
opaque as the run makes it - over the child's own transform and opacity. The
run's order is the drawing order: the panel holds its children back to front
in that order, which is the order GTK draws them in and the reverse of the
order a click tries them in, so the one drawn in front takes the click. A
placed grid's second child is its shade, drawn as opaque as the run says.

A test reads what is drawn: the widget drawn afresh from its parent, as a
frame's paint draws it, rendered to a texture by its window's renderer and
read back as premultiplied colour, sampled at the points the test names. A
widget's own paintable shows only the drawing GTK last kept, which a layout
since has thrown away.

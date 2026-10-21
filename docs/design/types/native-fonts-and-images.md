# Native font files and in-memory images

Desktop clients that already own a typesetting algorithm can use `FontFace`
without registering or resolving a font family. The Windows host opens the exact
OTF with DirectWrite; GTK uses FreeType for glyph metrics and outlines, and
HarfBuzz for OpenType shaping. DirectWrite and Pango supply Unicode script,
bidi and line-break analysis. Glyph names are read from the font's CFF/post
tables. No external glyph JSON or runtime exporter is involved.

`Font.metrics` resolves ordinary font descriptors through the same native font
families used by labels, and caches actual ascender, descender, leading and cap
height. Theme/font-map changes invalidate that cache. A failed lookup returns
nil rather than a proportion of the requested point size.

A face owns its native resources, and retains glyph metrics and paths for reuse.
A shaped glyph carries its font-unit position, advance and original UTF-16
cluster range. `SwiftOmniUIFoundation` exposes the CoreText/CoreGraphics subset
needed by existing desktop typesetters on top of these operations; it is not a
second math parser. It does not implement CoreText's system-font fallback or
promise identical mixed-font bidi behavior.

`BitmapImage` owns immutable premultiplied RGBA pixels and their logical size.
Pixel dimensions and logical dimensions remain separate, including when raster
sizes are rounded up for display scaling. `GraphicsContext.makeImage` replays
its existing drawing commands to Direct2D or GTK/Cairo once. Native decoders
load encoded image bytes; native encoders provide PNG bytes for interchange.
The Foundation adapter's `PlatformImage` retains this source and its size.
Neither decoding nor drawing requires temporary files.

## Inline layout

`ImageSource` carries memory pixels through the existing image property.
`Text(Image)` preserves image font traits, so native symbols retain an explicitly
requested size. It writes one object-replacement character into the same
continuous text as the surrounding words.

Windows uses RichTextBlock paragraphs for image-bearing text because TextBlock
cannot lay out InlineUIContainer. A native baseline host retains an image's
ascent and descent; text-layout reports use the arranged image's actual bounds.
GTK puts image shapes in the label's Pango layout and snapshots the retained
paintables at Pango's actual baselines. The same native layout decides wrapping,
line height and selection geometry. Color-only updates retain the image objects.

WinUI's native `MaxHeight` line stacking preserves tall inline images. A requested
`.lineSpacing` becomes a minimum line height of natural font height plus spacing.
WinUI does not expose an additive gap for every variable-height line: this is
not exact SwiftUI line-spacing equivalence for tall formula lines.

## Desktop selection and copying

`selectionInteraction` is for a view that already owns a selection model. Native
window events provide deselection, Ctrl+C and Ctrl+A; editable controls retain
their own commands. While dragging, native scroll containers scroll at their
visible edges and report the pointer's updated content coordinates. Handlers
and timers leave with the view; nested horizontal table scrollers do not hide a
document's vertical scroll container.

`Pasteboard.copy(bitmap)` publishes a native image. `Pasteboard.copy(html:plainText:)`
publishes both representations together. The Foundation attributed-document
attachment retains the image pixels and can serialize them into HTML image
URLs. Markdown source extraction, link hit testing and selection ranges remain
in the client; none of that document-specific behavior belongs in the host.

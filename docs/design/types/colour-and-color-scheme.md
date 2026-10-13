# Colour and color scheme

A colour is held as what it is, four channels, and a colour or a picture that
differs between the light and dark themes is one value with a half for each.
The half in force is picked in the core, where an element is built, and
nothing in a host binds anything.

## Four channels

`Color` holds four 8-bit sRGB channels, with an optional dark appearance.
Constant colors compare by their channels: `Color("#ff0000")` and
`Color(red: 1, green: 0, blue: 0)` are one value. A named UI color such as
`.red` is a light/dark palette entry, rather than that constant RGB primary.
Equality and hashing keep both appearances without reading the current theme.

The SwiftUI component initializer uses 0-1 values, including integer literals:
`Color(red: 0, green: 1, blue: 1)` is full-intensity RGB cyan. The older byte
overload remains for typed `Int` channels, with `alpha:` in byte units, but
does not take precedence over SwiftUI component literals. Hex is an explicit
way to spell constant byte colors. Linear sRGB and Display P3 input are
converted once into gamma-encoded sRGB before crossing the host boundary.
The current boundary quantizes to 8 bits and clips out-of-gamut values;
extended sRGB, HDR and full wide-gamut color transport are not represented.

A colour crosses as its own kind of value, four channels of a byte. It is
the value a tree carries most of and the cheapest to say exactly, and no host
parses a colour or has to know what one may look like. On a state the host
carries, a colour lies as four lanes from 0 to 1, which is what a colour
half way between two others is made of.

## Hex is read in the core

A colour is written as hex, `Color("#512BD4")`, as channels, or by name. The
parser is the core's and reads hex alone: `#RGB`, `#ARGB`, `#RRGGBB` or
`#AARRGGBB`, with or without the `#`, the alpha first when it is written.
Three and four digits are the shorthand where each digit stands for both of
its pair. Leaving the reading to a host would put the definition of a colour
inside that host's parser, and every other host would have to reproduce it
exactly or differ in silence.

Text that is not hex stops the program with a message naming it. A colour is
written as a literal, so it fails the first time the code runs rather than
drawing something nobody chose, and a colour's name is `Color.red` and its
kin, which the compiler checks where a string could not. Channels given as
numbers outside 0 to 255 are held to the range. There is no way back to hex
text: a colour crosses as bytes wherever it crosses.

## Named colours

Names shared with SwiftUI's standard UI palette (`red`, `orange`, `yellow`,
`green`, `mint`, `teal`, `cyan`, `blue`, `indigo`, `purple`, `pink`, `brown`,
and `gray`) carry reference light/dark sRGB variants. The palette follows
[Apple's published system color specifications](https://developer.apple.com/design/human-interface-guidelines/color).
For example, cyan is `#00C0E8` in light appearances and `#3CD3FE` in dark ones,
instead of CSS's `#00FFFF`. These references do not implement Apple's
increased-contrast or vibrancy variants.

Black, white and clear stay constant. Additional CSS-only names such as
`cornflowerBlue`, `magenta`, `lime`, `lightGray`, and `darkGray` keep their
constant channels. A particular CSS or brand color can always use explicit
hex or RGB components.

## A pair for each color scheme

`Color(light:dark:)` is one value that goes wherever a colour goes. It
travels as both halves, `PropValue.themed`, until the differ builds the
element wearing it. The differ then picks the half `AppInfo.colorScheme`
says and records that read against the element.

```text
  Color(light: .white, dark: .black)          written in a body, a style,
       |                                      or a session from a handler
       |  .themed(light: .color(white), dark: .color(black))
       v
  the differ builds the element wearing it
       |  resolvingColorScheme() reads AppInfo.colorScheme,
       |  and the element reads the color scheme from then on
       v
  .color(white) in the patch                  a color scheme change builds exactly
                                              this element again
```

A color scheme change therefore builds exactly the elements wearing a pair and
nothing around them. A pair written outside every build - into a session
from a handler, or in a style sheet made once - is right in both themes,
because it is resolved where it is worn. `.themed` never reaches a host. A
brush holding a pair among its stops, and a drawing holding one among its
records, are resolved the same way.

## A pair on a carried state

A pair written into a state the host carries crosses as the half in force,
read without recording anything: laying a value is no reason to build
anything. The state keeps the pair, and the element handing that state on
reads the color scheme, so a color scheme change builds that element again and the host
animates the colour to the other half, as it would a pair written on a node.

## Pictures for each color scheme

A picture may be two pictures: black artwork that reads well on a white page
disappears on a dark one. `ImageSource(light:dark:)` names two files and
crosses as a themed pair of file names, picked by the differ as a colour
pair is, so one name reaches the host and the element showing it builds
again when the color scheme changes. A tint would not do: it paints a picture in
one colour, while a second file keeps artwork of any colours as it was drawn.

## A background is a colour or a brush

`Background` is one colour or one brush, and the two stay apart in the
patch: a colour crosses as a colour and a brush as its kind and parts,
so a host paints a plain colour as the plain colour it is.

## A picture's own pixels

Code that works on the picture itself - an average colour an icon's tint
follows - reads its pixels back with `PicturePixels(named:)`. The name is
the one `Image` takes, so the file crosses no boundary: the pixels are asked
for where the picture already stands, and the host that shows it is the one
that reads them. Each host binds `PicturePixels.read` to its platform's own
decoder as it starts; where no host is bound, or the name stands for a
picture the decoder does not read - an SVG where only bitmaps are - the
answer is nil. The pixels cross as premultiplied RGBA rows on every host,
so code reading them is written once.

// The gallery's styles: what every control of a type looks like.
//
// A style with no key applies to every control of its type, so most of the
// gallery's appearance is decided here rather than in the views, in the values
// of the SwiftOmniUI ramp.
//
// Every colour comes through `Palette`, one name per job. That is what makes the
// look changeable in one file, and what makes it coherent: nothing here picks a
// colour, it says what the thing is FOR and the palette answers.
//
// WHAT IS NOT HERE:
//
//   - No font family. The gallery ships no fonts, and naming a family that is
//     not installed is a way to get a different font on every platform.
//   - Nothing a Style cannot NAME: a shadow is a property of the view that
//     casts it, a page's appearance is its `PageSession`'s, and the bars of
//     NavigationStack and TabView are written on the arrangement itself -
//     see MainWindow.detail.

import SwiftOmniUI

/// The application's styles, as the sheet the differ resolves against.
enum AppStyles {
    /// Built once, as the application is made, and never sent: the differ
    /// merges each style into the controls it applies to, so what crosses is a
    /// control with its values already on it. The formFactor comes from the
    /// application's `@Environment` - one style reads it: the SearchField's
    /// touch floor, which every formFactor but the desktop keeps.
    static func sheet(on formFactor: FormFactor) -> StyleSheet {
        StyleSheet {
            // MARK: Text

            Style<Text>()
                .foregroundStyle(Palette.text)
                .background(.transparent)
                .font(.system(size: 15))                

            // A page's own name for itself. Tight tracking, because a large
            // size at the default spacing reads loose.
            Style<Text>("Headline")
                .foregroundStyle(Palette.text)
                .font(.system(size: 32))
                .bold()
                .tracking(-0.5)
                .horizontalAlignment(.center)
                .multilineTextAlignment(.center)

            // A PAIR, and the second is written from the first: everything
            // about the shape of a quotation is stated once here, and
            // "QuoteLoud" adds the one property that makes it loud. The Styles
            // sample draws both, side by side.
            Style<Text>("Quote")
                .foregroundStyle(Palette.subtle)
                .font(.system(size: 17))
                .italic()
                .tracking(0.3)
                .multilineTextAlignment(.center)

            Style<Text>("QuoteLoud")
                .basedOn("Quote")
                .foregroundStyle(Palette.accent)

            // MARK: Buttons

            Style<Button>()
                .foregroundStyle(Palette.onAccent)
                .background(Palette.accent)
                .font(.system(size: 14))
                .bold()
                .strokeWidth(0)
                .shape(.roundedRectangle(10))                
                .padding(EdgeInsets(16, 11))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                    .background(Palette.outline)
                }

            // A button that lives in the WINDOW's chrome rather than on a
            // page. The implicit style above is an accent pill 44 points tall
            // - right in the content, and a foreign object in a strip half
            // that height: a filled pill up there reads as something stuck on,
            // whatever colour it is painted.
            //
            // So a chrome button is WORDS AND AN ICON and nothing else - no
            // fill, no outline - answering the pointer by brightening rather
            // than by growing a frame. The icon is the one its menu row
            // already carries, in the colour of the words beside it: see
            // nav_surprise_chrome.svg. The MARK is left white, the colour of
            // the application's name it stands beside - the mark and the name
            // are one thing said twice, and the accent belongs to the one
            // thing up here that can be pressed.
            //
            // The colour is the WINDOW's own yellow - read off the minimise
            // button of a running window - so what can be pressed in the
            // chrome matches the other things in the chrome that can be
            // pressed. Fixed rather than `Palette.accent` - the exception
            // Gallery/GalleryPage.swift makes for the toolbar icon: the title
            // bar does not follow the color scheme, so a themed colour would be right
            // in one color scheme and wrong in the other. It measures 5.0:1 on the
            // bar's violet, where `swiftOrangeLight` is 3.4:1 and fails AA for
            // text.
            //
            // A keyed style REPLACES the implicit one, so this states
            // everything it needs, the 44-point touch floor deliberately
            // dropped: a title bar is a desktop, and a mouse is not a thumb.
            Style<Button>("ChromeChip")
                .foregroundStyle(AppColors.windowYellow)
                .background(.transparent)
                .font(.system(size: 13))
                .bold()
                .strokeWidth(0)
                .padding(EdgeInsets(5, 0))
                .frame(height: 26)
                .visualState(.normal) { $0
                    .opacity(1)
                }
                .visualState(.pointerOver) { $0
                    .opacity(0.85)
                }

            // A button that lives in a LIST ROW, where the touch floor is
            // not merely unnecessary but harmful. A recycled cell measures a
            // minimum size INCONSISTENTLY: with one in the row, the cell
            // takes that height on some measure passes and the content's own
            // on others, so the rows draw at two heights and gaps open
            // between them - the platform's cell measurement rather than
            // anything this library does. Dropping the floor draws every row
            // the same height, and a button in a list row is a target beside
            // its text rather than a thumb target of its own.
            //
            // A keyed style REPLACES the implicit one, so this states
            // everything it needs - the ChromeChip rule again.
            Style<Button>("RowChip")
                .foregroundStyle(Palette.onAccent)
                .background(Palette.accent)
                .font(.system(size: 13))
                .bold()
                .strokeWidth(0)
                .shape(.roundedRectangle(10))
                .padding(EdgeInsets(14, 4))
                .frame(minHeight: 0)
                .frame(minWidth: 0)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                    .background(Palette.outline)
                }

            Style<Button>("IconButton")
                .opacity(1)
                .stroke(.transparent)
                .strokeWidth(0)
                .shape(.roundedRectangle(10))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .opacity(0.4)
                }

            // MARK: Fields

            Style<TextField>()
                .foregroundStyle(Palette.text)
                .background(.transparent)
                .placeholderColor(Palette.subtle)
                .font(.system(size: 15))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                }

            Style<TextEditor>()
                .foregroundStyle(Palette.text)
                .background(.transparent)
                .placeholderColor(Palette.subtle)
                .font(.system(size: 15))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                }

            Style<Picker>()
                .foregroundStyle(Palette.text)
                .background(.transparent)
                .font(.system(size: 15))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                }

            Style<DatePicker>()
                .foregroundStyle(Palette.text)
                .background(.transparent)
                .font(.system(size: 15))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                }

            Style<TimePicker>()
                .foregroundStyle(Palette.text)
                .background(.transparent)
                .font(.system(size: 15))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                }

            // NO background: a search field keeps the platform's own
            // look on a coloured surface, and that look is the host's. The
            // 44-point floor is a TOUCH screen's: on a desktop it shows as a
            // dead band under the field - a mouse is not a thumb, the
            // ChromeChip rule.
            Style<SearchField>()
                .foregroundStyle(Palette.text)
                .placeholderColor(Palette.subtle)
                .tint(Palette.accent)
                .font(.system(size: 15))
                .frame(minHeight: formFactor == .desktop ? 0 : 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                    .placeholderColor(Palette.disabled)
                }

            // MARK: Choices
            //
            // All four take the accent when they are ON, which is the whole
            // point of having one: whatever is chosen, anywhere, is orange.

            Style<Switch>()
                .tint(Palette.accent)
                .visualState(.disabled) { $0
                    .tint(Palette.disabled)
                }

            Style<CheckBox>()
                .tint(Palette.accent)
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .tint(Palette.disabled)
                }

            Style<RadioButton>()
                .background(.transparent)
                .foregroundStyle(Palette.text)
                .font(.system(size: 15))
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .visualState(.disabled) { $0
                    .foregroundStyle(Palette.disabled)
                }

            Style<Slider>()
                .tint(Palette.accent)
                .visualState(.disabled) { $0
                    .tint(Palette.disabled)
                }

            // MARK: Progress and indicators

            Style<ActivityIndicator>()
                .tint(Palette.accent)

            Style<ProgressBar>()
                .tint(Palette.accent)
                .visualState(.disabled) { $0
                    .tint(Palette.disabled)
                }

            Style<PositionIndicator>()
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)

            // MARK: The menu's rows
            //
            // A menu row is a view like any other, so it takes a style like any
            // other. What it does NOT take is a visual state saying which row
            // you are on: the application holds the section, so the row that is
            // chosen writes the two values it wants ON TOP of this style - see
            // Gallery/Views/MenuRow.swift, and the rule that a control's own
            // value wins over its style, per property.

            Style<HStack>("MenuRow")
                .spacing(14)
                .padding(EdgeInsets(18, 13))
                .background(.transparent)

            Style<Text>("MenuRowText")
                .font(.system(size: 16))
                .verticalAlignment(.center)
                .foregroundStyle(Palette.subtle)

            // MARK: Shapes

            // A card is a FILL on a tinted page, with a hairline to hold its
            // edge - which is what makes it read as raised without a shadow, on
            // both themes and on every platform. A shadow would need a colour
            // that works on both, and there is no such colour.
            //
            // A colour here is one property with the view's own background,
            // so a panel that sets its own - a colour, or a gradient like the
            // home page's - replaces this one, the animated panel included.
            // What a card holds is cut to its corners: a picture reaches them.
            Style<ZStack>("Card")
                .background(Palette.raised)
                .stroke(Palette.outline)
                .shape(.roundedRectangle(14))
                .strokeWidth(1)
                .clipsContent(true)

            // COLOUR, not background: a ColorPicker draws its colour, and a
            // background is a second square behind that one - which Android
            // does not turn with the view, so a rotated box would show it
            // standing still underneath. The gallery's clock hands are the
            // ones that showed it.
            Style<ColorPicker>()
                .color(Palette.accent)
        }
    }
}

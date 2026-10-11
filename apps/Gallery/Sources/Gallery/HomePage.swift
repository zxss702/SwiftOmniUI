// Where the gallery opens.

import SwiftOmniUI

/// What this is, and every group there is.
///
/// The one page that names the whole catalog, so a user who has never seen the
/// library can find the control they came for without opening the sidebar. The
/// groups are a GALLERY: one card each, swiped through, and the card in the
/// middle says underneath what is in it and opens when it is tapped.
///
/// **THE PAGE IS ARRANGED FROM ITS OWN MEASUREMENT**, which is the interesting
/// thing about it and the reason it is written the way it is. The run of cards
/// is given what the rows can spare, and what they can spare is not known until
/// the page has been laid out - so the page is a `GeometryReader`, and the same
/// `fitted` function answers both questions the room poses: which rows there
/// are, and how tall the run stands. WHICH ROWS THERE ARE is described, so it
/// renders - but only when a user turns the device or drags the window past a
/// threshold, which is a handful of times in a session rather than a handful of
/// times a second.
struct HomePage: View {
    /// The gallery this page is in - the scene its inspector button opens.
    @Environment var scene: SceneSession

    /// The page itself - what it is called, and its buttons.
    @Environment private var page: PageSession

    let catalog: Catalog

    /// Where the gallery is - a card switches the section.
    let nav: Navigation

    /// Which group's card is in the middle. The gallery writes it as the user
    /// swipes, so the words under the cards follow the hand.
    @State private var chosen = 0

    /// The device's facts, resolved from the standard environment - the
    /// formFactor for the count, and the footer's word.
    @Environment var device: DeviceInfo

    /// The screen, which decides whether a phone is on its side.
    @Environment var display: DeviceDisplay

    /// How far the page has come in.
    ///
    /// THE ROOM IS NOT KNOWN UNTIL IT IS MEASURED, and this page is arranged
    /// FROM that measurement: the cards' box is what the star row can spare,
    /// which the star row cannot say until it has been laid out. So the first
    /// arrangement is a guess, the second is the answer, and the step between
    /// them is a jump - not in the cards alone, but in everything standing
    /// under them. Rather than hide the step, the page fades in once it is
    /// over.
    @State private var shown = 0.0

    var body: some View {
        let groups = catalog.groups

        // THE PAGE'S OWN ROOM, read by the layout itself: a `GeometryReader`
        // hands the closure its measured size, which is the one value the
        // arrangement below is worked out from. Which rows stand and how tall
        // the run is are the same function's two answers - `fitted` below - so
        // a render knows both in one pass.
        return GeometryReader { room in
            let fitted = Self.fitted(
                in: Rect(0, 0, room.size.width, room.size.height), at: affords)

            // A GRID OF THREE ROWS: the heading takes what it needs, the run of
            // cards takes what is LEFT, and the two lines about what this is
            // sit at the foot.
            //
            // ONE GRID RATHER THAN A BRANCH PER SHAPE. An `if` in a builder is a
            // branch KEY, so a page that crossed the threshold would destroy the
            // run of cards and build it again; a row whose view is not visible
            // collapses to nothing, and the pair - centred in the star row - then
            // stands in the middle of the page by itself.
            Grid(horizontalSpacing: nil, verticalSpacing: Self.gap) {
            VStack {

                // The mark, the name and what it is, on the identity gradient -
                // the one place in the app that says all three at once.
                //
                // The panel paints its own background and its own edge: the
                // Card style fills a card and draws a hairline, and both would
                // show through the gradient.
                ZStack {
                    VStack {
                        Image("swiftomniui_mark.png")
                            .frame(width: 84)
                            .frame(height: 84)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("SwiftOmniUI Gallery")
                            .font(.system(size: 34))
                            .bold()
                            .tracking(-0.5)
                            .foregroundStyle(Palette.onBrand)

                        Text("Native interfaces, written in Swift")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.onBrand)
                            .opacity(0.85)
                    }
                    .spacing(10)
                    .padding(22)
                }
                .style("Card")
                .background(Palette.identity)
                .stroke(.transparent)
                .shape(.roundedRectangle(18))

                SectionTitle("\(catalog.sampleCount(on: device.formFactor)) SAMPLES "
                    + "IN \(groups.count) GROUPS")
            }
            .spacing(14)
            // A PHONE ON ITS SIDE has no height for a heading: the cards are
            // what the page is for, so they are what it keeps.
            .hidden(!fitted.chrome.heads)

            VStack {
                // ONE CARD PER GROUP, turned by a finger, a trackpad or a
                // wheel. A tapped card pushes its group - the tap is the face's
                // own, the run's job being to carry the cards.
                GalleryView(groups, id: \.route) { group in
                    GroupFace(title: group.title, summary: group.summary, picture: group.card)
                        .onTapGesture { nav.push(.group(group.route)) }
                }
                .position($chosen)
                // WHAT THE ROWS CAN SPARE, answered by the same `fitted` the
                // rows are.
                .frame(height: fitted.run)

                // AND THE SAME RUN, A CARD AT A TIME, directly under the cards
                // it steps. ON A DESKTOP ONLY: a finger has the run itself and
                // needs no buttons, where a mouse without a wheel - or a hand
                // on a keyboard - has no way to turn it at all.
                if device.formFactor == .desktop {
                    Steps(position: $chosen, count: groups.count)
                }

                // WHAT THE CARD IN THE MIDDLE IS, in the words its own face
                // has no room for. The NAME is not among them: the card
                // carries it, and saying it again a card's width below reads
                // as two things rather than one.
                //
                // THE BLOCK IS ONE HEIGHT WHATEVER IT SAYS, and the words
                // inside it are not cut to make that true. The summaries are
                // sentences of different lengths, so left to itself this
                // block is one line taller under one card than the next - and
                // its height is what the star row above it has LEFT to give
                // the run. A user swiping would then resize the gallery
                // from card to card, which lays the whole page out afresh and
                // moves everything under it.
                //
                // So the block is given the room the longest of them needs
                // and the words stand at the TOP of it: every summary wraps
                // to as many lines as it wants, the count sits under it, and
                // what changes between cards is how much of the block is
                // empty underneath rather than how tall it is.
                Caption(catalog: catalog, position: $chosen, formFactor: device.formFactor)
                    .frame(height: Self.caption)
            }
            .spacing(Self.gap)
            .frame(maxHeight: .infinity)

            // WHAT THIS IS, at the FOOT of the page and centred: the cards are
            // what a user came for, and these two lines are what they read
            // once they have found it. They go completely when the cards' cell
            // runs short - an auto row keeps its height whatever is left, and
            // words that no longer fit would be drawn OVER what is above them.
            VStack {
                Text("Every example here is described in Swift and rendered as real "
                    + "native controls.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)

                // The platform is the host's answer; the formFactor - phone,
                // tablet, desktop - is what lets the catalog list desktop
                // chrome only where it draws.
                Text("native: \(device.platform) · \(device.formFactor)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)
            }
            .spacing(4)
            .hidden(!fitted.chrome.foots)
        }
        // The margin is the rows' own to lose: the frame below is this grid's
        // outer one, so the arithmetic takes the margin off explicitly.
        .padding(Self.margin)
        }
        .opacity(shown)
        .animation(.easeOut(duration: Self.entrance), value: shown)
        .onAppear {
            shown = 1
            page.gallery("Home", scene: scene, nav: nil)
        }
    }

    /// How much of the page stands beside the run of cards.
    private enum Chrome {
        /// The heading, the cards, and the two lines at the foot.
        case full

        /// The heading and the cards - the room has nothing to spare below.
        case heading

        /// The cards alone, which is what a phone on its side is.
        case cards

        /// Whether the block that says what this is stands.
        var heads: Bool { self != .cards }

        /// Whether the two lines at the foot stand.
        var foots: Bool { self == .full }
    }

    /// The most chrome this DEVICE carries, before any room is measured.
    ///
    /// A phone on its side has no height for a heading. And the two lines at the
    /// foot are not a phone's at any size: its room is under the threshold
    /// however it is held, so asking would show them on the first render and
    /// take them away on the first measurement - which is a flash, and a resize
    /// of everything above them for nothing. Where there is never room, the
    /// answer is not to ask.
    private var affords: Chrome {
        guard device.formFactor == .phone else { return .full }

        return display.orientation == .landscape ? .cards : .heading
    }

    /// What the room holds, and how tall the run of cards stands in it.
    ///
    /// ONE FUNCTION BECAUSE TWO READERS ASK IT: the engine takes the height and
    /// the frame watcher takes the chrome. Answered apart they could disagree -
    /// a run sized for a heading no longer described overflows the row it
    /// stands in, and the words under it are what goes off the bottom.
    ///
    /// - Parameters:
    ///   - room: the page's own frame, as the platform laid it out.
    ///   - most: the most chrome this device carries.
    /// - Returns: the chrome that fits, and how tall the run stands.
    private static func fitted(in room: Rect, at most: Chrome) -> (chrome: Chrome, run: Double) {
        // What the rows have to share, once the page's own margin is out.
        let usable = room.height - 2 * margin

        // WHAT IS LEFT FOR THE CARDS once the heading, the gap and the words
        // have theirs - the one number every choice below is made from, and
        // arithmetic over stated heights rather than a second measurement.
        let spare = usable - heading - gap - words

        // THE HEADING STANDS WHILE WHAT IT LEAVES IS STILL A RUN WORTH DRAWING.
        // It is the page saying what it is, which is why it goes last rather
        // than first: a phone's room holds it and a run at about half its
        // ceiling, and that is a better page than cards alone. Only where the
        // run would be smaller than it is worth drawing at do the cards take
        // the whole room.
        let heads = most.heads && spare >= least

        // AND THE TWO LINES AT THE FOOT go after both, being what a user
        // reads once they have found the cards. They cost the run their own
        // height, so they stand only where it can spare it AND still reach its
        // ceiling - a page that had to shrink the cards has nothing to add at
        // the bottom.
        let foots = most.foots && heads && spare - gap - footer >= gallery

        return (foots ? .full : (heads ? .heading : .cards),
                // The run takes what is left, up to its own ceiling.
                max(min(heads ? spare : usable - words, gallery), least))
    }

    /// How long the page takes to come in, in seconds.
    private static var entrance: Double { 0.7 }

    /// The page's own margin, which the rows do not get to share.
    private static var margin: Double { 24 }

    /// How tall the block that says what this is stands - the mark, the name,
    /// the sentence under it and the count.
    ///
    /// STATED RATHER THAN MEASURED, for the reason `caption` is: the room
    /// left for the cards is what this block does not take, so measuring it
    /// would size the run from something the run's own layout can move.
    /// Rounded UP, so a font a platform draws a little larger costs the page
    /// nothing but a few points of slack.
    private static var heading: Double { 250 }

    /// A run of cards at its largest - the gallery's own ceiling.
    private static var gallery: Double { 400 }

    /// The two lines at the foot, their gap included - both what they take out
    /// of the page and what they give it back by going.
    private static var footer: Double { 54 }

    /// How tall the words under the run are - room for a summary of up to
    /// three lines and the count, at the sizes above.
    ///
    /// STATED RATHER THAN MEASURED, which is the whole point: a summary is a
    /// sentence, sentences differ in length, and a block left to its own
    /// height is a different height under every card. The run's room is what
    /// this block leaves, so that would resize the gallery on every swipe.
    /// Room for the longest rather than a cut to fit the shortest - nothing
    /// here is truncated, and a card whose summary is one line simply leaves
    /// the bottom of the block empty.
    private static var caption: Double { 88 }

    /// The gap between the run and the words under it.
    private static var gap: Double { 12 }

    /// What the words under the cards take out of the pair's room, the gap
    /// joining them included.
    private static var words: Double { caption + gap }

    /// The smallest a run of cards is worth drawing at.
    private static var least: Double { 150 }
}

/// WHAT THE CARD IN THE MIDDLE IS, in the words its own face has no room for.
///
/// A VIEW OF ITS OWN, AND IT IS THE READER OF THE POSITION - which is the whole
/// of why it is one: the page around it holds the heading, the run and the
/// footer, and a caption read in the PAGE's own closure would rebuild all of
/// them every card crossed. Here the read is this view's, so a card crossed
/// describes these two labels and leaves the page standing.
///
/// It is handed the catalog rather than the group: a class, compared by
/// identity, where a group holds its samples and could never compare cheaply.
private struct Caption: View {
    /// Every group there is - a class, so this view's inputs are three cheap
    /// ones.
    let catalog: Catalog

    /// Which card is in the middle. READ here, which is what makes this view
    /// the one built again when the user swipes.
    @Binding var position: Int

    /// What the device is, for the count - a phone is shown fewer samples.
    let formFactor: FormFactor

    var body: some View {
        let groups = catalog.groups
        let group = groups[min(max(position, 0), max(groups.count - 1, 0))]

        // THE NAME IS NOT AMONG THEM: the card carries it, and saying it again
        // a card's width below reads as two things rather than one.
        return VStack {
            Text("\(group.shown(on: formFactor).count) samples · tap the card to open")
                .font(.system(size: 12))
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.center)

            Text(group.summary)
                .font(.system(size: 14))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .spacing(4)
    }
}

/// The same run, a card at a time, directly under the cards it steps.
///
/// ON A DESKTOP ONLY: a finger has the run itself and needs no buttons, where a
/// mouse without a wheel - or a hand on a keyboard - has no way to turn it at
/// all. A VIEW OF ITS OWN for the reason the caption is one: whether an arrow
/// can be pressed follows the position, so this reads it and the page does not.
private struct Steps: View {
    /// Which card is in the middle - read for the arrows, written by them.
    @Binding var position: Int

    /// How many there are, which is where the arrows stop.
    let count: Int

    var body: some View {
        HStack {
            step("‹", to: position - 1)
            step("›", to: position + 1)
        }
        .spacing(10)
    }

    /// One arrow: where it goes, and whether there is anything there.
    private func step(_ caption: String, to: Int) -> any View {
        Button(caption, action: { position = to })
            .font(.system(size: 18))
            .foregroundStyle(Palette.subtle)
            .background(.transparent)
            .stroke(Palette.outline)
            .shape(.roundedRectangle(8))
            .padding(EdgeInsets(18, 2))
            .disabled(to < 0 || to >= count)
            
    }
}

/// One card of the run: a picture with a caption over it.
///
/// A VIEW OF ITS OWN, BUILT WITH TWO STRINGS AND A PICTURE, all compared by
/// value, which is what lets the run be described again - for the page's
/// caption, for a shape, for a press - while every card is CARRIED: a
/// composed view built with the same inputs is not built again, and the run
/// costs what the caption costs.
private struct GroupFace: View {
    let title: String
    let summary: String
    let picture: ImageSource

    var body: some View {
        ZStack {
            Grid {
                Image(picture)
                    .scaledToFill()

                Grid {
                    Text(title)
                        .font(.system(size: 18))
                        .bold()
                        .foregroundStyle(Palette.onBrand)
                        .truncationMode(.tail)
                        .padding(EdgeInsets(12, 10))
                }
                .background(Color("#B3000000"))
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            // THE PICTURE IS CUT AT THE CARD'S EDGE: a picture told to FILL
            // the card is painted at its own size all over the layout, so the
            // grid holding it - a layout, with edges to cut at - clips it.
            .clipped()
        }
        .style("Card")
        // A CARD OF THE RUN IS A PICTURE WITH A CAPTION OVER IT, and the run
        // itself takes the touch - so nothing here is a control on any
        // platform. The card says which group it is, and what its summary
        // says, which is what a user who cannot see the picture goes by and
        // what a script asks for by name. Handle.swift has the rule.
        .accessibilityIdentifier(handle("group", title))
        .accessibilityLabel(title)
        .accessibilityHint(summary)
        .stroke(.transparent)
        .shape(.roundedRectangle(16))
    }
}

import SwiftOmniUI

/// A driven rotation, sprung to real time by a plain Swift loop.
struct AnalogClockSample: SampleContent, ExampleContent {
    @State private var ticking = false

    /// Whether the first reading of this visit has SET the clock. Travelling
    /// there from noon would wind the whole day forward in a blur.
    @State private var started = false

    /// Which visit to this page the running loop belongs to. Each visit begins
    /// a loop of its own, and this is what tells any earlier one - even one
    /// still asleep when the next began - that its page is gone.
    @State private var visit = 0

    /// The angle each hand is GOING to. Each hand's rotation is DRIVEN by
    /// this state, so the host turns the hand on its own frames and a tick
    /// costs no render at all.
    ///
    /// It only ever grows - a movement to 0 from 354 would turn the long way
    /// back - and each tick's target is this angle plus the FORWARD distance
    /// to where the time says the hand should point, so a wrap and a catch-up
    /// after the page returns are the same small spring.
    @State private var sAngle = 0.0
    @State private var mAngle = 0.0
    @State private var hAngle = 0.0

    /// Where each mark sits and how it is shaped: a bar on the quarters, a
    /// dot on the other hours, at radius 94 from the centre. Written out
    /// because they are layout, not drawing - each is a small box pushed off
    /// centre by margins, with no rotation anywhere.
    static let marks: [(x: Double, y: Double, wide: Double, tall: Double)] = [
        (0, -94, 4, 14), (47, -81.4, 5, 5), (81.4, -47, 5, 5),
        (94, 0, 14, 4), (81.4, 47, 5, 5), (47, 81.4, 5, 5),
        (0, 94, 4, 14), (-47, 81.4, 5, 5), (-81.4, 47, 5, 5),
        (-94, 0, 14, 4), (-81.4, -47, 5, 5), (-47, -81.4, 5, 5),
    ]

    static let id = "analogClock"
    static let title = "Analog clock"
    static let summary = "Real time on springing hands, from a plain Swift loop."

    static let code = """
        @State private var ticking = false
        @State private var sAngle = 0.0
        @State private var mAngle = 0.0
        @State private var hAngle = 0.0
        @State private var started = false
        @State private var visit = 0

        static let marks: [(x: Double, y: Double, wide: Double, tall: Double)] = [
            (0, -94, 4, 14), (47, -81.4, 5, 5), (81.4, -47, 5, 5),
            (94, 0, 14, 4), (81.4, 47, 5, 5), (47, 81.4, 5, 5),
            (0, 94, 4, 14), (-47, 81.4, 5, 5), (-81.4, 47, 5, 5),
            (-94, 0, 14, 4), (-81.4, -47, 5, 5), (-47, -81.4, 5, 5),
        ]

        Grid {
            // The hands are driven, and nothing here reads them: this stays
            // at one build while the clock runs.

            ZStack().style("Card")
                .background(Palette.raised)
                .stroke(Palette.outline)
                .shape(.roundedRectangle(110))
                .frame(width: 220)
                .frame(height: 220)

            // The marks are laid out, not rotated: a quarter gets a bar,
            // the other hours a dot, each pushed off centre by margins -
            // margin(2x, 2y, 0, 0) shifts a centred view by (x, y).
            ForEach(Array(Self.marks.enumerated()), id: \\.offset) { pair in
                let (x, y, wide, tall) = pair.element
                return ColorPicker(Palette.outline)
                    .frame(width: wide)
                    .frame(height: tall)
                    .padding(EdgeInsets(2 * x, 2 * y, 0, 0))
            }

            hand(hAngle, length: 56, width: 6, color: Palette.text)
            hand(mAngle, length: 84, width: 4, color: Palette.text)
            hand(sAngle, length: 96, width: 2, color: Palette.accent)

            ZStack().style("Card")
                .background(Palette.accent)
                .shape(.roundedRectangle(6))
                .frame(width: 12)
                .frame(height: 12)
        }
        .onAppear {
            // Each visit starts a loop of its own and retires the last. The
            // hands come back at the angles the state kept, and the first
            // reading below ASSIGNS the time rather than flying through
            // everything that passed while the page was away.
            visit += 1
            let mine = visit
            ticking = true
            started = false

            while ticking && visit == mine {
                let lap = ContinuousClock.now
                let time = try await ClockTime.now()

                // Where each hand should POINT, within one turn.
                let second = Double(time.second) * 6
                let minute = Double(time.minute) * 6 + Double(time.second) * 0.1
                let hours = Double(time.hour % 12) * 30
                let minutesPast = Double(time.minute) * 0.5
                let secondsPast = Double(time.second) / 120
                let hour = hours + minutesPast + secondsPast

                if started {
                    // Advance by the forward distance only, so a wrap never
                    // spins back and a return catches up in one spring. The
                    // STATE is where the last movement was going, which is
                    // where the hand belongs now, so the arithmetic starts
                    // from it - never from the journey's value, which is
                    // wherever the host happened to have got to when this
                    // reading came in.
                    // `async let` starts all three at once; short and springy,
                    // because the snap IS the tick.
                    let atSecond = sAngle
                    let atMinute = mAngle
                    let atHour = hAngle

                    let toSecond = atSecond + (second - atSecond).forwardTurn
                    let toMinute = atMinute + (minute - atMinute).forwardTurn
                    let toHour = atHour + (hour - atHour).forwardTurn

                    async let s: Bool = $sAngle.journey.move(to:
                        toSecond, .bouncy(duration: 0.26))
                    async let m: Bool = $mAngle.journey.move(to:
                        toMinute, .easeOut(duration: 0.3))
                    async let h: Bool = $hAngle.journey.move(to:
                        toHour, .easeOut(duration: 0.3))
                    _ = try await (s, m, h)
                } else {
                    // The first reading SETS the hands: writing `value` is a
                    // snap, so there is no movement here and nothing to await.
                    started = true
                    ($sAngle.journey.value, $mAngle.journey.value, $hAngle.journey.value) = (second, minute, hour)
                    (sAngle, mAngle, hAngle) = (second, minute, hour)
                }

                // Sleep to the NEXT whole second, not for a fixed while: the
                // reading said how far into this one it was, the lap clock
                // says what the movements used, and the difference is what
                // keeps every tick landing just past the boundary.
                let used = lap.duration(to: .now)
                let wait = .milliseconds(1000 - time.millisecond) - used

                if wait > .milliseconds(20) {
                    try await Task.sleep(for: wait)
                }
            }
        }
        .onDisappear {
            ticking = false
        }

        /// One hand, turning about its foot. Rotating about `anchor: .bottom`
        /// pins the hand's own bottom edge; the offset lifts that edge onto
        /// the face's centre, so the hand sweeps the dial from its middle.
        private func hand(
            _ angle: Double,
            length: Double, width: Double, color: Color
        ) -> some View {
            ColorPicker(color)
                .frame(width: width)
                .frame(height: length)
                .rotationEffect(.degrees(angle), anchor: .bottom)
                .offset(y: -length / 2)
        }

        /// The forward distance to an angle within one turn, 0 up to but not
        /// 360 - the minute hand at 354 asked to show 0 steps +6, never -354.
        extension Double {
            var forwardTurn: Double {
                let step = truncatingRemainder(dividingBy: 360)
                return step >= 0 ? step : step + 360
            }
        }
        """

    var body: some View {
        Grid {

            ZStack().style("Card")
                .background(Palette.raised)
                .stroke(Palette.outline, width: 2)
                .shape(.roundedRectangle(110))
                .frame(width: 220)
                .frame(height: 220)

            ForEach(Array(Self.marks.enumerated()), id: \.offset) { pair in
                let (x, y, wide, tall) = pair.element
                return ColorPicker(Palette.outline)
                    .frame(width: wide)
                    .frame(height: tall)
                    .padding(EdgeInsets(2 * x, 2 * y, 0, 0))
            }

            hand(hAngle, length: 56, width: 6, color: Palette.text)
            hand(mAngle, length: 84, width: 4, color: Palette.text)
            hand(sAngle, length: 96, width: 2, color: Palette.accent)

            ZStack().style("Card")
                .background(Palette.accent)
                .stroke(.transparent)
                .shape(.roundedRectangle(6))
                .frame(width: 12)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Each visit starts a loop of its own and retires the last. The
            // hands come back at the angles the state kept, and the first
            // reading below ASSIGNS the time rather than flying through
            // everything that passed while the page was away.
            visit += 1
            let mine = visit
            ticking = true
            started = false

            while ticking && visit == mine {
                let lap = ContinuousClock.now
                let time = try await ClockTime.now()

                // Where each hand should POINT, within one turn.
                let second = Double(time.second) * 6
                let minute = Double(time.minute) * 6 + Double(time.second) * 0.1
                let hours = Double(time.hour % 12) * 30
                let minutesPast = Double(time.minute) * 0.5
                let secondsPast = Double(time.second) / 120
                let hour = hours + minutesPast + secondsPast

                if started {
                    // Advance by the forward distance only, so a wrap never
                    // spins back and a return catches up in one spring. The
                    // STATE is where the last movement was going, which is
                    // where the hand belongs now, so the arithmetic starts
                    // from it - never from the journey's value, which is
                    // wherever the host had got to when this reading came in. `async let` starts
                    // all three at once; short and springy, because the snap
                    // IS the tick.
                    let atSecond = sAngle
                    let atMinute = mAngle
                    let atHour = hAngle

                    let toSecond = atSecond + (second - atSecond).forwardTurn
                    let toMinute = atMinute + (minute - atMinute).forwardTurn
                    let toHour = atHour + (hour - atHour).forwardTurn

                    async let s: Bool = $sAngle.journey.move(to:
                        toSecond, .bouncy(duration: 0.26))
                    async let m: Bool = $mAngle.journey.move(to:
                        toMinute, .easeOut(duration: 0.3))
                    async let h: Bool = $hAngle.journey.move(to:
                        toHour, .easeOut(duration: 0.3))
                    _ = try await (s, m, h)
                } else {
                    // The first reading SETS the hands: writing `value` is a
                    // snap, so there is no movement here and nothing to await.
                    started = true
                    ($sAngle.journey.value, $mAngle.journey.value, $hAngle.journey.value) = (second, minute, hour)
                    (sAngle, mAngle, hAngle) = (second, minute, hour)
                }

                let used = lap.duration(to: .now)
                let wait = .milliseconds(1000 - time.millisecond) - used

                if wait > .milliseconds(20) {
                    try await Task.sleep(for: wait)
                }
            }
        }
        .onDisappear {
            ticking = false
        }
    }

    var notes: (any View)? {
        VStack {
            Text("The time comes from the platform - `ClockTime.now()` - and the wait is "
                + "plain `Task.sleep`, which resumes on time on every platform. Every tick "
                + "sleeps to the NEXT whole second rather than for a fixed while - the "
                + "reading carries milliseconds, so the spring lands just past each "
                + "boundary instead of drifting across one.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Each hand turns about its own foot: `rotationEffect` about "
                + "`anchor: .bottom` pins the bottom edge, and the `offset` lifts "
                + "that edge onto the face's centre - so the hand sweeps the dial "
                + "from its middle.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A hand's angle is read from state, and a `journey` walks that "
                + "state somewhere - so a tick is that state being sent somewhere "
                + "and the hand springs there as the tree is redrawn. sAngle "
                + "answers where the hand is GOING, which is what the next tick's "
                + "arithmetic wants - it adds the FORWARD distance to the time, so "
                + "the angles only grow and the hands never spin back.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Leaving this page stops the loop, and coming back starts a "
                + "fresh one. The hands are drawn wherever the angles were left, "
                + "because the angles are state, and the first reading ASSIGNS "
                + "the time instead of flying to it - each journey's `value` is "
                + "written, and the state to match, so nothing travels - and "
                + "the clock is right at once, with no winding through what "
                + "passed.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// One hand, turning about its foot. Rotating about `anchor: .bottom`
    /// pins the hand's own bottom edge; the offset lifts that edge onto the
    /// face's centre, so the hand sweeps the dial from its middle.
    private func hand(
        _ angle: Double,
        length: Double, width: Double, color: Color
    ) -> some View {
        ColorPicker(color)
            .frame(width: width)
            .frame(height: length)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .offset(y: -length / 2)
    }
}

/// The forward distance to an angle within one turn, 0 up to but not 360.
///
/// What lets a hand's angle only ever grow: the minute hand at 354 asked to
/// show 0 steps +6, never -354. On the difference between two angles in
/// degrees.
extension Double {
    var forwardTurn: Double {
        let step = truncatingRemainder(dividingBy: 360)
        return step >= 0 ? step : step + 360
    }
}

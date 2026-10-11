import SwiftOmniUI

/// A time of day in a picker - bound, and one-way with the write back by hand.
struct TimePickerSample: SampleContent, ExampleContent {
    @State private var alarm = ClockTime(hour: 7, minute: 30)
    @State private var picks = 0

    static let id = "timePicker"
    static let title = "TimePicker"
    static let summary = "A time of day - three integers, the way a date is three integers."

    static let code = """
        @State private var alarm = ClockTime(hour: 7, minute: 30)
        @State private var picks = 0

        VStack {
            // `alarm` is printed below, so picking a time builds this closure;
            // the picker itself is handed the state.
            DebugInfoLabel()

            TimePicker($alarm)
                .format("t")

            Text("Alarm at \\(alarm.text)")

            HStack {
                Button("Morning", action: { alarm = ClockTime(hour: 7, minute: 30) })
                    

                Button("Lunch", action: { alarm = ClockTime(hour: 12, minute: 0) })
                    

                Button("Evening", action: { alarm = ClockTime(hour: 21, minute: 5) })
                    
            }

            // The same time, one-way: `.time` is what puts it in the field,
            // and the write back is by hand.
            TimePicker()
                .time(alarm)
                .format("t")
                .onTimeChanged { time in
                    alarm = time
                    picks += 1
                }

            Text(picks == 0
                ? "onTimeChanged has not fired"
                : "onTimeChanged: \\(alarm.text), \\(picks) so far")
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            TimePicker($alarm)
                .accessibilityIdentifier("timePicker.alarm")
                .accessibilityLabel("Alarm")
                .format("t")

            Text("Alarm at \(alarm.text)")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            HStack {
                Button("Morning", action: { alarm = ClockTime(hour: 7, minute: 30) })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Lunch", action: { alarm = ClockTime(hour: 12, minute: 0) })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Evening", action: { alarm = ClockTime(hour: 21, minute: 5) })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    
            }
            .spacing(10)
            .horizontalAlignment(.center)

            SectionTitle("One-way, written back by hand")

            TimePicker()
                .accessibilityIdentifier("timePicker.alarm.oneWay")
                .accessibilityLabel("Alarm, written back by hand")
                .time(alarm)
                .format("t")
                .onTimeChanged { time in
                    alarm = time
                    picks += 1
                }

            Text(picks == 0
                ? "onTimeChanged has not fired"
                : "onTimeChanged: \(alarm.text), \(picks) so far")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("A `ClockTime` rather than a Foundation value, for the reason a "
                + "`CalendarDate` is not a `Date`: formatting one needs ICU, and ICU is "
                + "the dependency this library cannot take. It is three numbers - hour, "
                + "minute, second - and whether the user sees 21:05 or 9:05 PM is the "
                + "host's to decide, from the user's locale and the `.format`.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`TimePicker()` says nothing about a time, so `.time` is what puts one "
                + "in the field - the form a `Style<TimePicker>` or a picker built "
                + "elsewhere has to use. Nothing comes back on its own either: the "
                + "`alarm = time` in `onTimeChanged` is exactly the write the binding "
                + "above makes for you, which is why both fields move together.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The count answers the USER: the three buttons write `alarm` from the "
                + "tree, both fields follow, and no event fires.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

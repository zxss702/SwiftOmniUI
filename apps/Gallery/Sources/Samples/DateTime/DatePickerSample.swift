import SwiftOmniUI

/// A day picked from a calendar: a binding, and the event that answers a pick.
struct DatePickerSample: SampleContent, ExampleContent {
    @State private var due = CalendarDate(year: 2026, month: 8, day: 2)
    @State private var chosen = ""
    @State private var picks = 0

    static let id = "datePicker"
    static let title = "DatePicker"
    static let summary = "A day chosen from a calendar - three integers, not a Foundation Date."

    static let code = """
        @State private var due = CalendarDate(year: 2026, month: 8, day: 2)
        @State private var chosen = ""
        @State private var picks = 0

        VStack {
            // `due` is printed below, so picking a day builds this closure; the
            // picker itself is handed the state.

            DatePicker($due, in: CalendarDate(year: 2020, month: 1, day: 1)...CalendarDate(year: 2030, month: 12, day: 31))
                .format("D")
                .onChange(of: due) {
                    chosen = due.text
                    picks += 1
                }

            Text("Due \\(due.text)")

            Text(picks == 0
                ? "onChange has not fired"
                : "onChange: \\(chosen), \\(picks) so far")

            // `onChange` hears every write - the button's counts too, since a
            // write is a write no matter which side made it.
            Button("Push it to New Year", action: { due = CalendarDate(year: 2027, month: 1, day: 1) })
                
        }
        """

    var body: some View {
        VStack {

            DatePicker($due, in: CalendarDate(year: 2020, month: 1, day: 1)...CalendarDate(year: 2030, month: 12, day: 31))
                .accessibilityIdentifier("datePicker.due")
                .accessibilityLabel("Due date")
                .format("D")
                .onChange(of: due) {
                    chosen = due.text
                    picks += 1
                }

            Text("Due \(due.text)")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            Text(picks == 0
                ? "onChange has not fired"
                : "onChange: \(chosen), \(picks) so far")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)

            Button("Push it to New Year", action: { due = CalendarDate(year: 2027, month: 1, day: 1) })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
                
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`DatePicker($due, in:)` is the binding and the bounds in one: the "
                + "chosen day goes into state, and `.onChange(of: due)` hears every "
                + "write - a pick and the button's alike, since a write is a write no "
                + "matter which side made it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A CalendarDate rather than a Date: formatting a Date needs a "
                + "DateFormatter, a DateFormatter needs ICU, and ICU is the one "
                + "dependency this library cannot take. It is three numbers both "
                + "ways - into the picker, and back out of it when a day is picked "
                + "on screen.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The text in the field is the host's to write, in the user's locale; "
                + "`.format(\"D\")` asks for the long form.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

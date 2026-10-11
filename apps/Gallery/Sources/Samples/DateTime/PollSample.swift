import SwiftOmniUI

/// A ticker that does not repeat, restarted by the work it started.
struct PollSample: SampleContent, ExampleContent {
    /// One tick, then stopped - and the tick starts the next round when its
    /// work is done. So the gap is measured from where the work ENDED, and two
    /// rounds can never overlap however long one takes.
    @State private var poll = Ticker(every: .seconds(2), isRepeating: false)

    @State private var status = "Not started"
    @State private var rounds = 0
    @State private var checking = false

    static let id = "poll"
    static let title = "Poll"
    static let summary = "A tick that does the work and starts the next round when it "
        + "is done - so two rounds never overlap."

    static let code = """
        @State private var poll = Ticker(every: .seconds(2), isRepeating: false)
        @State private var status = "Not started"
        @State private var rounds = 0
        @State private var checking = false

        VStack {
            // What the poll last answered is read here, so every answer
            // builds this closure once.

            Text(status)
            Text("\\(rounds) round(s)")

            if checking { ProgressView() }

            Button(poll.isRunning || checking ? "Stop" : "Start", action: {
                    if poll.isRunning || checking {
                        poll.stop()
                        checking = false
                        status = "Stopped"
                        return
                    }

                    status = "Waiting"
                    poll.start()
                })
                
        }
        .onAppear {
            // Set here rather than in the initializer: the closure reads this
            // view's @State, which does not exist yet while the property that
            // holds the ticker is being initialized.
            poll.onTick = {
                checking = true
                status = "Checking"

                // Work of unknown length, on a task of its own - what a real
                // check would be. The ticker is already stopped by now, which
                // is what makes starting it again below the next round rather
                // than a second one alongside this.
                let answer = await Task.detached {
                    try? await Task.sleep(for: .milliseconds(1200))
                    return "All good"
                }.value

                rounds += 1
                checking = false
                status = "\\(answer) - next check in 2s"

                poll.start()
            }
        }
        .onDisappear { poll.stop() }
        """

    var body: some View {
        VStack {

            Text(status)
                .font(.system(size: 20))
                .bold()
                .multilineTextAlignment(.center)

            Text("\(rounds) round(s)")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            Group { if checking { ProgressView() } }
                .tint(Palette.accent)
                .frame(height: 28)

            Button(poll.isRunning || checking ? "Stop" : "Start", action: {
                    if poll.isRunning || checking {
                        poll.stop()
                        checking = false
                        status = "Stopped"
                        return
                    }

                    status = "Waiting"
                    poll.start()
                })
                .font(.system(size: 13))
                .padding(EdgeInsets(20, 6))
                
        }
        .spacing(12)
        .onAppear {
            // Set here rather than in the initializer: the closure reads this
            // view's @State, which does not exist yet while the property that
            // holds the ticker is being initialized.
            poll.onTick = {
                checking = true
                status = "Checking"

                // Work of unknown length, on a task of its own - what a real
                // check would be. The ticker is already stopped by now, which
                // is what makes starting it again below the next round rather
                // than a second one alongside this.
                let answer = await Task.detached {
                    try? await Task.sleep(for: .milliseconds(1200))
                    return "All good"
                }.value

                rounds += 1
                checking = false
                status = "\(answer) - next check in 2s"

                poll.start()
            }
        }
        .onDisappear { poll.stop() }
    }

    var notes: (any View)? {
        VStack {
            Text("A repeating timer would fire again while the work of the last round "
                + "was still going, and two checks would overlap. This one does not "
                + "repeat: it ticks once, the tick does the work, and the tick starts "
                + "the next round when that work is done - so the gap is measured from "
                + "the END of the work rather than from the start.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The last tick of a run stops the ticker BEFORE running its closure, "
                + "which is what makes that possible: start() on a ticker that is still "
                + "running does nothing, so the round would be lost in silence. Reading "
                + "isRunning therefore says whether another tick is coming, not whether "
                + "the work has finished - which is why the button above asks about both.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The work runs on a task of its own and the restart comes back from "
                + "there, off the thread the host draws on. `Ticker` keeps its state "
                + "behind a lock for exactly this: `start`, `stop` and `reset` are safe "
                + "from any thread.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

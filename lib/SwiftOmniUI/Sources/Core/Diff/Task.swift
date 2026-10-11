// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.task`: an async job tied to the view's life - started on appear, cancelled
// on disappear.
// Design: docs/design/core/identity-and-diffing.md#created-and-destroying

extension View {
    /// Runs an async job while the view is on screen: started when the view is
    /// first described, cancelled when it leaves the tree:
    ///
    ///     List { … }
    ///         .task { await items.load() }
    ///
    /// Once per element, the outermost first, as `.onAppear` is - and where
    /// the element leaves and comes back, a new job for a new element. The job
    /// outliving its view is cancelled, so a load in flight is dropped rather
    /// than written into state nobody shows.
    ///
    /// - Parameters:
    ///   - priority: the job's scheduling weight, as `Task` takes it.
    ///   - work: what to run; cancelled as the view leaves.
    public func task(
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ work: sending @escaping @isolated(any) () async -> Void
    ) -> ModifiedContent {
        let box = TaskBox()
        return onAppear {
            box.task = Task(priority: priority) { await work() }
        }
        .onDisappear {
            box.task?.cancel()
        }
    }

    /// As `.task`, and again whenever `id` moves: a view showing `id`'s
    /// question asks it afresh as `id` becomes another's, the stale answer's
    /// job cancelled first.
    ///
    ///     Text(answer)
    ///         .task(id: question) {
    ///             answer = await ask(question)
    ///         }
    ///
    /// - Parameters:
    ///   - id: what the job's answer is for.
    ///   - priority: the job's scheduling weight, as `Task` takes it.
    ///   - work: what to run; cancelled as `id` moves or the view leaves.
    public func task<ID: Equatable>(
        id: ID,
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ work: sending @escaping @isolated(any) () async -> Void
    ) -> ModifiedContent {
        let box = TaskBox()
        return onAppear {
            box.task = Task(priority: priority) { await work() }
        }
        .onChange(of: id) {
            box.task?.cancel()
            box.task = Task(priority: priority) { await work() }
        }
        .onDisappear {
            box.task?.cancel()
        }
    }
}

extension View {
    /// Performs `action` for each value an `AsyncSequence` produces while the
    /// view is on screen:
    ///
    ///     Text(clock)
    ///         .onReceive(ticks) { clock = $0 }
    ///
    /// The subscription is the `.task` it rides: starts when the view appears,
    /// cancelled when it leaves - so a sequence outliving its view stops
    /// writing state nobody shows. The sequence's own errors end the job the
    /// way a `.task` error does.
    ///
    /// Combine-shaped `.onReceive` callers on Darwin can pass any `Publisher`
    /// through `publisher.values`; on Linux an `AsyncSequence` is the honest
    /// currency type since Combine is an Apple framework.
    ///
    /// - Parameters:
    ///   - sequence: what produces the values.
    ///   - action: what runs per produced value, in receive order.
    public func onReceive<S: AsyncSequence>(
        _ sequence: S,
        perform action: @escaping @Sendable (S.Element) -> Void
    ) -> ModifiedContent {
        // The sequence itself is no longer Sendable once produced (an
        // AsyncPublisher is not); the box carries it across the task's
        // boundary since only its elements matter there.
        let box = OnReceiveBox(sequence)
        return task {
            do {
                for try await element in box.sequence {
                    if Swift.Task.isCancelled { break }
                    action(element)
                }
            } catch {
                // A sequence that throws ends the job; Combine-shaped callers
                // require `Failure == Never` anyway.
            }
        }
    }
}

/// Carries a not-necessarily-Sendable sequence into the `.task` job;
/// only its elements move through the job's work.
private final class OnReceiveBox<S: AsyncSequence>: @unchecked Sendable {
    /// The sequence being listened to.
    let sequence: S
    init(_ sequence: S) { self.sequence = sequence }
}

/// The running job a `.task` started, so its disappear can cancel it.
private final class TaskBox: @unchecked Sendable {
    /// The job running for the view, or none yet or anymore.
    var task: Task<Void, Never>?
}

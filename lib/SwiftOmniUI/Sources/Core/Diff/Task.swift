// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.task`: declarations belong to the authored node; running jobs belong to
// the rendered element, so a body rebuild cannot lose their cancellation handle.
// Design: docs/design/core/identity-and-diffing.md#created-and-destroying

extension View {
    /// Starts an async job when the view enters the tree and cancels it when
    /// the view or this modifier leaves:
    ///
    ///     List { … }
    ///         .task { await items.load() }
    ///
    /// Rebuilding the same view does not restart the job, even after it has
    /// completed. Cancellation is cooperative: the work must honor cancellation
    /// before publishing a result that is no longer wanted. The closure keeps
    /// the caller's actor isolation; the render does not await its completion.
    ///
    /// - Parameters:
    ///   - priority: the job's scheduling weight, as `Task` takes it.
    ///   - work: what to run; cancelled as the view leaves.
    public func task(
        priority: TaskPriority = .userInitiated,
        @_inheritActorContext _ work: sending @escaping @isolated(any) () async -> Void
    ) -> ModifiedContent {
        let declaration = TaskDeclaration(UnkeyedTask.value, priority: priority, work: work)
        return revised { $0.tasks.append(declaration) }
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
        let declaration = TaskDeclaration(id, priority: priority, work: work)
        return revised { $0.tasks.append(declaration) }
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
    /// writing state nobody shows. The sequence's own errors end the job.
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

/// A distinct key type keeps `.task` separate from `.task(id:)` at the same slot.
private enum UnkeyedTask: Equatable { case value }

/// One modifier's latest description. Its slot in the element pairs it with the
/// running job, independently of `.onChange` and `.onAppear` handlers.
struct TaskDeclaration {
    let value: Any
    let matches: (Any) -> Bool
    let priority: TaskPriority
    private let action: TaskAction

    init<ID: Equatable>(
        _ id: ID,
        priority: TaskPriority,
        work: sending @escaping @isolated(any) () async -> Void
    ) {
        value = id
        matches = { ($0 as? ID).map { $0 == id } ?? false }
        self.priority = priority
        action = TaskAction(work)
    }

    func start() -> Task<Void, Never> {
        let action = action
        return Task(priority: priority) {
            guard !Task.isCancelled else { return }
            await action.run()
        }
    }
}

/// The caller transfers the closure here once. Only the task invokes it, on
/// the executor carried by `@isolated(any)`; IDs and render state never cross.
private final class TaskAction: @unchecked Sendable {
    let run: @isolated(any) () async -> Void

    init(_ work: sending @escaping @isolated(any) () async -> Void) {
        run = work
    }
}

/// Held by `RenderedNode` across rebuilds, including after the job completes.
/// Only the render/lifecycle executor changes the handle, never the job itself.
final class MountedTask {
    let value: Any
    private var active = true
    private var task: Task<Void, Never>?

    init(_ declaration: TaskDeclaration) { value = declaration.value }

    func start(_ declaration: TaskDeclaration) {
        guard active, task == nil else { return }
        task = declaration.start()
    }

    /// Prevents a queued start from running after a later settling pass removed it.
    func retire() { active = false }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

extension Differ {
    /// Reuse an unchanged slot; restart a changed ID with this build's closure.
    func reconcileTasks(_ declarations: [TaskDeclaration], previous: [MountedTask]) -> [MountedTask] {
        var tasks: [MountedTask] = []
        for (index, declaration) in declarations.enumerated() {
            if index < previous.count, declaration.matches(previous[index].value) {
                tasks.append(previous[index])
            } else {
                if index < previous.count { stopTask(previous[index]) }
                let task = MountedTask(declaration)
                tasks.append(task)
                fire { task.start(declaration) }
            }
        }
        for task in previous.dropFirst(declarations.count) { stopTask(task) }
        return tasks
    }
}

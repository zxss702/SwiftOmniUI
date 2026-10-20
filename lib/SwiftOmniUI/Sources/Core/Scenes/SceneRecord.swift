// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One open scene: what it has open beside its main window, what the platform
/// kept for it, and the sessions it hands the views under it.
final class SceneRecord: @unchecked Sendable {
    /// Its number - "1" for the first scene - which is also its key in the tree.
    let id: String

    /// What it has open beside its main window, in the order they opened.
    @State var windows: [OpenedWindow] = []

    /// The legacy unnamed main window; named windows live in `windows`.
    @State var mainIsOpen = false
    var mainWindowType: WindowType?
    var declaresMainWindow = false

    /// Launch is requested once on connection, then only by explicit activation.
    var launchRequested = true
    var activationWindowKey: String?
    var pendingRestoredWindows: [(kind: String, value: String?)] = []

    /// Its session - what a view in the scene resolves as `SceneSession`.
    let session: SceneSession

    /// The groups its last build declared, by kind - written by that build.
    var declared: [WindowType: GroupShape] = [:]

    /// Whether the platform has handed it a window; the scene an application starts
    /// with waits for the first one.
    var handedOver: Bool

    /// The last number given to one of its windows.
    private var serial = 0

    /// Each window's session, kept while the window is open.
    private var windowSessions: [String: WindowSession] = [:]

    /// Held around the three tables below: a scene key's write lands from under its
    /// state's lock, from any thread.
    private let guarded = Lock()

    /// What the platform kept for the scene's keys, by name.
    private var restored: [String: PropValue] = [:]

    /// The storage standing for each key - one key, one piece of state.
    private var keyed: [String: AnyObject] = [:]

    /// The keys written since the host last took them, each with its last value.
    private var waiting: [String: PropValue] = [:]

    /// A scene, by its number, and whether the platform has handed it a window.
    init(id: String, handedOver: Bool) {
        self.id = id
        self.handedOver = handedOver
        session = SceneSession(id: id)
        session.record = self
    }

    // MARK: - Its windows

    /// Opens the window of a group that opens one.
    func open(_ type: WindowType) throws {
        try check(type, takes: nil)

        guard Scenes.opensWindows else { throw WindowError.unsupported }
        if type == mainWindowType { mainIsOpen = true; return }
        guard !windows.contains(where: { $0.type == type }) else { throw WindowError.alreadyOpen }

        windows.append(OpenedWindow(
            type: type, serial: nextSerial(), value: nil, text: nil,
            singleton: declared[type]?.isSingleton == true))
    }

    /// Opens the window for a value.
    func open<Value: Codable & Hashable>(_ type: WindowType, value: Value) throws {
        try check(type, takes: Value.self)

        guard Scenes.opensWindows else { throw WindowError.unsupported }

        let key = AnyHashable(value)

        guard !windows.contains(where: { $0.type == type && $0.value == key }) else {
            throw WindowError.alreadyOpen
        }

        windows.append(
            OpenedWindow(type: type, serial: nextSerial(), value: key, text: try ValueText.write(value),
                singleton: declared[type]?.isSingleton == true))
    }

    /// Opens the window `\.openWindow` asks for - the type-erased spelling of
    /// `open(_:value:)`, its value and the value's written text already made.
    func open(_ type: WindowType, valueType: Any.Type?, value: AnyHashable?, text: String?) throws {
        try check(type, takes: valueType)

        guard Scenes.opensWindows else { throw WindowError.unsupported }
        if type == mainWindowType, value == nil { mainIsOpen = true; return }
        guard !windows.contains(where: { $0.type == type && $0.value == value }) else {
            return
        }

        windows.append(OpenedWindow(
            type: type, serial: nextSerial(), value: value, text: text,
            singleton: declared[type]?.isSingleton == true))
    }

    /// Closes the window of a group that opens one.
    func close(_ type: WindowType) throws {
        try check(type, takes: nil)

        if type == mainWindowType {
            guard mainIsOpen else { throw WindowError.notOpen }
            mainIsOpen = false
            return
        }

        guard let index = windows.firstIndex(where: { $0.type == type }) else {
            throw WindowError.notOpen
        }

        windows.remove(at: index)
    }

    /// Closes the window for a value.
    func close<Value: Codable & Hashable>(_ type: WindowType, value: Value) throws {
        try check(type, takes: Value.self)

        let key = AnyHashable(value)

        guard let index = windows.firstIndex(where: { $0.type == type && $0.value == key }) else {
            throw WindowError.notOpen
        }

        windows.remove(at: index)
    }

    /// Closes one of its windows by its key - what that window's session asks for.
    func closeWindow(key: String) throws {
        if key == SceneElement.mainKey, mainWindowType != nil {
            guard mainIsOpen else { throw WindowError.notOpen }
            mainIsOpen = false
            return
        }
        guard windows.contains(where: { $0.key == key }) else { throw WindowError.notOpen }

        closed(key: key)
    }

    /// A named dismissal is independent of the caller's navigation presentation.
    /// Dismissing a window that is not open is a no-op, as in SwiftUI.
    func dismissWindows(type: WindowType?, valueType: Any.Type?, value: AnyHashable?) {
        let types = Set(declared.compactMap { kind, shape -> WindowType? in
            if let type, type != kind { return nil }
            if let valueType, !shape.takes(valueType) { return nil }
            return kind
        })
        if let mainWindowType, types.contains(mainWindowType), value == nil {
            mainIsOpen = false
        }
        windows.removeAll { types.contains($0.type) && (value == nil || $0.value == value) }
    }

    /// Makes one of its windows about another value - the window's own binding.
    func retarget<Value: Codable & Hashable>(_ serial: Int, to value: Value) {
        guard let index = windows.firstIndex(where: { $0.serial == serial }) else { return }

        windows[index].value = AnyHashable(value)
        windows[index].text = try? ValueText.write(value)
    }

    /// The user closed one of its windows; a report about one already gone changes
    /// nothing.
    func closed(key: String) {
        if key == SceneElement.mainKey, mainWindowType != nil { mainIsOpen = false }
        windows.removeAll { $0.key == key }
        if !mainIsOpen, windows.isEmpty { Scenes.shared.ended(self) }
    }

    /// The system restored one of its windows: back it goes where the scene still
    /// declares its kind and the text reads as its value, and nowhere else.
    /// Design: docs/design/core/scenes.md#what-the-platform-keeps
    func restored(kind name: String, text: String?) {
        let type = WindowType(name)

        guard let shape = declared[type], shape.restorationBehavior != .disabled else { return }
        if type == mainWindowType, text == nil { mainIsOpen = true; return }

        guard let text else {
            guard shape.valueType == nil, !windows.contains(where: { $0.type == type }) else { return }

            windows.append(OpenedWindow(
                type: type, serial: nextSerial(), value: nil, text: nil, singleton: shape.isSingleton))
            return
        }

        guard shape.valueType != nil, let value = shape.restore(text),
            !windows.contains(where: { $0.type == type && $0.value == value })
        else { return }

        windows.append(OpenedWindow(
            type: type, serial: nextSerial(), value: value, text: text,
            singleton: declared[type]?.isSingleton == true))
    }

    /// Resolves the default window after declarations and restored windows are known.
    /// Ordinary body updates only update the policy; they never request presentation.
    @MainActor func applyLaunchPolicy(_ windows: Windows) {
        let named = windows.groups.first {
            $0.valueType == nil && $0.launchBehavior == .presented
        } ?? windows.groups.first {
            $0.isLaunchCandidate && $0.launchBehavior == .automatic
        }
        let presentsMain = windows.main != nil && windows.launchBehavior == .presented
        let usesMain = presentsMain || (named?.launchBehavior != .presented
            && windows.main != nil && windows.launchBehavior != .suppressed)
        declaresMainWindow = usesMain || named != nil

        guard launchRequested else { return }
        launchRequested = false
        activationWindowKey = nil

        let needsWindow = !mainIsOpen && self.windows.isEmpty
        if usesMain {
            // Legacy unnamed main windows anchor their restored secondary windows.
            // Named SwiftUI-style Windows use independent groups and do not take this path.
            if needsWindow || windows.launchBehavior == .automatic { mainIsOpen = true }
            if mainIsOpen { activationWindowKey = SceneElement.mainKey }
        } else if let named {
            if needsWindow {
                // The initial window is allowed even on a host that cannot open
                // additional windows. Explicit openWindow still checks that capability.
                self.windows.append(OpenedWindow(
                    type: named.type, serial: nextSerial(), value: nil, text: nil,
                    singleton: declared[named.type]?.isSingleton == true))
            }
            activationWindowKey = self.windows.first(where: { $0.type == named.type && $0.value == nil })?.key
        }
        if activationWindowKey == nil {
            activationWindowKey = mainIsOpen ? SceneElement.mainKey : self.windows.first?.key
        }
    }

    /// The session of one of its windows, made once and kept.
    func windowSession(_ key: String) -> WindowSession {
        if let standing = windowSessions[key] {
            return standing
        }

        let made = WindowSession(key: key, record: self)
        windowSessions[key] = made
        return made
    }

    /// Lets go of the sessions of windows that have closed; its main window's
    /// is kept for as long as the scene is.
    func keepWindowSessions() {
        let open = Set(windows.map(\.key) + [SceneElement.mainKey])

        windowSessions = windowSessions.filter { open.contains($0.key) }
    }

    /// Checks a kind against what the scene declares.
    private func check(_ type: WindowType, takes valueType: Any.Type?) throws {
        guard let shape = declared[type] else { throw WindowError.undeclared(type) }
        guard shape.takes(valueType) else { throw WindowError.wrongValue(type) }
    }

    /// The next number for one of its windows.
    private func nextSerial() -> Int {
        serial += 1
        return serial
    }

    // MARK: - What it keeps

    /// Takes what the platform kept for the scene's keys - before its first
    /// build, which is where the states claiming them are built.
    func restore(_ values: [String: PropValue]) {
        guarded.withLock { restored = values }
    }

    /// The storage a key of this scene means: the one standing, or the offered one
    /// adopted, with what the platform kept landed in it.
    func claim(_ name: String, orAdopt storage: AnyObject, landing land: (PropValue) -> Void) -> AnyObject {
        let (owner, held): (AnyObject, PropValue?) = guarded.withLock {
            if let standing = keyed[name] { return (standing, nil) }

            keyed[name] = storage
            return (storage, restored[name])
        }

        if let held {
            land(held)
        }

        return owner
    }

    /// Marks a key as needing to be kept, replacing whatever value was
    /// waiting. Runs under the state's lock, so it records and nothing else.
    func record(_ name: String, _ value: PropValue) {
        guarded.withLock { waiting[name] = value }
    }

    /// How many keys are waiting to be kept.
    var pending: Int { guarded.withLock { waiting.count } }

    /// The keys waiting to be kept, sorted by name, taken.
    func takeWaiting() -> [(name: String, value: PropValue)] {
        guarded.withLock {
            let taken = waiting.sorted { $0.key < $1.key }
            waiting.removeAll(keepingCapacity: true)
            return taken.map { (name: $0.key, value: $0.value) }
        }
    }
}

/// What a scene's build declared about one of its window groups - what opening a
/// window is checked against, and what a restored window is read with.
struct GroupShape {
    /// The type of value the group opens one window per; nothing for a group of one.
    let valueType: Any.Type?

    /// A value read back out of the text it was written down as.
    let restore: (String) -> AnyHashable?
    var restorationBehavior: SceneRestorationBehavior = .automatic
    var isSingleton = false

    /// Whether this shape takes a value of `type` - nothing meaning none.
    func takes(_ type: Any.Type?) -> Bool {
        switch (valueType, type) {
        case (nil, nil): return true
        case let (declared?, given?): return ObjectIdentifier(declared) == ObjectIdentifier(given)
        default: return false
        }
    }
}

/// A window a scene has open beside its main one.
struct OpenedWindow: Equatable {
    /// Its group's kind.
    let type: WindowType

    /// Its number in its scene, in opening order - what keeps it the same window when
    /// its value changes.
    let serial: Int

    /// The value it stands for, where its group opens one per value.
    var value: AnyHashable?

    /// That value written down, the way the platform keeps it.
    var text: String?

    /// Named singleton windows retain an identity distinct from every other window.
    var singleton = false

    /// What the tree knows it by.
    var key: String { singleton ? "window \(type.name)" : "\(type.name) \(serial)" }
}

/// A state box a scene may keep - one declared with a `SceneKey`, which the
/// differ hands the scene it is built in.
protocol SceneClaiming: AnyObject {
    /// Pairs the box with the scene it is in: the storage the scene keeps
    /// under its key, and where its writes are kept.
    func claimScene(_ record: SceneRecord)
}

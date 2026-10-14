// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

/// One element of the mounted tree: the runtime's live instance of a described node.
/// Design: docs/design/host/tree.md#the-mounted-tree
@_spi(Host) @MainActor public final class MountedElement {
    /// The element's key.
    public let id: ElementId

    /// The element's node type.
    public let type: NodeType

    /// The element's instance number, which its animations are filed under.
    public let mount: UInt64

    /// The element that holds this one.
    public private(set) weak var parent: MountedElement?

    /// The elements this one holds, in order - a grid's and a ZStack's in the order they are drawn, by
    /// `zIndex`, ties in the order written.
    public private(set) var children: [MountedElement] = []

    /// Whether the last patch changed this element's children - the first counts.
    public private(set) var childrenChanged = false

    /// A content rebuild invalidates lazy measurements; viewport updates do not.
    public private(set) var lazyContentRevision = 0
    /// A lazy parent's data identity, kept separately from the view's explicit `.id()`.
    public private(set) var lazyIdentity: String?
    private var lazyIdentities: Set<String> = []

    /// The child the host keeps for this element as one its parent's view draws - a map's marker - the same object
    /// for as long as the element lives (`asChild`).
    var keptChild: HostChild?

    /// Each child's place in the order the last arrangement wrote them - known before the children are made.
    private(set) var writingOrder: [ElementId: Int] = [:]

    /// The properties the patches described.
    public private(set) var properties: [Prop: HostValue] = [:]

    /// The properties bound to states, by property.
    public private(set) var driven: [Prop: HostStateBinding] = [:]

    /// The handlers of the events the tree listens to, by event.
    public private(set) var events: [Event: Int32] = [:]

    /// How this element's children animate, as its patches said; nil while it says nothing.
    public private(set) var animation: HostLayoutMotion?

    /// Whether this element's frame, or any frame under it, is read.
    public private(set) var framesRead = false
    /// Last passive drawing size, independent of the full coordinate report.
    var reportedDrawingSize: Size?

    /// Whether this page tree is shown, as its phases last told.
    public internal(set) var isPagePresented = false

    /// Whether the element fades out on its way to being hidden, which it still stands shown for.
    public internal(set) var isLeaving = false

    /// Whether the element rides a removal transition - kept in its parent's
    /// children and shown while it goes.
    public internal(set) var isDeparting = false

    /// Which departure is in flight: a landing of an old one - reversed, or
    /// left behind by a newer - touches nothing.
    var departureSerial = 0

    /// The frame report this element last said, which a report the same says again to nobody.
    var reportedFrame: [Double] = []
    var reportedSafeAreaInsets: EdgeInsets?

    /// The named spaces the element last reported enclosing it.
    var reportedNamedFrames: [NamedSpaceFrame] = []

    /// The text layout this element last said, which a report the same says again to nobody.
    var reportedTextLayout: TextLayoutReport?

    /// Where the states a press dragged carries stood as it began.
    var dragStart = Point(x: 0, y: 0)

    /// The toolkit's half of the element.
    public private(set) var native: (any NativeElement)!

    private(set) weak var tree: MountedTree?
    private var wornStates: [Int32] = []
    private var drivenValues: [Prop: HostStateValue] = [:]
    private var created = false
    private var described = false

    init(_ patch: HostPatch, tree: MountedTree, parent: MountedElement?) {
        id = patch.id
        type = patch.type
        self.tree = tree
        self.parent = parent
        mount = tree.allocateMount()
        // The native half is made knowing what describes the element - a host picks its control by the
        // properties - so they stand while it is made; `apply` describes the element itself.
        properties = patch.properties
        native = nil
        native = tree.makeNative(self)
        tree.remember(self)
        tree.tally?.made += 1
        apply(patch)
    }

    /// Whether this element is a lazy run, building its rows as its window asks.
    var isLazyRun: Bool {
        type == .lazyVStack || type == .lazyHStack || type == .lazyVGrid || type == .lazyHGrid
    }

    /// Applies a patch of this element.
    public func apply(_ patch: HostPatch) {
        guard let tree else { return }
        // A patch re-described a departing element: its removal turns around.
        if isDeparting { revive() }

        let sceneBegan: ContinuousClock.Instant? = tree.tally != nil && patch.type == .scene ? .now : nil
        tree.tally?.nodes += 1
        defer {
            if let sceneBegan { tree.tally?.scenes[patch.id, default: .zero] += ContinuousClock.now - sceneBegan }
        }

        if patch.lazyContentChanged { lazyContentRevision += 1 }
        if let identity = patch.lazyIdentity { lazyIdentity = identity }
        let previouslyShown = isPagePresented ? shownChildren : []
        var changed = Set(patch.clearedProperties)
        changed.formUnion(patch.properties.keys)
        if case .replace(let replacement) = patch.driven {
            changed.formUnion(driven.keys)
            changed.formUnion(replacement.keys)
        }

        let standing = Dictionary(uniqueKeysWithValues: changed.compactMap { property in
            standingValue(property, target: patch.properties[property]).map { (property, $0) }
        })

        for property in patch.clearedProperties {
            properties[property] = nil
        }

        for (property, value) in patch.properties {
            properties[property] = value
        }

        // A value written on its own leaves the key it was found by behind: the lookup key shadowing it lifts,
        // its own standing alone.
        for (property, keyProp) in Self.keyProperties
        where patch.properties[property] != nil && patch.properties[keyProp] == nil {
            properties[keyProp] = nil
        }

        if case .replace(let events) = patch.events {
            self.events = events
        }

        if case .replace(let driven) = patch.driven {
            tree.replaceBindings(on: self, with: driven)
            self.driven = driven
            drivenValues = drivenValues.filter { driven[$0.key] != nil }
        }
        wear(driven)

        for (property, binding) in driven where binding.mode != .in {
            drivenValues[property] = tree.core.value(for: binding)
        }

        if let animation = patch.animation {
            self.animation = animation
            // The application says its animation once; every layout that says none animates under it.
            if type == .app { tree.layoutMotion.applicationMotion = animation.animation }
        }

        if case .unchanged = patch.children { childrenChanged = patch.lazyContentChanged } else { childrenChanged = true }

        let lazy = type == .lazyVStack || type == .lazyHStack || type == .lazyVGrid || type == .lazyHGrid
        // What a lazy run builds or lets go - its rows and the run itself - names no page's chrome.
        if !tree.chromeMayChange, !changed.isEmpty || { if case .arranged = patch.children { true } else { false } }(),
           sequence(first: self, next: \.parent).allSatisfy({ !$0.isLazyRun }) {
            tree.chromeMayChange = true
        }
        if lazy, changed.contains(.items) || !described {
            lazyIdentities = Set(value(.items)?.strings ?? [])
        }
        switch patch.children {
        case .unchanged:
            break

        case .arranged(let childPatches):
            writingOrder = Dictionary(childPatches.enumerated().map { ($1.id, $0) }) { first, _ in first }
            arrange(childPatches, tree: tree, virtualized: lazy ? lazyIdentities : nil)

        case .changed(let childPatches):
            // Each child patch finds its child by id: one table for a long list, not a search a patch.
            let places = childPatches.count > 4
                ? Dictionary(children.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }) : nil
            for childPatch in childPatches {
                // A new child arrives only in an arranged list; a sparse list naming a stranger drifted.
                guard let index = places?[childPatch.id] ?? children.firstIndex(where: { $0.id == childPatch.id }) else {
                    tree.intake.drifted(
                        "a patch names child '\(childPatch.id)' that '\(id)' does not have")
                    continue
                }
                let child = children[index]

                if child.type == childPatch.type, !childPatch.replace {
                    child.apply(childPatch)
                } else if childPatch.replace {
                    child.leave()
                    children[index] = MountedElement(childPatch, tree: tree, parent: self)
                } else {
                    tree.intake.drifted(
                        "a patch describes '\(childPatch.id)' as \(childPatch.type) where '\(id)' holds \(child.type)")
                }
            }
        }

        for property in changed.sorted() {
            let hasDrivenPresentation = driven[property].map { $0.mode != .in } ?? false
            tree.receiveProperty(
                mount: mount,
                property: property,
                standing: standing[property],
                target: resolvedValue(property),
                animation: hasDrivenPresentation || !native.animates(property)
                    ? nil
                    : patch.transitions[property]?.animation)
        }

        restack()
        if changed.contains(.layoutDirection) {
            directionTurned(arrangingItself: false)
        } else if !described {
            native.directionChanged()
        }
        framesRead = driven[.frame] != nil || events[.frameChanged] != nil
            || children.contains { $0.framesRead }
        native.applied(changed: changed, wasDescribed: described)
        described = true
        reconcilePresentation(from: previouslyShown)
    }

    /// Tells the element's handler of `event` as a phase, rendered in its turn before what comes after it.
    func tellPhase(_ event: Event) {
        guard let handler = handler(event) else { return }
        tree?.tellPhase(handler)
    }

    /// Reconciles a complete child arrangement by key.
    private func arrange(_ patches: [HostPatch], tree: MountedTree, virtualized: Set<String>?) {
        let before = children
        let previous = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })

        var arranged = patches.map { patch in
            if let child = previous[patch.id], child.type == patch.type, !patch.replace {
                child.parent = self
                // A lazy window's complete arrangement includes unchanged seats.
                // Their native properties, effects and descendants need no update.
                if virtualized == nil || !patch.isEmpty || child.isDeparting {
                    child.apply(patch)
                }
                return child
            }

            return MountedElement(patch, tree: tree, parent: self)
        }
        // A child the patch drops begins its removal transition here where it
        // has one, and keeps its seat - and its view - until the last component
        // lands.
        let staying = Set(arranged.map(ObjectIdentifier.init))
        for child in before where !staying.contains(ObjectIdentifier(child)) {
            let recycling: Bool
            if case .manual(let identity) = child.id, let virtualized {
                recycling = virtualized.contains(child.lazyIdentity ?? identity)
            } else {
                recycling = false
            }
            if !recycling, child.isDeparting || child.depart(room: child.native.departingRoom, closed: { [weak self] in
                self?.departed(child)
            }) { arranged.append(child) }
        }
        children = arranged
        leave(before)
    }

    /// Puts a grid's or a ZStack's children in the order they are drawn: by `zIndex`, ties in the order
    /// written. Answers whether the order moved.
    /// Design: docs/design/host/layout.md#drawing-order
    @discardableResult
    private func restack() -> Bool {
        guard Self.layered.contains(type), children.count > 1 else { return false }

        let drawnBefore = { (lhs: MountedElement, rhs: MountedElement) -> Bool in
            let (lower, upper) = (lhs.zIndex, rhs.zIndex)
            if lower != upper { return lower < upper }
            return (self.writingOrder[lhs.id] ?? .max) < (self.writingOrder[rhs.id] ?? .max)
        }
        guard zip(children, children.dropFirst()).contains(where: { drawnBefore($1, $0) }) else { return false }
        children.sort(by: drawnBefore)
        return true
    }

    /// The direction this element lays out in turned: it and every layout under it that inherits the direction
    /// arrange their children again, the element itself when its patch will not.
    /// Design: docs/design/host/layout.md#right-to-left
    func directionTurned(arrangingItself: Bool) {
        native.directionChanged()
        if arrangingItself, !children.isEmpty { native.arrangeChildren() }
        for child in children where child.inheritsDirection {
            child.directionTurned(arrangingItself: true)
        }
    }

    /// Whether this element says no direction of its own.
    private var inheritsDirection: Bool {
        LayoutDirection(rawValue: value(.layoutDirection)?.enumeration ?? 0).map { $0 == .inherited } ?? true
    }

    /// Where this element is drawn among its overlapping siblings, higher nearer the front.
    private var zIndex: Double { number(.zIndex) ?? 0 }

    /// The layouts whose children can overlap, drawn in `zIndex` order.
    private static let layered: Set<NodeType> = [.grid, .zStack]

    /// Detaches every one of `previous` that is no longer a child.
    private func leave(_ previous: [MountedElement]) {
        let staying = Set(children.map(ObjectIdentifier.init))
        for child in previous where !staying.contains(ObjectIdentifier(child)) {
            child.leave()
        }
    }

    /// A departure that landed: the child leaves, and its parent's layout drops
    /// its view.
    private func departed(_ child: MountedElement) {
        children.removeAll { $0 === child }
        native.arrangeChildren()
        // An element with no view passes its children up: the layout that held the view drops it.
        if !native.presentsView {
            var holder = parent
            while let each = holder, !each.native.presentsView { holder = each.parent }
            holder?.native.arrangeChildren()
        }
        tree?.arrangementChanged = true
    }

    /// Ties this element to the channels of the states its properties wear.
    private func wear(_ driven: [Prop: HostStateBinding]) {
        let worn = driven.values.filter { $0.kind == .property }.map(\.state).sorted()
        guard worn != wornStates, let tree else { return }

        for state in wornStates { tree.stateChannels.detach(state) }
        for state in worn { tree.stateChannels.attach(state) }
        wornStates = worn
    }

    /// Detaches this element and everything under it from the runtime as it leaves the tree.
    /// Design: docs/design/host/tree.md#leaving
    public func leave() {
        if let tree {
            for state in wornStates { tree.stateChannels.detach(state) }
            tree.forget(self)
            tree.removeMotions(mount: mount)
        }
        wornStates = []
        isLeaving = false
        native.leave()
        for child in children { child.leave() }
        isDeparting = false
    }

    /// The first element of `type` in this subtree, this one first.
    public func first(type sought: NodeType) -> MountedElement? {
        if type == sought { return self }

        for child in children {
            if let found = child.first(type: sought) { return found }
        }

        return nil
    }

    /// The nearest element of `type` holding this one, this one first.
    public func enclosing(type sought: NodeType) -> MountedElement? {
        var element: MountedElement? = self
        while let each = element, each.type != sought { element = each.parent }
        return element
    }

    /// The window elements in this subtree, in the tree's order; a window holds none.
    public var windows: [MountedElement] {
        type == .windowScene ? [self] : children.flatMap(\.windows)
    }

    /// Native ownership is an explicit floating-tool policy. A named window
    /// or a value-backed group still belongs to its scene for lifetime and
    /// restoration, but is otherwise an independent platform window.
    public var ownerWindow: MountedElement? {
        guard type == .windowScene, id != .manual("main"), value(.floatsOnTop)?.bool == true else { return nil }

        return enclosing(type: .scene)?.windows.first { $0.id == .manual("main") }
    }

    /// The first element with key `sought` in this subtree, this one first.
    public func first(id sought: ElementId) -> MountedElement? {
        if id == sought { return self }

        for child in children {
            if let found = child.first(id: sought) { return found }
        }

        return nil
    }

    /// Every element with key `sought` in this subtree.
    public func all(id sought: ElementId) -> [MountedElement] {
        var found = id == sought ? [self] : []
        for child in children {
            found.append(contentsOf: child.all(id: sought))
        }
        return found
    }

    /// The handlers of `created` raised by no render yet, in tree order; a window raises its own.
    public func takeCreatedHandlers() -> [Int32] {
        var handlers: [Int32] = []

        if !created {
            created = true
            if type != .windowScene, let handler = events[.created] {
                handlers.append(handler)
            }
        }

        for child in children {
            handlers.append(contentsOf: child.takeCreatedHandlers())
        }

        return handlers
    }

    /// Drops the first element in this subtree that `matches`, as a runtime that lost part of its tree would.
    public func forgetForTesting(where matches: (MountedElement) -> Bool) {
        if let index = children.firstIndex(where: matches) {
            children[index].leave()
            children.remove(at: index)
            return
        }
        for child in children { child.forgetForTesting(where: matches) }
    }

    /// Presents one frame's affected branches: bound states and moved properties, each parent arranged once.
    /// Design: docs/design/host/runtime.md#one-frame
    @discardableResult
    public func applyFrame(
        states valuesByState: [Int32: HostStateValue],
        properties propertiesByMount: [UInt64: Set<Prop>]
    ) -> FrameImpact {
        let affected = tree?.frameMounts(states: valuesByState, properties: propertiesByMount) ?? []
        return applyFrame(states: valuesByState, properties: propertiesByMount, affected: affected)
    }

    private func applyFrame(
        states valuesByState: [Int32: HostStateValue],
        properties propertiesByMount: [UInt64: Set<Prop>],
        affected: Set<UInt64>
    ) -> FrameImpact {
        guard affected.contains(mount) else { return .none }
        var changed = propertiesByMount[mount] ?? []

        for (property, binding) in driven where binding.mode != .in {
            guard let value = valuesByState[binding.state] else { continue }
            drivenValues[property] = value
            changed.insert(property)
        }

        let own = changed.isEmpty ? FrameImpact.none : presentFrame(changed)
        var descendants = FrameImpact.none

        for child in children where affected.contains(child.mount) {
            descendants = descendants.union(child.applyFrame(
                states: valuesByState, properties: propertiesByMount, affected: affected))
        }

        // A child's place is its parent's business; an element with no view passes it up.
        let restacked = descendants.content ? restack() : false
        // Opacity and drawing transforms already reach the native view in presentFrame.
        // Reassembling its children here would turn every transition tick into a layout update.
        let arrangesOwn = own.content && (!native.presentsView || !changed.isSubset(of: Self.drawingFrameProperties))
        if arrangesOwn || descendants.arrangement || restacked { native.arrangeChildren() }
        guard native.presentsView else { return own.union(descendants) }
        descendants.arrangement = false
        return own.union(descendants)
    }

    private static let drawingFrameProperties = Set<Prop>([.opacity, .blur, .renderTransform])
        .union(transformProperties)

    /// Presents `changed` on a frame and says what that asks around the element, the same on every host: its own
    /// presentation; its parent's arrangement where it moved in its slot or shows no view of its own, being drawn
    /// by its parent's; the window's chrome where the chrome shows what moved.
    /// Design: docs/design/host/runtime.md#one-frame
    private func presentFrame(_ changed: Set<Prop>) -> FrameImpact {
        native.presentFrame(changed)
        return FrameImpact(
            content: true,
            arrangement: !native.presentsView
                || !changed.subtracting(ownPlacementRun).isDisjoint(with: Self.arrangedProperties),
            windowChrome: WindowChrome.follows(type, changing: changed))
    }

    /// The value `property` presents: a running animation's, else the described or bound one -
    /// and where the element carries the property's lookup key, what the host's tables answer it.
    public func value(_ property: Prop) -> HostValue? {
        let presented = if driven[property].map({ $0.mode != .in }) == true {
            resolvedValue(property)
        } else {
            tree?.presentedPropertyValue(mount: mount, property: property) ?? resolvedValue(property)
        }
        if let key = lookupKey(for: property),
           let resolved = tree?.localization(key) {
            return .string(resolved)
        }
        return presented
    }

    /// The `*Key` property shadowing each one it looks its value up by.
    private static let keyProperties: [Prop: Prop] = [
        .text: .textKey,
        .title: .titleKey,
        .subtitle: .subtitleKey,
        .placeholder: .placeholderKey,
        .hint: .hintKey,
    ]

    /// The lookup key carried beside `property`, where `property` is one a
    /// `*Key` member shadows - `text`, `title`, `subtitle`, `placeholder`,
    /// `hint` - and none elsewhere.
    private func lookupKey(for property: Prop) -> LocalizedStringKey? {
        Self.keyProperties[property].flatMap { resolvedValue($0) }
            .flatMap(LocalizedStringKey.init(propValue:))
    }

    /// The text value of `property`.
    public func string(_ property: Prop) -> String? { value(property)?.string }

    /// The name value of `property`.
    public func name(_ property: Prop) -> String? { value(property)?.name }

    /// The number value of `property`.
    public func number(_ property: Prop) -> Double? { value(property)?.number }

    /// The Boolean value of `property`.
    public func bool(_ property: Prop) -> Bool? { value(property)?.bool }

    /// The four sides `property` gives - leading, top, trailing, bottom - or nothing all round where it gives none.
    public func insets(_ property: Prop) -> EdgeInsets {
        guard let sides = value(property)?.numbers, sides.count >= 4 else { return EdgeInsets(0) }
        return EdgeInsets(sides[0], sides[1], sides[2], sides[3])
    }

    /// The handler of `event`, when the tree listens to it.
    public func handler(_ event: Event) -> Int32? { events[event] }

    /// The direction this element lays out in: its own, or where it inherits, its parent's - the
    /// language's at the root, as the host reported the locale.
    /// Design: docs/design/host/layout.md#right-to-left
    public var layoutDirection: LayoutDirection {
        switch value(.layoutDirection)?.enumeration.flatMap(LayoutDirection.init(rawValue:)) {
        case .leftToRight?: return .leftToRight
        case .rightToLeft?: return .rightToLeft
        default: return parent?.layoutDirection ?? tree?.core.languageDirection ?? .leftToRight
        }
    }

    /// What a layout reads of this element as its child.
    /// Design: docs/design/host/layout.md#the-layout-arithmetic
    public var layoutValues: LayoutValues {
        var values = LayoutValues()
        if let sides = value(.padding)?.numbers, sides.count >= 4 {
            values.margin = insets(.padding)
        }
        values.flex = stated(.flex)
        values.isFrameContent = bool(.isFrameContent) ?? false
        values.isLayoutDecoration = bool(.isLayoutDecoration) ?? false
        switch type {
        case .textField, .searchField:
            values.expandingAxes = .horizontal
        case .textEditor:
            values.expandingAxes = .both
        case .scrollView:
            values.scrollAxes = value(.orientation)?.enumeration.flatMap(Axis.init(rawValue:)) ?? .vertical
            values.expandingAxes = values.scrollAxes == .vertical ? .both : values.scrollAxes
        case .webView:
            values.scrollAxes = .both
        case .page, .navigationStack, .tabView, .navigationSplitView:
            // An arrangement is a viewport: it takes the room it is given and
            // lays out its own pages and bars inside it.
            values.expandingAxes = .both
        case .hStack, .vStack, .zStack, .grid, .gridRow, .lazyHStack, .lazyVStack,
             .lazyHGrid, .lazyVGrid, .customLayout, .masked:
            var horizontal = false, vertical = false
            var expandsAcross = false, expandsDown = false
            for child in currentChildren {
                let childValues = child.layoutValues
                guard !childValues.isLayoutDecoration else { continue }
                let axes = childValues.scrollAxes
                let expands = childValues.expandingAxes
                expandsAcross = expandsAcross || expands == .horizontal || expands == .both
                    || (childValues.flex != nil && childValues.width == nil && type != .vStack && type != .lazyVStack)
                expandsDown = expandsDown || expands == .vertical || expands == .both
                    || (childValues.flex != nil && childValues.height == nil
                        && type != .hStack && type != .lazyHStack && type != .gridRow)
                horizontal = horizontal || (childValues.width == nil && (axes == .horizontal || axes == .both))
                vertical = vertical || (childValues.height == nil && (axes == .vertical || axes == .both))
            }
            values.scrollAxes = horizontal && vertical ? .both : horizontal ? .horizontal
                : vertical ? .vertical : .neither
            values.expandingAxes = expandsAcross && expandsDown ? .both : expandsAcross ? .horizontal
                : expandsDown ? .vertical : .neither
        default:
            break
        }
        if isGeometryReader {
            // Its content never supplies the reader's ideal size or scroll axes.
            values.scrollAxes = .neither
            values.expandingAxes = .both
        }
        values.horizontal = value(.horizontalAlignment)?.enumeration
            ?? value(.horizontalAlignmentDefault)?.enumeration ?? 3
        values.vertical = value(.verticalAlignment)?.enumeration
            ?? value(.verticalAlignmentDefault)?.enumeration ?? 3
        values.width = stated(.width)
        values.height = stated(.height)
        if isLayoutDivider {
            values.expandingAxes = dividerAxis
            if dividerAxis == .vertical { values.width = values.width ?? 1 }
            else { values.height = values.height ?? 1 }
        }
        // A bound covers the padding written before it - the view `.frame(min:)`
        // wraps in SwiftUI holds the padding inside - so the margin stands
        // inside the bound, the way the offered room already does.
        let across = values.margin.left + values.margin.right
        let down = values.margin.top + values.margin.bottom
        values.minimumWidth = stated(.minimumWidth).map { max(0, $0 - across) }
        values.minimumHeight = stated(.minimumHeight).map { max(0, $0 - down) }
        values.maximumWidth = number(.maximumWidth).flatMap { $0 >= 0 ? max(0, $0 - across) : nil }
        values.maximumHeight = number(.maximumHeight).flatMap { $0 >= 0 ? max(0, $0 - down) : nil }
        let expandsAcross = values.width == nil && (values.maximumWidth == .infinity
            || value(.horizontalAlignment)?.enumeration == AxisAlignment.fill.rawValue
            || values.expandingAxes == .horizontal || values.expandingAxes == .both
            || values.scrollAxes == .horizontal || values.scrollAxes == .both)
        let expandsDown = values.height == nil && (values.maximumHeight == .infinity
            || value(.verticalAlignment)?.enumeration == AxisAlignment.fill.rawValue
            || values.expandingAxes == .vertical || values.expandingAxes == .both
            || values.scrollAxes == .vertical || values.scrollAxes == .both)
        values.expandingAxes = expandsAcross && expandsDown ? .both : expandsAcross ? .horizontal
            : expandsDown ? .vertical : .neither
        values.row = whole(.gridRow) ?? 0
        values.column = whole(.gridColumn) ?? 0
        values.priority = stated(.layoutPriority) ?? 0
        if let guide = value(.horizontalGuide)?.numbers, guide.count >= 2 {
            values.horizontalGuide = AlignmentGuide(slot: Int32(guide[0]), offset: guide[1])
        }
        if let guide = value(.verticalGuide)?.numbers, guide.count >= 2 {
            values.verticalGuide = AlignmentGuide(slot: Int32(guide[0]), offset: guide[1])
        }
        values.rowSpan = max(whole(.gridRowSpan) ?? 1, 1)
        values.columnSpan = max(whole(.gridColumnSpan) ?? 1, 1)
        values.area = value(.area).flatMap(Area.init(propValue:))
        return values
    }

    /// A size the element states for itself; a negative one asks to be measured.
    private func stated(_ property: Prop) -> Double? {
        guard let value = number(property), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func whole(_ property: Prop) -> Int? {
        guard let number = value(property)?.number, number.isFinite else { return nil }
        return Int(number.rounded())
    }

    /// The bound state's value for `property`, as the last frame carried it or the core holds it.
    public func carriedValue(_ property: Prop) -> HostStateValue? {
        guard let binding = driven[property] else { return nil }
        return drivenValues[property] ?? tree?.core.value(for: binding)
    }

    /// The value `property` settles at: the bound state's, else the described one.
    public func resolvedValue(_ property: Prop) -> HostValue? {
        guard let binding = driven[property], binding.mode != .in else {
            return properties[property]
        }

        guard let state = drivenValues[property] ?? tree?.core.value(for: binding) else {
            return properties[property]
        }

        switch (binding.kind, state) {
        case (.text, .text(let text)):
            return .string(text)

        case (.plain, .lanes(let lanes)):
            return value(property, lanes: lanes)

        case (.property, let carried):
            let presented = tree?.presentedValue(for: binding, from: carried) ?? carried
            guard let journey = HostBoundary.journey(from: presented) else {
                return properties[property]
            }
            return value(property, lanes: journey.value)

        default:
            return properties[property]
        }
    }

    /// Where `property` stands before a change animates it.
    /// Design: docs/design/host/tree.md#standing-values
    private func standingValue(_ property: Prop, target: HostValue?) -> HostValue? {
        if let presented = tree?.presentedPropertyValue(mount: mount, property: property) {
            return presented
        }
        if let native = native.standingValue(property) { return native }
        if let value = resolvedValue(property) { return value }
        guard native.animates(property) else { return nil }

        switch property {
        case .padding, .contentPadding:
            return .numbers([0, 0, 0, 0])
        case .spacing, .rowSpacing, .columnSpacing:
            return .number(0)
        case .strokeWidth:
            return .number(1)
        case .strokeDashOffset, .x1, .y1, .x2, .y2:
            return .number(0)
        case .strokeMiterLimit:
            return .number(10)
        case .cornerRadius:
            if target?.number != nil {
                return .number(0)
            }
            if let radii = target?.numbers, radii.count == 4 {
                return .numbers(Array(repeating: 0, count: radii.count))
            }
            return nil
        case .rotation, .translationX, .translationY:
            return .number(0)
        case .scale:
            return .number(1)
        case .scaleX, .scaleY:
            return .number(resolvedValue(.scale)?.number ?? 1)
        case .renderTransform:
            return .values([
                .number(1), .number(0), .number(0),
                .number(1), .number(0), .number(0),
            ])
        default:
            return nil
        }
    }

    /// A bound state's lanes as the value `property` carries.
    private func value(_ property: Prop, lanes: [Double]) -> HostValue? {
        guard !lanes.isEmpty else { return nil }

        if Self.colorProperties.contains(property), lanes.count >= 4 {
            func channel(_ value: Double) -> UInt8 {
                UInt8(min(max((value * 255).rounded(), 0), 255))
            }

            return .color(
                red: channel(lanes[0]),
                green: channel(lanes[1]),
                blue: channel(lanes[2]),
                alpha: channel(lanes[3]))
        }

        if Self.booleanProperties.contains(property) {
            return .bool(lanes[0] != 0)
        }

        if Self.enumerationProperties.contains(property) {
            return .enumeration(Int32(lanes[0].rounded()))
        }

        return lanes.count == 1 ? .number(lanes[0]) : .numbers(lanes)
    }

    private static let colorProperties: Set<Prop> = [
        .background, .barBackgroundColor, .barForegroundColor, .color,
        .indicatorColor, .placeholderColor, .selectedIndicatorColor, .foregroundStyle, .tint,
    ]

    private static let booleanProperties: Set<Prop> = [
        .allowDrop, .hidesWhenInactive, .canDrag, .floatsOnTop, .growsWithText, .ignoresInput,
        .isAnimating, .clipsContent, .isDestructive,
        .isEnabled, .isMaximizable, .isMinimizable, .isTranslucent,
        .isOpen, .isPassword, .isSidebarVisible, .isReadOnly,
        .isRunning, .isScrollEnabled,
        .showsUserLocation, .isSpellCheckEnabled, .isTextPredictionEnabled,
        .isOn, .isTrafficEnabled, .isVisible, .isZoomEnabled, .letsInputThrough,
        .showsClearButton,
    ]

    private static let enumerationProperties: Set<Prop> = [
        .aspect, .layoutDirection, .fontAttributes, .fontTextStyle, .fontDesign,
        .horizontalAlignment, .horizontalScrollIndicators,
        .multilineTextAlignment, .textContentType,
        .lineBreak, .orientation, .submitLabel, .textDecorations, .textCase,
        .verticalAlignment, .verticalScrollIndicators, .verticalTextAlignment,
    ]
}

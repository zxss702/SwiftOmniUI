// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The WinUI half of a mounted element: its native element and everything hung on it.
/// Design: docs/design/host/tree.md#the-native-half
@MainActor
final class WinUIElement: NativeElement {
    /// The element of the mounted tree this is the WinUI half of; it owns this half.
    unowned let element: MountedElement

    /// The element's view; nil for an element drawn by its parent's, or none.
    private(set) var view: WinUIView?

    weak var host: WinUIRenderer?

    /// Whether a label shows its spans' runs in place of its own words.
    var hasRuns = false

    /// Whether the view was last given a context menu, and whether its menu changed in this patch.
    var hadContextMenu = false
    var contextMenuChanged = false

    /// Child layout inputs, separate from descendant paint and event changes.
    var layoutItemsDirty = true
    private(set) var layoutItemCollections = 0
    private var cachedLayoutValues: LayoutValues?
    private(set) var layoutInputResolutions = 0

    private struct PendingLayout {
        let element: MountedElement
        let depth: Int
    }
    private static var pendingLayouts: [ObjectIdentifier: PendingLayout] = [:]
    private static var layoutCommitScheduled = false

    /// Every property read by MountedElement.layoutValues, including derived
    /// expansion/scroll axes inherited from children.
    private static let layoutInputs = MountedElement.arrangedProperties.union([
        .flex, .isFrameContent, .isLayoutDecoration, .orientation,
        .horizontalAlignmentDefault, .verticalAlignmentDefault,
        .layoutPriority, .horizontalGuide, .verticalGuide,
    ])

    private static func geometryLanes(affectedBy properties: Set<Prop>) -> AnimationLanes {
        var lanes: AnimationLanes = []
        for property in properties where layoutInputs.contains(property) {
            switch property {
            case .height, .minimumHeight, .maximumHeight: lanes.formUnion([.y, .height])
            default: lanes.formUnion(.all)
            }
        }
        return lanes
    }

    var resolvedLayoutValues: LayoutValues {
        if let cachedLayoutValues { return cachedLayoutValues }
        let values = element.layoutValues(readingChildren: { $0.winUI.resolvedLayoutValues })
        layoutInputResolutions += 1
        cachedLayoutValues = values
        return values
    }

    func layoutItemChanged(followingPresentation: Bool = false, presentedLanes: AnimationLanes = []) {
        cachedLayoutValues = nil
        if followingPresentation || !presentedLanes.isEmpty {
            (view as? WinUITravellingLayout)?.followsPresentationFrame(lanes: presentedLanes, sample: followingPresentation)
        }
        var owners: [WinUIElement] = []
        // Only the branch whose intrinsic extent depends on this property
        // gives up its geometry lanes. A sibling can reorder on the same axis.
        var branch = view != nil ? element.mount : layoutItem?.mount
        var owner = parent
        while let each = owner {
            each.layoutItemsDirty = true
            each.cachedLayoutValues = nil
            if followingPresentation || !presentedLanes.isEmpty {
                (each.view as? WinUITravellingLayout)?.followsPresentationFrame(
                    lanes: presentedLanes, sample: followingPresentation, item: branch)
            }
            if each.view != nil { branch = each.element.mount }
            owners.append(each)
            owner = each.parent
        }
        guard ProgramWrite.isWriting, !owners.isEmpty else { return }
        for (index, each) in owners.enumerated() {
            Self.pendingLayouts[ObjectIdentifier(each)] = PendingLayout(
                element: each.element, depth: owners.count - index)
        }
        guard !Self.layoutCommitScheduled else { return }
        Self.layoutCommitScheduled = true
        ProgramWrite.afterWrites {
            let pending = Self.pendingLayouts.values.sorted { $0.depth > $1.depth }
            Self.pendingLayouts.removeAll(keepingCapacity: true)
            Self.layoutCommitScheduled = false
            // Frame traversal arranges the nearest native parent only. Derived
            // layout values farther up still need publishing in this batch,
            // including after the animation's final frame or a removal landing.
            ProgramWrite.perform {
                for entry in pending {
                    let element = entry.element.winUI
                    guard element.layoutItemsDirty, element.view?.isDetached != true else { continue }
                    element.arrangeChildren()
                }
            }
        }
    }

    func collectedLayoutItems() {
        layoutItemsDirty = false
        layoutItemCollections += 1
    }

    init(_ element: MountedElement, host: WinUIRenderer) {
        self.element = element
        self.host = host
        view = makeView()
        view?.sourceElement = element
        let hasTransitionBlur = element.transition?.insertion.blur != nil
            || element.transition?.removal.blur != nil
        var inLazyContainer = false
        if hasTransitionBlur {
            var ancestor = element.parent
            while let current = ancestor {
                if current.type == .lazyVStack || current.type == .lazyHStack
                    || current.type == .lazyVGrid || current.type == .lazyHGrid {
                    inLazyContainer = true
                    break
                }
                ancestor = current.parent
            }
        }
        if element.value(.blur) != nil || element.driven[.blur] != nil
            || (hasTransitionBlur && !inLazyContainer) {
            view?.prepareBlur()
        }
    }

    // MARK: - The element's tree, read through its mounted element

    var type: NodeType { element.type }
    var parent: WinUIElement? { element.parent?.winUI }
    var children: [WinUIElement] { element.children.map(\.winUI) }
    func value(_ property: Prop) -> HostValue? { element.value(property) }

    // MARK: - The native half's part in a patch

    var presentsView: Bool { view != nil }

    func standingValue(_ property: Prop) -> HostValue? {
        switch (type, property) {
        case (_, .opacity): view.map { .number($0.opacity) }
        case (_, .blur): view.map { .number($0.blur) }
        case (.slider, .value): (view as? WinUISliderView).map { .number($0.value) }
        default: nil
        }
    }

    func animates(_ property: Prop) -> Bool {
        (presentsView && (property == .blur || TransitionSurface.presentsDrawing(property)))
            || TransitionSurface.presents(property, on: type)
    }

    func applied(changed: Set<Prop>, wasDescribed: Bool) {
        if !wasDescribed || element.childOrderChanged || !changed.isDisjoint(with: Self.layoutInputs) {
            // A described height owns dependent vertical geometry, not every
            // sibling's animation. Width may also reflow height; other layout
            // inputs can affect both axes.
            var presented: Set<Prop> = []
            for property in changed where Self.layoutInputs.contains(property) {
                let driven = element.driven[property].map { binding in
                    binding.mode != .in && host?.runtime.animator.animation(for: .state(binding.state)) != nil
                } ?? false
                guard driven || host?.runtime.animator.animation(
                    for: .described(DescribedKey(mount: element.mount, property: property))) != nil else { continue }
                presented.insert(property)
            }
            layoutItemChanged(presentedLanes: Self.geometryLanes(affectedBy: presented))
        }
        if wasDescribed, changed.contains(.isVisible) { crossVisibility() }
        applyProperties(changed: changed)
        if let view, let host { element.applyDrawnChildren(to: view, through: WinUIRegistrations.registry, in: host.runtime) }
        configureGestures()
        if let label = view as? WinUITextView {
            label.onTextLayout = element.value(TextContract.reportsLayout.token)?.bool == true ? { [weak self] report in
                guard let self, let host = self.host else { return }
                self.element.reportTextLayout(report, in: host.runtime)
            } : nil
        }
        view?.setFocusChanged(element.handler(.isFocusedChanged) == nil ? nil : { [weak self] focused in
            self?.send(.isFocusedChanged, [.bool(focused)])
        })
        configureLayoutMotion()
        let plainLayout = view is WinUIStackView || view is WinUIZStackView || view is WinUIGridView
            || view is WinUILazyView || view is WinUIScrollView || view is WinUISingleChildView
        if !plainLayout || !wasDescribed || layoutItemsDirty || element.childOrderChanged
            || changed.contains(.layoutDirection) {
            arrangeChildren()
        } else if let lazy = view as? WinUILazyView {
            // A sparse patch can acknowledge a window or change row content
            // without changing the parent's list of layout items.
            lazy.refreshContent()
        }
        arrangePages(changed: changed)
        if changed.contains(.preferredColumnWidth) || (element.childrenChanged && parent?.type == .navigationSplitView),
           let split = element.parent?.enclosing(type: .navigationSplitView)?.winUI {
            split.arrangeChildren()
        }
        var declared = element.enclosing(type: .contextMenu)
        while let owner = declared?.parent?.winUI {
            owner.contextMenuChanged = true
            declared = owner.element.parent?.enclosing(type: .contextMenu)
        }
        refreshContextMenu()
        if let view { host?.runtime.frames.follow(self, order: view.number, reads: readsFrame) }
    }

    func presentFrame(_ changed: Set<Prop>) {
        if !changed.isDisjoint(with: Self.layoutInputs) {
            layoutItemChanged(followingPresentation: true, presentedLanes: Self.geometryLanes(affectedBy: changed))
        }
        applyProperties(changed: changed, followingPresentation: true)
    }

    func departureChanged() {
        layoutItemChanged()
        if element.isDeparting, element.transition?.removal.blur != nil {
            view?.prepareBlur()
        }
        view?.setIgnoresInput(element.isDeparting || element.value(.ignoresInput)?.bool == true)
    }

    func leave() {
        layoutItemChanged()
        if let view { host?.runtime.frames.follow(self, order: view.number, reads: false) }
        view?.detach()
    }
}

extension MountedElement {
    /// This element's WinUI half.
    var winUI: WinUIElement { native as! WinUIElement }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// An element's children matched against the last render's - by `.id()`, then by
// builder path, then by position - and patched.
// Design: docs/design/core/identity-and-diffing.md#keys

final class HostClaimedIds {
    var used: Set<ElementId> = []
    var variantCounts: [String: Int] = [:]
}

extension Differ {
    static func enclosingHostClaimedIds(excluding target: RenderedNode?) -> HostClaimedIds? {
        guard let target else { return nil }
        var host = target.parent
        while let current = host, current.type == .fragment {
            host = current.parent
        }
        guard let host else { return nil }
        let claimed = HostClaimedIds()
        func collect(_ node: RenderedNode) {
            guard node !== target else { return }
            if node.type == .fragment {
                for child in node.children { collect(child) }
            } else {
                claimed.used.insert(node.id)
            }
        }
        for child in host.children { collect(child) }
        return claimed
    }

    /// Matches this render's children against the last one's and patches each. An
    /// unchanged key sequence sends only the children with something to say; a
    /// changed one sends the complete list in order.
    /// Design: docs/design/core/identity-and-diffing.md#keys
    func reconcileChildren(
        of previous: RenderedNode?,
        node: Node,
        into patch: inout HostPatch,
        sizesArrive: Bool,
        keepingLazyRows: Bool = false,
        wrapFragmentChildren: Bool = false,
        hostClaimedIds: HostClaimedIds? = nil
    ) -> [RenderedNode] {
        let rendered = previous?.children ?? []
        let hostClaimed = hostClaimedIds ?? HostClaimedIds()

        var byManualId: [String: RenderedNode] = [:]
        var byKey: [String: RenderedNode] = [:]
        for child in rendered {
            if let raw = child.authoredManualId {
                if byManualId[raw] == nil { byManualId[raw] = child }
            } else if case .manual(let key) = child.id {
                byManualId[key] = child
            }

            // First wins, so two elements claiming one path behave like a repeated `.id()`.
            if let key = child.key, byKey[key] == nil {
                byKey[key] = child
            }
        }

        // Nodes put in by hand are matched by position among themselves.
        let unkeyed = rendered.filter { $0.key == nil }

        var children: [RenderedNode] = []
        var patches: [HostPatch] = []
        var claimed: Set<ElementId> = []
        var used: Set<ElementId> = []
        var unkeyedSoFar = 0
        var manualSeen: [String: Int] = [:]

        for (index, childNode) in node.children.enumerated() {
            // A repeated `.id()` takes a stable variant: the id, a NUL, its occurrence.
            // Design: docs/design/core/identity-and-diffing.md#repeated-ids
            var childNode = childNode
            let localAuthoredId: String?
            if let rawId = childNode.id {
                let occurrence = manualSeen[rawId, default: 0]
                manualSeen[rawId] = occurrence + 1

                if occurrence > 0 {
                    let disambiguated = "\(rawId)\u{0}\(occurrence)"
                    childNode.id = disambiguated
                    localAuthoredId = disambiguated
                } else {
                    localAuthoredId = rawId
                }
            } else {
                localAuthoredId = nil
            }

            let match = self.match(
                childNode,
                at: childNode.key == nil ? unkeyedSoFar : index,
                rendered: unkeyed,
                byManualId: byManualId,
                byKey: byKey,
                claimed: claimed)

            if childNode.key == nil {
                unkeyedSoFar += 1
            }

            if let match = match {
                claimed.insert(match.id)
            }

            var id: ElementId
            if let match, !used.contains(match.id), !hostClaimed.used.contains(match.id) {
                id = match.id
            } else {
                id = identity(for: childNode)
                if case .manual(let base) = id, used.contains(id) || hostClaimed.used.contains(id) {
                    var step = hostClaimed.variantCounts[base, default: 1]
                    var candidate = ElementId.manual("\(base)\u{0}\(step)")
                    while used.contains(candidate) || hostClaimed.used.contains(candidate) {
                        step += 1
                        candidate = .manual("\(base)\u{0}\(step)")
                    }
                    hostClaimed.variantCounts[base] = step + 1
                    id = candidate
                } else if used.contains(id) || hostClaimed.used.contains(id) {
                    id = .auto(allocateElementId())
                }
            }

            used.insert(id)

            let (child, childPatch) = if keepingLazyRows, let match {
                // Only the viewport moved. Keep the retained row's description,
                // while still visiting any state changes inside its subtree.
                revisit(match, walking: false)
            } else {
                element(id: id, rendered: match, node: childNode,
                        sizesArrive: sizesArrive, wrapFragmentChildren: wrapFragmentChildren,
                        hostClaimedIds: hostClaimed)
            }
            child.authoredManualId = localAuthoredId

            // A fragment anchors its subtree here but mounts no element of its
            // own: its children are patched into this list directly - every one
            // of them, an unchanged child as an empty patch, since an arranged
            // list the host reads as complete cannot silently drop a seat.
            if child.type == .fragment {
                for mountedId in mountedIds(of: [child]) { hostClaimed.used.insert(mountedId) }
                children.append(child)
                let nested: [HostPatch] = switch childPatch.children {
                case .arranged(let list), .changed(let list): list
                case .unchanged: []
                }
                let byID = Dictionary(nested.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                patches.append(contentsOf: flattened(of: child.children).map {
                    byID[$0.id] ?? HostPatch(id: $0.id, type: $0.type)
                })
            } else {
                hostClaimed.used.insert(child.id)
                children.append(child)
                patches.append(childPatch)
            }
        }

        for child in rendered where !claimed.contains(child.id) {
            forget(child)
        }

        // The arrangement is sent only when it changed - and what the host
        // arranges is the PATCH list: a fragment's children stand in it
        // directly, so the sequence to compare is the one the host was last
        // told, not the one `children` keeps (which holds the fragments).
        if describeAll || patches.map(\.id) != mountedIds(of: rendered) {
            patch.children = .arranged(patches)
        } else {
            let changed = patches.filter { !$0.isEmpty }
            patch.children = changed.isEmpty ? .unchanged : .changed(changed)
        }

        return children
    }

    /// The ids a host was told this list holds: a fragment mounts nothing of
    /// its own, so its children answer in its place - recursively, a fragment
    /// inside one standing in it the same way.
    func mountedIds(of rendered: [RenderedNode]) -> [ElementId] {
        flattened(of: rendered).map(\.id)
    }

    /// The children as the host holds them: fragments lifted out, their own
    /// children standing in their place however deep the nesting.
    func flattened(of rendered: [RenderedNode]) -> [RenderedNode] {
        rendered.flatMap { $0.type == .fragment ? flattened(of: $0.children) : [$0] }
    }

    /// The rendered element a node continues: by the author's `.id()`, then by the
    /// builder path, then by position - three ways that never meet.
    /// Design: docs/design/core/identity-and-diffing.md#keys
    private func match(
        _ node: Node,
        at index: Int,
        rendered: [RenderedNode],
        byManualId: [String: RenderedNode],
        byKey: [String: RenderedNode],
        claimed: Set<ElementId>
    ) -> RenderedNode? {
        if let id = node.id {
            let match = byManualId[id]
            return match.flatMap { claimed.contains($0.id) ? nil : $0 }
        }

        if let key = node.key {
            let match = byKey[key]
            return match.flatMap {
                claimed.contains($0.id) || $0.id.isManual ? nil : $0
            }
        }

        guard index < rendered.count else { return nil }

        let candidate = rendered[index]

        guard case .auto = candidate.id, !claimed.contains(candidate.id) else {
            return nil
        }

        return candidate
    }
}

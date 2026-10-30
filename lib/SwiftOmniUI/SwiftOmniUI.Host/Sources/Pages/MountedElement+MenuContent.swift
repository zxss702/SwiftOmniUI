// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

extension MountedElement {
    /// A native trigger requests one menu level, never all of its unopened descendants.
    public func requestMenuContent(mount: UInt64? = nil, in runtime: HostRuntime) {
        func find(in element: MountedElement) -> MountedElement? {
            if element.mount == mount { return element }
            for child in element.children where !child.isDeparting {
                if let found = find(in: child) { return found }
            }
            return nil
        }
        guard let menu = mount == nil ? self : find(in: self) else { return }
        let content = menu.children.first { $0.type == .contextMenu } ?? menu
        content.send(ContextMenuContract.contentRequested.token, [], in: runtime)
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension Aim where Target == ListContract {
    /// Scrolls the list until `item` stands where `anchor` says, as the
    /// platform scrolls.
    public nonisolated(nonsending) func scrollTo(_ item: some Hashable, anchor: ScrollAnchor = .nearest) async throws {
        try await call(ListContract.scrollTo, String(describing: item), anchor)
    }

    /// Scrolls a list of groups until `item` of the group named `group` stands
    /// where `anchor` says.
    public nonisolated(nonsending) func scrollTo(
        _ item: some Hashable, inGroup group: some Hashable, anchor: ScrollAnchor = .nearest
    ) async throws {
        try await call(ListContract.scrollTo, "\(group)\u{1F}\(item)", anchor)
    }
}

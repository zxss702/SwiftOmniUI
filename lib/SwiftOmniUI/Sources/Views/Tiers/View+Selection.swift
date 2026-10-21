// SPDX-License-Identifier: Apache-2.0
extension View {
    /// Native desktop commands and edge autoscrolling for a container that owns
    /// its text selection. Does not make the contents editable or steal focus
    /// from a native text field. The drag point uses this container's coordinates.
    public func selectionInteraction(
        isActive: Bool, dragPoint: Point?,
        onDeselect: @escaping () -> Void, onCopy: @escaping () -> Void,
        onSelectAll: @escaping () -> Void, onScroll: @escaping (Point) -> Void
    ) -> ModifiedContent {
        setting(ViewContract.selectionActive, isActive)
            .setting(ViewContract.selectionDragPoint, dragPoint.map { [$0.x, $0.y] } ?? [])
            .hearing(ViewContract.windowPointerPressed, onDeselect)
            .hearing(ViewContract.copyRequested, onCopy)
            .hearing(ViewContract.selectAllRequested, onSelectAll)
            .hearing(ViewContract.dragScrolled, onScroll)
    }
}

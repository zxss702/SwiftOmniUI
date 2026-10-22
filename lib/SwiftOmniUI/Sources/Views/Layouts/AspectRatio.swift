// SPDX-License-Identifier: Apache-2.0

extension View {
    /// Proposes a size with the given width-to-height ratio. With no explicit
    /// ratio, use the child's ideal proportions. Fit stays inside the proposal;
    /// fill covers it without clipping the child automatically.
    public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
        AspectRatioLayout(ratio: aspectRatio, mode: contentMode) { self }
    }

    public func aspectRatio(_ aspectRatio: Size, contentMode: ContentMode) -> some View {
        self.aspectRatio(aspectRatio.width / aspectRatio.height, contentMode: contentMode)
    }
}

struct AspectRatioLayout: Layout {
    typealias Cache = Void
    let ratio: Double?
    let mode: ContentMode

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> Size {
        guard let child = subviews.first else { return .zero }
        let offered = fittedProposal(proposal, child: child)
        return child.sizeThatFits(offered)
    }

    func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard let child = subviews.first else { return }
        child.place(at: Point(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2),
                    anchor: .center, proposal: fittedProposal(proposal, child: child))
    }

    private func fittedProposal(_ proposal: ProposedViewSize, child: LayoutSubview) -> ProposedViewSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let height = proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil }
        let ideal = ratio == nil || (width == nil && height == nil) ? child.sizeThatFits(.unspecified) : .zero
        let ratio = ratio ?? (ideal.height > 0 ? ideal.width / ideal.height : 0)
        guard ratio.isFinite, ratio > 0 else { return proposal }
        switch (width, height) {
        case let (width?, height?):
            let useWidth = mode == .fill ? width >= height * ratio : width <= height * ratio
            return useWidth ? ProposedViewSize(width: width, height: width / ratio)
                : ProposedViewSize(width: height * ratio, height: height)
        case let (width?, nil): return ProposedViewSize(width: width, height: width / ratio)
        case let (nil, height?): return ProposedViewSize(width: height * ratio, height: height)
        case (nil, nil):
            let height = max(ideal.height, ideal.width / ratio)
            return ProposedViewSize(width: height * ratio, height: height)
        }
    }
}

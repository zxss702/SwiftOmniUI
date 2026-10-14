// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Drawing clips and interaction regions share size feedback, but write
/// independent properties: a content shape must never clip the drawing.
struct SizedPathShape<Content: View, S: Shape>: View {
    enum Role: Equatable { case clip, interaction }
    let content: Content
    let shape: S
    let style: FillStyle
    let role: Role
    @State private var size: Size? = nil

    var body: some View {
        let path = size.map { shape.path(in: Rect(0, 0, $0.width, $0.height)) } ?? Path()
        var wrapper = ZStack { content }.node
        wrapper.write(role == .clip ? LayoutContract.clipPath : LayoutContract.hitPath,
                      path.geometry.arcsAsCubics.flatMap(\.numbers))
        wrapper.write(role == .clip ? LayoutContract.clipFillRule : LayoutContract.hitFillRule,
                      style.isEOFilled ? .evenOdd : .nonzero)
        return ModifiedContent(node: wrapper)
            .hearing(ViewContract.frameChanged) { numbers in
                guard let report = FrameReport(numbers) else { return }
                let next = Size(report.frame.width, report.frame.height)
                guard next != self.size else { return }
                var transaction = Transaction()
                transaction.isGeometryFeedback = true
                withTransaction(transaction) { self.size = next }
            }
    }
}

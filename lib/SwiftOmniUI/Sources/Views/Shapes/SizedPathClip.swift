// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

struct SizedPathClip<Content: View, S: Shape>: View {
    let content: Content
    let shape: S
    let style: FillStyle
    @State private var size: Size? = nil

    var body: some View {
        let path = size.map { shape.path(in: Rect(0, 0, $0.width, $0.height)) } ?? Path()
        ZStack { content }
            .setting(LayoutContract.clipPath, path.geometry.arcsAsCubics.flatMap(\.numbers))
            .setting(LayoutContract.clipFillRule, style.isEOFilled ? .evenOdd : .nonzero)
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

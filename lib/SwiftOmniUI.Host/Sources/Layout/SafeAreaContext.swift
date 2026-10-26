// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The proposal and the safe region in one container's coordinates. Native hosts
/// carry this with placement; geometry and scrolling read the same result.
@_spi(Host) public struct SafeAreaContext: Equatable, Sendable {
    public var bounds: Rect
    public var layout: Rect
    public var container: Rect
    public var keyboard: Rect
    public var consumed: EdgeInsets

    public init(bounds: Rect, layout: Rect? = nil, container: Rect? = nil, keyboard: Rect? = nil,
                consumed: EdgeInsets = EdgeInsets(0)) {
        self.bounds = bounds
        self.layout = layout ?? bounds
        self.container = container ?? bounds
        self.keyboard = keyboard ?? bounds
        self.consumed = consumed
    }

    /// Ancestors' regions can extend past a local child's proposal. Clip the
    /// usable region to that proposal before placing a local bar or its base.
    public var safe: Rect { Self.intersection(bounds, Self.intersection(container, keyboard)) }

    /// Remaining safe-area contributions, including strips outside a safe
    /// allocation. The layout size and this environment are separate values.
    public var insets: EdgeInsets { Self.insets(of: safe, in: bounds) }

    /// Apply the same edge contributions to another proposal. Regions belong
    /// to the layout that produced them; a new proposal changes their extent,
    /// rather than clipping itself against the previous allocation.
    public func resizedLayout(to proposal: Rect) -> Self {
        guard layout != proposal else { return self }
        func resized(_ region: Rect) -> Rect {
            // Preserve the region's edge contribution before applying a new
            // extent. (old + new) - old can differ from new by an ULP even
            // when the old region and layout are exactly the same rectangle.
            Rect(proposal.x + (region.x - layout.x),
                 proposal.y + (region.y - layout.y),
                 max(0, proposal.width + (region.width - layout.width)),
                 max(0, proposal.height + (region.height - layout.height)))
        }
        return Self(bounds: resized(bounds), layout: proposal,
                    container: resized(container), keyboard: resized(keyboard), consumed: consumed)
    }

    /// A child keeps the enclosing proposal's unsafe strips only at edges where
    /// it touches the safe region. A local card cannot acquire a window-wide bar.
    public func child(in frame: Rect, preservingOutsets: Bool = true) -> Self {
        let safe = self.safe
        let frameRight = frame.x + frame.width
        let frameBottom = frame.y + frame.height
        let left = frame.x <= safe.x ? min(frame.x, bounds.x) : frame.x
        let top = frame.y <= safe.y ? min(frame.y, bounds.y) : frame.y
        let right = frameRight >= safe.x + safe.width
            ? max(frameRight, bounds.x + bounds.width) : frameRight
        let bottom = frameBottom >= safe.y + safe.height
            ? max(frameBottom, bounds.y + bounds.height) : frameBottom
        func local(_ rect: Rect) -> Rect {
            Rect(rect.x - frame.x, rect.y - frame.y, rect.width, rect.height)
        }
        // Compare the original endpoints. Reconstructing an unchanged bottom
        // as top + (bottom - top) invents a consumed inset at fractional origins
        // and can make Measure/Arrange invalidate each other indefinitely.
        let outsets = EdgeInsets(
            top: frame.y - top, leading: frame.x - left,
            bottom: bottom - frameBottom, trailing: right - frameRight)
        let extended = Rect(left, top,
                            max(0, frame.width + outsets.left + outsets.right),
                            max(0, frame.height + outsets.top + outsets.bottom))
        let used = preservingOutsets ? EdgeInsets(0) : outsets
        let proposal = preservingOutsets ? extended : frame
        // A region covering an entire child axis has zero unsafe contribution
        // there. Keep that axis exactly equal to the child's proposal instead
        // of retaining distant parent endpoints whose cancellation changes on
        // resize. Preserve actual unsafe edges, including offscreen regions.
        func localRegion(_ region: Rect) -> Rect {
            let across = region.x <= proposal.x && region.x + region.width >= proposal.x + proposal.width
            let down = region.y <= proposal.y && region.y + region.height >= proposal.y + proposal.height
            return Rect((across ? proposal.x : region.x) - frame.x,
                        (down ? proposal.y : region.y) - frame.y,
                        across ? proposal.width : region.width,
                        down ? proposal.height : region.height)
        }
        return Self(bounds: local(proposal),
                    layout: Rect(0, 0, frame.width, frame.height),
                    container: localRegion(container), keyboard: localRegion(keyboard), consumed: consumed + used)
    }

    public func padding(_ insets: EdgeInsets) -> Self {
        var result = self
        result.container = container.inset(insets)
        return result
    }

    public func inset(edge: Edge, extent: Double, spacing: Double) -> Self {
        var insets = EdgeInsets(0)
        let amount = max(0, extent.isFinite ? extent : 0) + (spacing.isFinite ? spacing : 0)
        switch edge {
        case .top: insets.top = amount
        case .bottom: insets.bottom = amount
        case .leading: insets.left = amount
        case .trailing: insets.right = amount
        }
        return padding(insets)
    }

    /// Container and keyboard are independent regions. Ignoring one never
    /// clears the other, and an inner inset can reserve space again afterwards.
    public func ignoring(_ edges: SafeAreaEdges?) -> Self {
        guard let edges else { return self }
        let sides: [SafeArea]
        switch edges {
        case .uniform(let area): sides = [area, area, area, area]
        case .edges(let left, let top, let right, let bottom): sides = [left, top, right, bottom]
        }
        func cleared(_ rect: Rect, bit: Int32) -> Rect {
            let left = (sides[0].rawValue & bit) == 0 ? bounds.x : rect.x
            let top = (sides[1].rawValue & bit) == 0 ? bounds.y : rect.y
            let right = (sides[2].rawValue & bit) == 0 ? bounds.x + bounds.width : rect.x + rect.width
            let bottom = (sides[3].rawValue & bit) == 0 ? bounds.y + bounds.height : rect.y + rect.height
            return Rect(left, top, max(0, right - left), max(0, bottom - top))
        }
        var result = self
        result.container = cleared(container, bit: SafeArea.container.rawValue)
        result.keyboard = cleared(keyboard, bit: SafeArea.keyboard.rawValue)
        return result
    }

    /// A scroller can extend its native viewport on all four edges while
    /// keeping its own layout frame in the safe proposal.
    public func viewport(in frame: Rect, axes: Axis) -> Rect {
        // All four margins belong to the scroll container. Orientation controls
        // document proposals and movement, not whether its background extends.
        bounds
    }

    public func consuming(in frame: Rect) -> Self {
        Self(bounds: frame, consumed: consumed + Self.insets(of: safe, in: frame))
    }

    public static func insets(of safe: Rect, in frame: Rect) -> EdgeInsets {
        EdgeInsets(top: min(frame.height, max(0, safe.y - frame.y)),
                   leading: min(frame.width, max(0, safe.x - frame.x)),
                   bottom: min(frame.height, max(0, (frame.y + frame.height) - (safe.y + safe.height))),
                   trailing: min(frame.width, max(0, (frame.x + frame.width) - (safe.x + safe.width))))
    }

    public static func intersection(_ lhs: Rect, _ rhs: Rect) -> Rect {
        let x = max(lhs.x, rhs.x), y = max(lhs.y, rhs.y)
        func extent(_ first: Double, _ firstExtent: Double, _ second: Double, _ secondExtent: Double) -> Double {
            // A contained interval already has its exact extent. Rebuilding
            // that extent from its endpoints can shrink it by an ULP.
            if first == second { return max(0, min(firstExtent, secondExtent)) }
            let firstEnd = first + firstExtent, secondEnd = second + secondExtent
            if first > second, firstEnd <= secondEnd { return max(0, firstExtent) }
            if second > first, secondEnd <= firstEnd { return max(0, secondExtent) }
            return max(0, min(firstEnd, secondEnd) - max(first, second))
        }
        return Rect(x, y, extent(lhs.x, lhs.width, rhs.x, rhs.width),
                    extent(lhs.y, lhs.height, rhs.y, rhs.height))
    }
}

extension MountedElement {
    public var isGeometryReader: Bool { value(.isGeometryReader)?.bool == true }
    public var safeAreaInsetEdge: Edge? { value(.safeAreaInsetEdge).flatMap(Edge.init(propValue:)) }
    public var safeAreaPadding: EdgeInsets? {
        value(Prop("safeAreaPadding")) == nil ? nil : insets(Prop("safeAreaPadding"))
    }
    public var isSafeAreaBoundary: Bool {
        safeAreaInsetEdge != nil || safeAreaPadding != nil || ignoresSafeArea != nil
    }

    /// Scrollers span unsafe strips with their viewport. A reader instead
    /// accepts the safe allocation while observing the remaining contributions.
    public var preservesSafeAreaProposal: Bool {
        if isGeometryReader { return false }
        if isSafeAreaBoundary || type == .scrollView { return true }
        return safeAreaForwardedChild?.preservesSafeAreaProposal == true
    }

    /// Transparent wrappers, including unpadded single-child stacks, forward
    /// the safe-area environment. Ordinary content placed safely consumes it.
    public var observesSafeArea: Bool {
        if isSafeAreaBoundary || isGeometryReader || type == .scrollView { return true }
        return safeAreaForwardedChild?.observesSafeArea == true
    }

    private var safeAreaForwardedChild: MountedElement? {
        guard value(.clipsContent)?.bool != true,
              number(.width) == nil, number(.height) == nil,
              number(.maximumWidth).map({ !$0.isFinite || $0 < 0 }) ?? true,
              number(.maximumHeight).map({ !$0.isFinite || $0 < 0 }) ?? true,
              insets(.padding) == EdgeInsets(0), insets(.contentPadding) == EdgeInsets(0),
              currentChildren.count == 1,
              type == .page || !native.presentsView
                || type == .vStack || type == .hStack || type == .zStack
                || (type == .grid && currentChildren[0].value(.isFrameContent)?.bool == true)
        else { return nil }
        return currentChildren[0]
    }

    public var safeBarAllowsInput: Bool {
        var next: MountedElement? = self
        while let element = next {
            if element.isDeparting || element.value(.ignoresInput)?.bool == true
                || element.value(.isEnabled)?.bool == false || element.value(.isVisible)?.bool == false { return false }
            next = element.parent
        }
        return true
    }

    public var safeBarIsEnabled: Bool {
        var next: MountedElement? = self
        while let element = next {
            if element.value(.isEnabled)?.bool == false { return false }
            next = element.parent
        }
        return true
    }

    /// The nearest explicit choice wins, so one local bar can retain its
    /// material inside a subtree whose other bars are transparent.
    public var safeBarBackgroundHidden: Bool {
        var next: MountedElement? = self
        while let element = next {
            if let hidden = element.value(Prop("hiddenSafeBarBackground"))?.bool { return hidden }
            next = element.parent
        }
        return false
    }

    /// Only the page's uninterrupted root modifier chain joins native chrome.
    /// GeometryReader, scrolling, stacks and sized/padded local frames end it.
    public var pageTopSafeAreaBars: [MountedElement] {
        var bars: [MountedElement] = []
        var next: MountedElement? = self
        while let element = next {
            guard element.value(.isVisible)?.bool != false, element.value(.clipsContent)?.bool != true else { break }
            let children = element.currentChildren
            if let edge = element.safeAreaInsetEdge, children.count == 2 {
                guard edge == .top else { break }
                if (element.number(.spacing) ?? 0) < 0 { return [] }
                if edge == .top, children[1].value(.isVisible)?.bool != false {
                    bars.append(children[1])
                }
                next = children[0]
                continue
            }
            guard !element.isGeometryReader, element.safeAreaPadding == nil, element.ignoresSafeArea == nil,
                  element.value(.clipsContent)?.bool != true,
                  element.number(.width) == nil, element.number(.height) == nil,
                  element.number(.maximumWidth).map({ !$0.isFinite || $0 < 0 }) ?? true,
                  element.number(.maximumHeight).map({ !$0.isFinite || $0 < 0 }) ?? true,
                  element.insets(.padding) == EdgeInsets(0), element.insets(.contentPadding) == EdgeInsets(0),
                  element.type == .page || (children.count == 1 && (!element.native.presentsView
                      || (element.type == .grid && children[0].value(.isFrameContent)?.bool == true)))
            else { break }
            next = children.first
        }
        return bars
    }
}

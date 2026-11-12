// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A scroll destination, or a position taken over by the user.
public struct ScrollPosition: Equatable, Sendable {
    public private(set) var edge: Edge?
    public private(set) var point: CGPoint?
    public private(set) var x: CGFloat?
    public private(set) var y: CGFloat?
    public private(set) var viewID: (any Hashable & Sendable)?
    public private(set) var isPositionedByUser = false
    private var anchor: UnitPoint?
    private var revision = UUID()
    private var idType: any (Hashable & Sendable).Type

    public init(idType: (some Hashable & Sendable).Type = Never.self) {
        self.idType = idType
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) {
        self.idType = idType
        self.edge = edge
    }

    public init(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        idType = type(of: id)
        viewID = id
        self.anchor = anchor
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, point: CGPoint) {
        self.idType = idType
        self.point = point
        x = point.x
        y = point.y
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat) {
        self.idType = idType
        self.x = x
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, y: CGFloat) {
        self.idType = idType
        self.y = y
    }

    public init(idType: (some Hashable & Sendable).Type = Never.self, x: CGFloat, y: CGFloat) {
        self.init(idType: idType, point: CGPoint(x: x, y: y))
    }

    public func viewID<T: Hashable & Sendable>(type: T.Type) -> T? { viewID as? T }

    public mutating func scrollTo(edge: Edge) {
        self = ScrollPosition(idType: idType, edge: edge)
    }

    public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        let type = idType
        self = ScrollPosition(id: id, anchor: anchor)
        idType = type
    }

    public mutating func scrollTo(point: CGPoint) {
        self = ScrollPosition(idType: idType, point: point)
    }

    public mutating func scrollTo(x: CGFloat) {
        self = ScrollPosition(idType: idType, x: x)
    }

    public mutating func scrollTo(y: CGFloat) {
        self = ScrollPosition(idType: idType, y: y)
    }

    public mutating func scrollTo(x: CGFloat, y: CGFloat) {
        self = ScrollPosition(idType: idType, x: x, y: y)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.revision == rhs.revision && lhs.isPositionedByUser == rhs.isPositionedByUser
    }

    mutating func userScrolled() {
        edge = nil
        point = nil
        x = nil
        y = nil
        viewID = nil
        anchor = nil
        isPositionedByUser = true
    }

    func request(anchor: UnitPoint?) -> ScrollPositionRequest? {
        guard !isPositionedByUser, edge != nil || viewID != nil || x != nil || y != nil else { return nil }
        return ScrollPositionRequest(
            revision: revision.uuidString, edge: edge, id: viewID.map { String(describing: $0) },
            x: x.map(Double.init), y: y.map(Double.init), anchor: self.anchor ?? anchor)
    }
}

/// The destination crossing to a native scroller. Identity stays typed in the binding.
@_spi(Host) public struct ScrollPositionRequest: HostRepresentable, Equatable, Sendable {
    public let revision: String
    public let edge: Edge?
    public let id: String?
    public let x: Double?
    public let y: Double?
    public let anchor: UnitPoint?

    init(revision: String, edge: Edge?, id: String?, x: Double?, y: Double?, anchor: UnitPoint?) {
        self.revision = revision
        self.edge = edge
        self.id = id
        self.x = x
        self.y = y
        self.anchor = anchor
    }

    public var propValue: PropValue {
        .values([.string(revision), edge?.propValue ?? .nothing, id.map(PropValue.string) ?? .nothing,
                 x.map(PropValue.number) ?? .nothing, y.map(PropValue.number) ?? .nothing,
                 anchor?.propValue ?? .nothing])
    }

    public init?(propValue: PropValue) {
        guard case .values(let fields) = propValue, fields.count == 6,
              let revision = fields[0].string else { return nil }
        self.revision = revision
        edge = Edge(propValue: fields[1])
        id = fields[2].string
        x = fields[3].number
        y = fields[4].number
        anchor = UnitPoint(propValue: fields[5])
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// What an APPLICATION registers with this host, beside the elements the host realizes itself: the acts it performs,
/// by the host layer's rule. Said once, before `SwiftOmniUIWinUI.run()`.
/// Design: docs/design/platforms/winui/interop.md
@MainActor
enum WinUIInterop {
    /// The application's acts, performed where no act of the library's answers the call.
    static let acts = InteropActs<WinUIView>()
}

/// A control of the application's own on this host: an object that holds the WinUI element it shows.
///
/// The application makes the element with a relay of its own - C++/WinRT beside its head, behind C functions - and
/// hands its handle over as it is: the host takes a reference of its own, and places, sizes and shows the element as
/// it does its own; the element's own measure is what the host measures.
@MainActor
public protocol WinUIControl: AnyObject {
    /// The WinUI element the control shows: a `UIElement`'s default interface, `AddRef`'d, as the host's own handles
    /// are.
    var element: OpaquePointer { get }

    /// Whether an unbounded height proposal measures the entire content.
    /// Return false for a control with its own vertical scrolling viewport;
    /// its document height must not become the enclosing layout's minimum.
    var sizesToContentHeight: Bool { get }

    /// Whether changing this control's registered content properties can
    /// change the size it asks its parent for. Viewport controls may return
    /// false: their native document layout changes inside the allocated room.
    var contentAffectsSize: Bool { get }

    /// Opt in when the control owns a scrolling document. The native viewport
    /// then extends beneath enclosing SafeBars/window chrome. Keep the reported
    /// insets INSIDE the scrolling document, not as padding on its viewport.
    var scrollsUnderSafeArea: Bool { get }

    /// Remaining physical safe insets in DIPs, committed after the host layout
    /// transaction. Insets replace the previous values; they are not cumulative.
    /// The control retains ownership of its document, scrollbars and minimap.
    func safeAreaInsetsDidChange(top: Double, right: Double, bottom: Double, left: Double)
}

extension WinUIControl {
    public var sizesToContentHeight: Bool { true }
    public var contentAffectsSize: Bool { true }
    public var scrollsUnderSafeArea: Bool { false }
    public func safeAreaInsetsDidChange(top: Double, right: Double, bottom: Double, left: Double) {}
}

/// The controls an application adds to this host - its own elements, each realized with a control of its own.
///
/// Said once, from the application's WinUI head, before `SwiftOmniUIWinUI.run()`.
@MainActor
public enum SwiftOmniUIControls {
    /// Adds an element of the APPLICATION'S OWN, realized with a control of its own: how the control is made, and
    /// which of the element's members it takes and raises.
    ///
    ///     SwiftOmniUIControls.add(TrafficLightContract.self, create: { reports -> TrafficLightControl in
    ///         let light = TrafficLightControl()
    ///         light.onLampTapped = { index in reports.raise(TrafficLightContract.lampTapped, index) }
    ///         return light
    ///     }) { light in
    ///         light.property(TrafficLightContract.signal) { control, signal in
    ///             control.signal = signal ?? .stop
    ///         }
    ///     }
    ///
    /// What every view shares - margins, alignment, opacity, gestures, the frame reports - this host applies around
    /// the element, exactly as it does for the elements it realizes itself. A second registration of a contract
    /// replaces the first.
    ///
    /// - Parameters:
    ///   - contract: the element's contract.
    ///   - create: makes the control, once per element, handed what it reports through.
    ///   - members: registers the members the control takes and raises.
    public static func add<Realized: ElementContract, Made: WinUIControl>(
        _ contract: Realized.Type,
        create: @escaping (WinUIReports<Realized>) -> Made,
        members: (WinUIRegistration<Realized, Made>) -> Void = { _ in }
    ) {
        WinUIRegistrations.registry.add(
            contract,
            create: { reports in WinUIHostedView(create(WinUIReports(reports))) },
            members: { registration in members(WinUIRegistration(registration)) })
    }
}

/// The acts an application performs on this host - what its own calls, `stateUICall` and an `Aim`, reach.
///
/// Said once, from the application's WinUI head, before `SwiftOmniUIWinUI.run()`.
@MainActor
public enum SwiftOmniUIActs {
    /// Performs an act of the application's - one no control stands behind - when the application calls it with
    /// `stateUICall`.
    ///
    ///     SwiftOmniUIActs.add(GalleryContract.setClipboard) { text in
    ///         Clipboard.write(text)
    ///     }
    ///
    /// The values are the act's own, as its contract declares them, so a performer of another shape does not
    /// compile and a call carrying anything else fails with the reason. A performer may await, and the call is
    /// answered once it returns. A second registration replaces the first.
    ///
    /// - Parameters:
    ///   - act: the member, written with its contract.
    ///   - perform: given the arguments the contract declares, answering the values it declares. What it throws
    ///     fails the call, and the caller throws that reason.
    public static func add<
        Owner: ApplicationTier, each Argument: HostRepresentable, each Answer: HostRepresentable
    >(
        _ act: ElementAct<Owner, (repeat each Argument), (repeat each Answer)>,
        _ perform: @escaping @MainActor (repeat each Argument) async throws -> (repeat each Answer)
    ) {
        WinUIInterop.acts.add(act, perform)
    }

    /// Performs an act AIMED at one of the application's own elements, when the application calls it through an
    /// `Aim`: the performer is handed the element's control. An aim at nothing, or at an element no longer on
    /// screen, fails the call with that reason.
    ///
    ///     SwiftOmniUIActs.add(RatingBarContract.flash, on: RatingBarControl.self) { bar in
    ///         bar.flash()
    ///     }
    ///
    /// - Parameters:
    ///   - act: the member, written with its contract.
    ///   - control: the class the application's registration makes for the element.
    ///   - perform: given the element's control and the arguments the contract declares, answering the values it
    ///     declares.
    public static func add<
        Owner: Contract, Made: WinUIControl, each Argument: HostRepresentable, each Answer: HostRepresentable
    >(
        _ act: ElementAct<Owner, (repeat each Argument), (repeat each Answer)>,
        on control: Made.Type,
        _ perform: @escaping @MainActor (Made, repeat each Argument) async throws -> (repeat each Answer)
    ) {
        WinUIInterop.acts.add(act, control: { ($0 as? WinUIHostedView<Made>)?.control }, perform)
    }
}

/// The events an application raises through this host - the ones no control raises, heard by every
/// `HostEvents.on`.
public enum SwiftOmniUIEvents {
    /// Declares an event of the application's this host raises, where its source is wired: a handler listening for
    /// an event nothing declared is told, once, that it will not hear it.
    ///
    ///     SwiftOmniUIEvents.raises(GalleryContract.batteryChanged)
    ///
    /// - Parameter event: the member, written with its contract.
    @MainActor
    public static func raises<Owner: ApplicationTier, Payload>(_ event: ElementEvent<Owner, Payload>) {
        WinUIRegistrations.registry.raises(event)
    }

    /// Raises an event of the application's - one no control raises - with the values its contract declares.
    /// Every `HostEvents.on` subscription to the member hears it. Safe from any thread.
    ///
    ///     SwiftOmniUIEvents.raise(GalleryContract.batteryChanged, level, charging)
    ///
    /// - Parameters:
    ///   - event: the member, written with its contract.
    ///   - value: what it carries, in the order its contract declares.
    /// - Returns: how many subscriptions heard it - a raise nobody hears is an ordinary zero.
    @discardableResult
    public nonisolated static func raise<Owner: ApplicationTier, each Value: HostRepresentable>(
        _ event: ElementEvent<Owner, (repeat each Value)>,
        _ value: repeat each Value
    ) -> Int {
        CoreLink().raise(event, repeat each value)
    }
}

/// What an element of the APPLICATION'S OWN tells the application: an event of its own, and a value its user
/// changed. Handed to the control where it is made, so the control names members of its contract and never a
/// handler.
public struct WinUIReports<Realized: ElementContract> {
    private let reports: Reports<Realized>

    init(_ reports: Reports<Realized>) {
        self.reports = reports
    }

    /// Raises one of the element's own events with the values its contract declares.
    ///
    /// - Parameters:
    ///   - event: the member, written with its contract.
    ///   - value: what it carries, in the order its contract declares.
    public func raise<each Value: HostRepresentable>(
        _ event: ElementEvent<Realized, (repeat each Value)>,
        _ value: repeat each Value
    ) {
        reports.raise(event, repeat each value)
    }

    /// A value the USER changed: it lands on the state the element's value is carried in, and the event is raised
    /// with it.
    ///
    /// - Parameters:
    ///   - property: the value's member, written with its contract.
    ///   - value: what the user made it.
    ///   - event: the member the element raises for that change.
    public func report<Owner: Contract, Raised: Contract, Value: HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        _ value: Value,
        as event: ElementEvent<Raised, Value>
    ) {
        reports.report(property, value, as: event)
    }
}

/// The current values of an application's element during one property patch.
/// Read related members together without importing the core host SPI.
public struct WinUIElementValues<Realized: ElementContract> {
    private let values: ElementValues<Realized>

    init(_ values: ElementValues<Realized>) {
        self.values = values
    }

    public subscript<Owner: Contract, Value: HostRepresentable>(_ member: ElementProperty<Owner, Value>) -> Value? {
        values[member]
    }

    public func changed<Owner: Contract, Value: HostRepresentable>(_ member: ElementProperty<Owner, Value>) -> Bool {
        values.changed(member)
    }
}

/// How an application's own element is realized on this host, member by member: the properties its control takes,
/// and the events of its own it raises.
@MainActor
public final class WinUIRegistration<Realized: ElementContract, Made: WinUIControl> {
    private let registration: Registration<Realized, WinUIHostedView<Made>>

    init(_ registration: Registration<Realized, WinUIHostedView<Made>>) {
        self.registration = registration
    }

    /// A property the control takes, handed over as the type its contract declares - nil where the value is no
    /// longer described. A member of the element's contract or of a tier it wears; any other is refused, and said
    /// once.
    ///
    /// - Parameters:
    ///   - member: the property, written with its contract.
    ///   - apply: puts the value on the control.
    public func property<Owner: Contract, Value: HostRepresentable>(
        _ member: ElementProperty<Owner, Value>,
        _ apply: @escaping (Made, Value?) -> Void
    ) {
        registration.property(member) { hosted, value in apply(hosted.control, value) }
    }

    /// Applies related properties together, once per patch, so the control
    /// can install its content before resolving selections and navigation.
    /// `invalidatingLayout` names properties that require fresh native
    /// measurement even when `contentAffectsSize` is false, such as showing
    /// a pane that reallocates space inside a scrolling control.
    public func applies(
        _ members: [any ContractMember],
        invalidatingLayout layoutMembers: [any ContractMember] = [],
        _ apply: @escaping (Made, WinUIElementValues<Realized>) -> Void
    ) {
        let layoutProperties = Set(layoutMembers.map { Prop($0.name) })
        registration.applies(members) { hosted, values in
            hosted.registeredLayoutProperties.formUnion(layoutProperties)
            apply(hosted.control, WinUIElementValues(values))
        }
    }

    /// An event the control raises through its reports - recorded, so the core knows this host reports it.
    ///
    /// - Parameter event: the member, written with its contract.
    public func raises<Owner: Contract, Payload>(_ event: ElementEvent<Owner, Payload>) {
        registration.raises(event)
    }
}

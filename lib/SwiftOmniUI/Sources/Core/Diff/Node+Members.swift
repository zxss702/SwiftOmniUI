// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension [Prop: PropValue] {
    /// Writes one member's value into this map - a node's properties, or what
    /// a session keeps for the node it describes.
    mutating func write<Owner: Contract, Held: HostRepresentable>(
        _ property: ElementProperty<Owner, Held>,
        _ value: Held
    ) {
        self[property.token] = value.propValue
    }

    /// Writes one member's value into this map, or leaves the member
    /// undescribed where there is none - a setting taken as optional, whose
    /// absence the host reads as its own default.
    mutating func describe<Owner: Contract, Held: HostRepresentable>(
        _ property: ElementProperty<Owner, Held>,
        _ value: Held?
    ) {
        self[property.token] = value?.propValue
    }
}

extension Node {
    /// Disabled conditions accumulate. A false condition never re-enables an
    /// earlier modifier or an ancestor; the environment reaches composed/lazy
    /// content as well as the native element described by this node.
    mutating func disable(_ disabled: Bool) {
        props[.isEnabled] = .bool(props[.isEnabled]?.bool != false && !disabled)
        if disabled { environmentValues.isEnabled = false }
    }

    /// Native controls and visual-state rules consume the same answer as
    /// `@Environment(\.isEnabled)`. Do not put a default on every normal node.
    mutating func resolveEnabled(in values: EnvironmentValues) {
        if !values.isEnabled {
            props[.isEnabled] = .bool(false)
            driven[.isEnabled] = nil
        }
    }

    /// Button styles are a branch environment, including native menu triggers.
    mutating func resolveControlStyle(in scope: [(key: ObjectIdentifier, object: AnyObject)]) {
        guard type == .button || type == .menuButton,
              props[.buttonStyle] == nil, driven[.buttonStyle] == nil,
              let style = scope.last(where: { $0.key == ObjectIdentifier(ButtonStyle.self) })?.object as? ButtonStyle,
              style.kind != .automatic
        else { return }
        props[.buttonStyle] = style.kind.propValue
    }

    var controlContent: Node { isFrameWrapper ? children[0].controlContent : self }

    mutating func modifyControl(_ change: (inout Node) -> Void) {
        if isFrameWrapper { children[0].modifyControl(change) }
        else { change(&self) }
    }

    mutating func modifyContent<Owner: Contract>(for owner: Owner.Type, _ change: (inout Node) -> Void) {
        let type = ObjectIdentifier(owner)
        if isFrameWrapper && type != ObjectIdentifier(ViewContract.self)
            && type != ObjectIdentifier(VisualElementContract.self)
            && type != ObjectIdentifier(PropertyContainerContract.self) {
            children[0].modifyContent(for: owner, change)
        } else {
            change(&self)
        }
    }

    /// Writes one member's value into this node - what a modifier setting
    /// several members at once writes through, where `setValue` cannot chain.
    mutating func write<Owner: Contract, Value: HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        _ value: Value
    ) {
        modifyContent(for: Owner.self) { $0.props.write(property, value) }
    }

    /// A control member is direct; a container passes it to later content.
    mutating func writeOrInherit<Owner: Contract, Value: HostRepresentable>(
        _ property: ElementProperty<Owner, Value>, _ value: Value
    ) {
        modifyContent(for: Owner.self) { node in
            let owner = ObjectIdentifier(Owner.self)
            if LibraryContracts.byType[node.type]?.worn.contains(where: {
                ObjectIdentifier($0) == owner
            }) == true {
                node.props.write(property, value)
            } else {
                node.writeInherited(property, value)
            }
        }
    }

    /// Writes one member's value into this node, or leaves the member
    /// undescribed where there is none - a setting a modifier takes as
    /// optional, whose absence the host reads as its own default.
    mutating func describe<Owner: Contract, Value: HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        _ value: Value?
    ) {
        props.describe(property, value)
    }

    /// Writes one member's value here and on every element below wearing its
    /// contract - what an inheriting modifier writes, the way `.controlSize`
    /// reaches a `ProgressView`'s bar inside it. An element that names the
    /// member itself keeps its own, the way SwiftUI's inherited modifiers
    /// lose to an explicit one.
    mutating func writeInherited<Owner: Contract, Value: HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        _ value: Value
    ) {
        inherit(property.token, member: InheritedMember(
            owner: ObjectIdentifier(Owner.self), value: value.propValue))
    }

    mutating func inherit(_ property: Prop, member: InheritedMember) {
        var member = member
        let mergesAttributes = property == .fontAttributes && member.owner == ObjectIdentifier(FontElementContract.self)
        if mergesAttributes {
            let incoming = FontAttributes(propValue: member.value) ?? .none
            let pending = inheritedMembers[property].flatMap { FontAttributes(propValue: $0.value) } ?? .none
            let own = props[property].flatMap(FontAttributes.init(propValue:)) ?? .none
            member = InheritedMember(owner: member.owner, value: own.union(pending).union(incoming).propValue)
        }
        if hasExplicitFontBasis, member.owner == ObjectIdentifier(FontElementContract.self),
           property == .fontSize || property == .fontTextStyle || property == .fontFamily {
            return
        }
        guard inheritedMembers[property] == nil || (mergesAttributes && inheritedMembers[property] != member) else { return }
        inheritedMembers[property] = member
        if !member.isDefault, LibraryContracts.byType[type]?.worn.contains(where: {
            ObjectIdentifier($0) == member.owner
        }) == true, props[property] == nil || mergesAttributes {
            props[property] = member.value
        }
        for index in children.indices {
            children[index].inherit(property, member: member)
        }
    }

    // Design: docs/design/types/brushes.md#foreground-fill
    mutating func writeForeground(_ brush: Brush, textIsExplicit: Bool = false) {
        inherit(.fill, member: InheritedMember(
            owner: ObjectIdentifier(ShapeContract.self), value: brush.propValue, isDefault: true))
        if let color = brush.firstColor {
            if textIsExplicit { writeOrInherit(TextStyleElementContract.foregroundStyle, color) }
            else { writeInherited(TextStyleElementContract.foregroundStyle, color) }
        }
    }

    mutating func resolveShapeFill() {
        guard LibraryContracts.byType[type]?.worn.contains(where: {
            ObjectIdentifier($0) == ObjectIdentifier(ShapeContract.self)
        }) == true else { return }
        let paint: [Prop] = [.fill, .stroke, .strokeBorder]
        guard paint.allSatisfy({ props[$0] == nil && driven[$0] == nil }) else { return }
        props[.fill] = inheritedMembers[.fill]?.value ?? Brush.solidColor(.primary).propValue
    }
}

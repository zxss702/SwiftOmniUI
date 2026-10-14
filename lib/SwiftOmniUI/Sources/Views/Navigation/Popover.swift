// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.popover`: a transient view anchored to the element that carries it.
// Design: docs/design/views/pages.md

/// The element a `.popover` modifier hangs off its anchor: the popover card,
/// carrying what `content:` names, driven by `isPresented:`.
struct Popover<Content: View>: View {

    /// What the modifier keeps.
    var node: Node
    private let content: () -> Content

    /// - Parameters:
    ///   - isPresented: whether the popover shows, both ways.
    ///   - arrowEdge: the edge of the anchor its arrow prefers to stand on.
    ///   - content: the popover's view.
    init(isPresented: Binding<Bool>, arrowEdge: Edge,
         @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        var node = Node(contract: PopoverContract.self)
        node.producer = { isPresented.wrappedValue ? content().node.asChildren : [] }
        node.props[.arrowEdge] = arrowEdge.propValue
        node.drivePlain(PopoverContract.isOpen, by: isPresented)
        node.environmentValues[keyPath: \.dismiss] = DismissAction { [isPresented] in
            isPresented.wrappedValue = false
        }
        node.addHandler(PopoverContract.dismissed.token) {
            isPresented.wrappedValue = false
        }
        self.node = node
    }
}

/// A `PropertyContainer`, so the members a `.popover` builds can be carried
/// like a control's.
extension Popover: PropertyContainer {

    /// Whether the popover shows, by what the value says.
    @_spi(Host) public func isOpen(_ value: Bool) -> Popover {
        let content = content
        return modified {
            $0.driven[.isOpen] = nil
            $0.write(PopoverContract.isOpen, value)
            $0.producer = { value ? content().node.asChildren : [] }
        }
    }

    /// Whether the popover shows, by what the binding says.
    @_spi(Host) public func isOpen(_ binding: Binding<Bool>) -> Popover {
        let content = content
        return modified {
            $0.drivePlain(PopoverContract.isOpen, by: binding)
            $0.producer = { binding.wrappedValue ? content().node.asChildren : [] }
            $0.environmentValues[keyPath: \.dismiss] = DismissAction { binding.wrappedValue = false }
            $0.events[.dismissed] = { binding.wrappedValue = false }
        }
    }

    /// The edge of the anchor the popover's arrow prefers to stand on.
    @_spi(Host) public func arrowEdge(_ value: Edge) -> Popover {
        setValue(PopoverContract.arrowEdge, value)
    }
}

extension View {
    /// A small view presented beside this one while `isPresented` holds - the
    /// platform's own anchored presentation: a popover, a flyout, a panel
    /// under the view it hangs off:
    ///
    ///     Button("Rename", action: { renaming = true })
    ///         .popover(isPresented: $renaming, arrowEdge: .bottom) {
    ///             RenameForm()
    ///         }
    ///
    /// Writing `true` presents, writing `false` closes, and a dismissal the
    /// user makes - a click beside it, the platform's own gesture - writes
    /// `false` back. Where the bigger `sheet` is a page over the window, a
    /// popover is a card off one view: keep to it what asks for a tap or two.
    ///
    /// - Parameters:
    ///   - isPresented: whether the popover shows, both ways.
    ///   - arrowEdge: the edge of the anchor its arrow prefers to stand on.
    ///   - content: the popover's view.
    public func popover<Content: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> ModifiedContent {
        revised { node in
            node.children.append(Popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                content()
            }.node)
        }
    }
}

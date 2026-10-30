// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.sheet`: a view presented over the window, driven by a bool.
// Design: docs/design/views/pages.md#the-modal-stack-is-a-value

extension View {
    /// A page presented modally over the window while `isPresented` holds.
    ///
    ///     @State private var editing = false
    ///
    ///     Button("Edit", action: { editing = true })
    ///         .sheet(isPresented: $editing) { EditorSheet() }
    ///
    /// Writing `true` presents, writing `false` closes, and a dismissal the
    /// user makes - the platform's own gesture or button - writes `false`
    /// back. The presentation rides the window's `ModalStack`, so the content
    /// is a page in every sense the stack's own destinations are: it can hold
    /// a navigation of its own.
    ///
    /// Where several views offer a sheet at once the window takes the last to
    /// present, as one modal can stand over it at a time.
    ///
    /// - Parameters:
    ///   - isPresented: whether the sheet is up, both ways.
    ///   - content: the sheet's page, built when it is presented.
    public func sheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SheetAnchor(base: self, presented: isPresented, sheet: content)
    }

    /// A page presented modally over the window while `item` is non-nil, the
    /// item handed to the content:
    ///
    ///     @State private var request: CloneRequest?
    ///
    ///     TableOfRequests()
    ///         .sheet(item: $request) { request in
    ///             CloneSheet(request: request)
    ///         }
    ///
    /// Writing an item presents, writing `nil` closes, and a dismissal the
    /// user makes writes `nil` back. As with `sheet(isPresented:)` the page
    /// rides the window's `ModalStack`; a change to another non-nil item
    /// swaps the page the one presentation shows. An item is its `id` - a
    /// different value under the same identity keeps the one presentation.
    ///
    /// - Parameters:
    ///   - item: what to show, both ways.
    ///   - content: the sheet's page for the item.
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        ItemSheetAnchor(base: self, item: item, sheet: content)
    }
}

/// The anchor `.sheet` leaves in the tree: the view it was written on, plus a
/// hook that turns the binding into the window's modal stack and back.
struct SheetAnchor<Content: View>: View {
    /// The view `.sheet` was written on.
    let base: any View

    /// Whether the sheet is up.
    let presented: Binding<Bool>

    /// The sheet's page.
    let sheet: () -> Content

    /// The window this anchor presents over.
    @Environment var window: WindowSession

    /// One ticket while the sheet is up, none once it is gone - which is how
    /// the user's own dismissal is heard.
    @State private var tickets: [Int] = []

    var body: some View {
        base
            // Only the anchor that presented clears the stack - the window's
            // own modal stack is not this one's to take down.
            .onChange(of: presented.wrappedValue, initial: true) { _, shown in
                if shown {
                    tickets = [0]
                    window.modalStack = ModalStack($tickets) { _ in
                        sheet().environment(
                            \.dismiss, DismissAction { [presented] in
                                presented.wrappedValue = false
                            })
                    }
                } else if !tickets.isEmpty {
                    tickets = []
                    window.modalStack = nil
                }
            }
            .onChange(of: tickets) { _, remaining in
                if remaining.isEmpty { presented.wrappedValue = false }
            }
    }
}

/// The anchor `sheet(item:)` leaves in the tree - `SheetAnchor` keyed by an
/// item instead of a bool.
struct ItemSheetAnchor<Item: Identifiable, Content: View>: View {
    /// The view `.sheet` was written on.
    let base: any View

    /// What is presented, nil for nothing.
    let item: Binding<Item?>

    /// The sheet's page for one item.
    let sheet: (Item) -> Content

    /// The window this anchor presents over.
    @Environment var window: WindowSession

    /// The item in stack form - one element while the sheet is up.
    @State private var tickets: [Ticket] = []

    var body: some View {
        base
            .onChange(of: item.wrappedValue?.id != nil, initial: true) { _, shown in
                if shown, let presented = item.wrappedValue {
                    tickets = [Ticket(presented)]
                    window.modalStack = ModalStack($tickets) { [item] shown in
                        sheet(shown.item).environment(
                            \.dismiss, DismissAction { item.wrappedValue = nil })
                    }
                } else if !tickets.isEmpty {
                    tickets = []
                    window.modalStack = nil
                }
            }
            .onChange(of: item.wrappedValue?.id) { _, _ in
                if let presented = item.wrappedValue, !tickets.isEmpty,
                   tickets.first?.id != presented.id {
                    tickets = [Ticket(presented)]
                }
            }
            .onChange(of: tickets) { _, remaining in
                if remaining.isEmpty { item.wrappedValue = nil }
            }
    }

    /// One presented item in the modal stack. The stack asks `Hashable`, and
    /// an item is its `id` - equal identities are the one presentation, and
    /// the `id` alone names the page.
    struct Ticket: Hashable, CustomStringConvertible {
        /// The item the sheet's page is built for.
        let item: Item

        /// Who the item is - all the stack's `Hashable` needs.
        var id: Item.ID { item.id }

        var description: String { String(describing: id) }

        init(_ item: Item) { self.item = item }

        static func == (a: Ticket, b: Ticket) -> Bool { a.item.id == b.item.id }

        func hash(into hasher: inout Hasher) { item.id.hash(into: &hasher) }
    }
}

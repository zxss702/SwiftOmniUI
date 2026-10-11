import SwiftOmniUI

/// The item is a row's identity - what keeps a control across a change to
/// the list around it, and what a written `.id()` overrides.
struct IdentitySample: SampleContent, ExampleContent {
    @State private var items = ["Alpha", "Beta", "Gamma"]
    @State private var nextItem = 1

    static let id = "identity"
    static let title = "Identity and reuse"
    static let summary = "Same identity, same control - which is what keeps focus, caret and scroll."

    static let code = """
        @State var items = ["Alpha", "Beta", "Gamma"]
        @State private var nextItem = 1

        VStack {
            HStack {
                Button("Add", action: {
                        items.append("Item \\(nextItem)")
                        nextItem += 1
                    })
                    

                Button("Insert at the top", action: {
                        items.insert("Item \\(nextItem)", at: 0)
                        nextItem += 1
                    })
                    

                Button("Rotate", action: {
                        items = Array(items.dropFirst()) + [items[0]]
                    })
                    .disabled(items.count <= 1)
                    
            }

            // Each row is identified by its ITEM - ForEach's rule - so
            // inserting at the top MOVES the controls already on screen.
            VStack {
                // The list is described again on every change, and the rows
                // keep their controls through it - which is what identity is.

                ForEach(items) { item in
                    IdentityRow(item: item, items: $items)
                }
            }
        }

        private struct IdentityRow: View {
            let item: String
            @Binding var items: [String]
            @State private var typed = ""

            var body: some View {
                HStack {
                    Text(item)
                        .frame(width: 90)

                    TextField("type here", text: $typed)
                        .frame(maxWidth: .infinity)

                    Button("Remove", action: {
                            items = items.filter { $0 != item }
                        })
                        
                }
            }
        }
        """

    var body: some View {
        VStack {
            HStack {
                Button("Add", action: {
                        items.append("Item \(nextItem)")
                        nextItem += 1
                    })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Insert at the top", action: {
                        items.insert("Item \(nextItem)", at: 0)
                        nextItem += 1
                    })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Rotate", action: {
                        items = Array(items.dropFirst()) + [items[0]]
                    })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(items.count <= 1)
                    
            }
            .spacing(10)

            // Each row is identified by its ITEM - ForEach's rule, and the
            // reason a plain `for` does not compile here: known by position,
            // an inserted row would rewrite every row into the one below it.
            // A row may still write `.id()` of its own, and the author's wins.
            VStack {

                ForEach(items) { item in
                    IdentityRow(item: item, items: $items)                    
                }
            }
            .spacing(6)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Type in a field, then insert a row above it: the text stays where it "
                + "is, because the control did.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A row is identified by its item, which is `ForEach`'s rule. Known by "
                + "position, an inserted row would rewrite every row into the one below "
                + "it, which is why a plain `for` does not compile here. A row may still "
                + "write an `.id()` of its own, and the author's wins.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}

/// One row, with something worth keeping in it: what is typed lives in the
/// control, not in the tree.
private struct IdentityRow: View {
    let item: String
    @Binding var items: [String]
    @State private var typed = ""

    var body: some View {
        HStack {
            Text(item)
                .font(.system(size: 15))
                .frame(width: 90)

            TextField("type here", text: $typed)
                .accessibilityIdentifier("identity.typed")
                .accessibilityLabel("Anything typed here")
                .frame(maxWidth: .infinity)

            Button("Remove", action: {
                    items = items.filter { $0 != item }
                })
                .font(.system(size: 12))
                .padding(EdgeInsets(12, 6))
                
        }
        .spacing(10)
    }
}

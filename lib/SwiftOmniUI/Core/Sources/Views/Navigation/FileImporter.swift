// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.fileImporter`: the platform's own file-open panel, driven by a bool.

extension View {
    /// The platform's file-open panel, up while `isPresented` holds.
    ///
    ///     @State private var picking = false
    ///
    ///     Button("Import", action: { picking = true })
    ///         .fileImporter(isPresented: $picking) { result in
    ///             if case .success(let paths) = result { import(paths) }
    ///         }
    ///
    /// Writing `true` opens the panel, and either an answer - the paths the
    /// user picked - or their cancelling writes it `false` again. A path is
    /// whatever the platform calls a file, so a library that holds no
    /// `Foundation` can still hand it back: turn it into a `URL` where one is
    /// wanted with `URL(fileURLWithPath:)`. Cancelling answers
    /// `.failure`, as SwiftUI's does.
    ///
    /// - Parameters:
    ///   - isPresented: whether the panel is up, both ways.
    ///   - allowsMultipleSelection: whether several files may be picked.
    ///   - onCompletion: what runs with the answer - picked paths, or a
    ///     `.failure` when the user cancelled or the platform could not ask.
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[String], SwiftOmniUIError>) -> Void
    ) -> some View {
        FileImporterAnchor(
            base: self, presented: isPresented, types: [],
            multiple: allowsMultipleSelection, onCompletion: onCompletion)
    }

    /// The platform's file-open panel, its offering narrowed to files whose
    /// name ends in one of `types`.
    ///
    ///     .fileImporter(
    ///         isPresented: $picking, allowedTypes: ["md", "markdown"])
    ///     { result in … }
    ///
    /// The extensions are the platform's own filter - a `markdown` written
    /// here lets the panel offer every file it knows by that ending. An empty
    /// list is the plain overload: everything may be picked.
    ///
    /// - Parameters:
    ///   - isPresented: whether the panel is up, both ways.
    ///   - types: the extensions the panel narrows to, without the dot.
    ///   - allowsMultipleSelection: whether several files may be picked.
    ///   - onCompletion: what runs with the answer.
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedTypes types: [String],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[String], SwiftOmniUIError>) -> Void
    ) -> some View {
        FileImporterAnchor(
            base: self, presented: isPresented, types: types,
            multiple: allowsMultipleSelection, onCompletion: onCompletion)
    }
}

/// The anchor `.fileImporter` leaves in the tree: the view it was written on,
/// plus a hook that turns the binding into a `chooseFiles` act and back.
struct FileImporterAnchor: View {
    /// The view `.fileImporter` was written on.
    let base: any View

    /// Whether the panel is up.
    let presented: Binding<Bool>

    /// The extensions the panel narrows to; empty for everything.
    let types: [String]

    /// Whether several files may be picked.
    let multiple: Bool

    /// What runs with the answer.
    let onCompletion: (Result<[String], SwiftOmniUIError>) -> Void

    /// Whether a panel is already asking - a `true` that lands while one is
    /// waits for nothing of its own.
    @State private var asking = false

    var body: some View {
        base
            .onChange(of: presented.wrappedValue) { _, shown in
                guard shown, !asking else { return }
                asking = true
                do {
                    let paths = try await stateUICall(AppContract.chooseFiles, multiple, types)
                    asking = false
                    presented.wrappedValue = false
                    if paths.isEmpty {
                        onCompletion(.failure(SwiftOmniUIError(message: "the user cancelled")))
                    } else {
                        onCompletion(.success(paths))
                    }
                } catch let error as SwiftOmniUIError {
                    asking = false
                    presented.wrappedValue = false
                    onCompletion(.failure(error))
                }
            }
    }
}

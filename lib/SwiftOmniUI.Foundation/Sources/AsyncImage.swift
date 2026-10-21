// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@_spi(Host) import SwiftOmniUICore

/// The loading state of an image requested by URL.
public enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(any Error)

    public var image: Image? { if case .success(let image) = self { image } else { nil } }
    public var error: (any Error)? { if case .failure(let error) = self { error } else { nil } }
}

/// Loads file and network images without blocking layout. The platform's image
/// decoder draws the resulting file; URLSession supplies caching and transport.
public struct AsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content
    @State private var phase = AsyncImagePhase.empty

    public init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        // The loading job belongs to a stable layout, not the phase's leaf.
        // Empty -> Image changes the leaf type; attaching the job there would
        // cancel/restart it and continuously reset the phase back to empty.
        ZStack { content(phase) }.task(id: url) {
            phase = .empty
            guard let url else { return }
            do {
                let file = try await AsyncImageFiles.shared.file(for: url)
                try Task.checkCancellation()
                phase = .success(Image(ImageSource(asyncImagePath(file))))
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failure(error)
            }
        }
    }
}

private actor AsyncImageFiles {
    static let shared = AsyncImageFiles()
    private var requests: [URL: Task<URL, any Error>] = [:]

    func file(for url: URL) async throws -> URL {
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: asyncImagePath(url)) else {
                throw URLError(.fileDoesNotExist)
            }
            return url
        }
        if let request = requests[url] { return try await request.value }
        if requests.count >= 128 { requests.removeAll(keepingCapacity: true) }
        let request = Task<URL, any Error> {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftOmniUI-Images", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let suffix = url.pathExtension.isEmpty ? "image" : url.pathExtension
            let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
            try data.write(to: file, options: .atomic)
            return file
        }
        requests[url] = request
        do { return try await request.value }
        catch { requests[url] = nil; throw error }
    }
}

private func asyncImagePath(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    #if os(Windows)
    if path.hasPrefix("/"), path.dropFirst(2).hasPrefix(":") { path.removeFirst() }
    #endif
    return path
}

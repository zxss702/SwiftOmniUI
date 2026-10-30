//
//  NIOURLSession.swift
//  SwiftOmniUINetworking
//
//  Created by Codex on 2026-10-16.
//

#if os(Linux)
import Foundation
import AsyncHTTPClient
import NIOCore

/// Source-compatible transport for desktop async URLSession calls. It never
/// constructs FoundationNetworking.URLSession, including for redirects/TLS.
/// Foundation request, response and configuration types remain interoperable.
/// Supports async data/upload/download and session invalidation. Delegate/task
/// subclass APIs, WebSockets, URLProtocol and background sessions are outside
/// this adapter. Separately compiled dependencies keep their own transport.
public final class NIOURLSession: NSObject, @unchecked Sendable {
    public static let shared = NIOURLSession(configuration: .default, shared: true)

    private let transport: NIOHTTPTransport
    private let responseCache: NIOResponseCache
    private let isShared: Bool
    private let lock = NSLock()
    private var invalidated = false
    private var operations: [UUID: NIOSessionCancellation] = [:]
    private var descriptionValue: String?

    public var configuration: URLSessionConfiguration {
        transport.configuration.copy() as! URLSessionConfiguration
    }

    public var sessionDescription: String? {
        get { lock.withLock { descriptionValue } }
        set { lock.withLock { descriptionValue = newValue } }
    }

    public override convenience init() { self.init(configuration: .default) }

    public convenience init(configuration: URLSessionConfiguration) {
        self.init(configuration: configuration, shared: false)
    }

    private init(configuration: URLSessionConfiguration, shared: Bool) {
        transport = NIOHTTPTransport(configuration: configuration)
        responseCache = NIOResponseCache(configuration: configuration)
        isShared = shared
        super.init()
    }

    deinit {
        for operation in operations.values { operation.cancel() }
        // The running closures retain their transport until body consumption
        // ends. Its deinit asynchronously shuts down pools, never event loops.
    }

    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: request(for: url))
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let cache = responseCache
        let transport = transport
        let request = transport.addingSessionHeaders(to: request)
        return try await run(url: request.url) {
            if let cached = try cache.cachedResponse(for: request) {
                return (cached.data, cached.response)
            }
            return try await transport.perform(request) { body, response in
                var data = Data()
                // URLSession.data has no arbitrary 64-MiB response ceiling.
                // Downloads below stream to disk instead of collecting here.
                for try await buffer in body {
                    try Task.checkCancellation()
                    data.append(contentsOf: buffer.readableBytesView)
                }
                try Task.checkCancellation()
                cache.store(data, response: response, for: request)
                return (data, response as URLResponse)
            }
        }
    }

    public func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        try await upload(request, body: .data(bodyData))
    }

    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        try await upload(request, body: .file(fileURL))
    }

    private func upload(_ request: URLRequest, body: NIOHTTPTransport.UploadBody) async throws -> (Data, URLResponse) {
        let transport = transport
        return try await run(url: request.url) {
            try await transport.perform(request, body: body) { bytes, response in
                var data = Data()
                for try await buffer in bytes {
                    try Task.checkCancellation()
                    data.append(contentsOf: buffer.readableBytesView)
                }
                try Task.checkCancellation()
                return (data, response as URLResponse)
            }
        }
    }

    public func download(from url: URL) async throws -> (URL, URLResponse) {
        try await download(for: request(for: url))
    }

    public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        let transport = transport
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            return try await run(url: request.url) {
                try await transport.perform(request) { bytes, response in
                    let file = try await NIODownloadFile.create(at: fileURL)
                    do {
                        for try await buffer in bytes {
                            try Task.checkCancellation()
                            try await file.write(Data(buffer.readableBytesView))
                        }
                        try Task.checkCancellation()
                        try await file.close()
                        return (file.url, response as URLResponse)
                    } catch {
                        await file.discard()
                        throw error
                    }
                }
            }
        } catch {
            // Also covers a resource deadline / caller cancellation racing with
            // the successful body consumer after it has closed the temporary file.
            _ = await Task.detached { try? FileManager.default.removeItem(at: fileURL) }.value
            throw error
        }
    }

    /// Like the system shared session, the shared transport is process-owned.
    public func invalidateAndCancel() {
        guard !isShared else { return }
        let active = lock.withLock { () -> [NIOSessionCancellation] in
            invalidated = true
            return Array(operations.values)
        }
        for operation in active { operation.cancel() }
        if active.isEmpty { transport.shutdown() }
    }

    public func finishTasksAndInvalidate() {
        guard !isShared else { return }
        let empty = lock.withLock { () -> Bool in
            invalidated = true
            return operations.isEmpty
        }
        if empty { transport.shutdown() }
    }

    private func request(for url: URL) -> URLRequest {
        URLRequest(url: url, cachePolicy: transport.configuration.requestCachePolicy,
                   timeoutInterval: transport.configuration.timeoutIntervalForRequest)
    }

    private func run<Value: Sendable>(
        url: URL?, _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            try Task.checkCancellation()
            let id = UUID()
            let cancellation = NIOSessionCancellation()
            let accepted = lock.withLock { () -> Bool in
                guard !invalidated else { return false }
                operations[id] = cancellation
                return true
            }
            guard accepted else { throw URLError(.cancelled) }
            defer {
                let shouldClose = lock.withLock { () -> Bool in
                    operations[id] = nil
                    return invalidated && operations.isEmpty
                }
                if shouldClose { transport.shutdown() }
            }
            let task = Task {
                try cancellation.check()
                try Task.checkCancellation()
                return try await operation()
            }
            cancellation.attach { task.cancel() }
            return try await withTaskCancellationHandler {
                let result = try await task.value
                try cancellation.check()
                try Task.checkCancellation()
                return result
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            throw urlError(error, url: url)
        }
    }
}

/// Covers cancellation before the Swift task has been installed, as well as
/// session invalidation concurrent with a request starting.
private final class NIOSessionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var cancelTask: (@Sendable () -> Void)?

    func attach(_ cancel: @escaping @Sendable () -> Void) {
        let alreadyCancelled = lock.withLock { () -> Bool in
            cancelTask = cancel
            return cancelled
        }
        if alreadyCancelled { cancel() }
    }

    func cancel() {
        let cancel = lock.withLock { () -> (@Sendable () -> Void)? in
            cancelled = true
            return cancelTask
        }
        cancel?()
    }

    func check() throws {
        if lock.withLock({ cancelled }) { throw URLError(.cancelled) }
    }
}

/// Blocking filesystem work runs off NIO/UI executors. The file is private to
/// one download until it succeeds; cancellation/error always removes it.
private actor NIODownloadFile {
    nonisolated let url: URL
    private var handle: FileHandle?

    private init(url: URL, handle: FileHandle) { self.url = url; self.handle = handle }

    static func create(at url: URL) async throws -> NIODownloadFile {
        try await Task.detached {
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                attributes: [.posixPermissions: 0o600]) else {
                throw URLError(.cannotCreateFile)
            }
            do { return try NIODownloadFile(url: url, handle: FileHandle(forWritingTo: url)) }
            catch { try? FileManager.default.removeItem(at: url); throw error }
        }.value
    }

    func write(_ data: Data) throws {
        guard let handle else { throw URLError(.cannotWriteToFile) }
        try handle.write(contentsOf: data)
    }

    func close() throws {
        try handle?.close()
        handle = nil
    }

    func discard() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: url)
    }
}
#endif

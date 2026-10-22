//
//  NIOHTTPTransport.swift
//  SwiftOmniUINetworking
//
//  Created by Codex on 2026-10-16.
//

#if os(Linux)
import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import Glibc

/// Owns HTTP pools, not event-loop threads. Every pool shares NIO's singleton
/// event-loop group, also used by SwiftOpenAI, and is shut down asynchronously.
final class NIOHTTPTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [TimeInterval: HTTPClient] = [:]
    private var closed = false
    let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }

    func shutdown() {
        let clients = lock.withLock { () -> [HTTPClient] in
            guard !closed else { return [] }
            closed = true
            defer { self.clients.removeAll() }
            return Array(self.clients.values)
        }
        for client in clients { client.shutdown { _ in } }
    }

    deinit { shutdown() }

    private func client(idleTimeout: TimeInterval) throws -> HTTPClient {
        let idleTimeout = idleTimeout > 0 && idleTimeout.isFinite ? idleTimeout : 0
        return try lock.withLock {
            guard !closed else { throw URLError(.cancelled) }
            if let client = clients[idleTimeout] { return client }
            var settings = HTTPClient.Configuration()
            settings.redirectConfiguration = .disallow
            settings.decompression = .enabled(limit: .none)
            settings.timeout = .init(
                connect: nioTime(idleTimeout), read: nioTime(idleTimeout), write: nioTime(idleTimeout))
            settings.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit =
                max(1, configuration.httpMaximumConnectionsPerHost)
            let client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: settings)
            clients[idleTimeout] = client
            return client
        }
    }

    enum UploadBody: Sendable {
        case data(Data)
        case file(URL)
    }

    func addingSessionHeaders(to original: URLRequest) -> URLRequest {
        var request = original
        for (name, value) in configuration.httpAdditionalHeaders ?? [:] {
            let name = String(describing: name)
            if request.value(forHTTPHeaderField: name) == nil {
                request.setValue(String(describing: value), forHTTPHeaderField: name)
            }
        }
        return request
    }

    /// The resource deadline covers redirects AND body consumption. AHC's
    /// execute deadline alone ends at the response headers, which is too early.
    func perform<Value: Sendable>(
        _ original: URLRequest,
        body: UploadBody? = nil,
        consume: @escaping @Sendable (HTTPClientResponse.Body, HTTPURLResponse) async throws -> Value
    ) async throws -> Value {
        do {
            return try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask { [self] in
                    let (response, head) = try await self.response(for: original, body: body)
                    return try await consume(response.body, head)
                }
                let timeout = configuration.timeoutIntervalForResource
                if timeout > 0, timeout.isFinite {
                    group.addTask {
                        try await Task.sleep(nanoseconds: nanoseconds(timeout))
                        throw URLError(.timedOut)
                    }
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw URLError(.cancelled) }
                return result
            }
        } catch {
            throw urlError(error, url: original.url)
        }
    }

    private func response(
        for original: URLRequest, body: UploadBody?
    ) async throws -> (HTTPClientResponse, HTTPURLResponse) {
        guard let initialURL = original.url else { throw URLError(.badURL) }
        guard ["http", "https"].contains(initialURL.scheme?.lowercased() ?? "") else {
            throw URLError(.unsupportedURL)
        }
        var request = addingSessionHeaders(to: original)
        // URLRequest's public default is 60 seconds; a session's configured
        // request timeout supplies the default when the request leaves it alone.
        let timeout = request.timeoutInterval == 60
            ? configuration.timeoutIntervalForRequest : request.timeoutInterval
        let client = try self.client(idleTimeout: timeout)
        var redirectedBody = body
        var visited: Set<URL> = [initialURL]

        for redirect in 0...20 {
            try Task.checkCancellation()
            guard let url = request.url else { throw URLError(.badURL) }
            var outgoing = HTTPClientRequest(url: url.absoluteString)
            outgoing.method = HTTPMethod(rawValue: request.httpMethod ?? "GET")
            for (name, value) in request.allHTTPHeaderFields ?? [:] {
                outgoing.headers.add(name: name, value: value)
            }
            if configuration.httpShouldSetCookies, request.httpShouldHandleCookies,
               outgoing.headers["Cookie"].isEmpty,
               let cookies = configuration.httpCookieStorage?.cookies(for: url), !cookies.isEmpty {
                for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                    outgoing.headers.add(name: name, value: value)
                }
            }
            switch redirectedBody {
            case .data(let data): outgoing.body = .bytes(data)
            case .file(let file):
                guard let stream = InputStream(url: file) else { throw URLError(.fileDoesNotExist) }
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                outgoing.body = .stream(NIOInputStreamBody(stream), length: size.map { .known(Int64($0)) } ?? .unknown)
            case nil:
                if let data = request.httpBody {
                    outgoing.body = .bytes(data)
                } else if let stream = request.httpBodyStream {
                    // A caller-supplied stream is single-use, unlike a file URL.
                    if redirect > 0 { throw URLError(.requestBodyStreamExhausted) }
                    outgoing.body = .stream(NIOInputStreamBody(stream), length: .unknown)
                }
            }
            // Request timeout measures inactivity; progress resets NIO's read /
            // write timers. The resource timer in perform bounds the whole task.
            let response = try await client.execute(outgoing, deadline: .distantFuture)
            var fields: [String: String] = [:]
            for (name, value) in response.headers {
                // HTTPURLResponse has a dictionary-shaped public API; cookies
                // below are parsed separately so Expires commas are not split.
                let existing = fields.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame }
                if let existing { fields[existing, default: ""] += ", " + value }
                else { fields[name] = value }
            }
            guard let head = HTTPURLResponse(
                url: url, statusCode: Int(response.status.code),
                httpVersion: "HTTP/\(response.version.major).\(response.version.minor)", headerFields: fields
            ) else { throw URLError(.badServerResponse) }
            if configuration.httpShouldSetCookies, request.httpShouldHandleCookies,
               configuration.httpCookieAcceptPolicy != .never {
                for header in response.headers["Set-Cookie"] {
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url)
                    configuration.httpCookieStorage?.setCookies(cookies, for: url, mainDocumentURL: request.mainDocumentURL)
                }
            }
            let status = Int(response.status.code)
            guard [301, 302, 303, 307, 308].contains(status),
                  let location = response.headers.first(name: "Location"),
                  let target = URL(string: location, relativeTo: url)?.absoluteURL,
                  ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
                // HTTP error statuses are responses, not transport errors.
                return (response, head)
            }
            guard redirect < 20, visited.insert(target).inserted else {
                throw URLError(.httpTooManyRedirects)
            }
            let sameOrigin = url.scheme?.lowercased() == target.scheme?.lowercased()
                && url.host?.lowercased() == target.host?.lowercased()
                && effectivePort(url) == effectivePort(target)
            if !sameOrigin {
                request.setValue(nil, forHTTPHeaderField: "Authorization")
                request.setValue(nil, forHTTPHeaderField: "Proxy-Authorization")
                request.setValue(nil, forHTTPHeaderField: "Cookie")
            }
            request.setValue(nil, forHTTPHeaderField: "Host")
            let method = request.httpMethod?.uppercased() ?? "GET"
            if (status == 303 && method != "HEAD") || ([301, 302].contains(status) && method == "POST") {
                request.httpMethod = "GET"
                request.httpBody = nil
                request.httpBodyStream = nil
                redirectedBody = nil
                request.setValue(nil, forHTTPHeaderField: "Content-Length")
                request.setValue(nil, forHTTPHeaderField: "Content-Type")
                request.setValue(nil, forHTTPHeaderField: "Transfer-Encoding")
            }
            request.url = target
        }
        throw URLError(.httpTooManyRedirects)
    }
}

/// InputStream itself is not Sendable. This wrapper exclusively owns it and
/// reads serially on the blocking-I/O executor, never on an NIO event loop or UI
/// actor. Uploads keep bounded buffers instead of reading whole files into RAM.
private final class NIOInputStreamBody: AsyncSequence, @unchecked Sendable {
    typealias Element = ByteBuffer
    private let lock = NSLock()
    private let stream: InputStream
    private var opened = false
    private var ended = false

    init(_ stream: InputStream) { self.stream = stream }
    deinit { stream.close() }

    struct AsyncIterator: AsyncIteratorProtocol {
        let owner: NIOInputStreamBody
        mutating func next() async throws -> ByteBuffer? {
            try Task.checkCancellation()
            let owner = owner
            return try await Task.detached { try owner.read() }.value
        }
    }

    func makeAsyncIterator() -> AsyncIterator { .init(owner: self) }

    private func read() throws -> ByteBuffer? {
        try lock.withLock {
            guard !ended else { return nil }
            if !opened { stream.open(); opened = true }
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            let capacity = bytes.count
            let count = stream.read(&bytes, maxLength: capacity)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotOpenFile) }
            if count == 0 { ended = true; stream.close(); return nil }
            return ByteBuffer(bytes: bytes.prefix(count))
        }
    }
}

func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
    UInt64(min(max(0, seconds) * 1_000_000_000, Double(UInt64.max / 2)))
}

private func nioTime(_ seconds: TimeInterval) -> TimeAmount {
    guard seconds > 0, seconds.isFinite else { return .nanoseconds(Int64.max / 2) }
    return .nanoseconds(Int64(min(nanoseconds(seconds), UInt64(Int64.max / 2))))
}

private func effectivePort(_ url: URL) -> Int? {
    url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
}

func urlError(_ error: Error, url: URL?) -> URLError {
    if let error = error as? URLError { return error }
    let code: URLError.Code
    if error is CancellationError || (error as? HTTPClientError) == .cancelled {
        code = .cancelled
    } else if let http = error as? HTTPClientError {
        switch http {
        case .deadlineExceeded, .connectTimeout, .readTimeout, .writeTimeout,
             .tlsHandshakeTimeout, .getConnectionFromPoolTimeout: code = .timedOut
        case .invalidURL, .emptyHost, .emptyScheme: code = .badURL
        case .redirectLimitReached, .redirectCycleDetected: code = .httpTooManyRedirects
        case .remoteConnectionClosed: code = .networkConnectionLost
        case .alreadyShutdown: code = .cancelled
        default: code = .unknown
        }
    } else if error is SocketAddressError.UnknownHost {
        code = .cannotFindHost
    } else if let channel = error as? ChannelError {
        switch channel {
        case .connectTimeout: code = .timedOut
        case .eof, .ioOnClosedChannel: code = .networkConnectionLost
        default: code = .cannotConnectToHost
        }
    } else if let io = error as? IOError {
        switch io.errnoCode {
        case ECONNREFUSED: code = .cannotConnectToHost
        case ENETUNREACH, ENETDOWN, EHOSTUNREACH: code = .notConnectedToInternet
        case ECONNRESET, EPIPE: code = .networkConnectionLost
        default: code = .unknown
        }
    } else {
        code = .unknown
    }
    var info: [String: Any] = [NSUnderlyingErrorKey: error]
    if let url {
        info[NSURLErrorFailingURLErrorKey] = url
        info[NSURLErrorFailingURLStringErrorKey] = url.absoluteString
    }
    return URLError(code, userInfo: info)
}
#endif

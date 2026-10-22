//
//  NIOResponseCache.swift
//  SwiftOmniUINetworking
//
//  Created by Codex on 2026-10-16.
//

#if os(Linux)
import Foundation

/// Uses Foundation's cache container, never its networking engine. Protocol
/// caching is deliberately conservative: stale entries go back to the server,
/// and only explicit freshness can suppress a network request.
final class NIOResponseCache: @unchecked Sendable {
    private let cache: URLCache?
    private let defaultPolicy: URLRequest.CachePolicy
    private let configuration: URLSessionConfiguration
    private static let expiresKey = "SwiftOmniUI.NIOHTTP.expires"

    init(configuration: URLSessionConfiguration) {
        cache = configuration.urlCache
        defaultPolicy = configuration.requestCachePolicy
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }

    func cachedResponse(for request: URLRequest) throws -> CachedURLResponse? {
        let policy = request.cachePolicy == .useProtocolCachePolicy ? defaultPolicy : request.cachePolicy
        let requested = directives(request.value(forHTTPHeaderField: "Cache-Control"))
        let mayRead = canCache(request) && !requested.contains("no-store")
        let cached = mayRead ? cache?.cachedResponse(for: request) : nil
        switch policy {
        case .returnCacheDataDontLoad:
            guard let cached else { throw URLError(.resourceUnavailable) }
            return cached
        case .returnCacheDataElseLoad: return cached
        case .useProtocolCachePolicy:
            guard !requested.contains("no-cache"), !requested.contains("max-age=0"),
                  request.value(forHTTPHeaderField: "Pragma")?.lowercased() != "no-cache",
                  let cached,
                  let expiry = cached.userInfo?[Self.expiresKey] as? Date,
                  expiry > Date() else { return nil }
            return cached
        default: return nil
        }
    }

    func store(_ data: Data, response: HTTPURLResponse, for request: URLRequest) {
        guard let cache, canCache(request) else { return }
        let responseDirectives = directives(response.value(forHTTPHeaderField: "Cache-Control"))
        guard !responseDirectives.contains("no-store"),
              !directives(request.value(forHTTPHeaderField: "Cache-Control")).contains("no-store"),
              response.url == request.url,
              response.value(forHTTPHeaderField: "Vary") == nil,
              response.value(forHTTPHeaderField: "Set-Cookie") == nil,
              [200, 203, 204, 300, 301, 308, 404, 405, 410, 414, 501].contains(response.statusCode) else {
            cache.removeCachedResponse(for: request)
            return
        }
        var expiry: Date?
        if !responseDirectives.contains("no-cache") {
            if let maxAge = responseDirectives.first(where: { $0.hasPrefix("max-age=") }),
               let seconds = TimeInterval(maxAge.dropFirst(8).replacingOccurrences(of: "\"", with: "")) {
                let apparentAge = httpDate(response.value(forHTTPHeaderField: "Date"))
                    .map { max(0, Date().timeIntervalSince($0)) } ?? 0
                let age = max(apparentAge, TimeInterval(response.value(forHTTPHeaderField: "Age") ?? "0") ?? 0)
                expiry = Date().addingTimeInterval(max(0, seconds - age))
            } else {
                expiry = httpDate(response.value(forHTTPHeaderField: "Expires"))
            }
        }
        let info: [AnyHashable: Any]? = expiry.map { [Self.expiresKey: $0] }
        cache.storeCachedResponse(CachedURLResponse(response: response, data: data, userInfo: info, storagePolicy: .allowed),
                                  for: request)
    }

    private func canCache(_ request: URLRequest) -> Bool {
        guard (request.httpMethod ?? "GET").uppercased() == "GET",
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Range") == nil else { return false }
        if configuration.httpShouldSetCookies, request.httpShouldHandleCookies,
           let url = request.url, let cookies = configuration.httpCookieStorage?.cookies(for: url), !cookies.isEmpty {
            return false
        }
        return true
    }

    private func directives(_ header: String?) -> [String] {
        (header ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func httpDate(_ header: String?) -> Date? {
        guard let header else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return format.date(from: header)
    }
}
#endif

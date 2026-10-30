//
//  URLSession.swift
//  SwiftOmniUINetworking
//
//  Created by Codex on 2026-10-16.
//

import Foundation

#if os(Linux)
import FoundationNetworking

// Only the transport is replaced. These aliases preserve interoperability
// with SwiftOpenAI and the callers' Foundation request/response casts. Do not
// re-export the entire module: that would also expose its curl URLSession.
public typealias URLSession = NIOURLSession
public typealias URLSessionConfiguration = FoundationNetworking.URLSessionConfiguration
public typealias URLRequest = FoundationNetworking.URLRequest
public typealias URLResponse = FoundationNetworking.URLResponse
public typealias HTTPURLResponse = FoundationNetworking.HTTPURLResponse
public typealias URLCache = FoundationNetworking.URLCache
public typealias CachedURLResponse = FoundationNetworking.CachedURLResponse
public typealias HTTPCookie = FoundationNetworking.HTTPCookie
public typealias HTTPCookieStorage = FoundationNetworking.HTTPCookieStorage

#elseif os(Windows)
// Windows retains Foundation's implementation and its public types.
@_exported import FoundationNetworking
#endif

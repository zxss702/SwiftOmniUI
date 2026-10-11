// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif
#if os(Windows)
import WinSDK
#endif

/// What opens a URL with the system - the browser for `https`, whatever the
/// scheme's own handler is otherwise.
///
///     @Environment(\.openURL) private var openURL
///
///     Button("Website") { openURL("https://devin.ai") }
///
/// The system opens it on the caller's return. A view may write its own
/// handler with `.environment(\.openURL, OpenURLAction(...))` for a subtree -
/// how an in-app browser keeps its links.
public struct OpenURLAction: Sendable {
    /// Where the URL goes.
    private let act: @Sendable (String) -> Void

    /// An action that opens through `act` - for a subtree that handles its
    /// own links.
    ///
    /// - Parameter act: what runs for a URL.
    public init(_ act: @escaping @Sendable (String) -> Void) {
        self.act = act
    }

    /// An action that opens through the system.
    init() {
        act = { url in
            guard let open = OpenURLAction.opener else {
                complain("@Environment(\\.openURL) has no system handler on this platform.")
                return
            }
            open(url)
        }
    }

    /// Opens `url` - anything that describes itself as one, which is how a
    /// `URL` reaches here from a library that holds no `Foundation`.
    public func callAsFunction(_ url: some CustomStringConvertible) {
        act(String(describing: url))
    }

    /// The platform's own URL opener.
    private static let opener: (@Sendable (String) -> Void)? = {
        #if os(Windows)
        return { url in
            "open".withCString(encodedAs: UTF16.self) { verb in
                url.withCString(encodedAs: UTF16.self) { target in
                    _ = ShellExecuteW(nil, verb, target, nil, nil, SW_SHOWNORMAL)
                }
            }
        }
        #elseif canImport(Glibc) || canImport(Musl)
        return { url in spawn("xdg-open", url) }
        // Android's own opener is an Intent - the host hands openURL one, so
        // the system handler stands nowhere.
        #else
        return nil
        #endif
    }()

    #if canImport(Glibc) || canImport(Musl)
    /// Runs `tool url` beside the process - the shell backgrounds it and is
    /// reaped at once, so the opener outlives no call. The arguments live only
    /// inside their `withCString` scopes, which the spawn copies before it
    /// returns.
    private static func spawn(_ tool: String, _ url: String) {
        var pid = pid_t()
        let spawned = "/bin/sh".withCString { sh in
            "-c".withCString { flag in
                "\(tool) \"$1\" &".withCString { command in
                    "sh".withCString { name in
                        url.withCString { target in
                            var arguments: [UnsafeMutablePointer<CChar>?] = [
                                UnsafeMutablePointer(mutating: sh),
                                UnsafeMutablePointer(mutating: flag),
                                UnsafeMutablePointer(mutating: command),
                                UnsafeMutablePointer(mutating: name),
                                UnsafeMutablePointer(mutating: target),
                                nil,
                            ]
                            return arguments.withUnsafeMutableBufferPointer {
                                posix_spawn(&pid, "/bin/sh", nil, nil, $0.baseAddress!, nil)
                            }
                        }
                    }
                }
            }
        }
        guard spawned == 0 else { return }

        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
    }
    #endif
}

/// `\.openURL` reads an `OpenURLAction`.
struct OpenURLActionKey: EnvironmentKey {
    static let defaultValue = OpenURLAction()
}

extension EnvironmentValues {
    /// The URL opening of the scene the view stands in.
    public var openURL: OpenURLAction {
        get { self[OpenURLActionKey.self] }
        set { self[OpenURLActionKey.self] = newValue }
    }
}


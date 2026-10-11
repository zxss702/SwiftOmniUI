// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

/// What a host says for whoever reads its log rather than its screen, each line naming the host.
/// Design: docs/design/host/runtime.md#the-log
@_spi(Host) public struct HostLog: Sendable {
    /// The host's name, which begins each line.
    public let host: String

    private let output: @Sendable (String) -> Void

    /// A log for `host` written to standard error, which nothing buffers.
    public init(host: String) {
        self.init(host: host, output: Self.writeStandardError)
    }

    /// A log for `host` handed to `output`, line by line.
    public init(host: String, output: @escaping @Sendable (String) -> Void) {
        self.host = host
        self.output = output
    }

    /// Says something went wrong.
    public func error(_ message: String) {
        output(line(message))
    }

    /// Says how something long goes - a run's progress - as it goes.
    public func note(_ message: String) {
        output(line(message))
    }

    /// The line `message` is written as.
    public func line(_ message: String) -> String {
        "SwiftOmniUI \(host): \(message)\n"
    }

    /// Writes `text` to file descriptor 2, which nothing buffers. `SWIFTOMNIUI_LOG` names a file the line also lands
    /// in, for hosts whose standard error reaches no reader.
    static func writeStandardError(_ text: String) {
        var text = text
        text.withUTF8 { bytes in
            #if os(Windows)
            _ = _write(2, bytes.baseAddress, UInt32(bytes.count))
            #else
            _ = write(2, bytes.baseAddress, bytes.count)
            #endif
        }
        // `SWIFTOMNIUI_LOG` names a file the line also lands in, for hosts whose
        // standard error reaches no reader; C streams carry it, Foundation
        // never entering the library.
        if let path = logFile, let stream = fopen(path, "a") {
            var text = text
            text.withUTF8 { bytes in bytes.baseAddress.map { _ = fwrite($0, 1, bytes.count, stream) } }
            fclose(stream)
        }
    }

    /// The path `SWIFTOMNIUI_LOG` names, read once.
    private static let logFile: String? = getenv("SWIFTOMNIUI_LOG").map { String(cString: $0) }
}

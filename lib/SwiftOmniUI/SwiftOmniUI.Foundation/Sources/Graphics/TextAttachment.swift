// SPDX-License-Identifier: Apache-2.0
import Foundation
@_spi(Host) import SwiftOmniUICore

/// An image attachment in an attributed document. The image owns its decoded
/// pixels; no window, temporary file or native control is retained by a copy.
public final class NSTextAttachment: NSObject, @unchecked Sendable {
    public var image: PlatformImage?
    public var bounds: CGRect = .zero
}
public extension NSAttributedString.Key {
    static let attachment = Self("NSAttachment")
}
public extension NSAttributedString {
    convenience init(attachment: NSTextAttachment) {
        self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }
    /// Standard HTML carrying image contents, ready for the desktop clipboard.
    /// Plain text remains a separate clipboard representation, supplied by the caller.
    @MainActor func htmlRepresentation() -> String {
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        var content = ""
        var offset = 0
        while offset < length {
            var range = NSRange()
            let attributes = attributes(at: offset, effectiveRange: &range)
            defer { offset = NSMaxRange(range) }
            if let attachment = attributes[.attachment] as? NSTextAttachment,
               let image = attachment.image, let bitmap = image.source.bitmap,
               let png = bitmap.pngBytes() {
                let size = attachment.bounds.size == .zero ? image.size : attachment.bounds.size
                content += "<img width=\"\(size.width)\" height=\"\(size.height)\" src=\"data:image/png;base64,\(Data(png).base64EncodedString())\">"
            } else {
                content += escaped((string as NSString).substring(with: range))
            }
        }
        return "<html><body><div style=\"white-space:pre-wrap\">\(content)</div></body></html>"
    }
}

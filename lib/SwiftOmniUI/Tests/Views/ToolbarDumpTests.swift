// TEMPORARY debug probe - delete after reading.
import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class ToolbarDumpTests: XCTestCase {
    func testProbe() {
        let image = Image(systemName: "E774")
        print("PROBE-BEGIN")
        print("imageSource:", String(describing: image.imageSource))
        print("source prop:", String(describing: image.node.props[.source]))
        print("from prop:", String(describing: image.node.props[.source].flatMap(ImageSource.init(propValue:))))
        let erased: any View = Label("t", systemImage: "E774")
        print("erased is Label:", erased is Label, type(of: erased))
        let label = Label("t", systemImage: "E774")
        print("icon is Image:", label.icon is Image, type(of: label.icon))
        print("icon imageSource:", String(describing: (label.icon as? Image)?.imageSource))
        print("title is Text:", label.title is Text)
        print("PROBE-END")
    }
}

// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftOmniUICore

public extension View {
    func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
        self.aspectRatio(Double(aspectRatio.width / aspectRatio.height), contentMode: contentMode)
    }
}

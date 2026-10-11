// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import GalleryUI
import SwiftOmniUIAndroid

// What Android calls as it loads this library, on the UI thread: the
// application is named to the host and the host registers the native methods
// its activity calls.
@_cdecl("JNI_OnLoad")
public func JNI_OnLoad(_ machine: UnsafeMutableRawPointer?, _ reserved: UnsafeMutableRawPointer?) -> Int32 {
    swiftomniui_app_register()
    return SwiftOmniUIAndroid.load(machine)
}

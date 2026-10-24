// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The host this build is for, to the head that depends on SwiftOmniUIHead.

#if os(Android)
@_exported import SwiftOmniUIAndroid
#elseif os(Windows)
@_exported import SwiftOmniUIWinUI
#elseif os(Linux)
@_exported import SwiftOmniUIGTK
#elseif os(WASI)
@_exported import SwiftOmniUIWeb
#endif

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A custom renderer for `Text`, as SwiftUI's protocol names it.
///
/// A renderer is a code object, not a value: it rides the node like a
/// destination builder does and is handed to whatever draws the text. Hosts
/// whose text is a native control draw the words themselves; a renderer that
/// only observes layout (extracting glyph bounds, say) degrades to the
/// default drawing, and that is the declared behaviour for those hosts.
public protocol TextRenderer {}

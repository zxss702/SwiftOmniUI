// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The application's own fonts: files it carries, loaded privately for this
// process - Windows' own process-private font registration - so a `Font.custom`
// family has the chance to name them. How far the registration reaches -
// whether XAML's `FontFamily` resolves a family it holds - is Windows' to say;
// a family it does not resolve falls back as it did.
// Design: docs/design/platforms/winui/controls.md#words

#include "Relay.h"

using namespace swiftomniui;

extern "C" int32_t swiftomniui_winui_register_font(char const *path) {
    if (!path || !*path) return 0;
    return AddFontResourceExW(text(path).c_str(), FR_PRIVATE, nullptr);
}

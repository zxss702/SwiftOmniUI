// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "Relay.h"

namespace swiftomniui {
    // The standard caption is 32 DIPs. Commands leave two DIPs above and below
    // their 28-DIP face, with a centred 16-DIP glyph. Configure the templates,
    // not just the outer Height: AppBar's default inner margins are asymmetric
    // and its minimum heights otherwise keep the expanded command-bar row.
    inline void compactToolbarResources(xaml::ResourceDictionary const &resources) {
        auto number = [&](wchar_t const *key, double value) {
            resources.Insert(winrt::box_value(key), winrt::box_value(value));
        };
        auto margin = [&](wchar_t const *key, xaml::Thickness value) {
            resources.Insert(winrt::box_value(key), winrt::box_value(value));
        };
        number(L"AppBarThemeMinHeight", 28);
        number(L"AppBarThemeCompactHeight", 28);
        number(L"AppBarButtonContentHeight", 16);
        margin(L"AppBarButtonContentViewboxMargin", {8, 6, 0, 6});
        margin(L"AppBarButtonContentViewboxCompactMargin", {0, 6, 0, 6});
        margin(L"AppBarButtonContentViewboxCollapsedMargin", {0, 6, 0, 6});
        margin(L"AppBarButtonTextLabelOnRightMargin", {8, 0, 8, 0});
        margin(L"AppBarButtonTextLabelMargin", {8, 0, 8, 0});
        margin(L"AppBarToggleButtonTextLabelOnRightMargin", {8, 0, 8, 0});
        margin(L"AppBarToggleButtonTextLabelMargin", {8, 0, 8, 0});
        margin(L"AppBarButtonInnerBorderMargin", {0, 0, 0, 0});
        margin(L"AppBarButtonInnerBorderCompactMargin", {0, 0, 0, 0});
        margin(L"AppBarEllipsisButtonInnerBorderMargin", {0, 0, 0, 0});
        margin(L"CommandBarMoreButtonMargin", {0, 0, 0, 0});
    }

    inline void compactToolbarButton(controls::Control const &button) {
        // Some authored commands are measured before joining the TitleBar.
        // Give them the same metrics before their first template is applied.
        compactToolbarResources(button.Resources());
        button.VerticalAlignment(xaml::VerticalAlignment::Center);
        button.VerticalContentAlignment(xaml::VerticalAlignment::Center);
    }
}

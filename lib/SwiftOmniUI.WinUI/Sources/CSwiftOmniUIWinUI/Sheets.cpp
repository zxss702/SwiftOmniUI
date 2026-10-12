// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The pages a window presents over everything, as WinUI presents a dialog:
// each on a card over a veil across the whole window, the last on top and
// the page beneath out of reach, entering as a dialog enters.
// Design: docs/design/platforms/winui/pages.md#the-modal-stack

#include "Relay.h"

#include <limits>
#include <vector>

#include <winrt/Microsoft.UI.Xaml.Media.Animation.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;

namespace {
    /// The application's theme resource of that name, searched through the dictionaries it merges and their themes;
    /// null where there is none.
    IInspectable resource(wchar_t const *name) {
        return xaml::Application::Current().Resources().TryLookup(winrt::box_value(name));
    }

    /// The layer over the window's rows that holds its sheets, made the first time one is asked for.
    controls::Grid layer(xaml::Window const &window, bool make) {
        auto root = window.Content().as<controls::Grid>();
        for (auto const &child : root.Children())
            if (auto grid = child.try_as<controls::Grid>(); grid && winrt::unbox_value_or<winrt::hstring>(grid.Tag(), L"") == L"sheets")
                return grid;
        if (!make) return nullptr;

        controls::Grid sheets;
        sheets.Tag(winrt::box_value(L"sheets"));
        controls::Canvas::SetZIndex(sheets, 2);
        controls::Grid::SetRowSpan(sheets, 4);
        media::Animation::TransitionCollection transitions;
        transitions.Append(media::Animation::PopupThemeTransition());
        sheets.ChildrenTransitions(transitions);
        root.Children().Append(sheets);
        return sheets;
    }
}

bool swiftomniui::showsSheets(controls::Grid const &root) {
    for (auto const &child : root.Children())
        if (auto grid = child.try_as<controls::Grid>(); grid && winrt::unbox_value_or<winrt::hstring>(grid.Tag(), L"") == L"sheets")
            return grid.Children().Size() > 0;
    return false;
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_sheet_make(void) {
    try {
        // The veil: across the window, so nothing beneath it takes a click.
        controls::Grid sheet;
        winrt::Microsoft::UI::Xaml::Shapes::Rectangle veil;
        veil.Fill(resource(L"SmokeFillColorDefaultBrush").try_as<media::Brush>());
        sheet.Children().Append(veil);

        // The card: a dialog's own background, outline and corners, no wider than a dialog, clear of the edges.
        controls::Border card;
        card.Background(resource(L"ContentDialogBackground").try_as<media::Brush>());
        card.BorderBrush(resource(L"ContentDialogBorderBrush").try_as<media::Brush>());
        card.BorderThickness(winrt::unbox_value_or<xaml::Thickness>(resource(L"ContentDialogBorderWidth"), {1, 1, 1, 1}));
        card.CornerRadius(winrt::unbox_value_or<xaml::CornerRadius>(resource(L"OverlayCornerRadius"), {8, 8, 8, 8}));
        card.MinWidth(320);
        card.MaxWidth(548);
        card.MinHeight(184);
        card.Margin({48, 48, 48, 48});
        card.HorizontalAlignment(xaml::HorizontalAlignment::Center);
        card.VerticalAlignment(xaml::VerticalAlignment::Center);
        card.TabFocusNavigation(xaml::Input::KeyboardNavigationMode::Cycle);

        auto content = rows({true, false});
        controls::TextBlock title;
        if (auto style = resource(L"SubtitleTextBlockStyle").try_as<xaml::Style>()) title.Style(style);
        title.Margin({24, 20, 24, 8});
        title.TextTrimming(xaml::TextTrimming::CharacterEllipsis);
        controls::Grid::SetRow(title, 0);
        content.Children().Append(title);
        card.Child(content);
        sheet.Children().Append(card);
        return detach(sheet);
    } catch (...) {
        report("making a sheet");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_sheet_set(SwiftOmniUIObjectRef handle, char const *title, SwiftOmniUIObjectRef page) {
    try {
        auto card = borrow<controls::Grid>(handle).Children().GetAt(1).as<controls::Border>();
        auto content = card.Child().as<controls::Grid>();
        auto words = content.Children().GetAt(0).as<controls::TextBlock>();
        words.Text(text(title));
        words.Visibility(text(title).empty() ? xaml::Visibility::Collapsed : xaml::Visibility::Visible);
        standInRow(content, 1, page);
    } catch (...) {
        report("filling a sheet");
    }
}

extern "C" void swiftomniui_winui_sheet_set_height(SwiftOmniUIObjectRef handle, double height) {
    try {
        borrow<controls::Grid>(handle).Tag(winrt::box_value(height));
    } catch (...) {
        report("sizing a sheet");
    }
}

extern "C" void swiftomniui_winui_window_set_sheets(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef const *sheets, int32_t count) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto held = layer(window, count > 0);
        if (!held) return;
        std::vector<xaml::UIElement> shown;
        for (int32_t index = 0; index < count; ++index) shown.push_back(as<xaml::UIElement>(sheets[index]));
        auto children = held.Children();
        // Kept where it stands so it does not enter again; gone from the top, added on top.
        uint32_t kept = 0;
        while (kept < children.Size() && kept < shown.size() && children.GetAt(kept) == shown[kept]) ++kept;
        while (children.Size() > kept) children.RemoveAtEnd();
        for (auto index = kept; index < shown.size(); ++index) children.Append(shown[index]);
        // Each card's asked height, measured against the window where it is a share.
        auto room = window.Bounds().Height;
        for (auto const &child : children) {
            auto card = child.as<controls::Grid>().Children().GetAt(1).as<controls::Border>();
            auto asked = winrt::unbox_value_or<double>(child.as<xaml::FrameworkElement>().Tag(), 0.0);
            card.Height(asked == 0 ? std::numeric_limits<double>::quiet_NaN()
                                   : asked > 0 ? asked : -asked * room);
        }
        held.Visibility(count > 0 ? xaml::Visibility::Visible : xaml::Visibility::Collapsed);
        // The top sheet takes the keyboard: its first place that does.
        if (count > kept && count > 0) {
            auto top = shown.back().as<controls::Grid>().Children().GetAt(1);
            if (auto first = xaml::Input::FocusManager::FindFirstFocusableElement(top))
                if (auto focusable = first.try_as<xaml::UIElement>()) focusable.Focus(xaml::FocusState::Programmatic);
        }
    } catch (...) {
        report("presenting sheets");
    }
}

extern "C" int32_t swiftomniui_winui_window_sheets(SwiftOmniUIObjectRef handle) {
    try {
        auto held = layer(borrow<xaml::Window>(handle), false);
        return held ? static_cast<int32_t>(held.Children().Size()) : 0;
    } catch (...) {
        report("counting sheets");
        return 0;
    }
}

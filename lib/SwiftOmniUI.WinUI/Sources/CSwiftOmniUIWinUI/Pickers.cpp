// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A picker: WinUI's ComboBox, its choices, the one chosen - told through
// `chosen` - its placeholder while none is, and its list opening and closing,
// told through `presented`.
// Design: docs/design/platforms/winui/controls.md#a-picker

#include "Automation.h"

#include <algorithm>
#include <cstring>
#include <string>

#include <winrt/Windows.UI.Xaml.Interop.h>

using namespace swiftomniui;

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_picker_make(int64_t view) {
    try {
        controls::ComboBox box;
        box.SelectionChanged(guarded("handling SelectionChanged",
            [view](IInspectable const &sender, controls::SelectionChangedEventArgs const &) {
            callbacks.chosen(view, sender.as<controls::ComboBox>().SelectedIndex());
        }));
        box.DropDownOpened(guarded("handling DropDownOpened",
            [view](IInspectable const &, IInspectable const &) { callbacks.presented(view, true); }));
        box.DropDownClosed(guarded("handling DropDownClosed",
            [view](IInspectable const &, IInspectable const &) { callbacks.presented(view, false); }));
        return detach(box);
    } catch (...) {
        report("making a picker");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_picker_set_options(SwiftOmniUIObjectRef handle, char const *const *options, int32_t count) {
    try {
        auto items = borrow<controls::ComboBox>(handle).Items();
        items.Clear();
        for (int32_t index = 0; index < count; ++index) items.Append(winrt::box_value(text(options[index])));
    } catch (...) {
        report("giving a picker its choices");
    }
}

extern "C" void swiftomniui_winui_picker_set(SwiftOmniUIObjectRef handle, int32_t selected, bool writeSelected, char const *title) {
    try {
        auto box = borrow<controls::ComboBox>(handle);
        box.PlaceholderText(text(title));
        auto count = static_cast<int32_t>(box.Items().Size());
        if (writeSelected) box.SelectedIndex(selected >= 0 && selected < count ? selected : -1);
    } catch (...) {
        report("choosing in a picker");
    }
}

extern "C" void swiftomniui_winui_picker_set_alignment(SwiftOmniUIObjectRef handle, int32_t alignment) {
    try {
        // The choice shown and every choice in the list stand alike across the picker.
        auto box = borrow<controls::ComboBox>(handle);
        auto across = alignment == 1 ? xaml::HorizontalAlignment::Center
                      : alignment == 2 ? xaml::HorizontalAlignment::Right
                                       : xaml::HorizontalAlignment::Left;
        box.HorizontalContentAlignment(across);
        xaml::Style items{winrt::xaml_typename<controls::ComboBoxItem>()};
        items.Setters().Append(xaml::Setter(controls::Control::HorizontalContentAlignmentProperty(), winrt::box_value(across)));
        box.ItemContainerStyle(items);
    } catch (...) {
        report("setting a picker's choices across it");
    }
}

extern "C" void swiftomniui_winui_picker_set_open(SwiftOmniUIObjectRef handle, bool open) {
    try {
        borrow<controls::ComboBox>(handle).IsDropDownOpen(open);
    } catch (...) {
        report("opening a picker's list");
    }
}

extern "C" bool swiftomniui_winui_picker_is_open(SwiftOmniUIObjectRef handle) {
    try {
        return borrow<controls::ComboBox>(handle).IsDropDownOpen();
    } catch (...) {
        report("reading whether a picker's list shows");
        return false;
    }
}

extern "C" int32_t swiftomniui_winui_picker_selected(SwiftOmniUIObjectRef handle) {
    try {
        return borrow<controls::ComboBox>(handle).SelectedIndex();
    } catch (...) {
        report("reading a picker's choice");
        return -1;
    }
}

extern "C" int32_t swiftomniui_winui_picker_choices(SwiftOmniUIObjectRef handle, char *utf8, int32_t capacity) {
    try {
        std::wstring joined;
        for (auto const &item : borrow<controls::ComboBox>(handle).Items()) {
            if (!joined.empty()) joined += L'\n';
            joined += winrt::unbox_value_or<winrt::hstring>(item, L"");
        }
        auto words = winrt::to_string(joined);
        if (utf8 && capacity > 0) {
            auto count = std::min<size_t>(words.size(), static_cast<size_t>(capacity - 1));
            std::memcpy(utf8, words.data(), count);
            utf8[count] = 0;
        }
        return static_cast<int32_t>(words.size());
    } catch (...) {
        report("reading a picker's choices");
        return 0;
    }
}

extern "C" void swiftomniui_winui_picker_open_as_user(SwiftOmniUIObjectRef handle, bool open) {
    try {
        auto expanding = pattern<provider::IExpandCollapseProvider>(borrow<controls::ComboBox>(handle), PatternInterface::ExpandCollapse);
        if (open) expanding.Expand();
        else expanding.Collapse();
    } catch (...) {
        report("opening a picker's list as the user");
    }
}

extern "C" void swiftomniui_winui_picker_choose_as_user(SwiftOmniUIObjectRef handle, int32_t index) {
    try {
        borrow<controls::ComboBox>(handle).SelectedIndex(index);
    } catch (...) {
        report("choosing in a picker as the user");
    }
}

extern "C" void swiftomniui_winui_picker_set_style(SwiftOmniUIObjectRef handle, int32_t kind) {
    try {
        auto box = borrow<controls::ComboBox>(handle);
        // The kind is logical: `inline` takes the chrome away so the pick sits
        // in a row; the kinds a ComboBox cannot be stay its automatic look.
        if (kind == 5) {
            box.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
            box.BorderThickness({0, 0, 0, 0});
        } else {
            box.ClearValue(controls::Control::BackgroundProperty());
            box.ClearValue(controls::Control::BorderThicknessProperty());
        }
    } catch (...) {
        report("styling a picker");
    }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The words the user types: a field on one line, whose Enter submits; an
// editor of several lines, whose Enter starts a new one; and a search box,
// WinUI's AutoSuggestBox, whose query submits. Each change of the words is told
// through `textChanged` as it happens.
// Design: docs/design/platforms/winui/controls.md#a-field-and-its-words

#include "Automation.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <vector>

#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.UI.Xaml.Interop.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;

namespace {
    void centerSingleLine(controls::TextBox const &box) {
        if (box.AcceptsReturn()) return;
        box.ApplyTemplate();
        std::vector<xaml::DependencyObject> pending{box};
        while (!pending.empty()) {
            auto at = pending.back(); pending.pop_back();
            if (auto element = at.try_as<xaml::FrameworkElement>(); element &&
                (element.Name() == L"ContentElement" || element.Name() == L"PlaceholderTextContentPresenter"))
                element.VerticalAlignment(xaml::VerticalAlignment::Center);
            for (int32_t index = 0, count = media::VisualTreeHelper::GetChildrenCount(at); index < count; ++index)
                pending.push_back(media::VisualTreeHelper::GetChild(at, index));
        }
    }

    /// TextChanging only records the source of the write. It can run during
    /// XAML layout, where reporting state and rebuilding the visual tree is
    /// forbidden. TextChanged delivers the completed input outside that phase.
    void hearWords(controls::TextBox const &box, int64_t view) {
        auto userChange = std::make_shared<bool>(false);
        box.TextChanging(guarded("handling TextChanging",
            [userChange](controls::TextBox const &, controls::TextBoxTextChangingEventArgs const &args) {
            if (!args.IsContentChanging()) return;
            *userChange = !callbacks.isProgramWriting();
        }));
        box.TextChanged(guarded("handling TextChanged",
            [view, userChange](IInspectable const &sender, controls::TextChangedEventArgs const &) {
            if (!*userChange) return;
            *userChange = false;
            auto bytes = winrt::to_string(sender.as<controls::TextBox>().Text());
            callbacks.textChanged(view, bytes.c_str());
        }));
    }

    /// The case a text box puts typed letters in for SwiftOmniUI's `TextCase`: upper, lower, or as typed.
    controls::CharacterCasing casing(int32_t textCase) {
        return textCase == 3   ? controls::CharacterCasing::Upper
               : textCase == 2 ? controls::CharacterCasing::Lower
                               : controls::CharacterCasing::Normal;
    }

    /// Tells the view `view` that Enter was pressed in `field`.
    void hearEnter(controls::Control const &field, int64_t view) {
        field.KeyDown(guarded("handling KeyDown",
            [view](IInspectable const &, xaml::Input::KeyRoutedEventArgs const &args) {
            if (args.Key() == winrt::Windows::System::VirtualKey::Enter) callbacks.submitted(view);
        }));
    }

    /// The text box a field or an editor is, or the one a search box's template holds; null before it stands.
    controls::TextBox boxOf(SwiftOmniUIObjectRef handle) {
        auto control = as<IInspectable>(handle);
        if (auto search = control.try_as<controls::AutoSuggestBox>()) return first<controls::TextBox>(search);
        return control.as<controls::TextBox>();
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_field_make(int64_t view) {
    try {
        controls::TextBox field;
        field.Loaded(guarded("centering a field's words", [](IInspectable const &sender, xaml::RoutedEventArgs const &) {
            centerSingleLine(sender.as<controls::TextBox>());
        }));
        hearWords(field, view);
        hearEnter(field, view);
        return detach(field);
    } catch (...) {
        report("making a field");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_field_set_style(SwiftOmniUIObjectRef handle, int kind) {
    try {
        auto box = boxOf(handle);
        if (kind == 0) kind = 1;
        auto transparent = media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent());
        for (auto key : {L"TextControlBackgroundPointerOver", L"TextControlBackgroundFocused",
                        L"TextControlBackgroundDisabled", L"TextControlBorderBrushPointerOver",
                        L"TextControlBorderBrushFocused", L"TextControlBorderBrushDisabled"}) {
            auto name = winrt::box_value(key);
            if (kind == 1) box.Resources().Insert(name, transparent);
            else if (box.Resources().HasKey(name)) box.Resources().Remove(name);
        }
        // Automatic and plain are bare text; explicit border styles retain the native box.
        if (kind == 1) {
            box.Padding({0, 0, 0, 0});
            box.BorderThickness({0, 0, 0, 0});
            box.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
        } else {
            box.ClearValue(controls::Control::PaddingProperty());
            box.ClearValue(controls::Control::BorderThicknessProperty());
            box.ClearValue(controls::Control::BackgroundProperty());
        }
        if (kind == 3) box.CornerRadius({0, 0, 0, 0});
        else box.ClearValue(controls::Control::CornerRadiusProperty());
        centerSingleLine(box);
    } catch (...) {
        report("styling a field");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_editor_make(int64_t view) {
    try {
        controls::TextBox editor;
        editor.AcceptsReturn(true);
        editor.TextWrapping(xaml::TextWrapping::Wrap);
        // SwiftUI composition owns the editor's padding and allocated size.
        // TextBox's stock chrome otherwise expands a short slot internally
        // and clips it, even when DesiredSize reports the requested height.
        editor.MinWidth(0);
        editor.MinHeight(0);
        editor.Padding({0, 0, 0, 0});
        auto transparent = media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent());
        editor.BorderBrush(transparent);
        editor.BorderThickness({0, 0, 0, 0});
        editor.UseSystemFocusVisuals(false);
        // The focused template writes its own border thickness and brush, independently of the control's.
        for (auto key : {L"TextControlBorderBrush", L"TextControlBorderBrushPointerOver",
                        L"TextControlBorderBrushFocused", L"TextControlBorderBrushDisabled"})
            editor.Resources().Insert(winrt::box_value(key), transparent);
        for (auto key : {L"TextControlBorderThemeThickness", L"TextControlBorderThemeThicknessFocused"})
            editor.Resources().Insert(winrt::box_value(key), winrt::box_value(xaml::Thickness{0, 0, 0, 0}));
        controls::ScrollViewer::SetVerticalScrollBarVisibility(editor, controls::ScrollBarVisibility::Auto);
        hearWords(editor, view);
        return detach(editor);
    } catch (...) {
        report("making an editor");
        return nullptr;
    }
}

extern "C" bool swiftomniui_winui_editor_content_size(
    SwiftOmniUIObjectRef handle, double width, bool growing, double *size
) {
    try {
        auto editor = borrow<controls::TextBox>(handle);
        controls::TextBlock line;
        line.FontFamily(editor.FontFamily());
        line.FontSize(editor.FontSize());
        line.FontWeight(editor.FontWeight());
        line.FontStyle(editor.FontStyle());
        line.FontStretch(editor.FontStretch());
        line.CharacterSpacing(editor.CharacterSpacing());
        line.FlowDirection(editor.FlowDirection());
        constexpr auto unbounded = std::numeric_limits<float>::infinity();
        auto padding = editor.Padding();
        auto border = editor.BorderThickness();
        auto across = padding.Left + padding.Right + border.Left + border.Right;
        line.Text(L"Mg");
        line.TextWrapping(xaml::TextWrapping::NoWrap);
        line.Measure({unbounded, unbounded});
        auto desired = line.DesiredSize();
        auto lineHeight = double(desired.Height);
        double naturalWidth = 0;
        if (growing || !std::isfinite(width)) {
            auto words = editor.Text();
            line.Text(words.empty() ? editor.PlaceholderText() : words);
            line.TextWrapping(growing ? xaml::TextWrapping::Wrap : xaml::TextWrapping::NoWrap);
            auto offered = growing && std::isfinite(width)
                ? static_cast<float>(std::max(0.0, width - across)) : unbounded;
            line.Measure({offered, unbounded});
            desired = line.DesiredSize();
            naturalWidth = double(desired.Width);
        }
        auto measured = std::max(editor.MinHeight(), (growing ? std::max(lineHeight, double(desired.Height)) : lineHeight)
            + padding.Top + padding.Bottom + border.Top + border.Bottom);
        if (!std::isfinite(measured) || measured <= 0) throw winrt::hresult_error(E_UNEXPECTED);
        size[0] = std::max(editor.MinWidth(), naturalWidth + across);
        size[1] = measured;
        return true;
    } catch (...) {
        report("querying an editor's content size");
        return false;
    }
}

extern "C" void swiftomniui_winui_editor_set_allocated_height(SwiftOmniUIObjectRef handle, double height) {
    try {
        auto editor = borrow<controls::TextBox>(handle);
        // TextBox::OnSizeChanged starts its own 100 ms Height storyboard when
        // Height is Auto and a focused multiline box changes size. SOUI owns
        // this allocation, including every animation sample. Express that
        // ownership before Measure; leaving Height Auto gives XAML a second
        // geometry driver which also suppresses SizeChanged and caret updates.
        // https://github.com/microsoft/microsoft-ui-xaml/blob/main/dxaml/xcp/dxaml/lib/TextBox_Partial.cpp
        if (!std::isfinite(height) || height < 0) throw winrt::hresult_error(E_INVALIDARG);
        if (editor.Height() != height) editor.Height(height);
    } catch (...) {
        report("allocating an editor's height");
    }
}

extern "C" double swiftomniui_winui_editor_allocated_height(SwiftOmniUIObjectRef handle) {
    try {
        return borrow<controls::TextBox>(handle).Height();
    } catch (...) {
        report("reading an editor's allocated height");
        return std::numeric_limits<double>::quiet_NaN();
    }
}

extern "C" bool swiftomniui_winui_editor_intrinsic_height(SwiftOmniUIObjectRef handle, double *height) {
    double size[2] = {0, 0};
    if (!swiftomniui_winui_editor_content_size(handle, std::numeric_limits<double>::infinity(), false, size)) return false;
    *height = size[1];
    return true;
}

extern "C" void swiftomniui_winui_editor_set_background_hidden(SwiftOmniUIObjectRef handle, bool hidden) {
    try {
        auto editor = borrow<controls::TextBox>(handle);
        auto resources = editor.Resources();
        auto transparent = media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent());
        for (auto key : {L"TextControlBackground", L"TextControlBackgroundPointerOver",
                        L"TextControlBackgroundFocused", L"TextControlBackgroundDisabled"}) {
            auto name = winrt::box_value(key);
            if (hidden) resources.Insert(name, transparent);
            else if (resources.HasKey(name)) resources.Remove(name);
        }
        if (hidden) editor.Background(transparent);
        else editor.ClearValue(controls::Control::BackgroundProperty());
        // A loaded template must read the new resources even when it is already focused. Re-reading the theme
        // leaves the text box, caret and selection in place and restores native theme colours when shown again.
        readThemeAgain(editor);
    } catch (...) {
        report("setting an editor's canvas visibility");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_search_make(int64_t view) {
    try {
        controls::AutoSuggestBox search;
        search.QueryIcon(controls::SymbolIcon(controls::Symbol::Find));
        search.TextChanged(guarded("handling TextChanged",
            [view](controls::AutoSuggestBox const &sender, controls::AutoSuggestBoxTextChangedEventArgs const &args) {
            if (args.Reason() != controls::AutoSuggestionBoxTextChangeReason::UserInput) return;
            auto bytes = winrt::to_string(sender.Text());
            callbacks.textChanged(view, bytes.c_str());
        }));
        search.QuerySubmitted(guarded("handling QuerySubmitted",
            [view](controls::AutoSuggestBox const &, controls::AutoSuggestBoxQuerySubmittedEventArgs const &) {
            callbacks.submitted(view);
        }));
        return detach(search);
    } catch (...) {
        report("making a search box");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_field_set_text(SwiftOmniUIObjectRef handle, char const *utf8) {
    try {
        auto words = text(utf8);
        auto control = as<IInspectable>(handle);
        if (auto search = control.try_as<controls::AutoSuggestBox>()) {
            if (search.Text() != words) search.Text(words);
            return;
        }
        auto field = control.as<controls::TextBox>();
        if (field.Text() == words) return;
        field.Text(words);
        field.Select(static_cast<int32_t>(words.size()), 0);
    } catch (...) {
        report("setting a field's words");
    }
}

extern "C" void swiftomniui_winui_field_set_placeholder(SwiftOmniUIObjectRef handle, char const *utf8) {
    try {
        auto control = as<IInspectable>(handle);
        if (auto search = control.try_as<controls::AutoSuggestBox>()) search.PlaceholderText(text(utf8));
        else control.as<controls::TextBox>().PlaceholderText(text(utf8));
    } catch (...) {
        report("setting a field's placeholder");
    }
}

extern "C" void swiftomniui_winui_field_set_behaviour(
    SwiftOmniUIObjectRef handle, bool readOnly, bool spellChecked, bool predicted, int32_t scope
) {
    try {
        auto field = borrow<controls::TextBox>(handle);
        field.IsReadOnly(readOnly);
        field.IsSpellCheckEnabled(spellChecked);
        field.IsTextPredictionEnabled(predicted);
        field.InputScope(inputScope(scope));
    } catch (...) {
        report("setting how a field takes words");
    }
}

extern "C" void swiftomniui_winui_field_set_casing(SwiftOmniUIObjectRef handle, int32_t textCase) {
    try {
        borrow<controls::TextBox>(handle).CharacterCasing(casing(textCase));
    } catch (...) {
        report("setting the case a field's typing takes");
    }
}

extern "C" void swiftomniui_winui_search_set_box(SwiftOmniUIObjectRef handle, bool readOnly, int32_t textCase) {
    try {
        // The box types in the text box its template holds, which takes the style the box gives it: WinUI's own,
        // with the case typing takes and whether it is read only.
        xaml::Style style{winrt::xaml_typename<controls::TextBox>()};
        auto own = xaml::Application::Current().Resources().TryLookup(winrt::box_value(L"AutoSuggestBoxTextBoxStyle"));
        if (own) style.BasedOn(own.as<xaml::Style>());
        style.Setters().Append(xaml::Setter(controls::TextBox::CharacterCasingProperty(), winrt::box_value(casing(textCase))));
        style.Setters().Append(xaml::Setter(controls::TextBox::IsReadOnlyProperty(), winrt::box_value(readOnly)));
        borrow<controls::AutoSuggestBox>(handle).TextBoxStyle(style);
    } catch (...) {
        report("setting how a search box takes words");
    }
}

extern "C" void swiftomniui_winui_field_set_look(SwiftOmniUIObjectRef handle, int32_t alignment, uint32_t placeholderArgb, bool placeholderColored) {
    try {
        auto field = borrow<controls::TextBox>(handle);
        field.TextAlignment(alignment == 1 ? xaml::TextAlignment::Center
                            : alignment == 2 ? xaml::TextAlignment::Right
                                             : xaml::TextAlignment::Left);
        if (placeholderColored)
            field.PlaceholderForeground(media::SolidColorBrush(winrt::Windows::UI::Color{
                static_cast<uint8_t>(placeholderArgb >> 24), static_cast<uint8_t>(placeholderArgb >> 16),
                static_cast<uint8_t>(placeholderArgb >> 8), static_cast<uint8_t>(placeholderArgb)}));
        else
            field.ClearValue(controls::TextBox::PlaceholderForegroundProperty());
    } catch (...) {
        report("setting a field's look");
    }
}

extern "C" void swiftomniui_winui_field_select(SwiftOmniUIObjectRef handle, int32_t start, int32_t length) {
    try {
        auto field = borrow<controls::TextBox>(handle);
        auto size = static_cast<int32_t>(field.Text().size());
        auto from = std::clamp(start, 0, size);
        field.Select(from, std::clamp(length, 0, size - from));
    } catch (...) {
        report("selecting in a field");
    }
}

extern "C" void swiftomniui_winui_field_facts(SwiftOmniUIObjectRef handle, int32_t *facts) {
    try {
        auto field = boxOf(handle);
        auto names = field.InputScope() ? field.InputScope().Names() : nullptr;
        int32_t const read[] = {
            field.IsReadOnly(), field.IsSpellCheckEnabled(), field.IsTextPredictionEnabled(),
            names && names.Size() > 0 ? static_cast<int32_t>(names.GetAt(0).NameValue()) : -1,
            static_cast<int32_t>(field.TextAlignment()), field.SelectionStart(), field.SelectionLength(),
            field.PlaceholderForeground() != nullptr, field.AcceptsReturn(),
        };
        std::memcpy(facts, read, sizeof read);
    } catch (...) {
        report("reading a field");
    }
}

extern "C" void swiftomniui_winui_search_type(SwiftOmniUIObjectRef handle, char const *utf8) {
    try {
        // The box's own text box, which its template holds: words changed there are the user's to the search box.
        std::vector<xaml::DependencyObject> left{as<xaml::DependencyObject>(handle)};
        while (!left.empty()) {
            auto at = left.back();
            left.pop_back();
            if (auto box = at.try_as<controls::TextBox>()) {
                box.Text(text(utf8));
                return;
            }
            for (int32_t index = 0, count = media::VisualTreeHelper::GetChildrenCount(at); index < count; ++index)
                left.push_back(media::VisualTreeHelper::GetChild(at, index));
        }
    } catch (...) {
        report("typing in a search box");
    }
}

extern "C" void swiftomniui_winui_search_submit_as_user(SwiftOmniUIObjectRef handle) {
    try {
        // A search box's automation peer submits its query as its own button does.
        pattern<provider::IInvokeProvider>(as<xaml::UIElement>(handle), PatternInterface::Invoke).Invoke();
    } catch (...) {
        report("submitting a search as the user");
    }
}

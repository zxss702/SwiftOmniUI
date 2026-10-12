// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The controls: a text block and a button, and what the user does to them.
// Each handler names its view by number and holds nothing of the control it is
// on.

#include "Automation.h"

#include <algorithm>
#include <string>

#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.ViewManagement.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace swiftomniui;
namespace primitives = winrt::Microsoft::UI::Xaml::Controls::Primitives;

namespace {
    /// Whether a button keeps its pressed look - what `button_set_on` wrote
    /// into its tag, `isOn` worn on the element at all.
    bool keeps(primitives::ToggleButton const &button) {
        return winrt::unbox_value_or<bool>(button.Tag(), false);
    }

    /// Writes `value` under every look state a toggle's template names:
    /// `ToggleButton{property}{state}` - ordinary, pointed, pressed, and the
    /// checked and indeterminate ones a keeping button can sit in.
    void keepToggleKeys(xaml::ResourceDictionary const &resources, wchar_t const *property,
                        xaml::Media::Brush const &ordinary, xaml::Media::Brush const &pointed,
                        xaml::Media::Brush const &pressed) {
        struct Entry { wchar_t const *state; xaml::Media::Brush const *value; };
        Entry entries[] = {
            {L"", &ordinary}, {L"PointerOver", &pointed}, {L"Pressed", &pressed},
            {L"Checked", &pressed}, {L"CheckedPointerOver", &pointed}, {L"CheckedPressed", &pressed},
            {L"Indeterminate", &ordinary}, {L"IndeterminatePointerOver", &pointed},
            {L"IndeterminatePressed", &pressed},
        };
        for (auto const &entry : entries) {
            auto name = winrt::box_value((std::wstring(L"ToggleButton") + property + entry.state).c_str());
            if (resources.HasKey(name)) resources.Remove(name);
            if (*entry.value) resources.Insert(name, *entry.value);
        }
    }

    /// What a label with no background is drawn over: nothing, which is still hit across its bounds.
    xaml::Media::SolidColorBrush clearGround() {
        return xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0});
    }

    /// Dresses a control standing on the bar: no ground of its own - the bar shows through - and the bar's own
    /// faint fill under the pointer and pressed. A toggle reads the `ToggleButton*` keys, any other control the
    /// `Button*` ones.
    void barLook(controls::Control const &control) {
        auto resources = control.Resources();
        auto transparent = clearGround();
        auto theme = xaml::Application::Current().Resources();
        auto pointed = theme.Lookup(winrt::box_value(L"SubtleFillColorSecondaryBrush")).as<xaml::Media::Brush>();
        auto pressed = theme.Lookup(winrt::box_value(L"SubtleFillColorTertiaryBrush")).as<xaml::Media::Brush>();
        control.Background(transparent);
        control.BorderThickness({0, 0, 0, 0});
        control.CornerRadius({4, 4, 4, 4});
        keepToggleKeys(resources, L"Background", transparent, pointed, pressed);
        keepToggleKeys(resources, L"BorderBrush", transparent, transparent, transparent);
        struct State { wchar_t const *suffix; xaml::Media::Brush fill; };
        for (auto const &state : {State{L"", transparent}, State{L"PointerOver", pointed},
                                  State{L"Pressed", pressed}, State{L"Disabled", transparent}}) {
            resources.Insert(winrt::box_value(winrt::hstring(std::wstring(L"ButtonBackground") + state.suffix)), state.fill);
            resources.Insert(winrt::box_value(winrt::hstring(std::wstring(L"ButtonBorderBrush") + state.suffix)), transparent);
        }
    }
}

controls::TextBlock swiftomniui::wordsOf(IInspectable const &element) {
    if (auto block = element.try_as<controls::TextBlock>()) return block;
    if (auto border = element.try_as<controls::Border>()) return border.Child().try_as<controls::TextBlock>();
    return nullptr;
}

controls::TextBlock swiftomniui::labelWords(SwiftOmniUIObjectRef handle) {
    auto words = wordsOf(as<IInspectable>(handle));
    if (!words) winrt::throw_hresult(E_INVALIDARG);
    return words;
}

xaml::UIElement swiftomniui::metOf(IInspectable const &element) {
    if (auto border = element.try_as<controls::Border>()) {
        if (auto block = border.Child().try_as<controls::TextBlock>()) return block;
    }
    return element.as<xaml::UIElement>();
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_text_make(void) {
    try {
        // The words stand in a border, which draws what they are drawn over and stands them across its height as
        // their alignment says: a text block does neither.
        controls::TextBlock block;
        // The outer label uses SOUI's DIP proposals. Its inner TextBlock
        // must use the same width and height when it measures and draws,
        // including small custom-font captions inside a fixed-height frame.
        block.UseLayoutRounding(false);
        block.TextWrapping(xaml::TextWrapping::Wrap);
        controls::Border label;
        label.Background(clearGround());
        label.Child(block);
        return detach(label);
    } catch (...) {
        report("making a label");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_text_set_text(SwiftOmniUIObjectRef handle, char const *utf8) {
    try {
        labelWords(handle).Text(text(utf8));
    } catch (...) {
        report("setting a label's words");
    }
}

extern "C" void swiftomniui_winui_text_set_background(SwiftOmniUIObjectRef handle, SwiftOmniUIBrush background) {
    try {
        auto fill = brush(background);
        borrow<controls::Border>(handle).Background(fill ? fill : clearGround());
    } catch (...) {
        report("setting what a label is drawn over");
    }
}

extern "C" void swiftomniui_winui_text_set_vertical(SwiftOmniUIObjectRef handle, int32_t vertical) {
    try {
        labelWords(handle).VerticalAlignment(vertical == 1 ? xaml::VerticalAlignment::Center
                                             : vertical == 2 ? xaml::VerticalAlignment::Bottom
                                                             : xaml::VerticalAlignment::Stretch);
    } catch (...) {
        report("standing a label's words across its height");
    }
}

namespace {
    /// What every button of ours reports: its checks - taken back at once on one that keeps nothing - its click,
    /// and being held down and let go.
    void wireButton(primitives::ToggleButton const &button, int64_t view) {
        button.Checked(guarded("handling Checked", [view](IInspectable const &sender, xaml::RoutedEventArgs const &) {
            auto b = sender.as<primitives::ToggleButton>();
            if (!keeps(b)) { b.IsChecked(false); return; }
            callbacks.toggled(view, true);
        }));
        button.Unchecked(guarded("handling Unchecked", [view](IInspectable const &sender, xaml::RoutedEventArgs const &) {
            if (keeps(sender.as<primitives::ToggleButton>())) callbacks.toggled(view, false);
        }));
        button.Click(guarded("handling Click",
            [view](IInspectable const &, xaml::RoutedEventArgs const &) { callbacks.clicked(view); }));
        // Held down by a pointer or a key, and let go: what WinUI's own pressed look follows.
        button.RegisterPropertyChangedCallback(
            controls::Primitives::ButtonBase::IsPressedProperty(),
            [view](xaml::DependencyObject const &sender, xaml::DependencyProperty const &) {
                callbacks.held(view, sender.as<controls::Primitives::ButtonBase>().IsPressed());
            });
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_button_make(int64_t view) {
    try {
        // A staying-pressed button at heart: it draws the platform's ordinary
        // button until `isOn` gives it a state to keep - a press on one that
        // keeps nothing has its check taken back at once, to false rather than
        // nothing: nothing is the button's THIRD, indeterminate look, which
        // keeps none of the resources the look set.
        primitives::ToggleButton button;
        wireButton(button, view);
        return detach(button);
    } catch (...) {
        report("making a button");
        return nullptr;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_toolbar_button_make(int64_t view) {
    try {
        // The bar's own button, WinUI's AppBarToggleButton: momentary until `button_set_on` has it keep a state -
        // a press on one that keeps nothing is taken back at once. Its icon slot and label are what it shows;
        // `toolbar_button_set_icon` and `set_caption` fill them.
        controls::AppBarToggleButton button;
        button.LabelPosition(controls::CommandBarLabelPosition::Collapsed);
        wireButton(button, view);
        return detach(button);
    } catch (...) {
        report("making a toolbar button");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_button_set_on(SwiftOmniUIObjectRef handle, int32_t toggleable, int32_t on) {
    try {
        // Asked for, not borrowed: the bar's button is an AppBarToggleButton, whose default interface is not
        // ToggleButton's - IsChecked read through it calls another method of its table.
        auto button = as<primitives::ToggleButton>(handle);
        // The mark of a staying-pressed button, read by the checks above.
        button.Tag(winrt::box_value(toggleable != 0));
        auto want = toggleable != 0 && on != 0;
        auto current = button.IsChecked();
        if ((current && current.Value()) != want)
            button.IsChecked(winrt::Windows::Foundation::IReference<bool>(want));
    } catch (...) {
        report("turning a button on or off");
    }
}

extern "C" void swiftomniui_winui_button_set_look(
    SwiftOmniUIObjectRef handle, SwiftOmniUIBrush background, SwiftOmniUIBrush stroke, double strokeWidth, double cornerRadius,
    double underPointer, double pressed
) {
    try {
        auto button = as<primitives::ToggleButton>(handle);
        auto resources = button.Resources();
        // Under the pointer and pressed, the fill is drawn a little fainter each time, as WinUI's own buttons draw it.
        auto fill = brush(background);
        auto faded = [&](double opacity) {
            auto made = brush(background);
            if (made) made.Opacity(opacity);
            return made;
        };
        if (fill) button.Background(fill);
        else button.ClearValue(controls::Control::BackgroundProperty());
        keepToggleKeys(resources, L"Background", fill, faded(underPointer), faded(pressed));

        auto outline = strokeWidth > 0 ? brush(stroke) : xaml::Media::Brush{nullptr};
        if (outline) {
            button.BorderBrush(outline);
            button.BorderThickness({strokeWidth, strokeWidth, strokeWidth, strokeWidth});
        } else {
            button.ClearValue(controls::Control::BorderBrushProperty());
            button.ClearValue(controls::Control::BorderThicknessProperty());
        }
        keepToggleKeys(resources, L"BorderBrush", outline, outline, outline);

        if (cornerRadius >= 0) button.CornerRadius({cornerRadius, cornerRadius, cornerRadius, cornerRadius});
        else button.ClearValue(controls::Control::CornerRadiusProperty());
    } catch (...) {
        report("dressing a button");
    }
}

extern "C" void swiftomniui_winui_button_set_face(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef content) {
    try {
        as<controls::ContentControl>(handle).Content(content ? as<xaml::UIElement>(content) : nullptr);
    } catch (...) { report("giving a button its label view"); }
}

extern "C" void swiftomniui_winui_set_caption(SwiftOmniUIObjectRef handle, char const *utf8) {
    try {
        auto control = as<controls::ContentControl>(handle);
        auto words = text(utf8);
        // The bar's button is named by its label; with a picture in its icon slot the words move to its tip.
        auto place = [&](auto const &command) {
            bool pictured = command.Icon() != nullptr;
            bool collapsed = words.empty() || pictured;
            command.Label(words);
            command.LabelPosition(collapsed ? controls::CommandBarLabelPosition::Collapsed
                                            : controls::CommandBarLabelPosition::Default);
            // Showing its icon alone, the button stands as wide as the bar's own back and pane buttons - the
            // system gives those 40. Words alone keep the default width, which a label needs.
            if (collapsed) command.Width(40);
            else command.ClearValue(xaml::FrameworkElement::WidthProperty());
            if (pictured && !words.empty()) controls::ToolTipService::SetToolTip(command, winrt::box_value(words));
        };
        if (auto toggle = control.try_as<controls::AppBarToggleButton>()) return place(toggle);
        if (auto command = control.try_as<controls::AppBarButton>()) return place(command);
        control.Content(winrt::box_value(words));
    } catch (...) {
        report("setting a caption");
    }
}

extern "C" void swiftomniui_winui_toolbar_button_set_look(SwiftOmniUIObjectRef handle) {
    // The app menu's trigger on the bar.
    try {
        barLook(as<controls::Control>(handle));
    } catch (...) { report("styling a toolbar button"); }
}

extern "C" void swiftomniui_winui_button_set_style(SwiftOmniUIObjectRef handle, int kind) {
    try {
        auto button = as<primitives::ToggleButton>(handle);
        auto resources = button.Resources();
        // The kind is logical: the button is a toggle at heart, whose template reads
        // the `ToggleButton*` look keys, so each kind writes the look directly -
        // the accent style's fill is the system's accent under every state.
        if (kind == 2) {
            winrt::Windows::UI::ViewManagement::UISettings settings;
            auto accent = settings.GetColorValue(winrt::Windows::UI::ViewManagement::UIColorType::Accent);
            xaml::Media::SolidColorBrush fill(accent);
            xaml::Media::SolidColorBrush lighter(accent), dimmer(accent);
            lighter.Opacity(0.9);
            dimmer.Opacity(0.8);
            xaml::Media::SolidColorBrush words(winrt::Windows::UI::Color{255, 255, 255, 255});
            button.Background(fill);
            button.Foreground(words);
            keepToggleKeys(resources, L"Background", fill, lighter, dimmer);
            keepToggleKeys(resources, L"Foreground", words, words, words);
        } else if (kind == 3 || kind == 4) {
            // Borderless and plain show the caption on what stands beneath it.
            button.ClearValue(controls::Control::BackgroundProperty());
            button.ClearValue(controls::Control::BorderBrushProperty());
            button.BorderThickness({0, 0, 0, 0});
            xaml::Media::Brush nothing{nullptr};
            keepToggleKeys(resources, L"Background", nothing, nothing, nothing);
            keepToggleKeys(resources, L"BorderBrush", nothing, nothing, nothing);
        } else {
            // Anything else clears back to the platform's own look.
            button.ClearValue(xaml::FrameworkElement::StyleProperty());
        }
    } catch (...) {
        report("styling a button");
    }
}

extern "C" void swiftomniui_winui_button_invoke(SwiftOmniUIObjectRef handle) {
    try {
        pattern<provider::IToggleProvider>(
            as<primitives::ToggleButton>(handle), PatternInterface::Toggle).Toggle();
    } catch (...) {
        report("pressing a button");
    }
}

extern "C" void swiftomniui_winui_button_set_shortcut(SwiftOmniUIObjectRef handle, int32_t key, int32_t modifiers) {
    try {
        auto button = as<primitives::ToggleButton>(handle);
        // No key takes the shortcut away; any other is a Windows virtual key
        // the Swift side chose, the modifiers its flags in the same order.
        auto accelerators = button.KeyboardAccelerators();
        accelerators.Clear();
        if (key == 0) return;
        xaml::Input::KeyboardAccelerator accelerator;
        accelerator.Key(static_cast<winrt::Windows::System::VirtualKey>(key));
        accelerator.Modifiers(static_cast<winrt::Windows::System::VirtualKeyModifiers>(modifiers));
        accelerators.Append(accelerator);
    } catch (...) {
        report("setting a button's shortcut");
    }
}

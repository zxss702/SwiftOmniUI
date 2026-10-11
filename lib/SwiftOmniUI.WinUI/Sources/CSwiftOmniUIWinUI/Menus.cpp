// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Menus: a view's context menu - WinUI's MenuFlyout on the element, opened by
// a right click, the menu key, a long press - and a window's menu bar, WinUI's
// MenuBar. Both are written from the same flat entries - items, separators
// and submenus - each item's choice told through `menuChosen` by its place
// among the items.
// Design: docs/design/platforms/winui/pages.md#menus

#include "Automation.h"

#include <winrt/Microsoft.UI.Xaml.Automation.h>

#include <algorithm>
#include <functional>
#include <cstring>
#include <string>
#include <vector>

using namespace swiftomniui;
using Entries = winrt::Windows::Foundation::Collections::IVector<controls::MenuFlyoutItemBase>;

namespace {
    /// Gives `entry` the identifier whatever drives the application finds it by; none for an empty one.
    void identify(xaml::UIElement const &entry, char const *identifier) {
        if (identifier && *identifier) {
            xaml::Automation::AutomationProperties::SetAutomationId(entry, text(identifier));
        }
    }

    /// Writes a menu's flat entries into the lists they belong to: an item (0), a separator (1), a submenu opening
    /// (2) and closing (3). On a bar, a menu at the top is one of the bar's own.
    struct Writer {
        int64_t view;
        controls::MenuBar bar{nullptr};
        std::vector<Entries> levels;
        int32_t chosen = 0;

        void write(int32_t kind, char const *title, bool enabled, char const *identifier) {
            if (kind == 3) {
                if (levels.size() > (bar ? 0u : 1u)) levels.pop_back();
                return;
            }
            if (bar && levels.empty()) {
                if (kind != 2) return;
                controls::MenuBarItem menu;
                menu.Title(text(title));
                menu.IsEnabled(enabled);
                identify(menu, identifier);
                bar.Items().Append(menu);
                levels.push_back(menu.Items());
                return;
            }
            switch (kind) {
            case 0: {
                controls::MenuFlyoutItem item;
                item.Text(text(title));
                item.IsEnabled(enabled);
                identify(item, identifier);
                item.Click(guarded("handling Click",
                    [view = view, place = chosen++](IInspectable const &, xaml::RoutedEventArgs const &) {
                    callbacks.menuChosen(view, place);
                }));
                levels.back().Append(item);
                break;
            }
            case 1:
                levels.back().Append(controls::MenuFlyoutSeparator());
                break;
            case 2: {
                controls::MenuFlyoutSubItem sub;
                sub.Text(text(title));
                sub.IsEnabled(enabled);
                identify(sub, identifier);
                levels.back().Append(sub);
                levels.push_back(sub.Items());
                break;
            }
            }
        }
    };

    /// The entries as a test reads them: items by caption, "!" before one that cannot be chosen, "-" a separator,
    /// a submenu's entries in brackets after its caption, ";" between.
    std::wstring described(Entries const &entries) {
        std::wstring text;
        for (auto const &entry : entries) {
            if (!text.empty()) text += L";";
            if (entry.try_as<controls::MenuFlyoutSeparator>()) {
                text += L"-";
            } else if (auto sub = entry.try_as<controls::MenuFlyoutSubItem>()) {
                text += (sub.IsEnabled() ? L"" : L"!") + std::wstring(sub.Text()) + L"[" + described(sub.Items()) + L"]";
            } else if (auto item = entry.try_as<controls::MenuFlyoutItem>()) {
                text += (item.IsEnabled() ? L"" : L"!") + std::wstring(item.Text());
            }
        }
        return text;
    }

    /// The item at `index` among the entries' items, submenus' included, in the order they stand; null past the last.
    controls::MenuFlyoutItem item(Entries const &entries, int32_t &index) {
        for (auto const &entry : entries) {
            if (auto sub = entry.try_as<controls::MenuFlyoutSubItem>()) {
                if (auto found = item(sub.Items(), index)) return found;
            } else if (auto each = entry.try_as<controls::MenuFlyoutItem>()) {
                if (index-- == 0) return each;
            }
        }
        return nullptr;
    }

    /// The entries of each menu an element offers: its context menu's, a button's flyout's, or each of a bar's
    /// menus.
    std::vector<Entries> menus(xaml::UIElement const &element) {
        std::vector<Entries> found;
        if (auto bar = element.try_as<controls::MenuBar>()) {
            for (auto const &menu : bar.Items()) found.push_back(menu.Items());
        } else if (auto flyout = element.ContextFlyout().try_as<controls::MenuFlyout>()) {
            found.push_back(flyout.Items());
        } else if (auto button = element.try_as<controls::Button>()) {
            if (auto flyout = button.Flyout().try_as<controls::MenuFlyout>()) {
                found.push_back(flyout.Items());
            }
        }
        return found;
    }
}

extern "C" void swiftomniui_winui_set_context_menu(
    SwiftOmniUIObjectRef handle, int64_t view, int32_t const *kinds, char const *const *titles, bool const *enabled,
    char const *const *identifiers, int32_t count
) {
    try {
        auto element = as<xaml::UIElement>(handle);
        if (count == 0) {
            element.ContextFlyout(nullptr);
        } else {
            controls::MenuFlyout flyout;
            Writer writer{view, nullptr, {flyout.Items()}};
            for (int32_t index = 0; index < count; ++index) {
                writer.write(kinds[index], titles[index], enabled[index], identifiers[index]);
            }
            element.ContextFlyout(flyout);
        }
        holdHitArea(element, view);
    } catch (...) {
        report("giving a view its context menu");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_menu_button_make(int64_t view) {
    try {
        // A menu living in the view: a `Button` whose `Flyout` a press opens, its face a row - the label child
        // before a chevron the indicator setting shows or hides.
        controls::Button button;
        controls::StackPanel face;
        face.Orientation(controls::Orientation::Horizontal);
        face.Spacing(2);
        controls::TextBlock chevron;
        chevron.FontFamily(xaml::Media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
        chevron.FontSize(12);
        chevron.Text(L"\uE70D");
        chevron.VerticalAlignment(xaml::VerticalAlignment::Center);
        face.Children().Append(chevron);
        button.Content(face);
        button.Click(guarded("handling Click",
            [view](IInspectable const &, xaml::RoutedEventArgs const &) { callbacks.clicked(view); }));
        button.RegisterPropertyChangedCallback(
            controls::Primitives::ButtonBase::IsPressedProperty(),
            [view](xaml::DependencyObject const &sender, xaml::DependencyProperty const &) {
                callbacks.held(view, sender.as<controls::Primitives::ButtonBase>().IsPressed());
            });
        return detach(button);
    } catch (...) {
        report("making a menu button");
        return nullptr;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_toolbar_menu_button_make(int64_t view) {
    try {
        // A menu on the bar: WinUI's own command button, its flyout the menu, its content its icon's slot.
        controls::AppBarButton button;
        button.LabelPosition(controls::CommandBarLabelPosition::Collapsed);
        button.Click(guarded("handling Click",
            [view](IInspectable const &, xaml::RoutedEventArgs const &) { callbacks.clicked(view); }));
        return detach(button);
    } catch (...) {
        report("making a toolbar menu button");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_menu_button_set_face(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef content) {
    try {
        auto button = borrow<controls::Button>(handle);
        if (auto command = button.try_as<controls::AppBarButton>()) {
            command.Content(content ? as<xaml::UIElement>(content) : nullptr);
            return;
        }
        auto face = button.Content().as<controls::StackPanel>();
        auto children = face.Children();
        if (children.Size() > 1) children.RemoveAt(0);
        if (content) children.InsertAt(0, as<xaml::UIElement>(content));
    } catch (...) {
        report("giving a menu button its face");
    }
}

extern "C" void swiftomniui_winui_menu_button_set_indicator(SwiftOmniUIObjectRef handle, int32_t shown) {
    try {
        auto face = borrow<controls::Button>(handle).Content().as<controls::StackPanel>();
        face.Children().GetAt(face.Children().Size() - 1)
            .Visibility(shown ? xaml::Visibility::Visible : xaml::Visibility::Collapsed);
    } catch (...) {
        report("showing a menu button's chevron or hiding it");
    }
}

extern "C" void swiftomniui_winui_menu_button_set_borderless(SwiftOmniUIObjectRef handle, int32_t borderless) {
    try {
        auto button = borrow<controls::Button>(handle);
        auto transparent = xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0});
        for (auto key : {L"ButtonBackgroundPointerOver", L"ButtonBackgroundPressed", L"ButtonBackgroundDisabled",
                        L"ButtonBorderBrushPointerOver", L"ButtonBorderBrushPressed", L"ButtonBorderBrushDisabled"}) {
            auto name = winrt::box_value(key);
            if (borderless) button.Resources().Insert(name, transparent);
            else if (button.Resources().HasKey(name)) button.Resources().Remove(name);
        }
        if (!borderless) {
            button.ClearValue(xaml::FrameworkElement::StyleProperty());
            button.ClearValue(controls::Control::BackgroundProperty());
            button.ClearValue(controls::Control::BorderThicknessProperty());
            button.ClearValue(controls::Control::PaddingProperty());
            return;
        }
        button.Background(transparent);
        button.BorderThickness({0, 0, 0, 0});
        button.Padding({0, 0, 0, 0});
    } catch (...) {
        report("styling a menu button");
    }
}

extern "C" void swiftomniui_winui_menu_button_set_menu(
    SwiftOmniUIObjectRef handle, int64_t view, int32_t const *kinds, char const *const *titles, bool const *enabled,
    char const *const *identifiers, int32_t count
) {
    try {
        auto button = borrow<controls::Button>(handle);
        if (count == 0) {
            button.Flyout(nullptr);
        } else {
            controls::MenuFlyout flyout;
            Writer writer{view, nullptr, {flyout.Items()}};
            for (int32_t index = 0; index < count; ++index) {
                writer.write(kinds[index], titles[index], enabled[index], identifiers[index]);
            }
            button.Flyout(flyout);
        }
    } catch (...) {
        report("writing a menu button's menu");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_app_menu_make(int64_t view) {
    try {
        // The scene's commands behind one button at the title bar's leading edge - the platform's own application
        // menu's place on this family, its face the navigation glyph. `menu_button_set_menu` writes its flyout.
        controls::Button button;
        controls::SymbolIcon icon{controls::Symbol::GlobalNavigationButton};
        button.Content(icon);
        return detach(button);
    } catch (...) {
        report("making an app menu button");
        return nullptr;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_menu_bar_make(int64_t) {
    try {
        return detach(controls::MenuBar());
    } catch (...) {
        report("making a menu bar");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_menu_bar_set(
    SwiftOmniUIObjectRef handle, int64_t view, int32_t const *kinds, char const *const *titles, bool const *enabled,
    char const *const *identifiers, int32_t count
) {
    try {
        auto bar = borrow<controls::MenuBar>(handle);
        bar.Items().Clear();
        Writer writer{view, bar, {}};
        for (int32_t index = 0; index < count; ++index) {
            writer.write(kinds[index], titles[index], enabled[index], identifiers[index]);
        }
    } catch (...) {
        report("writing a menu bar");
    }
}

extern "C" int32_t swiftomniui_winui_menus(SwiftOmniUIObjectRef handle, char *utf8, int32_t capacity) {
    try {
        auto element = as<xaml::UIElement>(handle);
        std::wstring text;
        if (auto bar = element.try_as<controls::MenuBar>()) {
            for (auto const &menu : bar.Items()) {
                if (!text.empty()) text += L";";
                text += (menu.IsEnabled() ? L"" : L"!") + std::wstring(menu.Title()) + L"[" + described(menu.Items()) + L"]";
            }
        } else if (auto flyout = element.ContextFlyout().try_as<controls::MenuFlyout>()) {
            text = described(flyout.Items());
        }
        auto bytes = winrt::to_string(text);
        if (utf8 && capacity > 0) {
            auto size = std::min<size_t>(bytes.size(), static_cast<size_t>(capacity - 1));
            std::memcpy(utf8, bytes.data(), size);
            utf8[size] = 0;
        }
        return static_cast<int32_t>(bytes.size());
    } catch (...) {
        report("reading a view's menus");
        return 0;
    }
}

extern "C" void swiftomniui_winui_menus_choose(SwiftOmniUIObjectRef handle, int32_t index) {
    try {
        for (auto const &entries : menus(as<xaml::UIElement>(handle))) {
            if (auto chosen = item(entries, index)) {
                pattern<provider::IInvokeProvider>(chosen, PatternInterface::Invoke).Invoke();
                return;
            }
        }
    } catch (...) {
        report("choosing in a view's menus");
    }
}

extern "C" int32_t swiftomniui_winui_menus_identifiers(SwiftOmniUIObjectRef handle, char *utf8, int32_t capacity) {
    try {
        std::wstring text;
        std::function<void(Entries const &)> each = [&](Entries const &entries) {
            for (auto const &entry : entries) {
                if (auto sub = entry.try_as<controls::MenuFlyoutSubItem>()) {
                    each(sub.Items());
                } else if (auto item = entry.try_as<controls::MenuFlyoutItem>()) {
                    if (!text.empty()) text += L";";
                    text += std::wstring(xaml::Automation::AutomationProperties::GetAutomationId(item));
                }
            }
        };
        for (auto const &entries : menus(as<xaml::UIElement>(handle))) each(entries);
        auto bytes = winrt::to_string(text);
        if (utf8 && capacity > 0) {
            auto size = std::min<size_t>(bytes.size(), static_cast<size_t>(capacity - 1));
            std::memcpy(utf8, bytes.data(), size);
            utf8[size] = 0;
        }
        return static_cast<int32_t>(bytes.size());
    } catch (...) {
        report("reading a view's menus' identifiers");
        return 0;
    }
}

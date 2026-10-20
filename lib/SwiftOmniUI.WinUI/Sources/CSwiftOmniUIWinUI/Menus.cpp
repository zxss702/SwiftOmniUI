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
#include <initializer_list>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

using namespace swiftomniui;
using Entries = winrt::Windows::Foundation::Collections::IVector<controls::MenuFlyoutItemBase>;

extern "C" void swiftomniui_winui_menu_set_shortcuts(
    SwiftOmniUIObjectRef handle, int64_t view, int32_t const *keys,
    int32_t const *modifiers, int32_t const *items, int32_t count) {
    try {
        auto owner = as<xaml::UIElement>(handle);
        auto accelerators = owner.KeyboardAccelerators();
        accelerators.Clear();
        owner.KeyboardAcceleratorPlacementMode(xaml::Input::KeyboardAcceleratorPlacementMode::Hidden);
        for (int32_t at = 0; at < count; ++at) {
            if (!keys[at]) continue;
            xaml::Input::KeyboardAccelerator accelerator;
            accelerator.Key(static_cast<winrt::Windows::System::VirtualKey>(keys[at]));
            accelerator.Modifiers(static_cast<winrt::Windows::System::VirtualKeyModifiers>(modifiers[at]));
            accelerator.Invoked(guarded("handling a menu shortcut",
                [view, item = items[at]](auto const &, xaml::Input::KeyboardAcceleratorInvokedEventArgs const &args) {
                    args.Handled(true);
                    callbacks.menuChosen(view, item);
                }));
            accelerators.Append(accelerator);
        }
    } catch (...) { report("setting menu shortcuts"); }
}

namespace {
    /// Gives `entry` the identifier whatever drives the application finds it by; none for an empty one.
    void identify(xaml::UIElement const &entry, char const *identifier) {
        xaml::Automation::AutomationProperties::SetAutomationId(entry, text(identifier ? identifier : ""));
    }

    /// Writes a menu's flat entries into the lists they belong to: an item (0), a separator (1), a submenu opening
    /// (2) and closing (3). On a bar, a menu at the top is one of the bar's own.
    struct Writer {
        int64_t view;
        controls::MenuBar bar{nullptr};
        std::vector<Entries> levels;
        std::vector<uint64_t> owners;
        std::vector<std::unordered_map<uint64_t, controls::MenuFlyoutSubItem>> previous;
        std::vector<uint32_t> positions;
        std::unordered_map<uint64_t, controls::MenuBarItem> previousBar;
        uint32_t barPosition = 0;
        int32_t chosen = 0;

        Writer(int64_t view, controls::MenuBar const &bar, std::initializer_list<Entries> initial)
            : view(view), bar(bar) {
            if (bar) for (auto const &item : bar.Items()) {
                auto mount = winrt::unbox_value_or<uint64_t>(item.Tag(), 0);
                if (mount) previousBar.emplace(mount, item);
            }
            for (auto const &entries : initial) enter(entries);
        }

        void enter(Entries const &entries, uint64_t owner = 0) {
            std::unordered_map<uint64_t, controls::MenuFlyoutSubItem> old;
            for (auto const &entry : entries) if (auto sub = entry.try_as<controls::MenuFlyoutSubItem>()) {
                auto mount = winrt::unbox_value_or<uint64_t>(sub.Tag(), 0);
                if (mount) old.emplace(mount, sub);
            }
            previous.push_back(std::move(old));
            levels.push_back(entries);
            owners.push_back(owner);
            positions.push_back(0);
        }

        void put(controls::MenuFlyoutItemBase const &item, bool reusing = false) {
            auto entries = levels.back();
            auto &index = positions.back();
            if (index < entries.Size() && entries.GetAt(index) == item) { ++index; return; }
            uint32_t previousIndex;
            if (reusing && entries.IndexOf(item, previousIndex)) {
                entries.RemoveAt(previousIndex);
                entries.InsertAt(index, item);
            } else if (index < entries.Size()) entries.SetAt(index, item);
            else entries.Append(item);
            ++index;
        }

        void leave() {
            auto entries = levels.back();
            while (entries.Size() > positions.back()) entries.RemoveAtEnd();
            levels.pop_back(); owners.pop_back(); previous.pop_back(); positions.pop_back();
        }

        void finish() {
            while (!levels.empty()) leave();
            if (bar) while (bar.Items().Size() > barPosition) bar.Items().RemoveAtEnd();
        }

        void write(int32_t kind, char const *title, bool enabled, char const *identifier, uint64_t mount) {
            if (kind == 3) {
                if (levels.size() > (bar ? 0u : 1u)) leave();
                return;
            }
            if (bar && levels.empty()) {
                if (kind != 2) return;
                controls::MenuBarItem menu{nullptr};
                if (auto found = previousBar.find(mount); found != previousBar.end()) menu = found->second;
                if (!menu) menu = controls::MenuBarItem();
                menu.Tag(winrt::box_value(mount));
                menu.Title(text(title));
                menu.IsEnabled(enabled);
                identify(menu, identifier);
                auto items = bar.Items();
                if (barPosition >= items.Size() || items.GetAt(barPosition) != menu) {
                    uint32_t previousIndex;
                    if (items.IndexOf(menu, previousIndex)) {
                        items.RemoveAt(previousIndex);
                        items.InsertAt(barPosition, menu);
                    } else if (barPosition < items.Size()) items.SetAt(barPosition, menu);
                    else items.Append(menu);
                }
                ++barPosition;
                enter(menu.Items(), mount);
                return;
            }
            switch (kind) {
            case 0:
            case 4: { // A disabled Text entry, including an unrequested level's placeholder.
                controls::MenuFlyoutItem item;
                item.Text(text(title));
                item.IsEnabled(enabled);
                identify(item, identifier);
                item.Click(guarded("handling Click",
                    [view = view, place = chosen++](IInspectable const &, xaml::RoutedEventArgs const &) {
                    callbacks.menuChosen(view, place);
                }));
                // Submenu presenters are created only when WinUI expands them.
                // Their placeholder's native Loaded event also covers keyboard and UI Automation expansion,
                // without confusing the main menu's initial focus with opening a submenu.
                if (kind == 4 && owners.back()) {
                    item.Loaded(guarded("requesting visible submenu contents",
                        [view = view, mount = owners.back()](auto const &, auto const &) {
                            if (callbacks.menuContentRequested) callbacks.menuContentRequested(view, mount);
                        }));
                }
                put(item);
                break;
            }
            case 1:
                put(controls::MenuFlyoutSeparator());
                break;
            case 2: {
                controls::MenuFlyoutSubItem sub{nullptr};
                if (auto found = previous.back().find(mount); found != previous.back().end()) sub = found->second;
                bool reusing = static_cast<bool>(sub);
                if (!sub) sub = controls::MenuFlyoutSubItem();
                sub.Tag(winrt::box_value(mount));
                sub.Text(text(title));
                sub.IsEnabled(enabled);
                identify(sub, identifier);
                put(sub, reusing);
                enter(sub.Items(), mount);
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
    char const *const *identifiers, uint64_t const *mounts, int32_t count
) {
    try {
        auto element = as<xaml::UIElement>(handle);
        if (count == 0) {
            element.ContextFlyout(nullptr);
        } else {
            auto flyout = element.ContextFlyout().try_as<controls::MenuFlyout>();
            if (!flyout) {
                flyout = controls::MenuFlyout();
                flyout.Opening(guarded("requesting context menu contents", [view](auto const &, auto const &) {
                    if (callbacks.menuContentRequested) callbacks.menuContentRequested(view, 0);
                }));
                // The menu standing over the pointer: what is under it holds its hover until it goes.
                flyout.Opened(guarded("handling a context menu's Opened",
                    [view](auto const &, auto const &) { callbacks.presented(view, true); }));
                flyout.Closed(guarded("handling a context menu's Closed",
                    [view](auto const &, auto const &) { callbacks.presented(view, false); }));
                element.ContextFlyout(flyout);
            }
            Writer writer{view, nullptr, {flyout.Items()}};
            for (int32_t index = 0; index < count; ++index) {
                writer.write(kinds[index], titles[index], enabled[index], identifiers[index], mounts[index]);
            }
            writer.finish();
        }
        holdHitArea(element, view);
    } catch (...) {
        report("giving a view its context menu");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_menu_button_make(int64_t view) {
    try {
        // Give the label a finite share of the button's content width. A
        // horizontal StackPanel measures it unbounded, losing flexible frame
        // alignment and centring the whole label/chevron at its natural size.
        controls::Button button;
        button.HorizontalContentAlignment(xaml::HorizontalAlignment::Stretch);
        button.VerticalContentAlignment(xaml::VerticalAlignment::Center);
        controls::Grid face;
        controls::ColumnDefinition labelColumn, indicatorColumn;
        labelColumn.Width(xaml::GridLengthHelper::FromValueAndType(1, xaml::GridUnitType::Star));
        indicatorColumn.Width(xaml::GridLengthHelper::Auto());
        face.ColumnDefinitions().Append(labelColumn);
        face.ColumnDefinitions().Append(indicatorColumn);
        face.ColumnSpacing(2);
        face.Tag(winrt::box_value(2.0));
        controls::TextBlock chevron;
        chevron.FontFamily(xaml::Media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
        chevron.FontSize(12);
        chevron.Text(L"\uE70D");
        chevron.VerticalAlignment(xaml::VerticalAlignment::Center);
        controls::Grid::SetColumn(chevron, 1);
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
    // A menu on the bar: the view's own menu button, dressed as the bar's - no ground of its own, the bar's fill
    // under the pointer.
    try {
        auto handle = swiftomniui_winui_menu_button_make(view);
        if (handle) {
            swiftomniui_winui_toolbar_button_set_look(handle);
            auto face = borrow<controls::Button>(handle).Content().as<controls::Grid>();
            face.ColumnSpacing(6);
            face.Tag(winrt::box_value(6.0));
        }
        return handle;
    } catch (...) {
        report("making a toolbar menu button");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_menu_button_set_face(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef content) {
    try {
        auto face = borrow<controls::Button>(handle).Content().as<controls::Grid>();
        auto children = face.Children();
        auto replacement = content ? as<xaml::UIElement>(content) : xaml::UIElement{nullptr};
        if ((children.Size() > 1 ? children.GetAt(0) : xaml::UIElement{nullptr}) == replacement) return;
        if (children.Size() > 1) children.RemoveAt(0);
        if (replacement) children.InsertAt(0, replacement);
    } catch (...) {
        report("giving a menu button its face");
    }
}

extern "C" void swiftomniui_winui_menu_button_set_indicator(SwiftOmniUIObjectRef handle, int32_t shown) {
    try {
        auto face = borrow<controls::Button>(handle).Content().as<controls::Grid>();
        face.Children().GetAt(face.Children().Size() - 1)
            .Visibility(shown ? xaml::Visibility::Visible : xaml::Visibility::Collapsed);
        face.ColumnSpacing(shown ? winrt::unbox_value_or<double>(face.Tag(), 2.0) : 0);
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
    char const *const *identifiers, uint64_t const *mounts, int32_t count
) {
    try {
        auto button = borrow<controls::Button>(handle);
        if (count == 0) {
            button.Flyout(nullptr);
        } else {
            auto flyout = button.Flyout().try_as<controls::MenuFlyout>();
            if (!flyout) {
                flyout = controls::MenuFlyout();
                flyout.Opening(guarded("requesting menu contents", [view](auto const &, auto const &) {
                    if (callbacks.menuContentRequested) callbacks.menuContentRequested(view, 0);
                }));
                // As the context menu's: the menu standing over the pointer holds what is under it.
                flyout.Opened(guarded("handling a menu's Opened",
                    [view](auto const &, auto const &) { callbacks.presented(view, true); }));
                flyout.Closed(guarded("handling a menu's Closed",
                    [view](auto const &, auto const &) { callbacks.presented(view, false); }));
                button.Flyout(flyout);
            }
            Writer writer{view, nullptr, {flyout.Items()}};
            for (int32_t index = 0; index < count; ++index) {
                writer.write(kinds[index], titles[index], enabled[index], identifiers[index], mounts[index]);
            }
            writer.finish();
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

extern "C" void swiftomniui_winui_menu_open_for_testing(SwiftOmniUIObjectRef handle) {
    try {
        auto button = as<controls::Button>(handle);
        if (auto flyout = button.Flyout()) flyout.ShowAt(button);
    } catch (...) { report("opening a menu for testing"); }
}

extern "C" void swiftomniui_winui_menu_close_for_testing(SwiftOmniUIObjectRef handle) {
    try {
        auto button = as<controls::Button>(handle);
        if (auto flyout = button.Flyout()) flyout.Hide();
    } catch (...) { report("closing a menu for testing"); }
}

extern "C" uint64_t swiftomniui_winui_menu_identity_for_testing(SwiftOmniUIObjectRef handle) {
    try {
        auto flyout = as<controls::Button>(handle).Flyout();
        return reinterpret_cast<uint64_t>(winrt::get_abi(flyout));
    } catch (...) { report("reading a menu identity for testing"); return 0; }
}

extern "C" bool swiftomniui_winui_menu_open_submenu_for_testing(SwiftOmniUIObjectRef handle, uint64_t mount) {
    try {
        auto flyout = as<controls::Button>(handle).Flyout().as<controls::MenuFlyout>();
        std::function<controls::MenuFlyoutSubItem(Entries const &)> find = [&](Entries const &entries) {
            for (auto const &entry : entries) {
                if (auto sub = entry.try_as<controls::MenuFlyoutSubItem>()) {
                    if (winrt::unbox_value_or<uint64_t>(sub.Tag(), 0) == mount) return sub;
                    if (auto found = find(sub.Items())) return found;
                }
            }
            return controls::MenuFlyoutSubItem{nullptr};
        };
        auto sub = find(flyout.Items());
        if (!sub) return false;
        pattern<provider::IExpandCollapseProvider>(sub, PatternInterface::ExpandCollapse).Expand();
        return true;
    } catch (...) { report("opening a submenu for testing"); return false; }
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
    char const *const *identifiers, uint64_t const *mounts, int32_t count
) {
    try {
        auto bar = borrow<controls::MenuBar>(handle);
        Writer writer{view, bar, {}};
        for (int32_t index = 0; index < count; ++index) {
            writer.write(kinds[index], titles[index], enabled[index], identifiers[index], mounts[index]);
        }
        writer.finish();
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

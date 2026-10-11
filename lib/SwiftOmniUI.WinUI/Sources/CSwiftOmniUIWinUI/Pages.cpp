// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The native parts of a window and its arrangements of pages: the window's
// chrome in WinUI's TitleBar, a split view's NavigationView, and a row of tabs.
// Each says what the user chose by the view's number and the entry's place.
// Design: docs/design/platforms/winui/pages.md

#include "Relay.h"

#include <winrt/Microsoft.UI.Xaml.Automation.h>
#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Content.h>
#include <winrt/Microsoft.UI.Windowing.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;

namespace {
    using winrt::Windows::System::VirtualKey;
    using winrt::Windows::System::VirtualKeyModifiers;

    /// The `key`+`modifiers` accelerator on every button in `element`'s template loses it, and every element's
    /// accelerator tooltip is hidden. The window's own accelerators already answer the shortcut, and a button's
    /// own one shows its tooltip on hover - which never closes over an airspace island like a WebView, where
    /// pointer moves never reach XAML.
    void unaccelerate(xaml::DependencyObject const &element, VirtualKey key, VirtualKeyModifiers modifiers) {
        for (int32_t index = 0, count = media::VisualTreeHelper::GetChildrenCount(element); index < count; ++index) {
            auto child = media::VisualTreeHelper::GetChild(element, index);
            if (auto ui = child.try_as<xaml::UIElement>()) {
                ui.KeyboardAcceleratorPlacementMode(xaml::Input::KeyboardAcceleratorPlacementMode::Hidden);
                auto accelerators = ui.KeyboardAccelerators();
                for (uint32_t at = 0; at < accelerators.Size();) {
                    auto accelerator = accelerators.GetAt(at);
                    if (accelerator.Key() == key && accelerator.Modifiers() == modifiers)
                        accelerators.RemoveAt(at);
                    else ++at;
                }
            }
            unaccelerate(child, key, modifiers);
        }
    }

    /// The columns WinUI's TitleBar keeps at its edges for the window's own buttons, and the room those take in
    /// DIPs; null columns where the bar stands in no window yet.
    struct CaptionRoom {
        controls::ColumnDefinition leading{nullptr};
        controls::ColumnDefinition trailing{nullptr};
        double leadingRoom = 0;
        double trailingRoom = 0;
    };

    CaptionRoom captionRoom(controls::TitleBar const &bar) {
        CaptionRoom found;
        auto root = bar.XamlRoot();
        auto grid = first<controls::Grid>(bar);
        if (!root || !grid) return found;
        auto window = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            root.ContentIslandEnvironment().AppWindowId());
        if (!window) return found;
        auto column = [&](wchar_t const *name) {
            auto named = grid.FindName(name);
            return named ? named.try_as<controls::ColumnDefinition>() : nullptr;
        };
        found.leading = column(L"LeftPaddingColumn");
        found.trailing = column(L"RightPaddingColumn");
        auto scale = root.RasterizationScale();
        found.leadingRoom = window.TitleBar().LeftInset() / scale;
        found.trailingRoom = window.TitleBar().RightInset() / scale;
        return found;
    }

    /// Caps the room the bar keeps for the window's own buttons at theirs: WinUI keeps it in pixels, unscaled
    /// (microsoft-ui-xaml #10344), and a cap leaves a room WinUI keeps right as it is.
    /// Design: docs/design/platforms/winui/pages.md#the-windows-chrome
    void capCaptionRoom(controls::TitleBar const &bar) {
        auto found = captionRoom(bar);
        if (found.leading) found.leading.MaxWidth(found.leadingRoom);
        if (found.trailing) found.trailing.MaxWidth(found.trailingRoom);
    }

    /// Whether the program is setting a row of tabs: a selection it makes - a tab chosen, or the row's own after
    /// the chosen tab is taken away - is heard by nobody.
    bool settingTabs = false;

    winrt::Windows::UI::Color color(uint32_t argb) {
        return {static_cast<uint8_t>(argb >> 24), static_cast<uint8_t>(argb >> 16), static_cast<uint8_t>(argb >> 8),
                static_cast<uint8_t>(argb)};
    }

    /// The title bar's right header: the page's actions, then the authored trailing content.
    controls::StackPanel rightHeader(controls::TitleBar const &bar) {
        return bar.RightHeader().as<controls::StackPanel>();
    }

    /// The title bar's left header: the app menu's button first, then the authored leading content.
    controls::StackPanel leftHeader(controls::TitleBar const &bar) {
        return bar.LeftHeader().as<controls::StackPanel>();
    }

    void fill(controls::ContentControl const &slot, SwiftOmniUIObjectRef element) {
        auto shown = element ? as<xaml::UIElement>(element) : xaml::UIElement{nullptr};
        if (slot.Content() != shown) slot.Content(shown);
    }

    /// A split's pane content, which WinUI leaves drawn under an overlay it has closed, is collapsed or shown.
    void showSidebar(controls::NavigationView const &split, bool shown) {
        auto sidebar = split.PaneCustomContent();
        auto visibility = shown ? xaml::Visibility::Visible : xaml::Visibility::Collapsed;
        if (sidebar && sidebar.Visibility() != visibility) sidebar.Visibility(visibility);
    }

    /// Asks WinUI to measure `element` and everything in it again.
    void measureAgain(xaml::DependencyObject const &element) {
        if (auto each = element.try_as<xaml::UIElement>()) each.InvalidateMeasure();
        for (int32_t index = 0, count = xaml::Media::VisualTreeHelper::GetChildrenCount(element); index < count; ++index)
            measureAgain(xaml::Media::VisualTreeHelper::GetChild(element, index));
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_title_bar_make(int64_t view) {
    try {
        controls::TitleBar bar;
        bar.Tag(winrt::box_value(view));
        bar.BackRequested(guarded("handling BackRequested",
            [view](controls::TitleBar const &, IInspectable const &) { callbacks.chosen(view, -1); }));
        bar.PaneToggleRequested(guarded("handling PaneToggleRequested",
            [view](controls::TitleBar const &, IInspectable const &) { callbacks.chosen(view, -2); }));
        controls::StackPanel left;
        left.Orientation(controls::Orientation::Horizontal);
        left.Spacing(4);
        left.Children().Append(controls::ContentControl());
        left.Children().Append(controls::ContentControl());
        controls::CommandBar leadingActions;
        leadingActions.Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        leadingActions.VerticalAlignment(xaml::VerticalAlignment::Center);
        left.Children().Append(leadingActions);
        bar.LeftHeader(left);
        bar.Content(controls::ContentControl());
        bar.Loaded(guarded("handling Loaded", [](IInspectable const &sender, xaml::RoutedEventArgs const &) {
            auto titleBar = sender.as<controls::TitleBar>();
            unaccelerate(titleBar, VirtualKey::Left, VirtualKeyModifiers::Menu);
            unaccelerate(titleBar, VirtualKey::GoBack, VirtualKeyModifiers::None);
            capCaptionRoom(titleBar);
        }));
        bar.SizeChanged(guarded("handling SizeChanged",
            [](IInspectable const &sender, xaml::SizeChangedEventArgs const &) {
            capCaptionRoom(sender.as<controls::TitleBar>());
        }));

        controls::CommandBar actions;
        actions.DefaultLabelPosition(controls::CommandBarDefaultLabelPosition::Right);
        actions.Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        actions.VerticalAlignment(xaml::VerticalAlignment::Center);
        controls::StackPanel right;
        right.Orientation(controls::Orientation::Horizontal);
        right.Children().Append(actions);
        right.Children().Append(controls::ContentControl());
        bar.RightHeader(right);
        return detach(bar);
    } catch (...) {
        report("making a title bar");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_title_bar_set(
    SwiftOmniUIObjectRef handle, char const *title, bool back, bool paneToggle, bool hasBackground, uint32_t background,
    bool hasForeground, uint32_t foreground, int32_t words
) {
    try {
        auto bar = borrow<controls::TitleBar>(handle);
        if (bar.Title() != text(title)) bar.Title(text(title));
        bar.IsBackButtonVisible(back);
        bar.IsPaneToggleButtonVisible(paneToggle);
        if (hasBackground) bar.Background(media::SolidColorBrush(color(background)));
        else bar.ClearValue(controls::Control::BackgroundProperty());
        if (hasForeground) bar.Foreground(media::SolidColorBrush(color(foreground)));
        else bar.ClearValue(controls::Control::ForegroundProperty());
        auto theme = words == 1 ? xaml::ElementTheme::Dark
            : words == 2 ? xaml::ElementTheme::Light : xaml::ElementTheme::Default;
        if (bar.RequestedTheme() != theme) bar.RequestedTheme(theme);
    } catch (...) {
        report("setting a title bar");
    }
}

extern "C" void swiftomniui_winui_title_bar_caption_room(SwiftOmniUIObjectRef handle, double *kept, double *room) {
    try {
        auto found = captionRoom(borrow<controls::TitleBar>(handle));
        *kept = found.trailing ? found.trailing.ActualWidth() : -1;
        *room = found.trailingRoom;
    } catch (...) {
        report("reading the room a title bar keeps");
    }
}

extern "C" int32_t swiftomniui_winui_title_bar_words(SwiftOmniUIObjectRef handle) {
    try {
        switch (borrow<controls::TitleBar>(handle).RequestedTheme()) {
        case xaml::ElementTheme::Dark: return 1;
        case xaml::ElementTheme::Light: return 2;
        default: return 0;
        }
    } catch (...) {
        report("reading a title bar's words");
        return 0;
    }
}

extern "C" void swiftomniui_winui_title_bar_set_actions(
    SwiftOmniUIObjectRef handle, char const *const *texts, char const *const *identifiers, char const *const *icons,
    char const *const *symbols, bool const *overflows, bool const *enabled, SwiftOmniUIObjectRef const *contents,
    int32_t const *kinds,
    int32_t count, int32_t leadingCount
) {
    try {
        auto bar = borrow<controls::TitleBar>(handle);
        auto view = winrt::unbox_value<int64_t>(bar.Tag());
        auto actions = rightHeader(bar).Children().GetAt(0).as<controls::CommandBar>();
        auto leading = leftHeader(bar).Children().GetAt(2).as<controls::CommandBar>();
        leading.PrimaryCommands().Clear();
        leading.SecondaryCommands().Clear();
        actions.PrimaryCommands().Clear();
        actions.SecondaryCommands().Clear();
        for (int32_t index = 0; index < count; ++index) {
            auto commands = index < leadingCount ? leading.PrimaryCommands()
                : overflows[index] ? actions.SecondaryCommands() : actions.PrimaryCommands();
            // A spacer: the platform's gap between entries, or all the room a flexible one takes - both a
            // separator here, a CommandBar having no stretchable room of its own.
            if (kinds[index] != 0) {
                commands.Append(controls::AppBarSeparator());
                continue;
            }
            // A view the item carries stands in the button's place, in a container the bar knows.
            if (contents[index]) {
                controls::AppBarElementContainer container;
                container.VerticalContentAlignment(xaml::VerticalAlignment::Center);
                container.Content(borrow<xaml::UIElement>(contents[index]));
                commands.Append(container);
                continue;
            }
            controls::AppBarButton button;
            button.Label(text(texts[index]));
            button.IsEnabled(enabled[index]);
            if (identifiers[index] && *identifiers[index]) {
                xaml::Automation::AutomationProperties::SetAutomationId(button, text(identifiers[index]));
            }
            // An action with a picture shows the picture alone; its words name it to Narrator and in its tip. A
            // symbol is a Segoe Fluent glyph, as an Image draws one.
            controls::IconElement icon{nullptr};
            if (auto file = pictureFile(icons[index]); !file.empty()) {
                controls::ImageIcon image;
                image.Source(pictureSource(file));
                image.Tag(winrt::box_value(winrt::hstring(file)));
                icon = image;
            } else if (symbols[index] && *symbols[index]) {
                controls::FontIcon glyph;
                glyph.FontFamily(media::FontFamily(L"Segoe Fluent Icons"));
                glyph.Glyph(text(symbols[index]));
                icon = glyph;
            }
            if (icon) {
                button.Icon(icon);
                button.LabelPosition(controls::CommandBarLabelPosition::Collapsed);
                controls::ToolTipService::SetToolTip(button, winrt::box_value(text(texts[index])));
            }
            button.Click(guarded("handling Click", [view, index](IInspectable const &, xaml::RoutedEventArgs const &) {
                callbacks.chosen(view, index);
            }));
            commands.Append(button);
        }
    } catch (...) {
        report("setting a title bar's actions");
    }
}

extern "C" void swiftomniui_winui_title_bar_set_slots(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef leading, SwiftOmniUIObjectRef center, SwiftOmniUIObjectRef trailing
) {
    try {
        auto bar = borrow<controls::TitleBar>(handle);
        fill(leftHeader(bar).Children().GetAt(1).as<controls::ContentControl>(), leading);
        fill(bar.Content().as<controls::ContentControl>(), center);
        fill(rightHeader(bar).Children().GetAt(1).as<controls::ContentControl>(), trailing);
    } catch (...) {
        report("filling a title bar");
    }
}

extern "C" void swiftomniui_winui_title_bar_set_app_menu(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef button) {
    try {
        fill(leftHeader(borrow<controls::TitleBar>(handle)).Children().GetAt(0).as<controls::ContentControl>(),
            button);
    } catch (...) {
        report("filling a title bar's app menu");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_split_make(int64_t view, double expandsAt) {
    try {
        controls::NavigationView split;
        split.PaneDisplayMode(controls::NavigationViewPaneDisplayMode::Auto);
        split.CompactModeThresholdWidth(expandsAt);
        split.ExpandedModeThresholdWidth(expandsAt);
        split.CompactPaneLength(0);
        split.IsSettingsVisible(false);
        split.IsBackButtonVisible(controls::NavigationViewBackButtonVisible::Collapsed);
        split.IsPaneToggleButtonVisible(false);
        split.IsTitleBarAutoPaddingEnabled(false);
        split.Content(rows({true, false}));
        // The pane's own content stands in a row sized to what it holds, so a sidebar's scroller would never scroll.
        // Design: docs/design/platforms/winui/pages.md#a-split-view
        split.Loaded(guarded("handling Loaded", [](IInspectable const &sender, xaml::RoutedEventArgs const &) {
            auto split = sender.as<controls::NavigationView>();
            auto sidebar = first<controls::ContentControl>(split, L"PaneCustomContentBorder");
            auto items = first<controls::Grid>(split, L"ItemsContainerGrid");
            auto pane = sidebar ? xaml::Media::VisualTreeHelper::GetParent(sidebar).try_as<controls::Grid>() : nullptr;
            if (!pane || !items) return;
            auto rows = pane.RowDefinitions();
            rows.GetAt(controls::Grid::GetRow(sidebar)).Height(xaml::GridLengthHelper::FromValueAndType(1, xaml::GridUnitType::Star));
            rows.GetAt(controls::Grid::GetRow(items)).Height(xaml::GridLengthHelper::Auto());
            // Laid out once already, in the row sized to what it holds: measured again, it takes the pane's height.
            measureAgain(sidebar);
        }));
        split.PaneOpening(guarded("handling PaneOpening",
            [view](controls::NavigationView const &sender, IInspectable const &) {
            showSidebar(sender, true);
            callbacks.presented(view, true);
        }));
        split.PaneClosing(guarded("handling PaneClosing",
            [view](controls::NavigationView const &, controls::NavigationViewPaneClosingEventArgs const &) {
            callbacks.presented(view, false);
        }));
        split.PaneClosed(guarded("handling PaneClosed",
            [](controls::NavigationView const &sender, IInspectable const &) {
            if (!sender.IsPaneOpen()) showSidebar(sender, false);
        }));
        split.DisplayModeChanged(guarded("handling DisplayModeChanged",
            [](controls::NavigationView const &sender, IInspectable const &) {
            if (!sender.IsPaneOpen()) showSidebar(sender, false);
        }));
        return detach(split);
    } catch (...) {
        report("making a split view");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_split_set(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef pane, SwiftOmniUIObjectRef content, SwiftOmniUIObjectRef row, bool open,
    double paneLength
) {
    try {
        auto split = borrow<controls::NavigationView>(handle);
        auto sidebar = pane ? as<xaml::UIElement>(pane) : xaml::UIElement{nullptr};
        bool anew = split.PaneCustomContent() != sidebar;
        if (anew) split.PaneCustomContent(sidebar);
        auto detail = split.Content().as<controls::Grid>();
        standInRow(detail, 0, row);
        standInRow(detail, 1, content);
        // A pane over the detail collapses its sidebar once it has closed; one beside it tells no closing, and a
        // view WinUI has not loaded, or a new sidebar, tells nothing.
        bool beside = split.DisplayMode() == controls::NavigationViewDisplayMode::Expanded;
        if (open || anew || beside || !split.IsLoaded()) showSidebar(split, open);
        if (split.IsPaneOpen() != open) split.IsPaneOpen(open);
        if (paneLength > 0 && split.OpenPaneLength() != paneLength) split.OpenPaneLength(paneLength);
    } catch (...) {
        report("setting a split view");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_tabs_make(int64_t view) {
    try {
        controls::SelectorBar tabs;
        tabs.SelectionChanged(guarded("handling SelectionChanged",
            [view](controls::SelectorBar const &sender, controls::SelectorBarSelectionChangedEventArgs const &) {
            if (settingTabs) return;
            uint32_t index = 0;
            if (sender.SelectedItem() && sender.Items().IndexOf(sender.SelectedItem(), index)) {
                callbacks.chosen(view, static_cast<int32_t>(index));
            }
        }));
        return detach(tabs);
    } catch (...) {
        report("making a row of tabs");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_tabs_choose_as_user(SwiftOmniUIObjectRef handle, int32_t index) {
    try {
        // The row's own selection, which the user's click makes and SelectionChanged tells.
        auto tabs = borrow<controls::SelectorBar>(handle);
        if (index >= 0 && index < static_cast<int32_t>(tabs.Items().Size())) tabs.SelectedItem(tabs.Items().GetAt(index));
    } catch (...) {
        report("choosing a tab as the user");
    }
}

extern "C" void swiftomniui_winui_tabs_set(SwiftOmniUIObjectRef handle, char const *const *titles, int32_t count, int32_t selected) {
    struct Setting {
        Setting() { settingTabs = true; }
        ~Setting() { settingTabs = false; }
    } setting;
    try {
        auto tabs = borrow<controls::SelectorBar>(handle);
        auto items = tabs.Items();
        while (static_cast<int32_t>(items.Size()) > count) items.RemoveAtEnd();
        for (int32_t index = 0; index < count; ++index) {
            if (index >= static_cast<int32_t>(items.Size())) items.Append(controls::SelectorBarItem());
            auto item = items.GetAt(index);
            if (item.Text() != text(titles[index])) item.Text(text(titles[index]));
        }
        if (selected >= 0 && selected < count && tabs.SelectedItem() != items.GetAt(selected)) {
            tabs.SelectedItem(items.GetAt(selected));
        }
    } catch (...) {
        report("setting a row of tabs");
    }
}

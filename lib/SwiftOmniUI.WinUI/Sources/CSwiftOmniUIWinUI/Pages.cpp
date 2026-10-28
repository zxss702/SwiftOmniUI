// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The native parts of a window and its arrangements of pages: the window's
// chrome in WinUI's TitleBar, native SplitViews, and a row of tabs.
// Each says what the user chose by the view's number and the entry's place.
// Design: docs/design/platforms/winui/pages.md

#include "Relay.h"
#include "AcrylicScene.h"

#include <winrt/Microsoft.UI.Xaml.Automation.h>
#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Content.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Input.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>
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
        if (slot.Content() != shown) {
            slot.Content(shown);
            acrylicStructureChanged(slot);
        }
    }

    using SplitWidths = winrt::Windows::Foundation::Collections::IVector<double>;

    // Only the transparent Thumb is a hit target. Its overlay contributes no
    // desired size, and the cursor follows native hit testing and drag capture.
    struct SplitGrip : controls::PanelT<SplitGrip> {
        explicit SplitGrip(bool trailing) : trailing(trailing) {}

        void resizeCursor() {
            ProtectedCursor(winrt::Microsoft::UI::Input::InputSystemCursor::Create(
                winrt::Microsoft::UI::Input::InputSystemCursorShape::SizeWestEast));
        }

        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size room) {
            Children().GetAt(0).Measure({6, room.Height});
            return {0, 0};
        }

        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size room) {
            auto width = std::min(6.0f, room.Width);
            Children().GetAt(0).Arrange({trailing ? 0.0f : room.Width - width, 0, width, room.Height});
            return room;
        }

        bool trailing;
    };

    // The native pane remembers a user-resized width independently of the modifier's ideal.
    // Tag holds minimum, ideal, maximum, user width, breakpoint, and content minimum/maximum.
    struct SplitRoom {
        bool beside;
        double length;
    };

    SplitRoom splitRoom(controls::SplitView const &split, double width, bool alone) {
        auto widths = split.Tag().as<SplitWidths>();
        // Before attachment there is no native allocation. Do not undo the
        // initial mode selected from the window's known client width.
        bool beside = split.DisplayMode() == controls::SplitViewDisplayMode::Inline;
        if (width > 0 || widths.GetAt(4) == 0 || alone)
            beside = widths.GetAt(4) == 0 || alone
                || width >= std::max(widths.GetAt(4), widths.GetAt(0) + widths.GetAt(5));
        auto length = std::clamp(widths.GetAt(3), widths.GetAt(0), widths.GetAt(2));
        if (width > 0 && beside) {
            auto least = std::max(widths.GetAt(0), width - widths.GetAt(6));
            auto most = std::max(least, std::min(widths.GetAt(2), width - widths.GetAt(5)));
            length = alone ? width : std::min(width, std::clamp(length, least, most));
        }
        return {beside, length};
    }

    void sizeSplit(controls::SplitView const &split, double width) {
        auto widths = split.Tag().as<SplitWidths>();
        bool alone = split.Content().as<controls::Grid>().Visibility() == xaml::Visibility::Collapsed;
        auto pane = split.Pane().as<controls::Grid>();
        auto grip = pane.Children().GetAt(1);
        bool resizable = widths.GetAt(0) < widths.GetAt(2);
        auto [beside, length] = splitRoom(split, width, alone);
        auto mode = beside ? controls::SplitViewDisplayMode::Inline : controls::SplitViewDisplayMode::Overlay;
        // The mode can already be Inline when its default style first loads.
        // Do not leave that first pane using the opaque native chrome brush.
        if (beside) {
            auto fill = split.PaneBackground().try_as<media::SolidColorBrush>();
            if (!fill || fill.Color().A != 0)
                split.PaneBackground(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        }
        if (split.DisplayMode() != mode) {
            // Inline columns reveal the window surface. An overlay needs the
            // native themed pane brush to cover the detail behind it.
            if (!beside) split.ClearValue(controls::SplitView::PaneBackgroundProperty());
            split.DisplayMode(mode);
        }
        bool handleShown = split.IsPaneOpen() && beside && !alone && resizable;
        grip.Visibility(handleShown ? xaml::Visibility::Visible : xaml::Visibility::Collapsed);
        if (split.OpenPaneLength() != length) split.OpenPaneLength(length);
        // SplitView can measure a closed pane at zero while arranging its
        // sliding content at OpenPaneLength. The pane's content has that
        // declared width even while the native template clips it away.
        // Keep its Measure and Arrange proposals on the same native boundary.
        if (pane.Width() != length) pane.Width(length);
    }

    void sizeSplit(controls::SplitView const &split) { sizeSplit(split, split.ActualWidth()); }

    void resizeSplit(controls::SplitView const &split, double change) {
        auto widths = split.Tag().as<SplitWidths>();
        auto available = std::max(0.0, split.ActualWidth());
        auto least = std::max(widths.GetAt(0), available - widths.GetAt(6));
        auto most = std::max(least, std::min(widths.GetAt(2), available - widths.GetAt(5)));
        bool trailing = split.PanePlacement() == controls::SplitViewPanePlacement::Right;
        auto length = split.OpenPaneLength() + (trailing ? -change : change);
        widths.SetAt(3, std::clamp(length, least, most));
        sizeSplit(split);
    }

}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_title_bar_make(int64_t view) {
    try {
        controls::TitleBar bar;
        bar.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        // Keep an 8-DIP gap between the trailing toolbar and native caption
        // buttons instead of TitleBar's default 48-DIP drag strip.
        bar.Resources().Insert(winrt::box_value(L"TitleBarMinDragRegionWidth"), winrt::box_value(8.0));
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

extern "C" double swiftomniui_winui_title_bar_layout_height(SwiftOmniUIObjectRef handle) {
    try {
        auto bar = borrow<controls::TitleBar>(handle);
        // This is TitleBar::UpdateHeight's state selection. Its template has
        // a declared row height, independent of the commands it contains.
        // Before activation, native Measure can still answer DesiredSize=0;
        // that provisional answer must not determine the window's first size.
        auto key = winrt::box_value(bar.Content() || bar.LeftHeader() || bar.RightHeader()
            ? L"TitleBarExpandedHeight" : L"TitleBarCompactHeight");
        auto value = bar.Resources().TryLookup(key);
        if (!value) value = xaml::Application::Current().Resources().Lookup(key);
        return winrt::unbox_value<double>(value);
    } catch (...) {
        report("reading a title bar's declared row height");
        return 0;
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
        else bar.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        if (hasForeground) bar.Foreground(media::SolidColorBrush(color(foreground)));
        else bar.ClearValue(controls::Control::ForegroundProperty());
        auto theme = words == 1 ? xaml::ElementTheme::Dark
            : words == 2 ? xaml::ElementTheme::Light : xaml::ElementTheme::Default;
        if (bar.RequestedTheme() != theme) bar.RequestedTheme(theme);
    } catch (...) {
        report("setting a title bar");
    }
}

extern "C" void swiftomniui_winui_title_bar_set_subtitle(SwiftOmniUIObjectRef handle, char const *subtitle) {
    try {
        auto bar = borrow<controls::TitleBar>(handle);
        auto value = text(subtitle);
        if (bar.Subtitle() != value) bar.Subtitle(value);
    } catch (...) {
        report("setting a title bar subtitle");
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

namespace {
    /// The picture a bar's button shows: the first of its files the application's pictures hold, else the Fluent
    /// glyph its symbol is; none for words alone.
    controls::IconElement barIcon(char const *symbol, char const *icons) {
        if (auto file = pictureFile(icons); !file.empty()) {
            controls::ImageIcon image;
            image.Source(pictureSource(file));
            image.Tag(winrt::box_value(winrt::hstring(file)));
            return image;
        }
        if (symbol && *symbol) {
            controls::FontIcon glyph;
            glyph.FontFamily(media::FontFamily(L"Segoe Fluent Icons"));
            glyph.Glyph(text(symbol));
            return glyph;
        }
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_toolbar_button_set_icon(SwiftOmniUIObjectRef handle, char const *symbol, char const *icons) {
    try {
        // A picture stands in the icon slot and the words move to the tip; words alone are the label.
        auto icon = barIcon(symbol, icons);
        auto control = borrow<controls::Control>(handle);
        auto place = [&](auto const &command) {
            command.Icon(icon);
            auto words = command.Label();
            bool collapsed = icon || words.empty();
            command.LabelPosition(collapsed ? controls::CommandBarLabelPosition::Collapsed
                                            : controls::CommandBarLabelPosition::Default);
            // Showing its icon alone, the button stands as wide as the bar's own back and pane buttons - the
            // system gives those 40. Words alone keep the default width, which a label needs.
            if (collapsed) command.Width(40);
            else command.ClearValue(xaml::FrameworkElement::WidthProperty());
            if (icon && !words.empty()) controls::ToolTipService::SetToolTip(command, winrt::box_value(words));
        };
        if (auto toggle = control.try_as<controls::AppBarToggleButton>()) return place(toggle);
        if (auto command = control.try_as<controls::AppBarButton>()) return place(command);
    } catch (...) {
        report("giving a toolbar button its icon");
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
        using Command = controls::ICommandBarElement;
        using Commands = winrt::Windows::Foundation::Collections::IObservableVector<Command>;
        std::array<Commands, 4> lists{leading.PrimaryCommands(), leading.SecondaryCommands(),
                                     actions.PrimaryCommands(), actions.SecondaryCommands()};
        std::array<std::vector<Command>, 4> desired;
        std::vector<Command> previous;
        for (auto const &list : lists)
            for (auto const &command : list) previous.push_back(command);
        for (int32_t index = 0; index < count; ++index) {
            auto &commands = desired[index < leadingCount ? 0 : overflows[index] ? 3 : 2];
            // A spacer: the platform's gap between entries, or all the room a flexible one takes - both a
            // separator here, a CommandBar having no stretchable room of its own.
            if (kinds[index] != 0) {
                commands.push_back(controls::AppBarSeparator());
                continue;
            }
            // A view the item carries stands in the button's place: the bar's own button as a command, any other in
            // a container the bar knows.
            if (contents[index]) {
                auto content = borrow<xaml::UIElement>(contents[index]);
                if (auto command = content.try_as<controls::ICommandBarElement>()) {
                    commands.push_back(command);
                    continue;
                }
                // Reuse the container too: an element can have only one
                // parent. Replacing it unloads focused inputs and may leave
                // their content attached to a discarded container.
                controls::AppBarElementContainer container{nullptr};
                for (auto const &old : previous) {
                    auto candidate = old.try_as<controls::AppBarElementContainer>();
                    if (candidate && candidate.Content() == content) { container = candidate; break; }
                }
                if (!container) {
                    container = controls::AppBarElementContainer();
                    container.VerticalContentAlignment(xaml::VerticalAlignment::Center);
                    container.Content(content);
                }
                commands.push_back(container);
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
            auto icon = barIcon(symbols[index], icons[index]);
            if (icon) {
                button.Icon(icon);
                button.LabelPosition(controls::CommandBarLabelPosition::Collapsed);
                // As wide as the bar's own back and pane buttons - the system gives those 40. The AppBarButton
                // default is a labelled command bar's width, which an icon alone does not need.
                button.Width(40);
                controls::ToolTipService::SetToolTip(button, winrt::box_value(text(texts[index])));
            }
            button.Click(guarded("handling Click", [view, index](IInspectable const &, xaml::RoutedEventArgs const &) {
                callbacks.chosen(view, index);
            }));
            commands.push_back(button);
        }
        // Remove only departing commands before inserting their replacements.
        // Inserting a new neighbor shifts retained inputs without unloading
        // them, preserving keyboard focus, selection and composition.
        for (size_t group = 0; group < lists.size(); ++group) {
            auto const &commands = lists[group];
            auto const &next = desired[group];
            for (uint32_t at = 0; at < commands.Size();) {
                if (std::find(next.begin(), next.end(), commands.GetAt(at)) == next.end()) commands.RemoveAt(at);
                else ++at;
            }
        }
        for (size_t group = 0; group < lists.size(); ++group) {
            auto const &commands = lists[group];
            auto const &next = desired[group];
            for (uint32_t at = 0; at < next.size(); ++at) {
                if (at < commands.Size() && commands.GetAt(at) == next[at]) continue;
                uint32_t old;
                if (commands.IndexOf(next[at], old)) commands.RemoveAt(old);
                commands.InsertAt(at, next[at]);
            }
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

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_split_make(int64_t view, double expandsAt, bool trailing) {
    try {
        controls::SplitView split;
        split.HorizontalContentAlignment(xaml::HorizontalAlignment::Stretch);
        split.VerticalContentAlignment(xaml::VerticalAlignment::Stretch);
        split.CompactPaneLength(0);
        split.PanePlacement(trailing ? controls::SplitViewPanePlacement::Right : controls::SplitViewPanePlacement::Left);
        if (trailing) {
            // The auxiliary split is always inline and open. WinUI's default
            // OpenInlineRight storyboard temporarily restores the left-pane
            // column widths whenever OpenPaneLength changes, measuring the
            // conversation at the auxiliary width before correcting next frame.
            // Bind these two columns directly; the outer split retains WinUI's
            // adaptive/overlay template and its presentation transitions.
            split.Template(xaml::Markup::XamlReader::Load(
                LR"(<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="SplitView">
                    <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                        <ContentPresenter Content="{TemplateBinding Content}" HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch"/>
                        <ContentPresenter Grid.Column="1" Content="{TemplateBinding Pane}" Width="{TemplateBinding OpenPaneLength}"
                                          HorizontalContentAlignment="Stretch" VerticalContentAlignment="Stretch"/>
                    </Grid>
                </ControlTemplate>)").as<controls::ControlTemplate>());
        }
        split.Tag(winrt::single_threaded_vector<double>({0, 256, INFINITY, 256, expandsAt, 0, INFINITY}));
        split.RegisterPropertyChangedCallback(controls::SplitView::OpenPaneLengthProperty(),
            guarded("changing a split column's width", [view](xaml::DependencyObject const &sender, xaml::DependencyProperty const &) {
                auto split = sender.as<controls::SplitView>();
                if (auto pane = split.Pane().try_as<controls::Grid>(); pane && pane.Width() != split.OpenPaneLength())
                    pane.Width(split.OpenPaneLength());
                callbacks.paneWidthChanged(view);
            }));
        split.Content(rows({true, false}));
        controls::Grid pane;
        pane.Width(split.OpenPaneLength());
        controls::ContentControl face;
        face.HorizontalContentAlignment(xaml::HorizontalAlignment::Stretch);
        face.VerticalContentAlignment(xaml::VerticalAlignment::Stretch);
        controls::Primitives::Thumb grip;
        grip.Template(xaml::Markup::XamlReader::Load(
            LR"(<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                                 TargetType="Thumb"><Grid Background="Transparent" /></ControlTemplate>)")
            .as<controls::ControlTemplate>());
        xaml::Automation::AutomationProperties::SetName(grip, trailing ? L"Resize detail column" : L"Resize sidebar column");
        grip.UseSystemFocusVisuals(false);
        grip.VerticalAlignment(xaml::VerticalAlignment::Stretch);
        auto gripOverlay = winrt::make<SplitGrip>(trailing).as<controls::Panel>();
        gripOverlay.Children().Append(grip);
        gripOverlay.Loaded(guarded("setting a split resize cursor",
            [](IInspectable const &sender, xaml::RoutedEventArgs const &) {
                winrt::get_self<SplitGrip>(sender.as<xaml::IFrameworkElementOverrides>())->resizeCursor();
            }));
        pane.Children().Append(face);
        pane.Children().Append(gripOverlay);
        split.Pane(pane);
        auto weak = winrt::make_weak(split);
        grip.DragDelta(guarded("resizing a split column",
            [weak](IInspectable const &, controls::Primitives::DragDeltaEventArgs const &args) {
                if (auto split = weak.get()) resizeSplit(split, args.HorizontalChange());
            }));
        split.SizeChanged(guarded("sizing a split view", [](IInspectable const &sender, xaml::SizeChangedEventArgs const &) {
            sizeSplit(sender.as<controls::SplitView>());
        }));
        split.PaneOpening(guarded("handling PaneOpening",
            [view](controls::SplitView const &, IInspectable const &) {
                callbacks.presented(view, true);
            }));
        split.PaneClosing(guarded("handling PaneClosing",
            [view](controls::SplitView const &, controls::SplitViewPaneClosingEventArgs const &) {
                callbacks.presented(view, false);
            }));
        return detach(split);
    } catch (...) {
        report("making a split view");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_split_prepare_room(SwiftOmniUIObjectRef handle, double width) {
    try {
        if (std::isfinite(width) && width > 0) sizeSplit(borrow<controls::SplitView>(handle), width);
    } catch (...) { report("preparing a split view's initial room"); }
}

extern "C" void swiftomniui_winui_split_resize(SwiftOmniUIObjectRef handle, double change) {
    try {
        if (std::isfinite(change)) resizeSplit(borrow<controls::SplitView>(handle), change);
    } catch (...) { report("resizing a split column"); }
}

extern "C" void swiftomniui_winui_split_clear(SwiftOmniUIObjectRef handle) {
    try {
        auto split = borrow<controls::SplitView>(handle);
        split.Pane().as<controls::Grid>().Children().GetAt(0).as<controls::ContentControl>().Content(nullptr);
        split.Content().as<controls::Grid>().Children().Clear();
        acrylicStructureChanged(split);
    } catch (...) { report("releasing split columns"); }
}

extern "C" double swiftomniui_winui_split_minimum_width(SwiftOmniUIObjectRef handle) {
    try {
        auto split = borrow<controls::SplitView>(handle);
        auto widths = split.Tag().as<SplitWidths>();
        bool contentShown = split.Content().as<controls::Grid>().Visibility() == xaml::Visibility::Visible;
        auto minimum = contentShown ? widths.GetAt(5) : 0;
        if (split.IsPaneOpen()) minimum += widths.GetAt(0);
        return minimum;
    } catch (...) { report("reading split column bounds"); return 0; }
}

extern "C" void swiftomniui_winui_split_remove(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef child) {
    try {
        auto split = borrow<controls::SplitView>(handle);
        auto element = as<xaml::UIElement>(child);
        auto face = split.Pane().as<controls::Grid>().Children().GetAt(0).as<controls::ContentControl>();
        if (face.Content() == element) face.Content(nullptr);
        auto children = split.Content().as<controls::Grid>().Children();
        uint32_t index;
        if (children.IndexOf(element, index)) children.RemoveAt(index);
    } catch (...) { report("releasing a split slot"); }
}

extern "C" void swiftomniui_winui_split_set(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef pane, SwiftOmniUIObjectRef content, SwiftOmniUIObjectRef row, bool open,
    double minimum, double ideal, double maximum, bool contentShown, double contentMinimum, double contentMaximum
) {
    try {
        auto split = borrow<controls::SplitView>(handle);
        auto widths = split.Tag().as<SplitWidths>();
        if (widths.GetAt(0) != minimum || widths.GetAt(1) != ideal || widths.GetAt(2) != maximum) {
            widths.SetAt(0, minimum);
            widths.SetAt(1, ideal);
            widths.SetAt(2, maximum);
            widths.SetAt(3, std::clamp(ideal, minimum, maximum));
        }
        widths.SetAt(5, contentMinimum);
        widths.SetAt(6, contentMaximum);
        auto face = split.Pane().as<controls::Grid>().Children().GetAt(0).as<controls::ContentControl>();
        fill(face, pane);
        // IsPaneOpen and the SplitView template own pane visibility. Collapsing
        // its content separately adds another layout/visibility lifecycle.
        auto detail = split.Content().as<controls::Grid>();
        detail.MinWidth(contentMinimum);
        detail.MaxWidth(contentMaximum);
        detail.Visibility(contentShown ? xaml::Visibility::Visible : xaml::Visibility::Collapsed);
        standInRow(detail, 0, row);
        standInRow(detail, 1, content);
        acrylicStructureChanged(split);
        if (split.IsPaneOpen() != open) split.IsPaneOpen(open);
        sizeSplit(split);
    } catch (...) {
        report("setting a split view");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_tabs_make(int64_t view) {
    try {
        controls::SelectorBar tabs;
        tabs.Background(media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
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

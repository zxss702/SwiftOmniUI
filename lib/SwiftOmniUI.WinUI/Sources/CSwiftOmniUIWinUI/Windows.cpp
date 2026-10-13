// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A window: its title, and a root of four rows - the window's chrome, its
// menu bar, the row of tabs, and the arrangement of pages - with the overlay
// laid over the page, shown and closed; its activation and its minimizing
// told as the application's phase.
// Design: docs/design/platforms/winui/pages.md#the-windows-chrome

#include "Relay.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Input.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace swiftomniui;
using winrt::Windows::System::VirtualKey;
using winrt::Windows::System::VirtualKeyModifiers;

namespace windowing = winrt::Microsoft::UI::Windowing;

namespace {
    controls::Grid root(xaml::Window const &window) {
        return window.Content().as<controls::Grid>();
    }

    /// The window's way back - the mouse's back button, Alt+Left and the Back key - chosen on its chrome as -1; and
    /// Escape, which takes a sheet away.
    void takeTheWayBack(controls::Grid const &grid, int64_t chrome) {
        grid.AddHandler(
            xaml::UIElement::PointerPressedEvent(),
            winrt::box_value(xaml::Input::PointerEventHandler(guarded("handling PointerPressed",
                [chrome](IInspectable const &sender, xaml::Input::PointerRoutedEventArgs const &args) {
                    auto point = args.GetCurrentPoint(sender.as<xaml::UIElement>());
                    if (!point.Properties().IsXButton1Pressed()) return;
                    callbacks.chosen(chrome, -1);
                    args.Handled(true);
                }))),
            true);
        // Hidden keeps the accelerators' tooltip from showing on hover - an accelerator added to a container
        // shows it over whatever child the pointer rests on (microsoft-ui-xaml#8), and over an airspace island
        // like a WebView the pointer never reaches XAML to close it again.
        grid.KeyboardAcceleratorPlacementMode(xaml::Input::KeyboardAcceleratorPlacementMode::Hidden);
        auto accelerate = [&](VirtualKey key, VirtualKeyModifiers modifiers) {
            xaml::Input::KeyboardAccelerator accelerator;
            accelerator.Key(key);
            accelerator.Modifiers(modifiers);
            accelerator.Invoked(guarded("handling Invoked",
                [chrome](auto const &, xaml::Input::KeyboardAcceleratorInvokedEventArgs const &args) {
                callbacks.chosen(chrome, -1);
                args.Handled(true);
            }));
            grid.KeyboardAccelerators().Append(accelerator);
        };
        accelerate(VirtualKey::Left, VirtualKeyModifiers::Menu);
        accelerate(VirtualKey::GoBack, VirtualKeyModifiers::None);

        // Escape takes the top sheet away, chosen on the chrome as -3; with no sheet it is left to whatever has it.
        xaml::Input::KeyboardAccelerator escape;
        escape.Key(VirtualKey::Escape);
        escape.Invoked(guarded("handling Invoked",
            [chrome](auto const &, xaml::Input::KeyboardAcceleratorInvokedEventArgs const &args) {
            auto root = args.Element().try_as<controls::Grid>();
            if (!root || !showsSheets(root)) return;
            callbacks.chosen(chrome, -3);
            args.Handled(true);
        }));
        grid.KeyboardAccelerators().Append(escape);
    }

    /// Whether `window` stands minimized.
    bool minimized(windowing::AppWindow const &window) {
        auto presenter = window.Presenter().try_as<windowing::OverlappedPresenter>();
        return presenter && presenter.State() == windowing::OverlappedPresenterState::Minimized;
    }

    /// Lets go of the windows `owner` owns, so Windows does not destroy them with it: each closes as the tree
    /// closes it. Only the application's own windows - a flyout's or a popup's window is left to its owner.
    void releaseOwned(HWND owner) {
        EnumThreadWindows(GetCurrentThreadId(), [](HWND each, LPARAM owner) -> BOOL {
            wchar_t name[64] = {};
            GetClassNameW(each, name, 64);
            if (GetWindow(each, GW_OWNER) == reinterpret_cast<HWND>(owner)
                && std::wcscmp(name, L"WinUIDesktopWin32WindowClass") == 0) {
                SetWindowLongPtrW(each, GWLP_HWNDPARENT, 0);
            }
            return TRUE;
        }, reinterpret_cast<LPARAM>(owner));
    }

    /// Whether `window` stands off the screen: minimized, or hidden.
    bool offScreen(windowing::AppWindow const &window) {
        return minimized(window) || !window.IsVisible();
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_window_make(int64_t number) {
    try {
        xaml::Window window;
        window.SystemBackdrop(xaml::Media::MicaBackdrop());
        window.Content(rows({true, true, true, false}));
        // The window's state is read at each of them: a minimized window is also told it lost its activation, and
        // one hidden - with the window it belongs to, or by its scene - stands off the screen as a minimized one.
        window.Activated(guarded("handling Activated",
            [number](IInspectable const &sender, xaml::WindowActivatedEventArgs const &args) {
            auto activated = args.WindowActivationState() != xaml::WindowActivationState::Deactivated;
            // A window UI Automation closes is told it lost its activation once its AppWindow is gone: off the screen.
            auto hidden = true;
            try {
                hidden = offScreen(sender.as<xaml::Window>().AppWindow());
            } catch (winrt::hresult_invalid_argument const &) {
            }
            callbacks.windowStateChanged(number, hidden, activated);
        }));
        window.AppWindow().Changed(
            guarded("handling Changed",
                [number](windowing::AppWindow const &sender, windowing::AppWindowChangedEventArgs const &args) {
                if (args.DidVisibilityChange()) {
                    auto active = GetActiveWindow() == reinterpret_cast<HWND>(sender.Id().Value);
                    callbacks.windowStateChanged(number, offScreen(sender), active && sender.IsVisible());
                    return;
                }
                if (!args.DidPresenterChange() && !args.DidSizeChange()) return;
                if (minimized(sender)) callbacks.windowStateChanged(number, true, false);
            }));
        window.Closed(guarded("handling Closed", [number](IInspectable const &sender, xaml::WindowEventArgs const &) {
            releaseOwned(reinterpret_cast<HWND>(sender.as<xaml::Window>().AppWindow().Id().Value));
            // windowClosed renders - and a render inside XAML's teardown of this very window touches what is
            // dying, so the tree hears of the close once the event is through.
            winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread().TryEnqueue(
                guarded("handling Closed", [number] { callbacks.windowClosed(number); }));
        }));
        return detach(window);
    } catch (...) {
        report("making a window");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_window_set_title(SwiftOmniUIObjectRef handle, char const *title) {
    try {
        borrow<xaml::Window>(handle).Title(text(title));
    } catch (...) {
        report("titling a window");
    }
}

extern "C" void swiftomniui_winui_window_set_content(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef content) {
    try {
        standInRow(root(borrow<xaml::Window>(handle)), 3, content);
    } catch (...) {
        report("filling a window");
    }
}

extern "C" void swiftomniui_winui_window_set_overlay(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef overlay) {
    try {
        auto children = root(borrow<xaml::Window>(handle)).Children();
        controls::Grid layer{nullptr};
        for (auto const &child : children)
            if (auto grid = child.try_as<controls::Grid>(); grid && winrt::unbox_value_or<winrt::hstring>(grid.Tag(), L"") == L"overlay")
                layer = grid;
        if (!layer && !overlay) return;
        if (!layer) {
            // Where the page stands, over it and over its sheets; with no background, a click beside what it holds
            // goes on to them.
            layer = controls::Grid();
            layer.Tag(winrt::box_value(L"overlay"));
            controls::Grid::SetRow(layer, 3);
            controls::Canvas::SetZIndex(layer, 3);
            children.Append(layer);
        }
        layer.Children().Clear();
        if (overlay) layer.Children().Append(as<xaml::UIElement>(overlay));
        else if (uint32_t index; children.IndexOf(layer, index)) children.RemoveAt(index);
    } catch (...) {
        report("laying the overlay over a window");
    }
}

extern "C" void swiftomniui_winui_window_set_safe_area_bars(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef const *bars, int32_t count,
    bool hasBackground, uint32_t background
) {
    try {
        auto children = root(borrow<xaml::Window>(handle)).Children();
        controls::Grid layer{nullptr};
        for (auto const &child : children)
            if (auto panel = child.try_as<controls::Grid>(); panel
                && winrt::unbox_value_or<winrt::hstring>(panel.Tag(), L"") == L"safeAreaBars") layer = panel;
        if (!layer && count == 0) return;
        if (!layer) {
            layer = controls::Grid();
            layer.Tag(winrt::box_value(L"safeAreaBars"));
            layer.VerticalAlignment(xaml::VerticalAlignment::Top);
            controls::Grid::SetRow(layer, 3);
            controls::Canvas::SetZIndex(layer, 1);
            controls::StackPanel stack;
            stack.Tag(winrt::box_value(L"safeAreaBarContent"));
            layer.Children().Append(stack);
            controls::Border edge;
            edge.Tag(winrt::box_value(L"safeAreaBarEdge"));
            edge.Height(1);
            edge.VerticalAlignment(xaml::VerticalAlignment::Bottom);
            edge.IsHitTestVisible(false);
            edge.Opacity(0);
            auto resources = xaml::Application::Current().Resources();
            auto key = winrt::box_value(L"ControlStrokeColorDefaultBrush");
            if (resources.HasKey(key)) edge.Background(resources.Lookup(key).try_as<xaml::Media::Brush>());
            else edge.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{48, 128, 128, 128}));
            layer.Children().Append(edge);
            children.Append(layer);
        }
        // Share the TitleBar's effective background, including the native
        // default; authored backgrounds stay on each original bar view.
        if (hasBackground) {
            winrt::Windows::UI::Color color{static_cast<uint8_t>(background >> 24),
                static_cast<uint8_t>(background >> 16), static_cast<uint8_t>(background >> 8),
                static_cast<uint8_t>(background)};
            layer.Background(xaml::Media::SolidColorBrush(color));
        } else {
            xaml::Media::Brush background{nullptr};
            for (auto const &child : children)
                if (auto title = child.try_as<controls::TitleBar>()) { background = title.Background(); break; }
            layer.Background(background);
        }
        auto held = layer.Children().GetAt(0).as<controls::StackPanel>().Children();
        bool same = held.Size() == static_cast<uint32_t>(count);
        for (int32_t index = 0; same && index < count; ++index)
            same = held.GetAt(index) == as<xaml::UIElement>(bars[index]);
        if (!same) {
            held.Clear();
            for (int32_t index = 0; index < count; ++index) held.Append(as<xaml::UIElement>(bars[index]));
        }
        if (count == 0) {
            uint32_t index;
            if (children.IndexOf(layer, index)) children.RemoveAt(index);
        }
    } catch (...) { report("hosting a page's safe area bars"); }
}

void swiftomniui::refreshSafeAreaScrollEdge(controls::ScrollView const &scroller) {
    // A nested document has its own edge effects; it cannot change the
    // page-level chrome. Walk native ancestors, never unrelated windows.
    auto ancestor = xaml::Media::VisualTreeHelper::GetParent(scroller);
    while (ancestor) {
        if (ancestor.try_as<controls::ScrollView>() || ancestor.try_as<controls::ScrollViewer>()) return;
        if (auto grid = ancestor.try_as<controls::Grid>()) {
            for (auto const &child : grid.Children()) {
                auto layer = child.try_as<controls::Grid>();
                if (!layer || winrt::unbox_value_or<winrt::hstring>(layer.Tag(), L"") != L"safeAreaBars") continue;
                auto edge = layer.Children().GetAt(1).as<controls::Border>();
                auto opacity = scroller.VerticalOffset() > 0.5 ? 1.0 : 0.0;
                if (edge.Opacity() != opacity) edge.Opacity(opacity);
                return;
            }
        }
        ancestor = xaml::Media::VisualTreeHelper::GetParent(ancestor);
    }
}

extern "C" void swiftomniui_winui_window_set_chrome(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef titleBar, SwiftOmniUIObjectRef menuBar, SwiftOmniUIObjectRef tabs
) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto grid = root(window);
        standInRow(grid, 0, titleBar);
        standInRow(grid, 1, menuBar);
        standInRow(grid, 2, tabs);
        // A page's scroller can extend into these rows. Native chrome stays
        // above that viewport, independent of the root grid's child order.
        for (auto handle : {titleBar, menuBar, tabs}) {
            if (handle) controls::Canvas::SetZIndex(as<xaml::UIElement>(handle), 2);
        }
        if (titleBar && !window.ExtendsContentIntoTitleBar()) {
            auto bar = as<controls::TitleBar>(titleBar);
            window.ExtendsContentIntoTitleBar(true);
            window.SetTitleBar(bar);
            window.AppWindow().TitleBar().PreferredHeightOption(winrt::Microsoft::UI::Windowing::TitleBarHeightOption::Tall);
            takeTheWayBack(grid, winrt::unbox_value<int64_t>(bar.Tag()));
        }
        if (titleBar) as<controls::TitleBar>(titleBar).ApplyTemplate();
    } catch (...) {
        report("dressing a window");
    }
}

extern "C" void swiftomniui_winui_window_activate(SwiftOmniUIObjectRef handle) {
    try {
        borrow<xaml::Window>(handle).Activate();
    } catch (...) {
        report("showing a window");
    }
}

extern "C" void swiftomniui_winui_window_close(SwiftOmniUIObjectRef handle) {
    try {
        auto window = borrow<xaml::Window>(handle);
        releaseOwned(reinterpret_cast<HWND>(window.AppWindow().Id().Value));
        window.Close();
    } catch (...) {
        report("closing a window");
    }
}

extern "C" void swiftomniui_winui_window_set_owner(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef owner) {
    try {
        auto app = borrow<xaml::Window>(handle).AppWindow();
        auto owning = owner ? reinterpret_cast<HWND>(borrow<xaml::Window>(owner).AppWindow().Id().Value) : nullptr;
        // A window owned stands above its owner, is hidden with it, and has no button of its own in the switchers.
        SetWindowLongPtrW(reinterpret_cast<HWND>(app.Id().Value), GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owning));
        app.IsShownInSwitchers(owner == nullptr);
    } catch (...) {
        report("giving a window its owner");
    }
}

extern "C" bool swiftomniui_winui_window_belongs_to(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef owner) {
    try {
        auto app = borrow<xaml::Window>(handle).AppWindow();
        auto owning = reinterpret_cast<HWND>(borrow<xaml::Window>(owner).AppWindow().Id().Value);
        return GetWindow(reinterpret_cast<HWND>(app.Id().Value), GW_OWNER) == owning && !app.IsShownInSwitchers();
    } catch (...) {
        report("reading a window's owner");
        return false;
    }
}

extern "C" void swiftomniui_winui_window_show_as_user(SwiftOmniUIObjectRef handle, int32_t command) {
    try {
        ShowWindow(reinterpret_cast<HWND>(borrow<xaml::Window>(handle).AppWindow().Id().Value), command);
    } catch (...) {
        report("minimizing or restoring a window as the user");
    }
}

extern "C" void swiftomniui_winui_window_set_shown(SwiftOmniUIObjectRef handle, bool shown) {
    try {
        auto app = borrow<xaml::Window>(handle).AppWindow();
        if (shown) app.Show(false);
        else app.Hide();
    } catch (...) {
        report("showing or hiding a window");
    }
}

namespace {
    /// How many pixels a DIP is in `window`, known before its content is laid out: a window's id is its HWND.
    double scale(xaml::Window const &window) {
        auto dpi = GetDpiForWindow(reinterpret_cast<HWND>(window.AppWindow().Id().Value));
        return dpi ? dpi / 96.0 : 1.0;
    }

    /// The work area of the display `window` stands on, in pixels.
    winrt::Windows::Graphics::RectInt32 workArea(xaml::Window const &window) {
        auto area = windowing::DisplayArea::GetFromWindowId(window.AppWindow().Id(), windowing::DisplayAreaFallback::Nearest);
        return area.WorkArea();
    }
}

extern "C" void swiftomniui_winui_window_set_frame(SwiftOmniUIObjectRef handle, bool const *has, double const *values) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto app = window.AppWindow();
        auto pixels = scale(window);
        if (has[0] || has[1]) {
            auto area = workArea(window);
            auto previous = app.Position();
            auto at = previous;
            if (has[0]) at.X = area.X + static_cast<int32_t>(std::lround(values[0] * pixels));
            if (has[1]) at.Y = area.Y + static_cast<int32_t>(std::lround(values[1] * pixels));
            if (at.X != previous.X || at.Y != previous.Y) app.Move(at);
        }
        if (has[2] || has[3]) {
            // The content covers the title bar, which ResizeClient would add again: the frame is what stands now.
            auto previous = app.Size();
            auto outer = previous;
            auto client = app.ClientSize();
            if (has[2]) outer.Width += static_cast<int32_t>(std::lround(values[2] * pixels)) - client.Width;
            if (has[3]) outer.Height += static_cast<int32_t>(std::lround(values[3] * pixels)) - client.Height;
            if (outer.Width != previous.Width || outer.Height != previous.Height) app.Resize(outer);
        }
    } catch (...) {
        report("placing a window");
    }
}

extern "C" void swiftomniui_winui_window_set_anchor(SwiftOmniUIObjectRef handle, double const *anchor) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto app = window.AppWindow();
        auto area = workArea(window);
        auto size = app.Size();
        app.Move(winrt::Windows::Graphics::PointInt32{
            area.X + static_cast<int32_t>(std::lround((area.Width - size.Width) * anchor[0])),
            area.Y + static_cast<int32_t>(std::lround((area.Height - size.Height) * anchor[1]))});
    } catch (...) {
        report("placing a window by an anchor");
    }
}

extern "C" void swiftomniui_winui_window_set_limits(SwiftOmniUIObjectRef handle, double const *limits) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto presenter = window.AppWindow().Presenter().try_as<windowing::OverlappedPresenter>();
        if (!presenter) return;
        auto pixels = scale(window);
        auto outer = window.AppWindow().Size();
        auto client = window.AppWindow().ClientSize();
        auto size = [&](double dips, int32_t border) -> winrt::Windows::Foundation::IReference<int32_t> {
            if (dips <= 0) return nullptr;
            return static_cast<int32_t>(std::lround(dips * pixels)) + border;
        };
        auto equal = [](winrt::Windows::Foundation::IReference<int32_t> const &a,
                        winrt::Windows::Foundation::IReference<int32_t> const &b) {
            return (!a && !b) || (a && b && a.Value() == b.Value());
        };
        auto minimumWidth = size(limits[0], outer.Width - client.Width);
        auto minimumHeight = size(limits[1], outer.Height - client.Height);
        auto maximumWidth = size(limits[2], outer.Width - client.Width);
        auto maximumHeight = size(limits[3], outer.Height - client.Height);
        // Compare the actual pixel constraints, rather than caching DIPs in Swift:
        // moving between displays or changing the presenter can change their conversion.
        if (!equal(presenter.PreferredMinimumWidth(), minimumWidth)) presenter.PreferredMinimumWidth(minimumWidth);
        if (!equal(presenter.PreferredMinimumHeight(), minimumHeight)) presenter.PreferredMinimumHeight(minimumHeight);
        if (!equal(presenter.PreferredMaximumWidth(), maximumWidth)) presenter.PreferredMaximumWidth(maximumWidth);
        if (!equal(presenter.PreferredMaximumHeight(), maximumHeight)) presenter.PreferredMaximumHeight(maximumHeight);
    } catch (...) {
        report("bounding a window");
    }
}

extern "C" void swiftomniui_winui_window_set_traits(
    SwiftOmniUIObjectRef handle, bool maximizable, bool minimizable, bool resizable, bool translucent, bool floats
) {
    try {
        auto window = borrow<xaml::Window>(handle);
        if (auto presenter = window.AppWindow().Presenter().try_as<windowing::OverlappedPresenter>()) {
            if (presenter.IsMaximizable() != maximizable) presenter.IsMaximizable(maximizable);
            if (presenter.IsMinimizable() != minimizable) presenter.IsMinimizable(minimizable);
            if (presenter.IsResizable() != resizable) presenter.IsResizable(resizable);
            if (presenter.IsAlwaysOnTop() != floats) presenter.IsAlwaysOnTop(floats);
        }
        // The backdrop is made again only where it turns.
        auto acrylic = window.SystemBackdrop().try_as<xaml::Media::DesktopAcrylicBackdrop>();
        if (translucent == static_cast<bool>(acrylic)) return;
        if (translucent) window.SystemBackdrop(xaml::Media::DesktopAcrylicBackdrop());
        else window.SystemBackdrop(xaml::Media::MicaBackdrop());
    } catch (...) {
        report("setting what a window is");
    }
}

extern "C" double swiftomniui_winui_window_title_bar_height(SwiftOmniUIObjectRef handle) {
    try {
        auto window = borrow<xaml::Window>(handle);
        return window.AppWindow().TitleBar().Height() / scale(window);
    } catch (...) {
        report("reading the title bar height");
        return 0;
    }
}

extern "C" void swiftomniui_winui_window_client_size(SwiftOmniUIObjectRef handle, double *size) {
    size[0] = size[1] = 0;
    try {
        auto window = borrow<xaml::Window>(handle);
        auto pixels = scale(window);
        auto client = window.AppWindow().ClientSize();
        size[0] = client.Width / pixels;
        size[1] = client.Height / pixels;
    } catch (...) {
        report("reading a window's client size");
    }
}

extern "C" void swiftomniui_winui_window_frame(SwiftOmniUIObjectRef handle, double *values) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto app = window.AppWindow();
        auto pixels = scale(window);
        auto area = workArea(window);
        auto at = app.Position();
        auto size = app.ClientSize();
        values[0] = (at.X - area.X) / pixels;
        values[1] = (at.Y - area.Y) / pixels;
        values[2] = size.Width / pixels;
        values[3] = size.Height / pixels;
        auto presenter = app.Presenter().try_as<windowing::OverlappedPresenter>();
        auto outer = app.Size();
        auto dips = [&](winrt::Windows::Foundation::IReference<int32_t> const &value, int32_t border) {
            return value ? std::max(0, value.Value() - border) / pixels : 0.0;
        };
        values[4] = presenter ? dips(presenter.PreferredMinimumWidth(), outer.Width - size.Width) : 0;
        values[5] = presenter ? dips(presenter.PreferredMinimumHeight(), outer.Height - size.Height) : 0;
        values[6] = presenter ? dips(presenter.PreferredMaximumWidth(), outer.Width - size.Width) : 0;
        values[7] = presenter ? dips(presenter.PreferredMaximumHeight(), outer.Height - size.Height) : 0;
        values[8] = presenter && presenter.IsMaximizable() ? 1 : 0;
        values[9] = presenter && presenter.IsMinimizable() ? 1 : 0;
        values[10] = window.SystemBackdrop().try_as<xaml::Media::DesktopAcrylicBackdrop>() ? 1 : 0;
        values[11] = presenter && presenter.IsAlwaysOnTop() ? 1 : 0;
        values[12] = app.IsVisible() ? 1 : 0;
    } catch (...) {
        report("reading a window's frame");
    }
}

extern "C" int32_t swiftomniui_winui_window_system_title(SwiftOmniUIObjectRef handle, char *utf8, int32_t capacity) {
    try {
        auto bytes = winrt::to_string(borrow<xaml::Window>(handle).AppWindow().Title());
        if (utf8 && capacity > 0) {
            auto size = std::min<size_t>(bytes.size(), static_cast<size_t>(capacity - 1));
            std::memcpy(utf8, bytes.data(), size);
            utf8[size] = 0;
        }
        return static_cast<int32_t>(bytes.size());
    } catch (...) {
        report("reading a window's name");
        return 0;
    }
}

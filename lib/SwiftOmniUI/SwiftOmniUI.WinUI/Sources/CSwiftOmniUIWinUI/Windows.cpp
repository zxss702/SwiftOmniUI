// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A window: its title, and a root of four rows - the window's chrome, its
// menu bar, the row of tabs, and the arrangement of pages - with the overlay
// laid over the page, shown and closed; its activation and its minimizing
// told as the application's phase.
// Design: docs/design/platforms/winui/pages.md#the-windows-chrome

#include "Relay.h"
#include "ChromeAcrylic.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <iterator>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <commctrl.h>
#include <dwmapi.h>

#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
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
namespace dispatching = winrt::Microsoft::UI::Dispatching;

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

    namespace composition = winrt::Microsoft::UI::Composition;

    /// The backdrop of a transparent window: a brush of alpha 0. A window with no backdrop at all is not
    /// transparent - XAML paints its own opaque theme colour under the content, which shows as a white window until
    /// the page draws - so "no material" has to be said as a backdrop that paints nothing.
    struct TransparentBackdrop : xaml::Media::SystemBackdropT<TransparentBackdrop> {
        // The target takes a brush of the system compositor (Windows.UI.Composition), not the XAML one.
        winrt::Windows::UI::Composition::Compositor compositor{nullptr};
        void OnTargetConnected(composition::ICompositionSupportsSystemBackdrop const &target, xaml::XamlRoot const &) {
            if (!compositor) compositor = winrt::Windows::UI::Composition::Compositor();
            target.SystemBackdrop(compositor.CreateColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        }
        void OnTargetDisconnected(composition::ICompositionSupportsSystemBackdrop const &target) {
            target.SystemBackdrop(nullptr);
        }
    };
    std::vector<winrt::weak_ref<xaml::Media::SystemBackdrop>> transparentBackdrops;

    bool isTransparentBackdrop(xaml::Media::SystemBackdrop const &backdrop) {
        std::erase_if(transparentBackdrops, [](auto const &entry) { return !entry.get(); });
        if (!backdrop) return false;
        for (auto const &entry : transparentBackdrops) if (entry.get() == backdrop) return true;
        return false;
    }

    // Layered + transparent removes the entire HWND from desktop mouse hit
    // testing, including when the next window belongs to another process.
    constexpr LONG_PTR mousePassthroughStyle = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
    constexpr wchar_t addedMousePassthroughStyles[] = L"SwiftOmniUI.AddedMousePassthroughStyles";
    void setWindowMousePassthrough(HWND hwnd, bool ignoresMouse) {
        auto saved = GetPropW(hwnd, addedMousePassthroughStyles);
        if (!ignoresMouse && !saved) return;
        auto current = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        auto added = saved ? static_cast<LONG_PTR>(reinterpret_cast<ULONG_PTR>(saved) - 1)
                           : mousePassthroughStyle & ~current;
        auto wanted = ignoresMouse ? current | mousePassthroughStyle : current & ~added;
        if (ignoresMouse && !saved &&
            !SetPropW(hwnd, addedMousePassthroughStyles, reinterpret_cast<HANDLE>(static_cast<ULONG_PTR>(added) + 1))) {
            winrt::throw_last_error();
        }
        if (current != wanted) {
            SetLastError(ERROR_SUCCESS);
            if (!SetWindowLongPtrW(hwnd, GWL_EXSTYLE, wanted) && GetLastError()) winrt::throw_last_error();
            if (ignoresMouse && !(current & WS_EX_LAYERED) && !SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)) {
                auto error = GetLastError();
                SetWindowLongPtrW(hwnd, GWL_EXSTYLE, current);
                winrt::throw_hresult(error ? HRESULT_FROM_WIN32(error) : E_FAIL);
            }
            SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
        if (!ignoresMouse) RemovePropW(hwnd, addedMousePassthroughStyles);
    }

    // The property holds the affinity to restore, plus one to distinguish WDA_NONE from an absent property.
    // It belongs to the HWND, so destroying a window also discards its saved affinity.
    constexpr wchar_t captureAffinityToRestore[] = L"SwiftOmniUI.CaptureAffinityToRestore";
    unsigned appCaptureExclusions = 0;
    HWINEVENTHOOK windowShowEvents = nullptr;

    HANDLE savedAffinity(DWORD affinity) {
        return reinterpret_cast<HANDLE>(static_cast<ULONG_PTR>(affinity) + 1);
    }

    // All calls are on the UI thread. Only touch a window that is visible or is about to be shown by WinUI.
    void updateCaptureAffinityForShow(HWND hwnd) {
        auto saved = GetPropW(hwnd, captureAffinityToRestore);
        if (appCaptureExclusions) {
            if (saved) return;
            DWORD affinity = WDA_NONE;
            GetWindowDisplayAffinity(hwnd, &affinity);
            if (!SetPropW(hwnd, captureAffinityToRestore, savedAffinity(affinity))) return;
            if (affinity != WDA_EXCLUDEFROMCAPTURE && !SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)) {
                auto error = GetLastError();
                RemovePropW(hwnd, captureAffinityToRestore);
                std::fprintf(stderr, "SwiftOmniUI WinUI: excluding a window from capture failed: %lu\n", error);
            }
        } else if (saved) {
            auto affinity = static_cast<DWORD>(reinterpret_cast<ULONG_PTR>(saved) - 1);
            if (affinity == WDA_EXCLUDEFROMCAPTURE || SetWindowDisplayAffinity(hwnd, affinity)) {
                RemovePropW(hwnd, captureAffinityToRestore);
            }
        }
    }

    bool isVisibleAppWindow(HWND hwnd) {
        DWORD pid = 0;
        GetWindowThreadProcessId(hwnd, &pid);
        return pid == GetCurrentProcessId() && GetAncestor(hwnd, GA_ROOT) == hwnd && IsWindowVisible(hwnd);
    }

    void CALLBACK appWindowShown(HWINEVENTHOOK, DWORD, HWND hwnd, LONG object, LONG child, DWORD, DWORD) {
        if (object == OBJID_WINDOW && child == CHILDID_SELF && hwnd &&
            (appCaptureExclusions || GetPropW(hwnd, captureAffinityToRestore)) && isVisibleAppWindow(hwnd)) {
            updateCaptureAffinityForShow(hwnd);
        }
    }

    void updateVisibleAppWindowsForCapture() {
        EnumWindows([](HWND hwnd, LPARAM) -> BOOL {
            if (isVisibleAppWindow(hwnd)) updateCaptureAffinityForShow(hwnd);
            return TRUE;
        }, 0);
    }

    void setWindowCapturePreference(HWND hwnd, bool excludesCapture) {
        auto wanted = excludesCapture ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE;
        bool visible = IsWindowVisible(hwnd);
        if (appCaptureExclusions && visible) updateCaptureAffinityForShow(hwnd);
        if (GetPropW(hwnd, captureAffinityToRestore)) {
            // A traits update changes what we will restore. The active capture still excludes this window.
            SetPropW(hwnd, captureAffinityToRestore, savedAffinity(wanted));
            if (!appCaptureExclusions && visible) updateCaptureAffinityForShow(hwnd);
            return;
        }
        DWORD affinity = WDA_NONE;
        GetWindowDisplayAffinity(hwnd, &affinity);
        if (affinity != wanted) SetWindowDisplayAffinity(hwnd, wanted);
    }

    bool clearWindowBacking(HWND hwnd, HDC dc) {
        RECT client{};
        // DWM interprets GDI's all-zero pixels as transparent once it is
        // configured to composite the backing with alpha.
        return dc && GetClientRect(hwnd, &client)
            && FillRect(dc, &client, reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    }

    HRESULT configureTransparentBacking(HWND hwnd, bool transparent) {
        DWM_BLURBEHIND backing{};
        backing.dwFlags = DWM_BB_ENABLE;
        backing.fEnable = transparent ? TRUE : FALSE;
        // Keep the region outside the client so DWM composites the alpha
        // without adding a visible effect behind the window.
        auto region = transparent ? CreateRectRgn(-2, -2, -1, -1) : nullptr;
        if (transparent && !region) return E_OUTOFMEMORY;
        if (region) {
            backing.dwFlags |= DWM_BB_BLURREGION;
            backing.hRgnBlur = region;
        }
        auto result = DwmEnableBlurBehindWindow(hwnd, &backing);
        if (region) DeleteObject(region);
        return result;
    }

    LRESULT CALLBACK transparentWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                           UINT_PTR id, DWORD_PTR clearBacking) {
        if (message == WM_ERASEBKGND) {
            if (!clearBacking || clearWindowBacking(hwnd, reinterpret_cast<HDC>(wparam))) return 1;
        }
        if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, transparentWindowProc, id);
        return DefSubclassProc(hwnd, message, wparam, lparam);
    }

    void setTransparentWindowPainting(HWND hwnd, bool transparent) {
        if (transparent) {
            const MARGINS margins{};
            DwmExtendFrameIntoClientArea(hwnd, &margins);
        } else if (!RemoveWindowSubclass(hwnd, transparentWindowProc, 0)) {
            return;
        }
        if (auto result = configureTransparentBacking(hwnd, transparent); FAILED(result)) {
            std::fprintf(stderr, "SwiftOmniUI WinUI: setting native window alpha failed: 0x%08x\n",
                static_cast<unsigned>(result));
            if (transparent) return;
        }
        if (transparent) SetWindowSubclass(hwnd, transparentWindowProc, 0, 1);
        // The XAML site has its own HWND. Treat only this window's native
        // composition host, leaving embedded controls and other windows alone.
        EnumChildWindows(hwnd, [](HWND child, LPARAM suppress) -> BOOL {
            if (GetWindowThreadProcessId(child, nullptr) != GetCurrentThreadId()) return TRUE;
            wchar_t name[64]{};
            if (GetClassNameW(child, name, 64) &&
                std::wstring_view(name) == L"Microsoft.UI.Content.DesktopChildSiteBridge") {
                if (suppress) SetWindowSubclass(child, transparentWindowProc, 0, 0);
                else RemoveWindowSubclass(child, transparentWindowProc, 0);
            }
            return TRUE;
        }, transparent);

        if (transparent) {
            // A white backing may already have been painted by WinUI before
            // the window or its content acquired the transparent backdrop.
            if (auto dc = GetDC(hwnd)) {
                clearWindowBacking(hwnd, dc);
                ReleaseDC(hwnd, dc);
            }
        }
    }

    xaml::Media::SystemBackdrop makeTransparentBackdrop() {
        auto backdrop = winrt::make<TransparentBackdrop>().as<xaml::Media::SystemBackdrop>();
        transparentBackdrops.push_back(winrt::make_weak(backdrop));
        return backdrop;
    }

    std::unordered_set<HWND> firstShownWindows;

    // Screen overlays are click-through, unowned tool windows. Explorer keeps
    // them outside its per-virtual-desktop window list. Maintain their order
    // against the taskbar and other topmost windows in the desktop band.
    std::unordered_set<HWND> screenOverlays;
    constexpr DWORD overlayOrderEvents[] = {
        EVENT_SYSTEM_FOREGROUND, EVENT_OBJECT_SHOW, EVENT_OBJECT_REORDER, EVENT_OBJECT_UNCLOAKED
    };
    HWINEVENTHOOK overlayOrderHooks[std::size(overlayOrderEvents)]{};

    void raiseScreenOverlay(HWND hwnd) {
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }

    bool screenOverlayIsCovered(HWND overlay) {
        if (!(GetWindowLongPtrW(overlay, GWL_EXSTYLE) & WS_EX_TOPMOST)) return true;
        RECT screen{};
        if (!GetWindowRect(overlay, &screen)) return false;

        // Reading the band avoids trying to reorder windows that Windows placed in a separate layer.
        using GetWindowBand = BOOL (WINAPI *)(HWND, DWORD *);
        static const auto getWindowBand = reinterpret_cast<GetWindowBand>(
            GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetWindowBand"));
        DWORD overlayBand = 0;
        const bool hasOverlayBand = getWindowBand && getWindowBand(overlay, &overlayBand);
        for (auto above = GetWindow(overlay, GW_HWNDPREV); above; above = GetWindow(above, GW_HWNDPREV)) {
            if (screenOverlays.contains(above) || !IsWindowVisible(above) || IsIconic(above)) continue;
            if (!(GetWindowLongPtrW(above, GWL_EXSTYLE) & WS_EX_TOPMOST)) continue;
            RECT bounds{}, overlap{};
            if (!GetWindowRect(above, &bounds) || !IntersectRect(&overlap, &screen, &bounds)) continue;
            DWORD band = 0;
            if (hasOverlayBand && getWindowBand(above, &band) && band != overlayBand) continue;
            DWORD cloaked = 0;
            DwmGetWindowAttribute(above, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
            if (!cloaked) return true;
        }
        return false;
    }

    void CALLBACK screenOverlayOrderChanged(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG object, LONG child, DWORD, DWORD) {
        if (!hwnd || child != CHILDID_SELF || screenOverlays.contains(hwnd)) return;
        // Moving an existing top-level window in Z order is reported on the desktop's client object.
        const bool reorderedDesktop = event == EVENT_OBJECT_REORDER && object == OBJID_CLIENT && hwnd == GetDesktopWindow();
        if (!reorderedDesktop && (object != OBJID_WINDOW || GetAncestor(hwnd, GA_ROOT) != hwnd)) return;
        if (event == EVENT_OBJECT_SHOW && !(GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST)) return;
        for (auto overlay : screenOverlays) {
            if (IsWindowVisible(overlay) && screenOverlayIsCovered(overlay)) raiseScreenOverlay(overlay);
        }
    }

    void setScreenOverlayOrder(HWND hwnd, bool enabled) {
        if (enabled) {
            if (!screenOverlays.insert(hwnd).second) return;
        } else if (!screenOverlays.erase(hwnd)) {
            return;
        }
        // Out-of-context hooks run on the registering UI thread. No work is
        // scheduled or performed when the last screen overlay closes.
        for (size_t index = 0; index < std::size(overlayOrderEvents); ++index) {
            auto &hook = overlayOrderHooks[index];
            if (enabled && !hook) {
                auto event = overlayOrderEvents[index];
                hook = SetWinEventHook(event, event, nullptr, screenOverlayOrderChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
            } else if (screenOverlays.empty() && hook) {
                UnhookWinEvent(hook);
                hook = nullptr;
            }
        }
    }

    void prepareFirstMica(xaml::Window const &window, HWND hwnd) {
        if (isTransparentBackdrop(window.SystemBackdrop()) || !firstShownWindows.insert(hwnd).second) return;
        if (window.SystemBackdrop().try_as<xaml::Media::MicaBackdrop>()) return;
        auto grid = root(window);
        window.SystemBackdrop(xaml::Media::MicaBackdrop());
        grid.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
        refreshWindowMaterial(grid);
    }

    void showWindow(xaml::Window const &window, bool activate) {
        auto app = window.AppWindow();
        auto hwnd = reinterpret_cast<HWND>(app.Id().Value);
        prepareFirstMica(window, hwnd);
        updateCaptureAffinityForShow(hwnd);
        if (activate && minimized(app)) app.Presenter().as<windowing::OverlappedPresenter>().Restore();
        if (isTransparentBackdrop(window.SystemBackdrop())) setTransparentWindowPainting(hwnd, true);

        const bool focus = activate && !(GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_NOACTIVATE);
        app.Show(focus);
        if (screenOverlays.contains(hwnd)) raiseScreenOverlay(hwnd);
        if (focus) {
            window.Activate();
            // A redirected launch can have foreground permission even when XAML alone won't raise the window.
            SetForegroundWindow(hwnd);
        }
    }

    // WinUI can render before the HWND's first show. Keep that first native
    // show for the moment when DWM can animate the window with its content.
    struct WindowStartup : std::enable_shared_from_this<WindowStartup> {
        winrt::weak_ref<xaml::Window> window;
        xaml::Media::CompositionTarget::Rendered_revoker rendered;
        dispatching::DispatcherQueueTimer deadline{nullptr};
        uint64_t attempt = 0;
        bool activate = false;

        explicit WindowStartup(xaml::Window const &window) : window(window) {}

        void cancel() {
            rendered.revoke();
            if (deadline) deadline.Stop();
            deadline = nullptr;
        }

        bool pending(uint64_t generation) const { return deadline && attempt == generation; }

        void start(bool requestActivation) {
            if (deadline) {
                activate |= requestActivation;
                return;
            }
            activate = requestActivation;
            auto queue = dispatching::DispatcherQueue::GetForCurrentThread();
            auto weak = weak_from_this();
            const auto generation = ++attempt;
            deadline = queue.CreateTimer();
            deadline.IsRepeating(false);
            deadline.Interval(std::chrono::milliseconds(500));
            deadline.Tick(guarded("showing a window when its first frame is unavailable",
                [weak, generation](auto const &, auto const &) {
                    if (auto startup = weak.lock()) startup->show(generation);
                }));
            rendered = xaml::Media::CompositionTarget::Rendered(winrt::auto_revoke,
                guarded("waiting for a window's first frame", [weak, generation](auto const &, auto const &) {
                    auto startup = weak.lock();
                    if (!startup || !startup->pending(generation)) return;
                    auto window = startup->window.get();
                    if (!window) return;
                    auto grid = root(window);
                    // Rendered is shared across windows. This window's XAML root must have been laid out.
                    if (!grid.IsLoaded() || grid.ActualWidth() <= 0 || grid.ActualHeight() <= 0) return;
                    startup->show(generation);
                }));
            deadline.Start();
            // The hidden site may already be idle if a previous show was canceled.
            if (auto window = this->window.get()) root(window).InvalidateArrange();
        }

        void show(uint64_t generation);
    };

    // Only windows that have yet to be shown need startup state.
    std::unordered_map<HWND, std::shared_ptr<WindowStartup>> windowStartups;

    void WindowStartup::show(uint64_t generation) {
        if (!pending(generation)) return;
        cancel();
        if (auto window = this->window.get()) {
            windowStartups.erase(reinterpret_cast<HWND>(window.AppWindow().Id().Value));
            showWindow(window, activate);
        }
    }

    void requestWindowShow(xaml::Window const &window, bool activate) {
        auto hwnd = reinterpret_cast<HWND>(window.AppWindow().Id().Value);
        auto grid = root(window);
        if (grid.IsLoaded() && grid.ActualWidth() > 0 && grid.ActualHeight() > 0) {
            showWindow(window, activate);
            return;
        }
        if (auto found = windowStartups.find(hwnd); found != windowStartups.end()) {
            auto startup = found->second;
            try {
                startup->start(activate);
                return;
            } catch (...) {
                report("preparing a window's first frame");
                startup->cancel();
                windowStartups.erase(hwnd);
            }
        }
        showWindow(window, activate);
    }
}

extern "C" int32_t swiftomniui_winui_begin_excluding_app_windows_from_capture() {
    // Native dialogs and popup windows may be shown without going through the WinUI window host.
    // Keep the show observer so windows that were hidden at the end can safely restore on their next show.
    if (!windowShowEvents) {
        windowShowEvents = SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, nullptr, appWindowShown,
            GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
        if (!windowShowEvents) {
            auto error = GetLastError();
            return error ? HRESULT_FROM_WIN32(error) : E_FAIL;
        }
    }
    if (++appCaptureExclusions == 1) updateVisibleAppWindowsForCapture();
    return S_OK;
}

extern "C" void swiftomniui_winui_end_excluding_app_windows_from_capture() {
    if (appCaptureExclusions && --appCaptureExclusions == 0) updateVisibleAppWindowsForCapture();
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_window_make(int64_t number, bool transparent) {
    try {
        xaml::Window window;
        auto grid = rows({true, true, true, false});
        if (transparent) {
            // Set a clear XAML backdrop while the native window is hidden.
            auto app = window.AppWindow();
            if (auto presenter = app.Presenter().try_as<windowing::OverlappedPresenter>())
                presenter.SetBorderAndTitleBar(false, false);
            // Custom title-bar mode can inset the XAML site by one physical
            // pixel. A borderless window already has the full client area.
            window.SystemBackdrop(makeTransparentBackdrop());
            grid.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
        } else {
            window.SystemBackdrop(xaml::Media::MicaBackdrop());
            // Keep the XAML root itself clear while a window is being closed.
            // The page owns its visible surfaces and the system backdrop remains
            // underneath them during the native transition.
            grid.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
        }
        window.Content(grid);
        auto hwnd = reinterpret_cast<HWND>(window.AppWindow().Id().Value);
        takeTheWayBack(grid, number);
        try {
            auto material = winrt::make<ChromeAcrylic>().as<xaml::FrameworkElement>();
            controls::Grid::SetRowSpan(material, 4);
            controls::Canvas::SetZIndex(material, 1);
            grid.Children().Append(material);
        } catch (...) { report("creating the optional window material layer"); }
        auto layoutToken = std::make_shared<winrt::event_token>();
        *layoutToken = grid.LayoutUpdated(guarded("committing settled layout",
            [weakGrid = winrt::make_weak(grid)](IInspectable const &, IInspectable const &) {
                auto grid = weakGrid.get();
                if (!grid || !grid.IsLoaded() || !grid.XamlRoot()) return;
                if (callbacks.layoutCommitted) callbacks.layoutCommitted();
            }));
        auto shortcutToken = std::make_shared<winrt::event_token>();
        *shortcutToken = grid.PreviewKeyDown(guarded("dispatching window keyboard shortcuts",
            [weakGrid = winrt::make_weak(grid), number](IInspectable const &, xaml::Input::KeyRoutedEventArgs const &args) {
                if (auto grid = weakGrid.get()) dispatchWindowShortcut(grid, number, args);
            }));
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
        window.Closed(guarded("handling Closed", [number, hwnd, weakGrid = winrt::make_weak(grid), layoutToken, shortcutToken](IInspectable const &, xaml::WindowEventArgs const &) {
            if (auto startup = windowStartups.extract(hwnd)) startup.mapped()->cancel();
            firstShownWindows.erase(hwnd);
            setScreenOverlayOrder(hwnd, false);
            if (IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
            if (auto grid = weakGrid.get()) {
                if (layoutToken->value) {
                    grid.LayoutUpdated(*layoutToken);
                    *layoutToken = {};
                }
                if (shortcutToken->value) {
                    grid.PreviewKeyDown(*shortcutToken);
                    *shortcutToken = {};
                }
            }
            releaseOwned(hwnd);
            // windowClosed renders - and a render inside XAML's teardown of this very window touches what is
            // dying, so the tree hears of the close once the event is through.
            winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread().TryEnqueue(
                guarded("handling Closed", [number] { callbacks.windowClosed(number); }));
        }));
        windowStartups.emplace(hwnd, std::make_shared<WindowStartup>(window));
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
        auto grid = root(borrow<xaml::Window>(handle));
        standInRow(grid, 3, content);
        setAcrylicContentRoot(grid, content ? as<xaml::FrameworkElement>(content) : xaml::FrameworkElement{nullptr});
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

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_safe_area_background_make(void) {
    try {
        return detach(winrt::make<LocalAcrylic>());
    } catch (...) { report("making a safe area acrylic background"); return nullptr; }
}

extern "C" void swiftomniui_winui_safe_area_host_set_background(SwiftOmniUIObjectRef handle, bool shown) {
    try {
        as<xaml::FrameworkElement>(handle).Resources().Insert(winrt::box_value(L"safeBarAcrylic"), winrt::box_value(shown));
        markAcrylicMaterialDirty();
    } catch (...) { report("setting a promoted safe bar's material visibility"); }
}

extern "C" void swiftomniui_winui_material_present(void) {
    try {
        (void)takeAcrylicMaterialDirty();
        presentAcrylicScenes();
        for (auto const &root : acrylicWindowRoots()) refreshWindowMaterial(root.as<controls::Grid>());
    } catch (...) { report("presenting material with the host animation transaction"); }
}

extern "C" void swiftomniui_winui_material_present_if_needed(void) {
    try {
        if (!takeAcrylicMaterialDirty()) return;
        presentAcrylicScenes();
        for (auto const &root : acrylicWindowRoots()) refreshWindowMaterial(root.as<controls::Grid>());
    } catch (...) { report("presenting material with the host animation transaction"); }
}

extern "C" void swiftomniui_winui_material_mark_dirty(void) {
    try { markAcrylicMaterialDirty(); }
    catch (...) { report("marking material presentation dirty"); }
}

extern "C" bool swiftomniui_winui_material_has_scroller_insets(void) {
    try { return hasAcrylicScrollerInsets(); }
    catch (...) { report("reading scroller material insets"); return false; }
}

extern "C" bool swiftomniui_winui_window_material_sampling_bounds(
    SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef element, double *rect
) {
    try {
        if (!rect) return false;
        auto grid = root(borrow<xaml::Window>(window));
        for (auto const &child : grid.Children()) {
            auto host = child.as<xaml::FrameworkElement>();
            if (winrt::unbox_value_or<winrt::hstring>(host.Tag(), L"") != L"chromeAcrylic") continue;
            auto layer = winrt::get_self<ChromeAcrylic>(host.as<xaml::IFrameworkElementOverrides>());
            for (auto const &column : layer->columns) {
                if (!acrylicSceneContains(column->material.scene(), as<xaml::FrameworkElement>(element))) continue;
                const auto bounds = column->material.samplingBounds();
                rect[0] = bounds.X; rect[1] = bounds.Y; rect[2] = bounds.Width; rect[3] = bounds.Height;
                return bounds.Width > 0 && bounds.Height > 0;
            }
        }
        return false;
    } catch (...) { report("reading a column's committed material sampling bounds"); return false; }
}

extern "C" bool swiftomniui_winui_window_material_follows_column(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef element) {
    try {
        auto grid = root(borrow<xaml::Window>(window));
        auto target = as<xaml::FrameworkElement>(element);
        for (auto const &child : grid.Children()) {
            auto host = child.as<xaml::FrameworkElement>();
            if (winrt::unbox_value_or<winrt::hstring>(host.Tag(), L"") != L"chromeAcrylic") continue;
            auto layer = winrt::get_self<ChromeAcrylic>(host.as<xaml::IFrameworkElementOverrides>());
            for (auto const &column : layer->columns) {
                if (!acrylicSceneContains(column->material.scene(), target)) continue;
                auto slot = acrylicColumnOwner(target, grid);
                IInspectable projected = *column.get();
                return slot && column->nativeOwner.get() == slot
                    && xaml::Media::VisualTreeHelper::GetParent(projected.as<xaml::FrameworkElement>()) == slot;
            }
        }
        return false;
    } catch (...) { report("reading native column material ownership"); return false; }
}

extern "C" bool swiftomniui_winui_window_material_covers(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef element) {
    try {
        auto grid = root(borrow<xaml::Window>(window));
        for (auto const &child : grid.Children()) {
            auto host = child.as<xaml::FrameworkElement>();
            if (winrt::unbox_value_or<winrt::hstring>(host.Tag(), L"") != L"chromeAcrylic") continue;
            auto layer = winrt::get_self<ChromeAcrylic>(host.as<xaml::IFrameworkElementOverrides>());
            auto target = as<xaml::FrameworkElement>(element);
            if (!target.IsLoaded()) return false;
            auto size = target.ActualSize();
            if (size.x <= 0 || size.y <= 0) return false;
            using Rect = winrt::Windows::Foundation::Rect;
            std::vector<Rect> uncovered{target.TransformToVisual(host).TransformBounds({0, 0, size.x, size.y})};
            auto covers = layer->regions;
            for (auto const &marker : acrylicMarkersForBar(target)) {
                auto local = winrt::get_self<LocalAcrylic>(marker.as<xaml::IFrameworkElementOverrides>());
                auto mapping = marker.TransformToVisual(host);
                for (auto const &rect : local->drawing.regions) covers.push_back(mapping.TransformBounds(rect));
            }
            for (auto const &cover : covers) {
                std::vector<Rect> next;
                for (auto const &rect : uncovered) {
                    auto x = std::max(rect.X, cover.X), y = std::max(rect.Y, cover.Y);
                    auto right = std::min(rect.X + rect.Width, cover.X + cover.Width);
                    auto bottom = std::min(rect.Y + rect.Height, cover.Y + cover.Height);
                    if (right <= x || bottom <= y) { next.push_back(rect); continue; }
                    if (x > rect.X) next.push_back({rect.X, rect.Y, x - rect.X, rect.Height});
                    if (right < rect.X + rect.Width) next.push_back({right, rect.Y, rect.X + rect.Width - right, rect.Height});
                    if (y > rect.Y) next.push_back({x, rect.Y, right - x, y - rect.Y});
                    if (bottom < rect.Y + rect.Height) next.push_back({x, bottom, right - x, rect.Y + rect.Height - bottom});
                }
                uncovered = std::move(next);
            }
            return uncovered.empty();
        }
        return false;
    } catch (...) { report("reading the committed material region"); return false; }
}

extern "C" void swiftomniui_winui_window_set_safe_area_bars(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef const *bars, int32_t count
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
            // The page's native column has not supplied a frame yet. A
            // visible zero-width host would measure live controls at a
            // competing constraint before that first frame can be committed.
            layer.Visibility(xaml::Visibility::Collapsed);
            layer.VerticalAlignment(xaml::VerticalAlignment::Top);
            controls::Grid::SetRow(layer, 3);
            controls::Canvas::SetZIndex(layer, 2);
            controls::StackPanel stack;
            stack.Tag(winrt::box_value(L"safeAreaBarContent"));
            layer.Children().Append(stack);
            // Controls stand above the one shared window material.
            children.Append(layer);
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

extern "C" void swiftomniui_winui_window_set_safe_area_bar_frame(
    SwiftOmniUIObjectRef handle, double x, double y, double width
) {
    try {
        for (auto const &child : root(borrow<xaml::Window>(handle)).Children()) {
            auto layer = child.try_as<controls::Grid>();
            if (!layer || winrt::unbox_value_or<winrt::hstring>(layer.Tag(), L"") != L"safeAreaBars") continue;
            if (width == 0) {
                layer.Visibility(xaml::Visibility::Collapsed);
                return;
            }
            layer.HorizontalAlignment(xaml::HorizontalAlignment::Left);
            auto margin = xaml::Thickness{x, y, 0, 0};
            if (layer.Margin() != margin) layer.Margin(margin);
            if (layer.Width() != width) layer.Width(width);
            // Keep the same subtree, and expose it only after its complete
            // native frame is ready. Hiding does not discard editor state.
            layer.Visibility(xaml::Visibility::Visible);
            return;
        }
    } catch (...) { report("placing the page's safe area bars"); }
}

extern "C" void swiftomniui_winui_window_set_background(
    SwiftOmniUIObjectRef handle, bool hasBackground, uint32_t background
) {
    try {
        xaml::Media::Brush fill{nullptr};
        if (hasBackground) {
            winrt::Windows::UI::Color color{
                static_cast<uint8_t>(background >> 24), static_cast<uint8_t>(background >> 16),
                static_cast<uint8_t>(background >> 8), static_cast<uint8_t>(background)};
            fill = xaml::Media::SolidColorBrush(color);
        }
        auto window = borrow<xaml::Window>(handle);
        auto grid = root(window);
        if (!fill && isTransparentBackdrop(window.SystemBackdrop()))
            fill = xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent());
        grid.Background(fill);
        refreshWindowMaterial(grid);
    } catch (...) {
        report("painting a window's background");
    }
}

extern "C" bool swiftomniui_winui_window_background(SwiftOmniUIObjectRef handle, uint32_t *background) {
    try {
        auto fill = root(borrow<xaml::Window>(handle)).Background().try_as<xaml::Media::SolidColorBrush>();
        if (!fill) return false;
        auto color = fill.Color();
        if (background) *background = (static_cast<uint32_t>(color.A) << 24) | (static_cast<uint32_t>(color.R) << 16)
            | (static_cast<uint32_t>(color.G) << 8) | static_cast<uint32_t>(color.B);
        return true;
    } catch (...) {
        report("reading a window's background");
        return false;
    }
}

extern "C" void swiftomniui_winui_window_set_chrome(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef titleBar, SwiftOmniUIObjectRef menuBar, SwiftOmniUIObjectRef tabs
) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto grid = root(window);
        xaml::UIElement previous{nullptr};
        for (auto const &child : grid.Children()) {
            auto part = child.as<xaml::FrameworkElement>();
            if (!isLayer(part) && controls::Grid::GetRow(part) == 0) { previous = part; break; }
        }
        auto next = titleBar ? as<xaml::UIElement>(titleBar) : xaml::UIElement{nullptr};
        standInRow(grid, 0, titleBar);
        standInRow(grid, 1, menuBar);
        standInRow(grid, 2, tabs);
        // A page's scroller can extend into these rows. Native chrome stays
        // above that viewport, independent of the root grid's child order.
        for (auto handle : {titleBar, menuBar, tabs}) {
            if (handle) controls::Canvas::SetZIndex(as<xaml::UIElement>(handle), 2);
        }
        if (titleBar && !window.ExtendsContentIntoTitleBar()) {
            window.ExtendsContentIntoTitleBar(true);
        }
        if (previous != next) {
            // Removing the XAML toolbar releases its layout row. The system still owns the caption buttons,
            // overlaid on the content; they do not reserve a blank strip at the top of the client area.
            window.SetTitleBar(next);
            auto caption = window.AppWindow().TitleBar();
            caption.PreferredHeightOption(titleBar ? windowing::TitleBarHeightOption::Tall
                                                  : windowing::TitleBarHeightOption::Standard);
            auto transparent = winrt::box_value(winrt::Windows::UI::Colors::Transparent())
                .as<winrt::Windows::Foundation::IReference<winrt::Windows::UI::Color>>();
            caption.ButtonBackgroundColor(transparent);
            caption.ButtonInactiveBackgroundColor(transparent);
            if (!titleBar) {
                // SetTitleBar(nullptr) restores the default caption drag strip. Clear only that region so
                // controls at the content's top edge receive input, leaving native caption buttons intact.
                winrt::Microsoft::UI::Input::InputNonClientPointerSource::GetForWindowId(window.AppWindow().Id())
                    .ClearRegionRects(winrt::Microsoft::UI::Input::NonClientRegionKind::Caption);
            }
        }
        if (titleBar) as<controls::TitleBar>(titleBar).ApplyTemplate();
        // The chrome row and the navigation columns must commit their material
        // from the same presentation sample during a page transition.
        markAcrylicMaterialDirty();
    } catch (...) {
        report("dressing a window");
    }
}

extern "C" void swiftomniui_winui_window_activate(SwiftOmniUIObjectRef handle) {
    try {
        requestWindowShow(borrow<xaml::Window>(handle), true);
    } catch (...) {
        report("showing a window");
    }
}

extern "C" void swiftomniui_winui_window_close(SwiftOmniUIObjectRef handle) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto app = window.AppWindow();
        auto hwnd = reinterpret_cast<HWND>(app.Id().Value);
        if (auto startup = windowStartups.find(hwnd); startup != windowStartups.end()) startup->second->cancel();
        firstShownWindows.erase(hwnd);
        // Remove the transparent window from the desktop before closing can
        // disconnect its backdrop or tear down the content.
        setScreenOverlayOrder(hwnd, false);
        if (IsWindowVisible(hwnd)) ShowWindow(hwnd, SW_HIDE);
        releaseOwned(hwnd);
        window.Close();
    } catch (...) {
        report("closing a window");
    }
}

extern "C" void swiftomniui_winui_window_minimize(SwiftOmniUIObjectRef handle) {
    try {
        auto app = borrow<xaml::Window>(handle).AppWindow();
        if (auto presenter = app.Presenter().try_as<windowing::OverlappedPresenter>(); presenter && presenter.IsMinimizable()) {
            presenter.Minimize();
        }
    } catch (...) {
        report("minimizing a window");
    }
}

extern "C" void swiftomniui_winui_window_toggle_fullscreen(SwiftOmniUIObjectRef handle) {
    try {
        auto app = borrow<xaml::Window>(handle).AppWindow();
        if (app.Presenter().Kind() == windowing::AppWindowPresenterKind::FullScreen) {
            app.SetPresenter(windowing::AppWindowPresenterKind::Overlapped);
        } else {
            app.SetPresenter(windowing::AppWindowPresenterKind::FullScreen);
        }
    } catch (...) {
        report("toggling window fullscreen");
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
        auto window = borrow<xaml::Window>(handle);
        if (shown) {
            requestWindowShow(window, false);
            return;
        }
        auto app = window.AppWindow();
        auto hwnd = reinterpret_cast<HWND>(app.Id().Value);
        if (auto found = windowStartups.find(hwnd); found != windowStartups.end()) found->second->cancel();
        if (app.IsVisible()) app.Hide();
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

extern "C" void swiftomniui_winui_window_set_screen_frame(SwiftOmniUIObjectRef handle, double const *rect) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto hwnd = reinterpret_cast<HWND>(window.AppWindow().Id().Value);
        auto pixels = [&](int index) { return static_cast<int32_t>(std::lround(rect[index])); };
        // The rectangle is the desktop's own and already in pixels: no work area to add, no DIPs to convert, and a
        // window with no frame of its own is the size it is placed at.
        // A window that covers a screen is that rectangle and nothing around it. Left to the presenter it keeps a
        // resize frame (invisible borders the window is inset by), the system's 1px accent border and rounded
        // corners: a lit band along the screen's edge, and a window smaller than the screen. Take them all away and
        // place the HWND itself, so the rectangle is exact whatever the presenter or the monitor's scale did.
        auto style = GetWindowLongPtrW(hwnd, GWL_STYLE);
        auto bare = style & ~static_cast<LONG_PTR>(WS_CAPTION | WS_THICKFRAME);
        if (bare != style) SetWindowLongPtrW(hwnd, GWL_STYLE, bare);
        auto extended = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        auto noFrame = extended & ~static_cast<LONG_PTR>(WS_EX_DLGMODALFRAME);
        if (noFrame != extended) SetWindowLongPtrW(hwnd, GWL_EXSTYLE, noFrame);
        const DWM_WINDOW_CORNER_PREFERENCE corners = DWMWCP_DONOTROUND;
        const COLORREF noBorder = DWMWA_COLOR_NONE;
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corners, sizeof(corners));
        DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &noBorder, sizeof(noBorder));
        auto onTop = (extended & WS_EX_TOPMOST) != 0;
        setScreenOverlayOrder(hwnd, onTop && !GetWindow(hwnd, GW_OWNER) &&
            (extended & mousePassthroughStyle) == mousePassthroughStyle && isTransparentBackdrop(window.SystemBackdrop()));
        SetWindowPos(hwnd, onTop ? HWND_TOPMOST : nullptr, pixels(0), pixels(1), pixels(2), pixels(3),
            SWP_FRAMECHANGED | SWP_NOACTIVATE | (onTop ? 0 : SWP_NOZORDER));
    } catch (...) {
        report("placing a window over the desktop");
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
    SwiftOmniUIObjectRef handle, bool maximizable, bool minimizable, bool resizable, bool translucent, bool floats,
    bool alwaysOnTop, bool ignoresMouse, bool excludesCapture, bool transparent
) {
    try {
        auto window = borrow<xaml::Window>(handle);
        auto app = window.AppWindow();
        if (auto presenter = app.Presenter().try_as<windowing::OverlappedPresenter>()) {
            if (presenter.IsMaximizable() != maximizable) presenter.IsMaximizable(maximizable);
            if (presenter.IsMinimizable() != minimizable) presenter.IsMinimizable(minimizable);
            if (presenter.IsResizable() != resizable) presenter.IsResizable(resizable);
            auto onTop = floats || alwaysOnTop;
            if (presenter.IsAlwaysOnTop() != onTop) presenter.IsAlwaysOnTop(onTop);
            // A transparent window is only its content: the frame and the caption go with the material.
            if (presenter.HasBorder() != !transparent || presenter.HasTitleBar() != !transparent)
                presenter.SetBorderAndTitleBar(!transparent, !transparent);
        }
        auto hwnd = reinterpret_cast<HWND>(app.Id().Value);
        auto previousBackdrop = window.SystemBackdrop();
        const auto wasTransparent = isTransparentBackdrop(previousBackdrop);
        auto grid = root(window);
        if (transparent && window.ExtendsContentIntoTitleBar()) {
            window.ExtendsContentIntoTitleBar(false);
        } else if (!transparent && wasTransparent) {
            bool hasToolbar = false;
            for (auto const &child : grid.Children()) {
                if (auto titleBar = child.try_as<controls::TitleBar>(); titleBar && controls::Grid::GetRow(titleBar) == 0) {
                    hasToolbar = true;
                    break;
                }
            }
            window.ExtendsContentIntoTitleBar(hasToolbar);
        }
        // Ordinary windows use the system Mica foundation. An explicit
        // translucency request retains the native Desktop Acrylic option.
        // A transparent window keeps no material at all: its pages' own alpha shows the desktop exactly.
        if (transparent) {
            if (!wasTransparent)
                window.SystemBackdrop(makeTransparentBackdrop());
        } else if (translucent) {
            if (!window.SystemBackdrop().try_as<xaml::Media::DesktopAcrylicBackdrop>())
                window.SystemBackdrop(xaml::Media::DesktopAcrylicBackdrop());
        } else if (!window.SystemBackdrop().try_as<xaml::Media::MicaBackdrop>()) {
            window.SystemBackdrop(xaml::Media::MicaBackdrop());
        }
        if (transparent && !grid.Background()) {
            grid.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
        }
        if (wasTransparent && !transparent) setTransparentWindowPainting(hwnd, false);
        if (transparent && !wasTransparent && app.IsVisible()) setTransparentWindowPainting(hwnd, true);
        if (previousBackdrop != window.SystemBackdrop()) refreshWindowMaterial(grid);
        try {
            setWindowMousePassthrough(hwnd, ignoresMouse);
        } catch (...) {
            report("setting window mouse passthrough");
        }
        setWindowCapturePreference(hwnd, excludesCapture);
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

extern "C" void swiftomniui_winui_window_screen_frame(SwiftOmniUIObjectRef handle, double *rect) {
    try {
        auto app = borrow<xaml::Window>(handle).AppWindow();
        // The desktop's own count: no work area taken off the place, no DIPs converted back from the size.
        auto at = app.Position();
        auto size = app.Size();
        rect[0] = at.X;
        rect[1] = at.Y;
        rect[2] = size.Width;
        rect[3] = size.Height;
    } catch (...) {
        report("reading a window's place over the desktop");
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

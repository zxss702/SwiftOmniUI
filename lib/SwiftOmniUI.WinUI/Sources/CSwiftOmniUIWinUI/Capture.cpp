// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What a test reads of the screen: an element rendered to pixels, sampled
// where the test asks, the thread's messages run while WinUI renders it.

#include "Relay.h"

#include <chrono>
#include <cmath>

#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Microsoft.UI.Windowing.h>

using namespace swiftomniui;
using winrt::Windows::Foundation::AsyncStatus;

namespace {
    /// Runs the thread's messages until `operation` ends, or five seconds pass; whether it completed.
    template <typename Operation>
    bool wait(Operation const &operation) {
        auto until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        MSG message;
        while (operation.Status() == AsyncStatus::Started && std::chrono::steady_clock::now() < until) {
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
        }
        return operation.Status() == AsyncStatus::Completed;
    }

    /// A panel with no background painted clear while it is rendered: the bitmap then holds its whole bounds from
    /// its corner, where it holds only what is drawn from the first thing drawn otherwise.
    struct WholeBounds {
        controls::Panel panel{nullptr};

        explicit WholeBounds(xaml::FrameworkElement const &element) {
            auto candidate = element.try_as<controls::Panel>();
            if (!candidate || candidate.Background()) return;
            panel = candidate;
            panel.Background(xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        }

        ~WholeBounds() {
            if (panel) panel.Background(nullptr);
        }
    };
}

/// Test-only sampling of the presented desktop image. RenderTargetBitmap omits
/// Composition child visuals, so it cannot verify an opacity-mask result.
/// The test window must be visible and unobscured at every requested point.
extern "C" bool swiftomniui_winui_presented_pixels(
    SwiftOmniUIObjectRef windowHandle, SwiftOmniUIObjectRef elementHandle,
    double const *points, int32_t count, uint32_t *argb
) {
    try {
        if (count < 0 || (count > 0 && (!points || !argb))) return false;
        auto window = as<xaml::Window>(windowHandle);
        auto element = as<xaml::FrameworkElement>(elementHandle);
        auto hwnd = reinterpret_cast<HWND>(window.AppWindow().Id().Value);
        POINT origin{};
        if (!IsWindowVisible(hwnd) || !ClientToScreen(hwnd, &origin)) return false;
        auto transform = element.TransformToVisual(window.Content());
        auto scale = element.XamlRoot().RasterizationScale();
        struct DesktopDC {
            HDC handle = GetDC(nullptr);
            ~DesktopDC() { if (handle) ReleaseDC(nullptr, handle); }
        } desktop;
        if (!desktop.handle) return false;
        for (int32_t index = 0; index < count; ++index) {
            auto at = transform.TransformPoint({static_cast<float>(points[2 * index]),
                                                static_cast<float>(points[2 * index + 1])});
            POINT pixel{origin.x + static_cast<LONG>(std::floor(at.X * scale)),
                        origin.y + static_cast<LONG>(std::floor(at.Y * scale))};
            if (GetAncestor(WindowFromPoint(pixel), GA_ROOT) != hwnd) return false;
            auto colour = GetPixel(desktop.handle, pixel.x, pixel.y);
            if (colour == CLR_INVALID) return false;
            argb[index] = 0xFF000000u | static_cast<uint32_t>(GetRValue(colour)) << 16
                | static_cast<uint32_t>(GetGValue(colour)) << 8 | GetBValue(colour);
        }
        return true;
    } catch (...) {
        report("reading presented pixels");
        return false;
    }
}

extern "C" bool swiftomniui_winui_pixels(SwiftOmniUIObjectRef handle, double const *points, int32_t count, uint32_t *argb) {
    try {
        auto element = as<xaml::FrameworkElement>(handle);
        WholeBounds whole(element);
        xaml::Media::Imaging::RenderTargetBitmap bitmap;
        auto rendering = bitmap.RenderAsync(element);
        if (!wait(rendering)) return false;
        auto reading = bitmap.GetPixelsAsync();
        if (!wait(reading)) return false;

        auto buffer = reading.GetResults();
        auto const *bytes = buffer.data();
        auto width = bitmap.PixelWidth(), height = bitmap.PixelHeight();
        // A large element's bitmap is rendered smaller than the screen shows it: a point is read by the bitmap's own
        // scale.
        auto rasterized = element.XamlRoot().RasterizationScale();
        auto across = element.ActualWidth() > 0 ? width / element.ActualWidth() : rasterized;
        auto down = element.ActualHeight() > 0 ? height / element.ActualHeight() : rasterized;
        for (int32_t index = 0; index < count; ++index) {
            auto x = static_cast<int32_t>(points[2 * index] * across);
            auto y = static_cast<int32_t>(points[2 * index + 1] * down);
            if (x < 0 || y < 0 || x >= width || y >= height) {
                argb[index] = 0;
                continue;
            }
            auto const *pixel = bytes + 4 * (static_cast<size_t>(y) * width + x);
            argb[index] = static_cast<uint32_t>(pixel[3]) << 24 | static_cast<uint32_t>(pixel[2]) << 16
                | static_cast<uint32_t>(pixel[1]) << 8 | pixel[0];
        }
        return true;
    } catch (...) {
        report("reading pixels");
        return false;
    }
}

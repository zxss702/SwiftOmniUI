// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A popover: WinUI's Flyout beside the view it hangs off, its content the popover's own layout, sized as that layout
// says. A click beside it or Escape takes it away, told through `presented`.

#include "Relay.h"

#include <limits>
#include <unordered_map>

#include <winrt/Windows.UI.Xaml.Interop.h>

using namespace swiftomniui;
namespace primitives = winrt::Microsoft::UI::Xaml::Controls::Primitives;

namespace {
    /// The anchors a popover waits on to be loaded before it opens beside them, by the popover's handle.
    std::unordered_map<SwiftOmniUIObjectRef, xaml::FrameworkElement::Loaded_revoker> waiting;

    /// The flyout's placement for the edge of the anchor its card prefers - `Edge`'s raw values.
    primitives::FlyoutPlacementMode placement(int32_t edge) {
        switch (edge) {
        case 2: return primitives::FlyoutPlacementMode::Left;
        case 4: return primitives::FlyoutPlacementMode::Bottom;
        case 8: return primitives::FlyoutPlacementMode::Right;
        default: return primitives::FlyoutPlacementMode::Top;
        }
    }

    void open(controls::Flyout const &flyout, xaml::FrameworkElement const &anchor, int32_t edge) {
        primitives::FlyoutShowOptions options;
        options.Placement(placement(edge));
        options.ShowMode(primitives::FlyoutShowMode::Standard);
        flyout.ShowAt(anchor, options);
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_popover_make(int64_t view, SwiftOmniUIObjectRef content) {
    try {
        controls::Flyout flyout;
        // The card is as big as its content says - no room of the platform's own around it, no cap of its width
        // or height but the window's, no scroller of its own: what the content asks to scroll, it scrolls.
        xaml::Style style{winrt::xaml_typename<controls::FlyoutPresenter>()};
        auto own = xaml::Application::Current().Resources().TryLookup(winrt::box_value(L"DefaultFlyoutPresenterStyle"));
        if (own) style.BasedOn(own.as<xaml::Style>());
        auto unbounded = winrt::box_value(std::numeric_limits<double>::infinity());
        auto setters = style.Setters();
        setters.Append(xaml::Setter(xaml::FrameworkElement::MaxWidthProperty(), unbounded));
        setters.Append(xaml::Setter(xaml::FrameworkElement::MaxHeightProperty(), unbounded));
        setters.Append(xaml::Setter(controls::Control::PaddingProperty(), winrt::box_value(xaml::Thickness{0, 0, 0, 0})));
        setters.Append(xaml::Setter(controls::ScrollViewer::HorizontalScrollModeProperty(),
                                    winrt::box_value(controls::ScrollMode::Disabled)));
        setters.Append(xaml::Setter(controls::ScrollViewer::HorizontalScrollBarVisibilityProperty(),
                                    winrt::box_value(controls::ScrollBarVisibility::Disabled)));
        setters.Append(xaml::Setter(controls::ScrollViewer::VerticalScrollModeProperty(),
                                    winrt::box_value(controls::ScrollMode::Disabled)));
        setters.Append(xaml::Setter(controls::ScrollViewer::VerticalScrollBarVisibilityProperty(),
                                    winrt::box_value(controls::ScrollBarVisibility::Disabled)));
        flyout.FlyoutPresenterStyle(style);
        flyout.Content(as<xaml::UIElement>(content));
        flyout.Closed(guarded("handling a popover's Closed",
            [view](IInspectable const &, IInspectable const &) { callbacks.presented(view, false); }));
        return detach(flyout);
    } catch (...) {
        report("making a popover");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_popover_show(SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef anchorHandle, int32_t edge) {
    try {
        waiting.erase(handle);
        auto flyout = borrow<controls::Flyout>(handle);
        auto anchor = as<xaml::FrameworkElement>(anchorHandle);
        if (anchor.IsLoaded() && anchor.XamlRoot()) return open(flyout, anchor, edge);
        // An anchor not in its window yet - made in the patch that opens the card: it opens once the anchor is.
        waiting[handle] = anchor.Loaded(winrt::auto_revoke, guarded("opening a popover once its anchor loaded",
            [weak = winrt::make_weak(flyout), handle, edge](IInspectable const &sender, xaml::RoutedEventArgs const &) {
                // Read before the wait is let go of: letting it go revokes this handler, and what it holds with it.
                auto flyout = weak.get();
                auto anchor = sender.as<xaml::FrameworkElement>();
                auto side = edge;
                auto key = handle;
                waiting.erase(key);
                if (flyout && anchor.XamlRoot()) open(flyout, anchor, side);
            }));
    } catch (...) {
        report("opening a popover");
    }
}

extern "C" void swiftomniui_winui_popover_hide(SwiftOmniUIObjectRef handle) {
    try {
        waiting.erase(handle);
        borrow<controls::Flyout>(handle).Hide();
    } catch (...) {
        report("closing a popover");
    }
}

extern "C" bool swiftomniui_winui_popover_is_open(SwiftOmniUIObjectRef handle) {
    try {
        return borrow<controls::Flyout>(handle).IsOpen();
    } catch (...) {
        report("reading whether a popover is open");
        return false;
    }
}

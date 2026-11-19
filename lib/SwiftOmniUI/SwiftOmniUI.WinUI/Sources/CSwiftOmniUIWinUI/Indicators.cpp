// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What shows work: a progress bar, how far along from 0 to 1, and a spinner,
// WinUI's ProgressRing, turning while its work runs.

#include "Relay.h"
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>

using namespace swiftomniui;

namespace {
    bool smoothSpinnerEdges(xaml::UIElement const &player) {
        auto visual = xaml::Hosting::ElementCompositionPreview::GetElementChildVisual(player);
        if (!visual) return false;
        // Preserve fractional coverage on the native arc, including when a SafeBar captures it.
        visual.BorderMode(winrt::Microsoft::UI::Composition::CompositionBorderMode::Soft);
        return true;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_progress_bar_make(void) {
    try {
        controls::ProgressBar bar;
        bar.Minimum(0);
        bar.Maximum(1);
        return detach(bar);
    } catch (...) {
        report("making a progress bar");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_progress_bar_set(SwiftOmniUIObjectRef handle, double progress) {
    try {
        borrow<controls::ProgressBar>(handle).Value(progress);
    } catch (...) {
        report("moving a progress bar");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_progress_ring_make(void) {
    try {
        controls::ProgressRing ring;
        ring.MinWidth(0);
        ring.MinHeight(0);
        ring.Width(24);
        ring.Height(24);
        ring.IsActive(false);
        ring.Loaded(guarded("smoothing spinner edges", [](IInspectable const &sender, auto const &) {
            auto player = first<controls::AnimatedVisualPlayer>(sender.as<controls::ProgressRing>());
            if (!player || smoothSpinnerEdges(player)) return;
            // The player may attach its composition visual in its own Loaded handler.
            player.Loaded(guarded("smoothing spinner animation edges", [](IInspectable const &sender, auto const &) {
                smoothSpinnerEdges(sender.as<controls::AnimatedVisualPlayer>());
            }));
        }));
        return detach(ring);
    } catch (...) {
        report("making a spinner");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_progress_ring_set_running(SwiftOmniUIObjectRef handle, bool running) {
    try {
        borrow<controls::ProgressRing>(handle).IsActive(running);
    } catch (...) {
        report("turning a spinner");
    }
}

extern "C" void swiftomniui_winui_progress_ring_set_size(SwiftOmniUIObjectRef handle, double diameter) {
    try {
        auto ring = borrow<controls::ProgressRing>(handle);
        ring.MinWidth(0);
        ring.MinHeight(0);
        ring.Width(diameter);
        ring.Height(diameter);
    } catch (...) {
        report("sizing a spinner");
    }
}

extern "C" double swiftomniui_winui_progress_bar_value(SwiftOmniUIObjectRef handle) {
    try {
        return borrow<controls::ProgressBar>(handle).Value();
    } catch (...) {
        report("reading how far along");
        return 0;
    }
}

extern "C" bool swiftomniui_winui_progress_ring_running(SwiftOmniUIObjectRef handle) {
    try {
        return borrow<controls::ProgressRing>(handle).IsActive();
    } catch (...) {
        report("reading whether a spinner turns");
        return false;
    }
}

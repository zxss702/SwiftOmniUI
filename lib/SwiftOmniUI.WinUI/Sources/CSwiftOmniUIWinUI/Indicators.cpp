// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What shows work: a progress bar, how far along from 0 to 1, and a spinner,
// WinUI's ProgressRing, turning while its work runs.

#include "Relay.h"

using namespace swiftomniui;

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

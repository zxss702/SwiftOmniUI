// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A ScrollView's scroller: WinUI's ScrollView around the document the host
// lays out, saying where its view stands and when the user holds it.
// Design: docs/design/platforms/winui/layout.md#scrolling

#include "Relay.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <iterator>
#include <unordered_map>
#include <vector>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Numerics.h>

using namespace swiftomniui;

namespace {
    using NativeScrollBar = xaml::Controls::Primitives::ScrollBar;
    struct IndicatorMargin {
        winrt::weak_ref<NativeScrollBar> bar;
        xaml::Thickness original{}, applied{};
    };
    struct ScrollerInsets {
        xaml::Thickness region{};
        std::vector<IndicatorMargin> indicators;
        bool pending = false;
    };
    std::unordered_map<void *, std::weak_ptr<ScrollerInsets>> insetStates;

    bool sameMargin(xaml::Thickness const &a, xaml::Thickness const &b) {
        return a.Left == b.Left && a.Top == b.Top && a.Right == b.Right && a.Bottom == b.Bottom;
    }

    void applyInsets(controls::ScrollView const &scroller, ScrollerInsets &state) {
        auto content = scroller.Content().try_as<xaml::DependencyObject>();
        state.indicators.erase(std::remove_if(state.indicators.begin(), state.indicators.end(),
            [](auto const &entry) { return !entry.bar.get(); }), state.indicators.end());
        std::vector<xaml::DependencyObject> pending{scroller};
        while (!pending.empty()) {
            auto at = pending.back();
            pending.pop_back();
            // Only this scroller's template parts. The content can contain its
            // own ScrollViews, ScrollViewers and scrollbars with other margins.
            if (at == content || (at != scroller
                && (at.try_as<controls::ScrollView>() || at.try_as<controls::ScrollViewer>()))) continue;
            if (auto bar = at.try_as<NativeScrollBar>()) {
                auto current = bar.Margin();
                auto found = std::find_if(state.indicators.begin(), state.indicators.end(),
                    [&](auto const &entry) { return entry.bar.get() == bar; });
                if (found == state.indicators.end()) {
                    state.indicators.push_back({winrt::make_weak(bar), current, current});
                    found = std::prev(state.indicators.end());
                } else if (!sameMargin(current, found->applied)) {
                    // A theme/template update supplied new native margins.
                    found->original = current;
                }
                auto margin = found->original;
                if (bar.Orientation() == controls::Orientation::Vertical) {
                    margin.Top += state.region.Top;
                    margin.Bottom += state.region.Bottom;
                } else {
                    margin.Left += state.region.Left;
                    margin.Right += state.region.Right;
                }
                found->applied = margin;
                if (!sameMargin(current, margin)) bar.Margin(margin);
                continue;
            }
            for (int32_t index = 0, count = xaml::Media::VisualTreeHelper::GetChildrenCount(at);
                 index < count; ++index) pending.push_back(xaml::Media::VisualTreeHelper::GetChild(at, index));
        }
        if (state.region.Top > 0) refreshSafeAreaScrollEdge(scroller);
    }

    void queueInsets(controls::ScrollView const &scroller, std::shared_ptr<ScrollerInsets> const &state) {
        if (state->pending) return;
        state->pending = true;
        auto weak = winrt::make_weak(scroller);
        auto queue = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();
        if (!queue || !queue.TryEnqueue(guarded("committing scroller margins", [weak, state] {
            state->pending = false;
            if (auto scroller = weak.get()) applyInsets(scroller, *state);
        }))) state->pending = false;
    }
    controls::ScrollingScrollBarVisibility visibility(bool scrolls, int32_t bar) {
        if (!scrolls) return controls::ScrollingScrollBarVisibility::Hidden;
        switch (bar) {
        case 1: return controls::ScrollingScrollBarVisibility::Visible;
        case 2: return controls::ScrollingScrollBarVisibility::Hidden;
        default: return controls::ScrollingScrollBarVisibility::Auto;
        }
    }

    // The wire's scroll mode - 0 off, 1 on, 2 where the content fills the view -
    // named on the new scroller, whose enum numbers Enabled first.
    controls::ScrollingScrollMode scrollMode(int32_t mode) {
        switch (mode) {
        case 0: return controls::ScrollingScrollMode::Disabled;
        case 1: return controls::ScrollingScrollMode::Enabled;
        default: return controls::ScrollingScrollMode::Auto;
        }
    }

    int32_t scrollModeBack(controls::ScrollingScrollMode mode) {
        switch (mode) {
        case controls::ScrollingScrollMode::Disabled: return 0;
        case controls::ScrollingScrollMode::Enabled: return 1;
        default: return 2;
        }
    }

    controls::ScrollingContentOrientation contentOrientation(int32_t orientation) {
        switch (orientation) {
        case 0: return controls::ScrollingContentOrientation::Vertical;
        case 1: return controls::ScrollingContentOrientation::Horizontal;
        case 2: return controls::ScrollingContentOrientation::Both;
        default: return controls::ScrollingContentOrientation::None;
        }
    }

    // A delta on a disabled axis finds no listener: it scrolls nothing here and
    // chains nowhere, rather than ending a pan the whole document bounces back
    // from. The live axis chains the way nested scrollers expect.
    void modes(controls::ScrollView const &scroller, int32_t verticalMode, int32_t horizontalMode) {
        auto vertical = scrollMode(verticalMode);
        auto horizontal = scrollMode(horizontalMode);
        scroller.VerticalScrollMode(vertical);
        scroller.HorizontalScrollMode(horizontal);
        scroller.VerticalScrollChainMode(vertical == controls::ScrollingScrollMode::Disabled
            ? controls::ScrollingChainMode::Never : controls::ScrollingChainMode::Auto);
        scroller.HorizontalScrollChainMode(horizontal == controls::ScrollingScrollMode::Disabled
            ? controls::ScrollingChainMode::Never : controls::ScrollingChainMode::Auto);
    }

    // The landing an animation announced, shared by the move's notices: while
    // one flies the compositor's per-frame word pairs where it stands with
    // where it lands. Realization follows the actual offset, not that endpoint.
    struct ScrollerFlight {
        double x = std::nan(""), y = std::nan("");
        bool held = false;
    };

    // The program's latest move per scroller. The presenter clamps a move to the reach the compositor last
    // committed - stale on a first frame - so a move that completes short of where it can now reach, neither
    // superseded nor taken over by the user, is asked again.
    std::unordered_map<void *, int32_t> latestMove;

    void scrollTo(controls::ScrollView const &scroller, double x, double y, bool animated) {
        auto id = scroller.ScrollTo(x, y, controls::ScrollingScrollOptions(
            animated ? controls::ScrollingAnimationMode::Enabled : controls::ScrollingAnimationMode::Disabled,
            controls::ScrollingSnapPointsMode::Ignore));
        latestMove[winrt::get_abi(scroller)] = id;
        // An animation lands where its own curve ends, and the user may take it over: only a jump is asked again.
        if (animated) return;
        auto token = std::make_shared<winrt::event_token>();
        *token = scroller.ScrollCompleted(guarded("handling ScrollCompleted", [=](controls::ScrollView const &self,
                                             controls::ScrollingScrollCompletedEventArgs const &args) {
            if (args.CorrelationId() != id) return;
            self.ScrollCompleted(*token);
            if (latestMove[winrt::get_abi(self)] != id || self.State() != controls::ScrollingInteractionState::Idle) return;
            double tx = std::clamp(x, 0.0, self.ScrollableWidth()), ty = std::clamp(y, 0.0, self.ScrollableHeight());
            if (std::abs(self.HorizontalOffset() - tx) > 0.5 || std::abs(self.VerticalOffset() - ty) > 0.5)
                scrollTo(self, x, y, animated);
        }));
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_scroller_make(int64_t view) {
    try {
        controls::ScrollView scroller;
        auto insets = std::make_shared<ScrollerInsets>();
        for (auto at = insetStates.begin(); at != insetStates.end();) {
            if (at->second.expired()) at = insetStates.erase(at); else ++at;
        }
        insetStates[winrt::get_abi(scroller)] = insets;
        scroller.Loaded(guarded("preparing scroller margins", [insets](IInspectable const &sender, auto const &) {
            queueInsets(sender.as<controls::ScrollView>(), insets);
        }));
        scroller.LayoutUpdated(guarded("refreshing scroller template margins", [weak = winrt::make_weak(scroller), insets](auto const &, auto const &) {
            if (auto scroller = weak.get()) queueInsets(scroller, insets);
        }));
        auto flight = std::make_shared<ScrollerFlight>();
        scroller.ZoomMode(controls::ScrollingZoomMode::Disabled);
        // The InteractionTracker's word of the view, every frame it moves: the
        // ear hears where it stands now paired with where an animation lands.
        scroller.ViewChanged(guarded("handling ViewChanged",
            [view, flight](controls::ScrollView const &scroller, IInspectable const &) {
            refreshSafeAreaScrollEdge(scroller);
            double x = scroller.HorizontalOffset(), y = scroller.VerticalOffset();
            callbacks.scrolling(view, x, y,
                std::isnan(flight->x) ? x : flight->x, std::isnan(flight->y) ? y : flight->y);
            if (scroller.State() == controls::ScrollingInteractionState::Interaction)
                callbacks.scrolled(view, x, y);
        }));
        // An animation - inertia's or a move the program animated - names its
        // landing as it starts. That endpoint is metadata, not a visible window.
        scroller.ScrollAnimationStarting(guarded("handling ScrollAnimationStarting",
            [view, flight](controls::ScrollView const &scroller,
                controls::ScrollingScrollAnimationStartingEventArgs const &args) {
            auto end = args.EndPosition();
            flight->x = end.x;
            flight->y = end.y;
            // The animation runs from the next frame, before StateChanged says so:
            // the scroller is held now; realization retains a moving look-ahead.
            if (!flight->held) {
                flight->held = true;
                callbacks.held(view, true);
            }
            callbacks.scrolling(view,
                scroller.HorizontalOffset(), scroller.VerticalOffset(), end.x, end.y);
        }));
        // Idle is the view at rest: anything else - the user's hand, the throw
        // after it, or a driven animation - is the scroller held.
        scroller.StateChanged(guarded("handling StateChanged",
            [view, flight](controls::ScrollView const &scroller, IInspectable const &) {
            auto state = scroller.State();
            bool held = state != controls::ScrollingInteractionState::Idle;
            if (held != flight->held) {
                flight->held = held;
                callbacks.held(view, held);
            }
            if (state == controls::ScrollingInteractionState::Interaction)
                flight->x = flight->y = std::nan("");
            if (state == controls::ScrollingInteractionState::Idle) {
                flight->x = flight->y = std::nan("");
                callbacks.scrolled(view, scroller.HorizontalOffset(), scroller.VerticalOffset());
            }
        }));
        // An anchor to hold the view by when the extent moves: the document
        // itself stands in for a run with no registered cell.
        scroller.AnchorRequested(guarded("handling AnchorRequested",
            [](controls::ScrollView const &scroller,
                controls::ScrollingAnchorRequestedEventArgs const &args) {
            if (auto content = scroller.Content()) args.AnchorCandidates().Append(content);
        }));
        return detach(scroller);
    } catch (...) {
        report("making a scroller");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_scroller_set(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef content, int32_t orientation, int32_t verticalBar, int32_t horizontalBar
) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto down = orientation == 0 || orientation == 2;
        auto across = orientation == 1 || orientation == 2;
        modes(scroller, down ? 1 : 0, across ? 1 : 0);
        scroller.ContentOrientation(contentOrientation(orientation));
        scroller.VerticalScrollBarVisibility(visibility(down, verticalBar));
        scroller.HorizontalScrollBarVisibility(visibility(across, horizontalBar));
        auto element = content ? as<xaml::UIElement>(content) : xaml::UIElement{nullptr};
        if (scroller.Content() != element) scroller.Content(element);
    } catch (...) {
        report("setting a scroller");
    }
}

extern "C" void swiftomniui_winui_scroller_modes(
    SwiftOmniUIObjectRef handle, int32_t verticalMode, int32_t horizontalMode) {
    try {
        modes(borrow<controls::ScrollView>(handle), verticalMode, horizontalMode);
    } catch (...) {
        report("setting a scroller's modes");
    }
}

extern "C" void swiftomniui_winui_scroller_move(SwiftOmniUIObjectRef handle, double x, double y, bool animated) {
    try {
        scrollTo(borrow<controls::ScrollView>(handle), x, y, animated);
    } catch (...) {
        report("moving a scroller");
    }
}

extern "C" void swiftomniui_winui_scroller_invalidate_presenter(SwiftOmniUIObjectRef handle) {
    try {
        if (auto presenter = borrow<controls::ScrollView>(handle).ScrollPresenter()) presenter.InvalidateMeasure();
    } catch (...) {
        report("invalidating a scroller's presenter");
    }
}

extern "C" void swiftomniui_winui_scroller_read_modes(SwiftOmniUIObjectRef handle, int32_t *modes) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        modes[0] = scrollModeBack(scroller.VerticalScrollMode());
        modes[1] = scrollModeBack(scroller.HorizontalScrollMode());
    } catch (...) {
        report("reading a scroller's modes");
    }
}

extern "C" void swiftomniui_winui_scroller_anchor(SwiftOmniUIObjectRef element, bool enabled) {
    try {
        // The framework registers every flagged descendant with the anchor
        // provider above it, whichever scroller that is.
        as<xaml::UIElement>(element).CanBeScrollAnchor(enabled);
    } catch (...) { report("registering a scroll anchor"); }
}

extern "C" void swiftomniui_winui_scroller_place_for(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef descendant, double anchorX, double anchorY,
    int32_t *found, double *place)
{
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto element = as<xaml::FrameworkElement>(descendant);
        auto content = scroller.Content().try_as<xaml::UIElement>();
        if (!element || !content) { *found = 0; return; }

        auto bounds = element.TransformToVisual(content).TransformBounds(
            winrt::Windows::Foundation::Rect(
                0, 0, (float)element.ActualWidth(), (float)element.ActualHeight()));

        xaml::Thickness insets{};
        if (auto found = insetStates.find(winrt::get_abi(scroller)); found != insetStates.end())
            if (auto state = found->second.lock()) insets = state->region;
        auto nearest = [](double start, double length, double room, double now) {
            if (start >= now && start + length <= now + room) return now;
            return start < now ? start : start + length - room;
        };

        double x = scroller.HorizontalOffset();
        double y = scroller.VerticalOffset();
        if (scroller.ComputedHorizontalScrollMode() == controls::ScrollingScrollMode::Enabled) {
            x = std::isnan(anchorX)
                ? nearest(bounds.X - insets.Left, bounds.Width,
                    std::max(0.0, scroller.ViewportWidth() - insets.Left - insets.Right), x)
                : bounds.X - insets.Left + anchorX * bounds.Width
                    - anchorX * std::max(0.0, scroller.ViewportWidth() - insets.Left - insets.Right);
        }
        if (scroller.ComputedVerticalScrollMode() == controls::ScrollingScrollMode::Enabled) {
            y = std::isnan(anchorY)
                ? nearest(bounds.Y - insets.Top, bounds.Height,
                    std::max(0.0, scroller.ViewportHeight() - insets.Top - insets.Bottom), y)
                : bounds.Y - insets.Top + anchorY * bounds.Height
                    - anchorY * std::max(0.0, scroller.ViewportHeight() - insets.Top - insets.Bottom);
        }
        place[0] = x;
        place[1] = y;
        *found = 1;
    } catch (...) {
        report("placing for a descendant");
        *found = 0;
    }
}

extern "C" void swiftomniui_winui_scroller_offset(SwiftOmniUIObjectRef handle, double *offset) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        offset[0] = scroller.HorizontalOffset();
        offset[1] = scroller.VerticalOffset();
        offset[2] = scroller.ScrollableWidth();
        offset[3] = scroller.ScrollableHeight();
    } catch (...) {
        report("reading a scroller");
    }
}

extern "C" void swiftomniui_winui_scroller_insets(
    SwiftOmniUIObjectRef handle, double top, double right, double bottom, double left
) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto found = insetStates.find(winrt::get_abi(scroller));
        if (found == insetStates.end()) return;
        if (auto state = found->second.lock()) {
            state->region = xaml::Thickness{left, top, right, bottom};
            queueInsets(scroller, state);
        }
    } catch (...) {
        report("insetting a scroller's bars");
    }
}

extern "C" void swiftomniui_winui_scroller_viewport(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef descendant, double *viewport
) {
    std::fill_n(viewport, 6, 0);
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto content = scroller.Content().try_as<xaml::UIElement>();
        if (!content) return;
        auto element = as<xaml::UIElement>(descendant);
        auto corner = element.TransformToVisual(content).TransformPoint({0, 0});
        viewport[0] = scroller.HorizontalOffset() - corner.X;
        viewport[1] = scroller.VerticalOffset() - corner.Y;
        viewport[2] = scroller.ViewportWidth();
        viewport[3] = scroller.ViewportHeight();
        auto parent = xaml::Media::VisualTreeHelper::GetParent(content).as<xaml::UIElement>();
        auto displayed = element.TransformToVisual(parent).TransformPoint({0, 0});
        viewport[4] = displayed.X;
        viewport[5] = displayed.Y;
    } catch (...) {
        report("reading a descendant's scroll viewport");
    }
}

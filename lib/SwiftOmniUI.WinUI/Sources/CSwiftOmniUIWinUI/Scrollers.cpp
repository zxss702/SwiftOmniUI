// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A ScrollView's scroller: WinUI's ScrollView around the document the host
// lays out, saying where its view stands and when the user holds it.
// Design: docs/design/platforms/winui/layout.md#scrolling

#include "Relay.h"
#include "AcrylicScene.h"

#include <algorithm>
#include <array>
#include <winrt/Microsoft.UI.Composition.h>
#include <cmath>
#include <memory>
#include <iterator>
#include <unordered_map>
#include <utility>
#include <vector>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
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
    struct ViewportRequest {
        winrt::weak_ref<xaml::FrameworkElement> element;
        winrt::event_token loaded{};
    };
    using ScrollController = controls::Primitives::IScrollController;
    struct ControllerRequests {
        winrt::weak_ref<ScrollController> controller;
        winrt::event_token to{}, by{};
        void clear() {
            if (auto current = controller.get()) {
                if (to.value) current.ScrollToRequested(to);
                if (by.value) current.ScrollByRequested(by);
            }
            controller = {}; to = {}; by = {};
        }
        ~ControllerRequests() { clear(); }
    };
    struct ScrollerInsets {
        int64_t view = 0;
        xaml::Thickness region{};
        std::vector<IndicatorMargin> indicators;
        bool pending = false;
        winrt::event_token templateLayout{};
        std::vector<ViewportRequest> viewportRequests;
        winrt::event_token viewportLayout{};
        winrt::event_token readerLayout{};
        winrt::event_token readerExtent{};
        winrt::event_token readerCompleted{};
        int32_t pendingJump = -1;
        double pendingX = 0, pendingY = 0;
        std::array<ControllerRequests, 2> controllers;
        std::array<ScrollController, 2> testingControllers{nullptr, nullptr};
    };
    std::unordered_map<void *, std::weak_ptr<ScrollerInsets>> insetStates;

    // ScrollTo is queued by ScrollPresenter's controller handler. Our handler
    // runs after it assigns the correlation, but before composition consumes
    // the request. Announce only explicit nonanimated destinations: an animated
    // endpoint must never materialize all the intervening rows.
    void prepareControllerJump(controls::ScrollView const &scroller,
                               std::shared_ptr<ScrollerInsets> const &state,
                               bool horizontal, double value, bool relative,
                               int32_t correlation, controls::ScrollingScrollOptions const &options) {
        if (correlation < 0 || !options || !std::isfinite(value)) return;
        if (options.AnimationMode() != controls::ScrollingAnimationMode::Disabled) {
            state->pendingJump = -1;
            return;
        }
        double x = state->pendingJump >= 0 ? state->pendingX : scroller.HorizontalOffset();
        double y = state->pendingJump >= 0 ? state->pendingY : scroller.VerticalOffset();
        auto &offset = horizontal ? x : y;
        offset = relative ? offset + value : value;
        x = std::clamp(x, 0.0, scroller.ScrollableWidth());
        y = std::clamp(y, 0.0, scroller.ScrollableHeight());
        state->pendingJump = correlation;
        state->pendingX = x;
        state->pendingY = y;
        callbacks.scrollPreparing(state->view, x, y, correlation);
    }

    void watchControllers(controls::ScrollView const &scroller,
                          std::shared_ptr<ScrollerInsets> const &state) {
        auto presenter = scroller.ScrollPresenter();
        if (!presenter) return;
        std::array<ScrollController, 2> controllers{
            presenter.HorizontalScrollController(), presenter.VerticalScrollController()};
        for (size_t index = 0; index < controllers.size(); ++index) {
            auto &watch = state->controllers[index];
            auto controller = controllers[index];
            if (watch.controller.get() == controller) continue;
            watch.clear();
            if (!controller) continue;
            watch.controller = winrt::make_weak(controller);
            auto weak = winrt::make_weak(scroller);
            std::weak_ptr<ScrollerInsets> weakState = state;
            watch.to = controller.ScrollToRequested(guarded("preparing a scrollbar destination",
                [weak, weakState, horizontal = index == 0](auto const &, auto const &args) {
                if (auto scroller = weak.get()) if (auto state = weakState.lock())
                    prepareControllerJump(scroller, state, horizontal, args.Offset(), false,
                                          args.CorrelationId(), args.Options());
            }));
            watch.by = controller.ScrollByRequested(guarded("preparing a scrollbar increment",
                [weak, weakState, horizontal = index == 0](auto const &, auto const &args) {
                if (auto scroller = weak.get()) if (auto state = weakState.lock())
                    prepareControllerJump(scroller, state, horizontal, args.OffsetDelta(), true,
                                          args.CorrelationId(), args.Options());
            }));
        }
    }

    bool isDescendantOf(xaml::DependencyObject const &element, xaml::DependencyObject const &ancestor) {
        for (auto at = element; at; at = xaml::Media::VisualTreeHelper::GetParent(at))
            if (at == ancestor) return true;
        return false;
    }

    SwiftOmniUIViewportStatus readViewport(controls::ScrollView const &scroller,
                                          xaml::FrameworkElement const &element, double *viewport) {
        try {
            auto content = scroller.Content().try_as<xaml::UIElement>();
            auto presenter = scroller.ScrollPresenter();
            if (!content || !scroller.IsLoaded() || !element.IsLoaded()
                || !scroller.XamlRoot() || scroller.XamlRoot() != element.XamlRoot()
                || !presenter) return SwiftOmniUIViewportNotReady;
            if (!isDescendantOf(element, content)) return SwiftOmniUIViewportNotReady;
            auto width = scroller.ViewportWidth(), height = scroller.ViewportHeight();
            if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0)
                return SwiftOmniUIViewportNotReady;
            auto parent = xaml::Media::VisualTreeHelper::GetParent(content).try_as<xaml::UIElement>();
            if (!parent) return SwiftOmniUIViewportNotReady;
            auto displayed = element.TransformToVisual(parent).TransformPoint({0, 0});
            auto initial = presenter.TransformToVisual(element).TransformBounds(
                winrt::Windows::Foundation::Rect(0, 0, static_cast<float>(width), static_cast<float>(height)));
            double left = initial.X, top = initial.Y;
            double right = left + initial.Width, bottom = top + initial.Height;
            auto intersect = [&](xaml::UIElement const &clipper, winrt::Windows::Foundation::Rect const &region) {
                auto bounds = clipper.TransformToVisual(element).TransformBounds(region);
                if (!std::isfinite(bounds.X) || !std::isfinite(bounds.Y)
                    || !std::isfinite(bounds.Width) || !std::isfinite(bounds.Height))
                    throw winrt::hresult_error(E_UNEXPECTED);
                left = std::max(left, double(bounds.X));
                top = std::max(top, double(bounds.Y));
                right = std::min(right, double(bounds.X) + bounds.Width);
                bottom = std::min(bottom, double(bounds.Y) + bounds.Height);
            };
            // Virtualization follows layout viewports. A native pane transition,
            // clipShape or alpha mask changes presentation, not the allocation
            // whose rows must already exist before it is revealed.
            for (xaml::DependencyObject at = element; at; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                auto visual = at.try_as<xaml::UIElement>();
                if (!visual) continue;
                if (visual.Visibility() == xaml::Visibility::Collapsed) return SwiftOmniUIViewportNotReady;
                if (auto presenter = visual.try_as<controls::Primitives::ScrollPresenter>()) {
                    auto across = presenter.ViewportWidth(), down = presenter.ViewportHeight();
                    if (!std::isfinite(across) || !std::isfinite(down) || across <= 0 || down <= 0)
                        return SwiftOmniUIViewportNotReady;
                    intersect(visual, {0, 0, static_cast<float>(across), static_cast<float>(down)});
                }
            }
            double values[]{left, top, std::max(0.0, right - left), std::max(0.0, bottom - top), displayed.X, displayed.Y};
            if (!std::all_of(std::begin(values), std::end(values), [](double value) { return std::isfinite(value); }))
                return SwiftOmniUIViewportNotReady;
            std::copy(std::begin(values), std::end(values), viewport);
            return SwiftOmniUIViewportReady;
        } catch (...) {
            report("reading a descendant's scroll viewport");
            return SwiftOmniUIViewportFailed;
        }
    }

    void resumeViewportRequests(controls::ScrollView const &scroller, std::shared_ptr<ScrollerInsets> const &state) {
        bool completed = false;
        state->viewportRequests.erase(std::remove_if(state->viewportRequests.begin(), state->viewportRequests.end(),
            [&](auto const &request) {
                auto element = request.element.get();
                if (!element) return true;
                auto content = scroller.Content().try_as<xaml::DependencyObject>();
                if (element.IsLoaded() && content && !isDescendantOf(element, content)) {
                    // A retained page can be promoted or reparented to another
                    // native owner. Its old scroller no longer owns the request.
                    element.Loaded(request.loaded);
                    return true;
                }
                double viewport[6];
                if (readViewport(scroller, element, viewport) == SwiftOmniUIViewportNotReady) return false;
                element.Loaded(request.loaded);
                completed = true;
                return true;
            }), state->viewportRequests.end());
        if (state->viewportRequests.empty() && state->viewportLayout.value != 0) {
            scroller.LayoutUpdated(state->viewportLayout);
            state->viewportLayout = {};
        }
        // Ready and Failed both complete a pending request. Existing scroll
        // ears read the explicit result; a failure never becomes a retry loop.
        if (completed) callbacks.scrolled(state->view, scroller.HorizontalOffset(), scroller.VerticalOffset());
    }

    void awaitViewport(controls::ScrollView const &scroller, xaml::FrameworkElement const &element) {
        auto found = insetStates.find(winrt::get_abi(scroller));
        if (found == insetStates.end()) return;
        auto state = found->second.lock();
        if (!state) return;
        auto weak = winrt::make_weak(scroller);
        if (std::none_of(state->viewportRequests.begin(), state->viewportRequests.end(),
                        [&](auto const &request) { return request.element.get() == element; })) {
            ViewportRequest request{winrt::make_weak(element)};
            std::weak_ptr<ScrollerInsets> weakState = state;
            request.loaded = element.Loaded(guarded("attaching a pending scroll viewport", [weak, weakState](auto const &, auto const &) {
                if (auto scroller = weak.get()) {
                    if (auto state = weakState.lock()) resumeViewportRequests(scroller, state);
                }
            }));
            state->viewportRequests.push_back(request);
        }
        if (state->viewportLayout.value != 0) return;
        state->viewportLayout = scroller.LayoutUpdated(guarded("resuming a ready scroll viewport", [weak, state](auto const &, auto const &) {
            if (auto scroller = weak.get()) resumeViewportRequests(scroller, state);
        }));
    }

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
            if (auto scroller = weak.get()) {
                watchControllers(scroller, state);
                applyInsets(scroller, *state);
            }
        }))) state->pending = false;
    }

    void templateInsets(controls::ScrollView const &scroller, std::shared_ptr<ScrollerInsets> const &state) {
        if (state->templateLayout) return;
        // TemplateProperty changes before the new parts are arranged. Observe
        // that one layout, then stop listening to unrelated window layouts.
        state->templateLayout = scroller.LayoutUpdated(guarded("preparing changed scroller template",
            [weak = winrt::make_weak(scroller), state](auto const &, auto const &) {
            if (auto scroller = weak.get()) {
                scroller.LayoutUpdated(std::exchange(state->templateLayout, {}));
                queueInsets(scroller, state);
            }
        }));
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

    // A test controller drives ScrollPresenter's real request event pipeline,
    // including correlation assignment/coalescing. No synthetic Swift offset
    // report or pointer injection is involved.
    struct RequestedScrollController : winrt::implements<RequestedScrollController, ScrollController> {
        using ToArgs = controls::Primitives::ScrollControllerScrollToRequestedEventArgs;
        using ByArgs = controls::Primitives::ScrollControllerScrollByRequestedEventArgs;
        using VelocityArgs = controls::Primitives::ScrollControllerAddScrollVelocityRequestedEventArgs;
        template<typename Args> using Handler = winrt::Windows::Foundation::TypedEventHandler<ScrollController, Args>;
        winrt::event<Handler<ToArgs>> to;
        winrt::event<Handler<ByArgs>> by;
        controls::Primitives::IScrollControllerPanningInfo PanningInfo() { return nullptr; }
        bool CanScroll() { return true; }
        bool IsScrollingWithMouse() { return false; }
        void SetIsScrollable(bool) {}
        void SetValues(double, double, double, double) {}
        winrt::Microsoft::UI::Composition::CompositionAnimation GetScrollAnimation(
            int32_t, winrt::Windows::Foundation::Numerics::float2 const &,
            winrt::Windows::Foundation::Numerics::float2 const &,
            winrt::Microsoft::UI::Composition::CompositionAnimation const &animation) { return animation; }
        void NotifyRequestedScrollCompleted(int32_t) {}
        winrt::event_token CanScrollChanged(Handler<IInspectable> const &) { return {}; }
        void CanScrollChanged(winrt::event_token const &) {}
        winrt::event_token IsScrollingWithMouseChanged(Handler<IInspectable> const &) { return {}; }
        void IsScrollingWithMouseChanged(winrt::event_token const &) {}
        winrt::event_token ScrollToRequested(Handler<ToArgs> const &handler) { return to.add(handler); }
        void ScrollToRequested(winrt::event_token const &token) { to.remove(token); }
        winrt::event_token ScrollByRequested(Handler<ByArgs> const &handler) { return by.add(handler); }
        void ScrollByRequested(winrt::event_token const &token) { by.remove(token); }
        winrt::event_token AddScrollVelocityRequested(Handler<VelocityArgs> const &) { return {}; }
        void AddScrollVelocityRequested(winrt::event_token const &) {}
    };

    void scrollTo(controls::ScrollView const &scroller, double x, double y, bool animated) {
        // Completion also reports cancellation. The native presenter owns the
        // request's lifetime; never resurrect its target from ScrollCompleted.
        auto correlation = scroller.ScrollTo(x, y, controls::ScrollingScrollOptions(
            animated ? controls::ScrollingAnimationMode::Enabled : controls::ScrollingAnimationMode::Disabled,
            controls::ScrollingSnapPointsMode::Ignore));
        auto found = insetStates.find(winrt::get_abi(scroller));
        if (found != insetStates.end()) {
            if (auto state = found->second.lock()) {
                state->pendingJump = animated ? -1 : correlation;
                state->pendingX = std::clamp(x, 0.0, scroller.ScrollableWidth());
                state->pendingY = std::clamp(y, 0.0, scroller.ScrollableHeight());
            }
        }
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_scroller_make(int64_t view) {
    try {
        controls::ScrollView scroller;
        registerAcrylicScroller(scroller);
        auto insets = std::make_shared<ScrollerInsets>();
        insets->view = view;
        for (auto at = insetStates.begin(); at != insetStates.end();) {
            if (at->second.expired()) at = insetStates.erase(at); else ++at;
        }
        insetStates[winrt::get_abi(scroller)] = insets;
        scroller.ScrollCompleted(guarded("completing a prepared scroll jump",
            [view, insets](controls::ScrollView const &scroller, controls::ScrollingScrollCompletedEventArgs const &args) {
            if (insets->pendingJump == -1 || insets->pendingJump != args.CorrelationId()) return;
            insets->pendingJump = -1;
            // Completion includes cancellation. Reconcile with the actual
            // viewport, never replay the old target after a newer input.
            callbacks.scrolled(view, scroller.HorizontalOffset(), scroller.VerticalOffset());
        }));
        scroller.Loaded(guarded("preparing scroller margins", [insets](IInspectable const &sender, auto const &) {
            auto scroller = sender.as<controls::ScrollView>();
            queueInsets(scroller, insets);
            resumeViewportRequests(scroller, insets);
        }));
        scroller.RegisterPropertyChangedCallback(controls::Control::TemplateProperty(),
            guarded("refreshing scroller template margins", [insets](xaml::DependencyObject const &sender,
                xaml::DependencyProperty const &) { templateInsets(sender.as<controls::ScrollView>(), insets); }));
        scroller.ActualThemeChanged(guarded("refreshing themed scroller margins",
            [insets](xaml::FrameworkElement const &sender, auto const &) {
                templateInsets(sender.as<controls::ScrollView>(), insets);
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

extern "C" bool swiftomniui_winui_scroller_request_from_controller(
    SwiftOmniUIObjectRef handle, bool horizontal, double value, bool relative, bool animated) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto presenter = scroller.ScrollPresenter();
        auto found = insetStates.find(winrt::get_abi(scroller));
        if (!presenter || found == insetStates.end()) return false;
        auto state = found->second.lock();
        if (!state) return false;
        auto &installed = state->testingControllers[horizontal ? 0 : 1];
        if (!installed) {
            installed = winrt::make<RequestedScrollController>();
            if (horizontal) presenter.HorizontalScrollController(installed);
            else presenter.VerticalScrollController(installed);
            watchControllers(scroller, state);
        }
        auto controller = winrt::get_self<RequestedScrollController>(installed);
        controls::ScrollingScrollOptions options(
            animated ? controls::ScrollingAnimationMode::Enabled : controls::ScrollingAnimationMode::Disabled,
            controls::ScrollingSnapPointsMode::Ignore);
        if (relative) {
            RequestedScrollController::ByArgs args(value, options);
            controller->by(installed, args);
            return args.CorrelationId() >= 0;
        }
        RequestedScrollController::ToArgs args(value, options);
        controller->to(installed, args);
        return args.CorrelationId() >= 0;
    } catch (...) {
        report("requesting a native controller scroll for testing");
        return false;
    }
}

extern "C" bool swiftomniui_winui_scroller_jump_pending(SwiftOmniUIObjectRef handle) {
    return swiftomniui_winui_scroller_pending_jump_id(handle) >= 0;
}

extern "C" int32_t swiftomniui_winui_scroller_pending_jump_id(SwiftOmniUIObjectRef handle) {
    try {
        auto found = insetStates.find(winrt::get_abi(borrow<controls::ScrollView>(handle)));
        if (found == insetStates.end()) return -1;
        auto state = found->second.lock();
        return state ? state->pendingJump : -1;
    } catch (...) {
        report("reading a pending scroll jump");
        return -1;
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
        double viewport[6]{};
        if (!element || !content || readViewport(scroller, element, viewport) != SwiftOmniUIViewportReady) {
            *found = 0; return;
        }
        // Arrange can publish the new row bounds before ScrollPresenter has
        // committed its new range. Clamping against that old range would
        // incorrectly complete a reader request at yesterday's document end.
        auto document = content.try_as<xaml::FrameworkElement>();
        auto sameExtent = [](double extent, double actual, double room) {
            return std::abs(std::max(extent, room) - std::max(actual, room)) <= 0.5;
        };
        if (document && (!sameExtent(scroller.ExtentWidth(), document.ActualWidth(), scroller.ViewportWidth())
            || !sameExtent(scroller.ExtentHeight(), document.ActualHeight(), scroller.ViewportHeight()))) {
            *found = 0; return;
        }

        auto bounds = element.TransformToVisual(content).TransformBounds(
            winrt::Windows::Foundation::Rect(
                0, 0, (float)element.ActualWidth(), (float)element.ActualHeight()));

        xaml::Thickness insets{};
        if (auto found = insetStates.find(winrt::get_abi(scroller)); found != insetStates.end())
            if (auto state = found->second.lock()) insets = state->region;
        auto nearest = [](double start, double length, double room, double now) {
            // Oversized content cannot fit between both safe edges. Keep the
            // trailing alignment stable: after reaching it, choosing `start`
            // on the next observation would alternate between the two edges.
            if (length > room) return start + length - room;
            if (start >= now && start + length <= now + room) return now;
            return start + length > now + room ? start + length - room : start;
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

extern "C" void swiftomniui_winui_scroller_watch_layout(
    SwiftOmniUIObjectRef handle, int64_t view, void (*callback)(int64_t)) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto found = insetStates.find(winrt::get_abi(scroller));
        if (found == insetStates.end()) return;
        auto state = found->second.lock();
        if (!state) return;
        if (state->readerLayout.value) scroller.LayoutUpdated(std::exchange(state->readerLayout, {}));
        if (state->readerExtent.value) scroller.ExtentChanged(std::exchange(state->readerExtent, {}));
        if (state->readerCompleted.value) scroller.ScrollCompleted(std::exchange(state->readerCompleted, {}));
        if (callback) {
            state->readerLayout = scroller.LayoutUpdated(guarded("resolving a reader destination",
                [view, callback](auto const &, auto const &) { callback(view); }));
            state->readerExtent = scroller.ExtentChanged(guarded("resolving a changed reader extent",
                [view, callback](auto const &, auto const &) { callback(view); }));
            state->readerCompleted = scroller.ScrollCompleted(guarded("completing a reader destination",
                [view, callback](auto const &, auto const &) { callback(view); }));
        }
    } catch (...) { report("observing a reader destination's layout"); }
}

extern "C" void swiftomniui_winui_scroller_insets(
    SwiftOmniUIObjectRef handle, double top, double right, double bottom, double left
) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto found = insetStates.find(winrt::get_abi(scroller));
        if (found == insetStates.end()) return;
        if (auto state = found->second.lock()) {
            auto region = xaml::Thickness{left, top, right, bottom};
            if (sameMargin(state->region, region)) return;
            state->region = region;
            queueInsets(scroller, state);
        }
    } catch (...) {
        report("insetting a scroller's bars");
    }
}

extern "C" SwiftOmniUIViewportStatus swiftomniui_winui_scroller_viewport(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef descendant, double *viewport
) {
    try {
        auto scroller = borrow<controls::ScrollView>(handle);
        auto element = as<xaml::FrameworkElement>(descendant);
        auto status = readViewport(scroller, element, viewport);
        if (status == SwiftOmniUIViewportNotReady) awaitViewport(scroller, element);
        return status;
    } catch (...) {
        report("reading a descendant's scroll viewport");
        return SwiftOmniUIViewportFailed;
    }
}

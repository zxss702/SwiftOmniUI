// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A ScrollView's scroller: WinUI's ScrollView around the document the host
// lays out, saying where its view stands and when the user holds it.
// Design: docs/design/platforms/winui/layout.md#scrolling

#include "Relay.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Composition.Interactions.h>
#include <winrt/Microsoft.UI.Content.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Numerics.h>

using namespace swiftomniui;

namespace {
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
    // where it lands, and the run's window realizes both ends.
    struct ScrollerFlight {
        double x = std::nan(""), y = std::nan("");
        bool held = false;
    };

    // Temporary migration diagnostics: one line in C:\Users\zxs20\lui-lazy.log.
    void scrollDiag(char const *fmt, ...) {
        FILE *log = fopen("C:\\Users\\zxs20\\lui-lazy.log", "a");
        if (!log) return;
        va_list args;
        va_start(args, fmt);
        vfprintf(log, fmt, args);
        va_end(args);
        fputc('\n', log);
        fclose(log);
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_scroller_make(int64_t view) {
    try {
        controls::ScrollView scroller;
        auto flight = std::make_shared<ScrollerFlight>();
        scroller.ZoomMode(controls::ScrollingZoomMode::Disabled);
        // The InteractionTracker's word of the view, every frame it moves: the
        // ear hears where it stands now paired with where an animation lands.
        scroller.ViewChanged(guarded("handling ViewChanged",
            [view, flight](controls::ScrollView const &scroller, IInspectable const &) {
            double x = scroller.HorizontalOffset(), y = scroller.VerticalOffset();
            callbacks.scrolling(view, x, y,
                std::isnan(flight->x) ? x : flight->x, std::isnan(flight->y) ? y : flight->y);
            if (scroller.State() == controls::ScrollingInteractionState::Interaction)
                callbacks.scrolled(view, x, y);
        }));
        // Temporary migration diagnostics.
        scroller.ViewChanged(guarded("tracing ViewChanged",
            [](controls::ScrollView const &scroller, IInspectable const &) {
            static int skipped = 0;
            if (scroller.State() != controls::ScrollingInteractionState::Idle || ++skipped % 60 == 1)
                scrollDiag("view.changed at=(%g,%g) state=%d room=(%g,%g) view=%gx%g presenter=%d",
                    scroller.HorizontalOffset(), scroller.VerticalOffset(), (int)scroller.State(),
                    scroller.ScrollableWidth(), scroller.ScrollableHeight(),
                    scroller.ViewportWidth(), scroller.ViewportHeight(),
                    scroller.ScrollPresenter() != nullptr);
        }));
        auto hooked = std::make_shared<bool>(false);
        scroller.SizeChanged(guarded("tracing SizeChanged",
            [view, hooked](IInspectable const &sender, xaml::SizeChangedEventArgs const &args) {
            auto scroller = sender.as<controls::ScrollView>();
            auto now = args.NewSize(), was = args.PreviousSize();
            scrollDiag("scroller[%lld].sized (%gx%g)->(%gx%g) align=%d desired=(%gx%g) presenter=%g",
                view, was.Width, was.Height, now.Width, now.Height,
                (int)scroller.VerticalAlignment(),
                scroller.DesiredSize().Width, scroller.DesiredSize().Height,
                scroller.ScrollPresenter() ? scroller.ScrollPresenter().ActualHeight() : -1.0);
            if (!*hooked) {
                if (auto presenter = scroller.ScrollPresenter()) {
                    *hooked = true;
                    scrollDiag("scroll.presenter seen loaded=%d", (int)presenter.IsLoaded());
                    presenter.Loaded([](IInspectable const &, xaml::RoutedEventArgs const &) {
                        scrollDiag("scroll.presenterLoaded");
                    });
                    presenter.Unloaded([](IInspectable const &, xaml::RoutedEventArgs const &) {
                        scrollDiag("scroll.presenterUnloaded");
                    });
                    presenter.ScrollCompleted([](winrt::Microsoft::UI::Xaml::Controls::Primitives::ScrollPresenter const &,
                        controls::ScrollingScrollCompletedEventArgs const &e) {
                        scrollDiag("scroll.presenterCompleted id=%d", (int)e.CorrelationId());
                    });
                }
            }
        }));
        // An animation - inertia's or a move the program animated - names its
        // landing as it starts: realized before the compositor can reach it.
        scroller.ScrollAnimationStarting(guarded("handling ScrollAnimationStarting",
            [view, flight](controls::ScrollView const &scroller,
                controls::ScrollingScrollAnimationStartingEventArgs const &args) {
            auto end = args.EndPosition();
            flight->x = end.x;
            flight->y = end.y;
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
            scrollDiag("state.changed state=%d at=(%g,%g)", (int)state,
                scroller.HorizontalOffset(), scroller.VerticalOffset());
        }));
        // Temporary migration diagnostics: does the scroller load, and does
        // the compositor tick rendering frames at all?
        scroller.Loaded(guarded("tracing Loaded",
            [](IInspectable const &sender, xaml::RoutedEventArgs const &) {
            scrollDiag("scroll.loaded");
            auto scroller = sender.as<controls::ScrollView>();
            if (auto presenter = scroller.ScrollPresenter()) {
                scrollDiag("scroll.presenter actual=(%gx%g) xamlroot=%d",
                    presenter.ActualWidth(), presenter.ActualHeight(), presenter.XamlRoot() != nullptr);
                presenter.Loaded([](IInspectable const &, xaml::RoutedEventArgs const &) {
                    scrollDiag("scroll.presenterLoaded");
                });
                presenter.Unloaded([](IInspectable const &, xaml::RoutedEventArgs const &) {
                    scrollDiag("scroll.presenterUnloaded");
                });
            }
        }));
        scroller.Unloaded(guarded("tracing Unloaded",
            [](IInspectable const &, xaml::RoutedEventArgs const &) {
            scrollDiag("scroll.unloaded");
        }));
        xaml::Media::CompositionTarget::Rendering([](IInspectable const &, IInspectable const &) {
            static int ticks = 0;
            if (++ticks % 60 == 1) scrollDiag("scroll.rendering tick=%d", ticks);
        });
        scroller.ScrollCompleted(guarded("tracing ScrollCompleted",
            [](controls::ScrollView const &, controls::ScrollingScrollCompletedEventArgs const &args) {
            scrollDiag("scroll.completed id=%d", (int)args.CorrelationId());
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
        auto scroller = borrow<controls::ScrollView>(handle);
        scrollDiag("scroll.move to=(%g,%g) anim=%d at=(%g,%g) room=(%g,%g) view=(%gx%g) doc=(%gx%g) presenter=%d state=%d actual=(%gx%g) presenterActual=(%gx%g) desired=(%gx%g)",
            x, y, (int)animated, scroller.HorizontalOffset(), scroller.VerticalOffset(),
            scroller.ScrollableWidth(), scroller.ScrollableHeight(),
            scroller.ViewportWidth(), scroller.ViewportHeight(),
            scroller.ExtentWidth(), scroller.ExtentHeight(),
            scroller.ScrollPresenter() != nullptr, (int)scroller.State(),
            scroller.ActualWidth(), scroller.ActualHeight(),
            scroller.ScrollPresenter() ? scroller.ScrollPresenter().ActualWidth() : -1.0,
            scroller.ScrollPresenter() ? scroller.ScrollPresenter().ActualHeight() : -1.0,
            scroller.DesiredSize().Width, scroller.DesiredSize().Height);
        scrollDiag("scroll.move xamlroot=%d presenterXamlRoot=%d loaded=%d presenterLoaded=%d",
            scroller.XamlRoot() != nullptr,
            scroller.ScrollPresenter() ? scroller.ScrollPresenter().XamlRoot() != nullptr : -1,
            (int)scroller.IsLoaded(),
            scroller.ScrollPresenter() ? (int)scroller.ScrollPresenter().IsLoaded() : -1);
        if (auto sources = scroller.ExpressionAnimationSources()) {
            auto at = [&sources](wchar_t const *name) {
                winrt::Windows::Foundation::Numerics::float2 v{ 0, 0 };
                return sources.TryGetVector2(name, v)
                    == winrt::Microsoft::UI::Composition::CompositionGetValueStatus::Succeeded
                    ? v : winrt::Windows::Foundation::Numerics::float2{ -1, -1 };
            };
            auto pos = at(L"Position"), lo = at(L"MinPosition"), hi = at(L"MaxPosition");
            auto ext = at(L"Extent"), vp = at(L"Viewport"), off = at(L"Offset");
            scrollDiag("scroll.move sources pos=(%g,%g) min=(%g,%g) max=(%g,%g) ext=(%g,%g) vp=(%g,%g) off=(%g,%g)",
                pos.x, pos.y, lo.x, lo.y, hi.x, hi.y, ext.x, ext.y, vp.x, vp.y, off.x, off.y);
        } else scrollDiag("scroll.move sources=0");
        auto id = scroller.ScrollTo(x, y, controls::ScrollingScrollOptions(
            animated ? controls::ScrollingAnimationMode::Enabled : controls::ScrollingAnimationMode::Disabled,
            controls::ScrollingSnapPointsMode::Ignore));
        scrollDiag("scroll.moved id=%d at=(%g,%g)", (int)id,
            scroller.HorizontalOffset(), scroller.VerticalOffset());
        // Temporary diagnostics: does this window's compositor evaluate
        // expression animations at all? A constant expression on a private
        // property set answers that with no ScrollPresenter involvement.
        auto probe = std::make_shared<winrt::Microsoft::UI::Composition::CompositionPropertySet>(nullptr);
        auto naked = std::make_shared<winrt::Microsoft::UI::Composition::Interactions::InteractionTracker>(nullptr);
        auto batch = std::make_shared<winrt::Microsoft::UI::Composition::CompositionScopedBatch>(nullptr);
        auto freshProbe = std::make_shared<winrt::Microsoft::UI::Composition::CompositionPropertySet>(nullptr);
        auto commitOp = std::make_shared<winrt::Windows::Foundation::IAsyncAction>(nullptr);
        winrt::Microsoft::UI::Composition::Compositor compositor{ nullptr };
        try {
            winrt::Microsoft::UI::Composition::Compositor fresh{};
            *freshProbe = fresh.CreatePropertySet();
            freshProbe->InsertScalar(L"v", 0.0f);
            freshProbe->StartAnimation(L"v", fresh.CreateExpressionAnimation(L"2.0"));
            compositor = winrt::Microsoft::UI::Xaml::Hosting::ElementCompositionPreview::GetElementVisual(scroller).Compositor();
            *probe = compositor.CreatePropertySet();
            probe->InsertScalar(L"v", 0.0f);
            probe->StartAnimation(L"v", compositor.CreateExpressionAnimation(L"2.0"));
            *naked = winrt::Microsoft::UI::Composition::Interactions::InteractionTracker::Create(compositor);
            naked->MinPosition(winrt::Windows::Foundation::Numerics::float3{ 0, 0, 0 });
            naked->MaxPosition(winrt::Windows::Foundation::Numerics::float3{ 0, 5000, 0 });
            auto requestId = naked->TryUpdatePosition(winrt::Windows::Foundation::Numerics::float3{ 0, 100, 0 });
            scrollDiag("scroll.naked req=%d", (int)requestId);
            auto cdq = compositor.DispatcherQueue();
            auto tdq = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();
            scrollDiag("scroll.move cdq=%d same=%d", cdq != nullptr,
                cdq && tdq && winrt::get_abi(cdq) == winrt::get_abi(tdq));
            if (auto root = scroller.XamlRoot()) {
                if (auto env = root.ContentIslandEnvironment()) {
                    auto hwnd = reinterpret_cast<HWND>(env.AppWindowId().Value);
                    RECT rect{};
                    GetWindowRect(hwnd, &rect);
                    scrollDiag("scroll.move hwnd=%p visible=%d iconic=%d rect=(%ld,%ld)-(%ld,%ld)",
                        hwnd, IsWindowVisible(hwnd), IsIconic(hwnd),
                        rect.left, rect.top, rect.right, rect.bottom);
                } else scrollDiag("scroll.move env=0");
                if (auto island = root.ContentIsland()) {
                    auto sz = island.ActualSize();
                    scrollDiag("scroll.island enabled=%d size=(%g,%g)", island.IsSiteEnabled(), sz.x, sz.y);
                } else scrollDiag("scroll.island=0");
            }
            *batch = compositor.CreateScopedBatch(winrt::Microsoft::UI::Composition::CompositionBatchTypes::AllAnimations);
            probe->StartAnimation(L"w", compositor.CreateExpressionAnimation(L"3.0"));
            batch->End();
            batch->Completed([](winrt::Windows::Foundation::IInspectable const &,
                winrt::Microsoft::UI::Composition::CompositionBatchCompletedEventArgs const &) {
                scrollDiag("scroll.batchDone");
            });
        } catch (...) { report("making a compositor probe"); }
        // The request stands three rendering frames in line before the tracker
        // hears it, and a still window renders none: keep it producing frames
        // until the view moves, bounded so a move that cannot land gives up.
        double const startX = scroller.HorizontalOffset(), startY = scroller.VerticalOffset();
        auto remaining = std::make_shared<int>(12);
        auto token = std::make_shared<winrt::event_token>();
        *token = xaml::Media::CompositionTarget::Rendering(
            [scroller, token, remaining, startX, startY, probe, naked, batch, compositor, freshProbe, commitOp](IInspectable const &, IInspectable const &) {
            if (compositor) {
                auto op = compositor.RequestCommitAsync();
                if (!*commitOp) {
                    *commitOp = op;
                    op.Completed([](winrt::Windows::Foundation::IAsyncAction const &a, winrt::Windows::Foundation::AsyncStatus s) {
                        scrollDiag("scroll.commitReq status=%d hr=%08X", (int)s, (unsigned)(int32_t)a.ErrorCode());
                    });
                }
            }
            if (--*remaining <= 0
                || scroller.HorizontalOffset() != startX || scroller.VerticalOffset() != startY) {
                xaml::Media::CompositionTarget::Rendering(*token);
                if (auto sources = scroller.ExpressionAnimationSources()) {
                    winrt::Windows::Foundation::Numerics::float2 v{ 0, 0 }, p{ 0, 0 };
                    float z = -1;
                    sources.TryGetVector2(L"MaxPosition", v);
                    sources.TryGetVector2(L"Position", p);
                    sources.TryGetScalar(L"ZoomFactor", z);
                    winrt::Windows::Foundation::Numerics::float2 o{ 0, 0 };
                    sources.TryGetVector2(L"Offset", o);
                    auto presenter = scroller.ScrollPresenter();
                    auto pv = presenter
                        ? winrt::Microsoft::UI::Xaml::Hosting::ElementCompositionPreview::GetElementVisual(presenter).Size()
                        : winrt::Windows::Foundation::Numerics::float2{ -1, -1 };
                    float probeV = -1, freshV = -1;
                    if (*probe) probe->TryGetScalar(L"v", probeV);
                    if (*freshProbe) freshProbe->TryGetScalar(L"v", freshV);
                    auto nakedPos = *naked ? (*naked).Position() : winrt::Windows::Foundation::Numerics::float3{ -1, -1, -1 };
                    auto nakedMax = *naked ? (*naked).MaxPosition() : winrt::Windows::Foundation::Numerics::float3{ -1, -1, -1 };
                    scrollDiag("scroll.pump end left=%d at=(%g,%g) max=(%g,%g) pos=(%g,%g) zoom=%g memberzoom=%g off=(%g,%g) state=%d pvisual=(%g,%g) minzoom=%g maxzoom=%g probe=%g naked=(%g,%g) nakedMax=(%g,%g) fresh=%g",
                        *remaining, scroller.HorizontalOffset(), scroller.VerticalOffset(),
                        v.x, v.y, p.x, p.y, z, scroller.ZoomFactor(), o.x, o.y, (int)scroller.State(),
                        pv.x, pv.y,
                        presenter ? presenter.MinZoomFactor() : -1.0f,
                        presenter ? presenter.MaxZoomFactor() : -1.0f, probeV,
                        nakedPos.x, nakedPos.y, nakedMax.x, nakedMax.y, freshV);
                }
                return;
            }
            scroller.InvalidateArrange();
        });
    } catch (...) {
        report("moving a scroller");
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

        auto nearest = [](double start, double length, double room, double now) {
            if (start >= now && start + length <= now + room) return now;
            return start < now ? start : start + length - room;
        };

        double x = scroller.HorizontalOffset();
        double y = scroller.VerticalOffset();
        if (scroller.ComputedHorizontalScrollMode() == controls::ScrollingScrollMode::Enabled) {
            x = std::isnan(anchorX)
                ? nearest(bounds.X, bounds.Width, scroller.ViewportWidth(), x)
                : bounds.X + anchorX * bounds.Width - anchorX * scroller.ViewportWidth();
        }
        if (scroller.ComputedVerticalScrollMode() == controls::ScrollingScrollMode::Enabled) {
            y = std::isnan(anchorY)
                ? nearest(bounds.Y, bounds.Height, scroller.ViewportHeight(), y)
                : bounds.Y + anchorY * bounds.Height - anchorY * scroller.ViewportHeight();
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
        scrollDiag("scroll.offset at=(%g,%g) room=(%g,%g) view=(%gx%g) extent=(%gx%g) content=%d presenter=%d",
            offset[0], offset[1], offset[2], offset[3], scroller.ViewportWidth(), scroller.ViewportHeight(),
            scroller.ExtentWidth(), scroller.ExtentHeight(),
            scroller.Content() != nullptr, scroller.ScrollPresenter() != nullptr);
        if (auto sources = scroller.ExpressionAnimationSources()) {
            winrt::Windows::Foundation::Numerics::float2 v{ 0, 0 };
            float z = -1;
            sources.TryGetVector2(L"MaxPosition", v);
            sources.TryGetScalar(L"ZoomFactor", z);
            auto pv = scroller.ScrollPresenter()
                ? winrt::Microsoft::UI::Xaml::Hosting::ElementCompositionPreview::GetElementVisual(
                      scroller.ScrollPresenter()).Size()
                : winrt::Windows::Foundation::Numerics::float2{ -1, -1 };
            scrollDiag("scroll.offset sources max=(%g,%g) zoom=%g pvisual=(%gx%g)", v.x, v.y, z, pv.x, pv.y);
        }
    } catch (...) {
        report("reading a scroller");
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

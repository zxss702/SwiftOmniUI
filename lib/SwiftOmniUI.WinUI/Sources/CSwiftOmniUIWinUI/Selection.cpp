// SPDX-License-Identifier: Apache-2.0
// Native window commands and edge autoscrolling for custom text selections.
#include "Relay.h"
#include <algorithm>
#include <chrono>
#include <memory>
#include <unordered_map>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.System.h>

using namespace swiftomniui;
namespace {
    using Point = winrt::Windows::Foundation::Point;
    using Input = void (*)(int64_t, int32_t, double, double);
    bool editing(xaml::DependencyObject node) {
        for (; node; node = xaml::Media::VisualTreeHelper::GetParent(node))
            if (node.try_as<controls::TextBox>() || node.try_as<controls::RichEditBox>()) return true;
        return false;
    }
    struct Selection : std::enable_shared_from_this<Selection> {
        int64_t number;
        winrt::weak_ref<xaml::FrameworkElement> element;
        xaml::UIElement root{nullptr};
        xaml::Input::PointerEventHandler pointer{nullptr};
        winrt::event_token key{}, focus{}, loaded{}, unloaded{}, changed{};
        winrt::Microsoft::UI::Dispatching::DispatcherQueueTimer timer{nullptr};
        controls::ScrollView scroll{nullptr};
        controls::ScrollViewer viewer{nullptr};
        Input input;
        bool active = false, dragging = false, ownsCommands = false, pendingScroll = false;
        Point point{}, viewportPoint{};
        Selection(xaml::FrameworkElement const &view, int64_t id, Input callback)
            : number(id), element(view), input(callback) {}
        void start() {
            auto view = element.get(); if (!view) return;
            auto weak = weak_from_this();
            loaded = view.Loaded(guarded("attaching selection input", [weak](auto const &, auto const &) {
                if (auto state = weak.lock()) state->attach();
            }));
            unloaded = view.Unloaded(guarded("detaching selection input", [weak](auto const &, auto const &) {
                if (auto state = weak.lock()) state->disconnect();
            }));
            timer = view.DispatcherQueue().CreateTimer(); timer.Interval(std::chrono::milliseconds(16));
            timer.Tick(guarded("autoscrolling a selection", [weak](auto const &, auto const &) {
                if (auto state = weak.lock()) state->tick();
            }));
            attach();
        }
        ~Selection() {
            try {
                disconnect();
                if (auto view = element.get()) { view.Loaded(loaded); view.Unloaded(unloaded); }
            } catch (...) { report("releasing selection handlers"); }
        }
        void stopScroll() {
            pendingScroll = false;
            if (scroll) scroll.ViewChanged(changed);
            if (viewer) viewer.ViewChanged(changed);
            scroll = nullptr; viewer = nullptr;
        }
        void disconnect() {
            if (timer) timer.Stop();
            stopScroll();
            if (root) {
                root.RemoveHandler(xaml::UIElement::PointerPressedEvent(), pointer);
                root.PreviewKeyDown(key); root.GotFocus(focus);
                root = nullptr; pointer = nullptr;
            }
            ownsCommands = false;
        }
        void attach() {
            auto view = element.get(); if (!view || !view.XamlRoot()) return;
            auto next = view.XamlRoot().Content(); if (root == next) return;
            disconnect(); root = next;
            auto weak = weak_from_this();
            pointer = guarded("following selection presses", [weak](IInspectable const &, xaml::Input::PointerRoutedEventArgs const &args) {
                auto state = weak.lock(); if (!state) return;
                auto view = state->element.get(); if (!view) return;
                auto position = args.GetCurrentPoint(view);
                if (!position.Properties().IsLeftButtonPressed()) return;
                auto p = position.Position();
                state->ownsCommands = p.X >= 0 && p.Y >= 0 && p.X <= view.ActualWidth() && p.Y <= view.ActualHeight()
                    && !editing(args.OriginalSource().try_as<xaml::DependencyObject>());
                state->input(state->number, 0, 0, 0);
            });
            root.AddHandler(xaml::UIElement::PointerPressedEvent(), pointer, true);
            focus = root.GotFocus(guarded("returning native edit commands", [weak](auto const &, xaml::RoutedEventArgs const &args) {
                if (auto state = weak.lock(); state && editing(args.OriginalSource().try_as<xaml::DependencyObject>()))
                    state->ownsCommands = false;
            }));
            key = root.PreviewKeyDown(guarded("handling selection commands", [weak](auto const &, xaml::Input::KeyRoutedEventArgs const &args) {
                auto state = weak.lock();
                if (!state || !(state->active || state->ownsCommands) || args.Handled() || !(GetKeyState(VK_CONTROL) & 0x8000)
                    || (GetKeyState(VK_MENU) & 0x8000) || (GetKeyState(VK_SHIFT) & 0x8000)) return;
                auto focus = xaml::Input::FocusManager::GetFocusedElement(state->root.XamlRoot()).try_as<xaml::DependencyObject>();
                if (!state->ownsCommands && editing(focus)) return;
                auto code = args.Key() == winrt::Windows::System::VirtualKey::C ? 1
                    : args.Key() == winrt::Windows::System::VirtualKey::A ? 2 : -1;
                if (code < 0) return;
                args.Handled(true); state->input(state->number, code, 0, 0);
            }));
            if (dragging) timer.Start();
        }
        xaml::UIElement scrollVisual() {
            if (scroll) return scroll.as<xaml::UIElement>();
            return viewer ? viewer.as<xaml::UIElement>() : nullptr;
        }
        void scrolled() {
            if (!pendingScroll || !dragging || !root) return;
            auto view = element.get(); auto visual = scrollVisual();
            if (!view || !visual || !view.XamlRoot() || view.XamlRoot().Content() != root) return;
            auto inverse = view.TransformToVisual(visual).Inverse(); if (!inverse) return;
            // ViewChanged, rather than a queued dispatcher turn, says the
            // native scroll offset and its content transform actually changed.
            point = inverse.TransformPoint(viewportPoint); pendingScroll = false;
            input(number, 3, point.X, point.Y);
        }
        void follow(controls::ScrollView const &native, controls::ScrollViewer const &legacy) {
            if (scroll == native && viewer == legacy) return;
            stopScroll(); scroll = native; viewer = legacy;
            auto weak = weak_from_this();
            auto report = guarded("reading selection scroll coordinates", [weak](auto const &, auto const &) {
                if (auto state = weak.lock()) state->scrolled();
            });
            if (scroll) changed = scroll.ViewChanged(report);
            else if (viewer) changed = viewer.ViewChanged(report);
        }
        void update(bool enabled, bool drag, double x, double y) {
            active = enabled; dragging = drag; point = {static_cast<float>(x), static_cast<float>(y)};
            attach();
            if (pendingScroll) {
                if (auto view = element.get(); view && scrollVisual()) viewportPoint = view.TransformToVisual(scrollVisual()).TransformPoint(point);
            }
            if (dragging && root) timer.Start();
            else { timer.Stop(); stopScroll(); }
        }
        void tick() {
            auto view = element.get(); if (!view || !dragging || !root) { timer.Stop(); return; }
            if (pendingScroll) return;
            for (auto node = xaml::Media::VisualTreeHelper::GetParent(view); node; node = xaml::Media::VisualTreeHelper::GetParent(node)) {
                auto native = node.try_as<controls::ScrollView>(); auto legacy = node.try_as<controls::ScrollViewer>();
                if (!native && !legacy) continue;
                auto visual = node.as<xaml::UIElement>();
                double oldX = native ? native.HorizontalOffset() : legacy.HorizontalOffset();
                double oldY = native ? native.VerticalOffset() : legacy.VerticalOffset();
                double width = native ? native.ViewportWidth() : legacy.ViewportWidth();
                double height = native ? native.ViewportHeight() : legacy.ViewportHeight();
                double limitX = native ? native.ScrollableWidth() : legacy.ScrollableWidth();
                double limitY = native ? native.ScrollableHeight() : legacy.ScrollableHeight();
                auto p = view.TransformToVisual(visual).TransformPoint(point);
                auto step = [](double position, double extent) {
                    return position < 28 ? -std::clamp((28.0 - position) / 28, 0.0, 1.0) * 16
                        : position > extent - 28 ? std::clamp((position - extent + 28) / 28, 0.0, 1.0) * 16 : 0;
                };
                double nextX = std::clamp(oldX + step(p.X, width), 0.0, std::max(0.0, limitX));
                double nextY = std::clamp(oldY + step(p.Y, height), 0.0, std::max(0.0, limitY));
                if (nextX == oldX && nextY == oldY) continue;
                follow(native, legacy); viewportPoint = p; pendingScroll = true;
                if (native) {
                    if (native.ScrollTo(nextX, nextY, controls::ScrollingScrollOptions(
                        controls::ScrollingAnimationMode::Disabled, controls::ScrollingSnapPointsMode::Ignore)) < 0) pendingScroll = false;
                } else if (!legacy.ChangeView(nextX, nextY, nullptr, true)) pendingScroll = false;
                return;
            }
        }
    };
    std::unordered_map<int64_t, std::shared_ptr<Selection>> selections;
}
extern "C" void swiftomniui_winui_selection_interaction(SwiftOmniUIObjectRef handle, int64_t view,
    bool active, bool dragging, double x, double y, Input input) {
    try {
        if (!input) return;
        auto &state = selections[view];
        if (!state) {
            state = std::make_shared<Selection>(as<xaml::FrameworkElement>(handle), view, input);
            state->start();
        }
        state->update(active, dragging, x, y);
    } catch (...) { report("following a desktop text selection"); }
}
extern "C" void swiftomniui_winui_selection_interaction_clear(int64_t view) {
    try {
        auto found = selections.find(view);
        if (found == selections.end()) return;
        auto state = std::move(found->second); selections.erase(found); state->disconnect();
    } catch (...) { report("releasing a desktop text selection"); }
}

// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The panel every SwiftOmniUI layout is: WinUI asks it to measure and arrange, and
// the host answers with the core's arithmetic.
// Design: docs/design/platforms/winui/layout.md#a-layout-is-a-panel

#include "Relay.h"
#include "AcrylicScene.h"

#include <algorithm>
#include <unordered_set>
#include <memory>
#include <vector>

#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Provider.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Media.Animation.h>
#include <winrt/Microsoft.UI.Xaml.Navigation.h>
#include <winrt/Windows.UI.Xaml.Interop.h>

using namespace swiftomniui;
using winrt::Windows::Foundation::Size;
namespace peers = winrt::Microsoft::UI::Xaml::Automation::Peers;
namespace provider = winrt::Microsoft::UI::Xaml::Automation::Provider;
namespace composition = winrt::Microsoft::UI::Composition;
using winrt::Windows::Foundation::Rect;

namespace {
    // Preserve the control handle and native input identity while allocating
    // its viewport beyond the safe layout slot, as SOUI ScrollView does.
    struct HostedViewport : controls::PanelT<HostedViewport> {
        xaml::FrameworkElement control;
        xaml::Thickness outsets{};
        explicit HostedViewport(xaml::FrameworkElement const &element) : control(element) {
            UseLayoutRounding(false);
            Children().Append(control);
            registerAcrylicScroller(control);
        }
        Size MeasureOverride(Size) { return {0, 0}; }
        Size ArrangeOverride(Size final) {
            const Size room{static_cast<float>(final.Width + outsets.Left + outsets.Right),
                            static_cast<float>(final.Height + outsets.Top + outsets.Bottom)};
            control.Measure(room);
            control.Arrange({static_cast<float>(-outsets.Left), static_cast<float>(-outsets.Top), room.Width, room.Height});
            return final;
        }
    };

    struct SwiftOmniUIPanel;

    // Use projected equality for every native child comparison. An unchanged
    // panel needs no edits; changed panels can then keep an overlap attached.
    bool sameChildren(winrt::Windows::Foundation::Collections::IVector<xaml::UIElement> const &items,
                      std::vector<xaml::UIElement> const &held) {
        if (items.Size() != held.size()) return false;
        for (uint32_t index = 0; index < held.size(); ++index) {
            if (items.GetAt(index) != held[index]) return false;
        }
        return true;
    }

    // A structural branch can move an existing UIElement from an HStack panel
    // into a VStack panel. XAML rejects insertion while the old panel still
    // owns it; detach that exact child before synchronizing the new parent.
    void detachFromForeignPanel(controls::Panel const &target, xaml::UIElement const &child) {
        auto parent = xaml::Media::VisualTreeHelper::GetParent(child);
        auto panel = parent.try_as<controls::Panel>();
        if (!panel || panel == target) return;
        uint32_t index;
        if (panel.Children().IndexOf(child, index)) panel.Children().RemoveAt(index);
    }

    // A moving lazy window normally drops children at one edge and adds them at
    // the other. Keep the overlapping projected UIElements attached. Comparing
    // projections here is intentional: their ABI interface pointers need not
    // be identical even when they refer to the same XAML element.
    bool syncEdgeChildren(controls::Panel const &owner,
                          winrt::Windows::Foundation::Collections::IVector<xaml::UIElement> const &items,
                          std::vector<xaml::UIElement> const &held) {
        auto oldCount = items.Size();
        auto newCount = static_cast<uint32_t>(held.size());
        uint32_t prefix = 0;
        while (prefix < oldCount && prefix < newCount && items.GetAt(prefix) == held[prefix]) ++prefix;
        if (prefix == std::min(oldCount, newCount)) {
            while (items.Size() > prefix) items.RemoveAtEnd();
            for (uint32_t index = prefix; index < newCount; ++index) {
                detachFromForeignPanel(owner, held[index]);
                items.Append(held[index]);
            }
            return true;
        }

        uint32_t oldStart;
        if (items.IndexOf(held.front(), oldStart) && oldStart > 0
            && oldCount - oldStart <= newCount) {
            auto overlap = oldCount - oldStart;
            bool equal = true;
            for (uint32_t index = 0; index < overlap; ++index) {
                if (items.GetAt(oldStart + index) != held[index]) { equal = false; break; }
            }
            if (equal) {
                for (uint32_t index = 0; index < oldStart; ++index) items.RemoveAt(0);
                for (uint32_t index = overlap; index < newCount; ++index) {
                    detachFromForeignPanel(owner, held[index]);
                    items.Append(held[index]);
                }
                return true;
            }
        }

        auto firstOld = items.GetAt(0);
        auto newStart = std::find(held.begin(), held.end(), firstOld);
        if (newStart != held.end()) {
            auto offset = static_cast<uint32_t>(newStart - held.begin());
            if (offset > 0 && newCount - offset <= oldCount) {
                auto overlap = newCount - offset;
                bool equal = true;
                for (uint32_t index = 0; index < overlap; ++index) {
                    if (items.GetAt(index) != held[offset + index]) { equal = false; break; }
                }
                if (equal) {
                    while (items.Size() > overlap) items.RemoveAtEnd();
                    for (uint32_t index = offset; index > 0; --index) {
                        detachFromForeignPanel(owner, held[index - 1]);
                        items.InsertAt(0, held[index - 1]);
                    }
                    return true;
                }
            }
        }
        return false;
    }

    void removeUnused(winrt::Windows::Foundation::Collections::IVector<xaml::UIElement> const &items,
                      std::vector<xaml::UIElement> const &held) {
        // Canonical COM identity avoids O(old * new) projected comparisons
        // when a lazy jump replaces an entire viewport. Both lists keep the
        // objects alive throughout this local membership check.
        std::unordered_set<::IUnknown *> retained;
        retained.reserve(held.size());
        for (auto const &child : held) retained.insert(child.as<::IUnknown>().get());
        for (uint32_t index = items.Size(); index > 0; --index) {
            if (!retained.contains(items.GetAt(index - 1).as<::IUnknown>().get())) items.RemoveAt(index - 1);
        }
    }

    void insertInOrder(winrt::Windows::Foundation::Collections::IVector<xaml::UIElement> const &items,
                       std::vector<xaml::UIElement> const &held, controls::Panel const &owner = nullptr) {
        if (sameChildren(items, held)) return;
        for (uint32_t index = 0; index < held.size(); ++index) {
            // A new tail need not search the prefix already put in order.
            if (index == items.Size()) {
                if (owner) detachFromForeignPanel(owner, held[index]);
                items.Append(held[index]);
                continue;
            }
            if (items.GetAt(index) == held[index]) continue;
            uint32_t previous;
            if (items.IndexOf(held[index], previous)) items.RemoveAt(previous);
            else if (owner) detachFromForeignPanel(owner, held[index]);
            items.InsertAt(index, held[index]);
        }
    }

    struct MaskSourcePeer : peers::FrameworkElementAutomationPeerT<MaskSourcePeer> {
        using Base = peers::FrameworkElementAutomationPeerT<MaskSourcePeer>;
        MaskSourcePeer(xaml::FrameworkElement const &owner, bool hidden) : Base(owner), hidden(hidden) {}

        winrt::Windows::Foundation::Collections::IVector<peers::AutomationPeer> GetChildrenCore() {
            if (hidden) return winrt::single_threaded_vector<peers::AutomationPeer>();
            return Base::GetChildrenCore();
        }

        bool hidden;
    };

    /// A native redirection boundary, not another layout engine. Swift still
    /// measures and arranges the original children in the parent's coordinates.
    struct MaskSourcePanel : controls::PanelT<MaskSourcePanel> {
        explicit MaskSourcePanel(bool mask) : mask(mask) {
            Resources().Insert(winrt::box_value(L"safeBarLocalPresentation"), winrt::box_value(true));
            HorizontalAlignment(xaml::HorizontalAlignment::Stretch);
            VerticalAlignment(xaml::VerticalAlignment::Stretch);
            if (mask) {
                IsHitTestVisible(false);
                gettingFocus = GettingFocus(winrt::auto_revoke,
                    guarded("handling a mask's GettingFocus",
                        [](xaml::UIElement const &, xaml::Input::GettingFocusEventArgs const &args) {
                            // A mask supplies drawing, never an input target. A
                            // routed focus request from any descendant ends here.
                            (void)args.TryCancel();
                        }));
            }
        }
        Size MeasureOverride(Size) { return Size(0, 0); }
        Size ArrangeOverride(Size final) { return final; }
        peers::AutomationPeer OnCreateAutomationPeer() {
            IInspectable self = *this;
            return winrt::make<MaskSourcePeer>(self.as<xaml::FrameworkElement>(), mask);
        }
        bool mask;
        xaml::UIElement::GettingFocus_revoker gettingFocus;
    };

    /// The same live visual-surface redirection as WinUI Gallery's OpacityMaskView.
    /// Keeping the hidden roots separate preserves every authored descendant's
    /// opacity, transform, clip, focus and native control identity.
    struct AlphaMask {
        controls::Panel content = winrt::make<MaskSourcePanel>(false).as<controls::Panel>();
        controls::Panel mask = winrt::make<MaskSourcePanel>(true).as<controls::Panel>();
        xaml::UIElement maskElement{nullptr};
        composition::CompositionVisualSurface contentSurface{nullptr}, maskSurface{nullptr};
        composition::CompositionSurfaceBrush sourceBrush{nullptr}, alphaBrush{nullptr};
        composition::CompositionMaskBrush brush{nullptr};
        composition::SpriteVisual output{nullptr};

        explicit AlphaMask(controls::Panel const &owner) {
            auto contentVisual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(content);
            auto maskVisual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(mask);
            auto compositor = contentVisual.Compositor();
            contentSurface = compositor.CreateVisualSurface();
            maskSurface = compositor.CreateVisualSurface();
            contentSurface.SourceVisual(contentVisual);
            maskSurface.SourceVisual(maskVisual);

            // VisualSurface omits its source root's own opacity. Hide only these
            // unstyled roots; the child's XAML/Composition opacity stays intact.
            contentVisual.Opacity(0);
            maskVisual.Opacity(0);
            sourceBrush = compositor.CreateSurfaceBrush(contentSurface);
            alphaBrush = compositor.CreateSurfaceBrush(maskSurface);
            for (auto const &surface : {sourceBrush, alphaBrush}) {
                surface.Stretch(composition::CompositionStretch::None);
                surface.HorizontalAlignmentRatio(0);
                surface.VerticalAlignmentRatio(0);
            }
            brush = compositor.CreateMaskBrush();
            brush.Source(sourceBrush);
            output = compositor.CreateSpriteVisual();
            output.Brush(brush);
            owner.Children().Append(content);
            owner.Children().Append(mask);
            xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(owner, output);
        }

        void setChildren(std::vector<xaml::UIElement> const &held) {
            std::vector<xaml::UIElement> source, alpha;
            for (auto const &child : held) {
                (maskElement && child == maskElement ? alpha : source).push_back(child);
            }
            // Remove from both parents before a child's role changes; intersecting
            // children remain attached so updating a mask never remounts content.
            removeUnused(content.Children(), source);
            removeUnused(mask.Children(), alpha);
            insertInOrder(content.Children(), source);
            insertInOrder(mask.Children(), alpha);
            brush.Mask(maskElement ? alphaBrush : nullptr);
        }

        void measure(Size available) {
            content.Measure(available);
            mask.Measure(available);
        }

        void arrange(Size final) {
            // Use the same local coordinate window for source and mask. Resizing
            // changes the surfaces' window, not the shape's coordinate system.
            Rect room(0, 0, final.Width, final.Height);
            content.Arrange(room);
            mask.Arrange(room);
            winrt::Windows::Foundation::Numerics::float2 size{final.Width, final.Height};
            contentSurface.SourceSize(size);
            maskSurface.SourceSize(size);
            output.Size(size);
        }

        void close(controls::Panel const &owner) {
            xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(owner, nullptr);
            output.Brush(nullptr);
            brush.Source(nullptr);
            brush.Mask(nullptr);
            contentSurface.SourceVisual(nullptr);
            maskSurface.SourceVisual(nullptr);
            sourceBrush.Surface(nullptr);
            alphaBrush.Surface(nullptr);
            maskElement = nullptr;
        }
    };

    /// What assistive technology reads of a panel: one it can press, as a tap, while its view listens for taps, and
    /// none of what stands in it while it is left out with its children.
    /// Design: docs/design/platforms/winui/input.md#pressed-by-assistive-technology
    struct SwiftOmniUIPanelPeer : peers::FrameworkElementAutomationPeerT<SwiftOmniUIPanelPeer, provider::IInvokeProvider> {
        using Base = peers::FrameworkElementAutomationPeerT<SwiftOmniUIPanelPeer, provider::IInvokeProvider>;

        SwiftOmniUIPanelPeer(xaml::FrameworkElement const &owner, int64_t view) : Base(owner), view(view) {}

        IInspectable GetPatternCore(peers::PatternInterface const &pattern) {
            if (pattern == peers::PatternInterface::Invoke && hearsTaps(view)) return *this;
            return Base::GetPatternCore(pattern);
        }

        void Invoke() {
            press(view);
        }

        winrt::Windows::Foundation::Collections::IVector<peers::AutomationPeer> GetChildrenCore();

        int64_t view;
    };

    struct SwiftOmniUIPanel : controls::PanelT<SwiftOmniUIPanel> {
        explicit SwiftOmniUIPanel(int64_t view) : view(view) {}

        peers::AutomationPeer OnCreateAutomationPeer() {
            IInspectable self = *this;
            return winrt::make<SwiftOmniUIPanelPeer>(self.as<xaml::FrameworkElement>(), view);
        }

        Size MeasureOverride(Size available) {
            if (alphaMask) alphaMask->measure(available);
            double size[2] = {0, 0};
            callbacks.measure(view, available.Width, available.Height, size);
            if (navigationViewport) navigationViewport.Measure({available.Width, available.Height + navigationTop + navigationBottom});
            return Size(static_cast<float>(size[0]), static_cast<float>(size[1]));
        }

        Size ArrangeOverride(Size final) {
            if (alphaMask) alphaMask->arrange(final);
            callbacks.arrange(view, final.Width, final.Height);
            if (navigationViewport) {
                auto bounds = Rect(0, -navigationTop, final.Width, final.Height + navigationTop + navigationBottom);
                auto clip = Rect(0, 0, bounds.Width, bounds.Height);
                if (navigationClip.Rect() != clip) navigationClip.Rect(clip);
                navigationViewport.Arrange(bounds);
            }
            return final;
        }

        int64_t view;
        std::unique_ptr<AlphaMask> alphaMask;
        controls::Frame navigation{nullptr};
        // A stable ancestor clips both pages and XAML's unloading transition
        // visuals to this navigation column, independently of authored clips.
        controls::Grid navigationViewport{nullptr};
        xaml::Media::RectangleGeometry navigationClip{nullptr};
        float navigationTop = 0;
        float navigationBottom = 0;
        xaml::UIElement navigationContent{nullptr};

        /// Whether assistive technology meets none of what stands in the panel.
        bool childrenHidden = false;
        xaml::FrameworkElement::EffectiveViewportChanged_revoker viewportChanged;
    };

    /// The panel a handle or a peer's owner holds, reached through an interface the panel implements itself: the
    /// panel it is made on answers the rest.
    SwiftOmniUIPanel *panel(xaml::UIElement const &element) {
        return winrt::get_self<SwiftOmniUIPanel>(element.as<xaml::IFrameworkElementOverrides>());
    }

    winrt::Windows::Foundation::Collections::IVector<peers::AutomationPeer> SwiftOmniUIPanelPeer::GetChildrenCore() {
        if (panel(Owner())->childrenHidden) return winrt::single_threaded_vector<peers::AutomationPeer>();
        return Base::GetChildrenCore();
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_panel_make(int64_t view) {
    try {
        return detach(winrt::make<SwiftOmniUIPanel>(view).as<controls::Panel>());
    } catch (...) {
        report("making a panel");
        return nullptr;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_navigation_make(int64_t view) {
    try {
        auto held = winrt::make<SwiftOmniUIPanel>(view).as<controls::Panel>();
        auto owner = panel(held);
        owner->navigation = controls::Frame();
        owner->navigationViewport = controls::Grid();
        owner->navigationViewport.UseLayoutRounding(false);
        owner->navigationClip = xaml::Media::RectangleGeometry();
        owner->navigationViewport.Clip(owner->navigationClip);
        owner->navigationViewport.Children().Append(owner->navigation);
        owner->navigation.IsNavigationStackEnabled(false);
        owner->navigation.HorizontalContentAlignment(xaml::HorizontalAlignment::Stretch);
        owner->navigation.VerticalContentAlignment(xaml::VerticalAlignment::Stretch);
        owner->navigation.Navigated(guarded("hosting a navigated page",
            [](IInspectable const &, xaml::Navigation::NavigationEventArgs const &args) {
                auto page = args.Content().as<controls::Page>();
                page.NavigationCacheMode(xaml::Navigation::NavigationCacheMode::Disabled);
                page.HorizontalContentAlignment(xaml::HorizontalAlignment::Stretch);
                page.VerticalContentAlignment(xaml::VerticalAlignment::Stretch);
                page.Background(nullptr);
                // Put the theme transition on every Page shell explicitly.
                // Its unload storyboard keeps the old shell visible until
                // the exit completes, as well as animating the entering page.
                xaml::Media::Animation::TransitionCollection transitions;
                transitions.Append(xaml::Media::Animation::NavigationThemeTransition());
                page.Transitions(transitions);
                page.Content(args.Parameter().as<xaml::UIElement>());
            }));
        held.Children().Append(owner->navigationViewport);
        return detach(held);
    } catch (...) {
        report("making a navigation frame");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_navigation_set(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef background, SwiftOmniUIObjectRef content,
    bool animated, bool back
) {
    try {
        auto held = as<controls::Panel>(handle);
        auto owner = panel(held);
        auto frame = owner->navigation;
        if (!frame) return;
        std::vector<xaml::UIElement> children;
        if (background) children.push_back(as<xaml::UIElement>(background));
        children.push_back(owner->navigationViewport);
        removeUnused(held.Children(), children);
        insertInOrder(held.Children(), children);
        auto next = content ? as<xaml::UIElement>(content) : xaml::UIElement{nullptr};
        if (next == owner->navigationContent) return;
        // Adding a drawing boundary can replace the current page's native
        // content without changing its logical page or navigation depth.
        if (auto page = frame.Content().try_as<controls::Page>(); page && page.Content() == next) {
            owner->navigationContent = next;
            return;
        }
        if (!next) {
            frame.Content(nullptr);
            owner->navigationContent = nullptr;
            return;
        }
        // A rapid return may find the retained Swift view in a Page whose
        // native transition is still finishing. It must have only one parent.
        for (auto parent = xaml::Media::VisualTreeHelper::GetParent(next); parent;
             parent = xaml::Media::VisualTreeHelper::GetParent(parent)) {
            if (auto page = parent.try_as<controls::Page>(); page && page.Content() == next) {
                page.Content(nullptr);
                break;
            }
        }
        using namespace xaml::Media::Animation;
        NavigationTransitionInfo transition{nullptr};
        if (animated && swiftomniui_winui_animations_enabled()) {
            SlideNavigationTransitionInfo slide;
            slide.Effect(back ? SlideNavigationTransitionEffect::FromLeft : SlideNavigationTransitionEffect::FromRight);
            transition = slide;
        } else {
            transition = SuppressNavigationTransitionInfo();
        }
        if (!frame.Navigate(winrt::xaml_typename<controls::Page>(), next, transition))
            throw winrt::hresult_error(E_FAIL, L"WinUI refused the navigation page");
        owner->navigationContent = next;
    } catch (...) {
        report("navigating the retained page");
    }
}

extern "C" void swiftomniui_winui_navigation_clear(SwiftOmniUIObjectRef handle) {
    try {
        auto owner = panel(as<xaml::UIElement>(handle));
        if (owner->navigation) owner->navigation.Content(nullptr);
        owner->navigationContent = nullptr;
        owner->navigation = nullptr;
        if (owner->navigationViewport) owner->navigationViewport.Children().Clear();
        owner->navigationViewport = nullptr;
        owner->navigationClip = nullptr;
        as<controls::Panel>(handle).Children().Clear();
    } catch (...) { report("releasing a navigation frame"); }
}

extern "C" void swiftomniui_winui_navigation_set_vertical_outsets(
    SwiftOmniUIObjectRef handle, double top, double bottom
) {
    try {
        auto owner = panel(as<xaml::UIElement>(handle));
        owner->navigationTop = static_cast<float>(std::max(0.0, top));
        owner->navigationBottom = static_cast<float>(std::max(0.0, bottom));
    } catch (...) { report("extending the navigation clip under native chrome"); }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_masked_panel_make(int64_t view) {
    try {
        auto held = winrt::make<SwiftOmniUIPanel>(view).as<controls::Panel>();
        panel(held)->alphaMask = std::make_unique<AlphaMask>(held);
        return detach(held);
    } catch (...) {
        report("making an alpha-masked panel");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_masked_panel_set_children(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef const *children, int32_t count, SwiftOmniUIObjectRef mask
) {
    try {
        auto owner = panel(as<xaml::UIElement>(handle));
        if (!owner->alphaMask) return;
        if (count < 0 || (count > 0 && !children)) throw winrt::hresult_invalid_argument();
        owner->alphaMask->maskElement = mask ? as<xaml::UIElement>(mask) : nullptr;
        std::vector<xaml::UIElement> held;
        held.reserve(count);
        for (int32_t index = 0; index < count; ++index) held.push_back(as<xaml::UIElement>(children[index]));
        owner->alphaMask->setChildren(held);
    } catch (...) {
        report("setting a panel's alpha source");
    }
}

extern "C" void swiftomniui_winui_masked_panel_clear(SwiftOmniUIObjectRef handle) {
    try {
        auto held = as<controls::Panel>(handle);
        auto owner = panel(held);
        if (owner->alphaMask) owner->alphaMask->close(held);
    } catch (...) {
        report("releasing a panel's alpha surfaces");
    }
}

extern "C" void swiftomniui_winui_panel_set_children(
    SwiftOmniUIObjectRef panel, SwiftOmniUIObjectRef const *children, int32_t count
) {
    try {
        auto owner = borrow<controls::Panel>(panel);
        auto items = owner.Children();
        std::vector<xaml::UIElement> held;
        held.reserve(count);
        for (int32_t index = 0; index < count; ++index) held.push_back(as<xaml::UIElement>(children[index]));
        if (sameChildren(items, held)) return;
        // A lazy window usually changes at its edges. Keep the intersecting
        // UIElements attached, preserving their native state and composition.
        // Only inserted elements can belong to another panel. Querying native
        // parents for the retained window repeats work for every dense row.
        if (!syncEdgeChildren(owner, items, held)) {
            removeUnused(items, held);
            insertInOrder(items, held, owner);
        }
        acrylicStructureChanged(owner);
    } catch (...) {
        report("holding a panel's children");
    }
}

extern "C" void swiftomniui_winui_panel_hide_children(SwiftOmniUIObjectRef handle, bool hidden) {
    try {
        panel(as<xaml::UIElement>(handle))->childrenHidden = hidden;
    } catch (...) {
        report("hiding a panel's children from assistive technology");
    }
}

extern "C" void swiftomniui_winui_panel_watch_viewport(SwiftOmniUIObjectRef handle, bool enabled) {
    try {
        auto element = as<xaml::FrameworkElement>(handle);
        auto owner = panel(element);
        owner->viewportChanged.revoke();
        if (enabled) {
            owner->viewportChanged = element.EffectiveViewportChanged(winrt::auto_revoke,
                guarded("handling EffectiveViewportChanged",
                    [view = owner->view](xaml::FrameworkElement const &, xaml::EffectiveViewportChangedEventArgs const &args) {
                        auto viewport = args.EffectiveViewport();
                        callbacks.viewportChanged(view, viewport.X, viewport.Y, viewport.Width, viewport.Height,
                            args.BringIntoViewDistanceX(), args.BringIntoViewDistanceY());
                    }));
        }
    } catch (...) {
        report("watching a panel's viewport");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_hosted_viewport_make(SwiftOmniUIObjectRef control) {
    try { return detach(winrt::make<HostedViewport>(as<xaml::FrameworkElement>(control)).as<controls::Panel>()); }
    catch (...) { report("making a native scrolling control's allocation boundary"); return nullptr; }
}

extern "C" void swiftomniui_winui_hosted_viewport_set(
    SwiftOmniUIObjectRef handle, double top, double right, double bottom, double left
) {
    try {
        auto viewport = winrt::get_self<HostedViewport>(as<xaml::IFrameworkElementOverrides>(handle));
        const xaml::Thickness next{left, top, right, bottom};
        if (viewport->outsets == next) return;
        viewport->outsets = next;
        viewport->InvalidateArrange();
    } catch (...) { report("allocating a native scrolling control beneath safe chrome"); }
}

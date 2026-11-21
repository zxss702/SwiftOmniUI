// SPDX-License-Identifier: Apache-2.0
#include "AcrylicScene.h"
#include <winrt/Microsoft.UI.Dispatching.h>
#include <algorithm>
#include <limits>
#include <cmath>
#include <utility>
#include <vector>

namespace swiftomniui {
    using Rect = winrt::Windows::Foundation::Rect;
    using Element = xaml::FrameworkElement;

    namespace {
        struct Inset {
            winrt::weak_ref<Element> owner, bar, material;
            AcrylicEdge edge = AcrylicEdge::fixed;
            bool localMaterial = false;
        };
        std::vector<Inset> insets;
        struct WindowRoot { winrt::weak_ref<Element> root, content; };
        std::vector<WindowRoot> windows;
        struct Columns {
            winrt::weak_ref<Element> owner;
            std::vector<winrt::weak_ref<Element>> pages;
        };
        std::vector<Columns> columnGroups;
        struct Scroller {
            winrt::weak_ref<Element> element;
            xaml::Thickness insets{};
            winrt::event_token viewChanged{};
            bool underTop = false, underBottom = false;
        };
        std::vector<Scroller> scrollers;
        std::vector<std::weak_ptr<AcrylicScene>> scenes;
        uint64_t generation = 0;
        bool materialDirty = true;
        xaml::Media::CompositionTarget::Rendering_revoker materialCommit;
        constexpr float edgeTolerance = 0.5f;

        bool descendant(xaml::DependencyObject element, xaml::DependencyObject const &root) {
            for (; element; element = xaml::Media::VisualTreeHelper::GetParent(element))
                if (element == root) return true;
            return false;
        }
        bool insideScroller(xaml::DependencyObject const &element, xaml::DependencyObject const &scope) {
            if (element == scope) return false;
            for (auto at = xaml::Media::VisualTreeHelper::GetParent(element); at;
                 at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                if (at == scope) break;
                if (at.try_as<controls::ScrollView>() || at.try_as<controls::ScrollViewer>()) return true;
            }
            return false;
        }
        Rect intersect(Rect const &a, Rect const &b) {
            auto x = std::max(a.X, b.X), y = std::max(a.Y, b.Y);
            return {x, y, std::max(0.0f, std::min(a.X + a.Width, b.X + b.Width) - x),
                          std::max(0.0f, std::min(a.Y + a.Height, b.Y + b.Height) - y)};
        }

        void queueMaterialCommit(Element const &element) {
            markAcrylicMaterialDirty();
            if (materialCommit || !element.DispatcherQueue()) return;
            // Scroll offsets can change after the last layout or host
            // animation sample. Commit the new edge and crop at the next
            // native frame boundary, even while the sidebar is still moving.
            materialCommit = xaml::Media::CompositionTarget::Rendering(winrt::auto_revoke,
                guarded("presenting changed material at rendering", [](auto const &, auto const &) {
                    materialCommit.revoke();
                    swiftomniui_winui_material_present_if_needed();
                }));
        }

        void observeNativeScroller(Scroller &state, Element const &element) {
            auto weak = winrt::make_weak(element);
            if (auto scroller = element.try_as<controls::ScrollView>()) {
                state.viewChanged = scroller.ViewChanged([weak](auto const &, auto const &) {
                    if (auto element = weak.get()) updateAcrylicScroller(element);
                });
                scroller.ExtentChanged([weak](auto const &, auto const &) {
                    if (auto element = weak.get()) updateAcrylicScroller(element);
                });
                scroller.ScrollCompleted(guarded("committing the settled scroll material",
                    [](controls::ScrollView const &sender, controls::ScrollingScrollCompletedEventArgs const &) {
                        // A nonanimated bottom jump and the sidebar slide
                        // have independent lifetimes. Publish the viewport's
                        // actual landing even if ViewChanged already recorded
                        // the same edge before this viewport was drawable.
                        updateAcrylicScroller(sender);
                        queueMaterialCommit(sender);
                    }));
            } else if (auto viewer = element.try_as<controls::ScrollViewer>()) {
                viewer.RegisterPropertyChangedCallback(controls::ScrollViewer::ScrollableHeightProperty(),
                    [weak](auto const &, auto const &) {
                        if (auto element = weak.get()) updateAcrylicScroller(element);
                    });
                state.viewChanged = viewer.ViewChanged([weak](auto const &, auto const &) {
                    if (auto element = weak.get()) updateAcrylicScroller(element);
                });
            }
            // An initial scroll-to-bottom can settle its offset while hidden.
            // Revealing that viewport changes the capture without moving the
            // scroll edge or causing another XAML layout.
            element.RegisterPropertyChangedCallback(xaml::UIElement::OpacityProperty(),
                guarded("updating a scroller's material visibility",
                    [](xaml::DependencyObject const &sender, xaml::DependencyProperty const &) {
                        queueMaterialCommit(sender.as<Element>());
                    }));
        }

        void discoverNativeScrollers(xaml::DependencyObject const &node) {
            if (auto element = node.try_as<Element>()) {
                if (element.try_as<controls::ScrollView>() || element.try_as<controls::ScrollViewer>()) {
                    registerAcrylicScroller(element);
                    // The outer viewport already supplies this scope's live
                    // document. Nested material scopes discover their own.
                    return;
                }
            }
            for (int32_t index = 0, count = xaml::Media::VisualTreeHelper::GetChildrenCount(node);
                 index < count; ++index)
                discoverNativeScrollers(xaml::Media::VisualTreeHelper::GetChild(node, index));
        }
    }

    Rect acrylicVisibleBounds(Element const &element, Element const &root) {
        if (!element || !root || !element.IsLoaded() || element.ActualWidth() <= 0 || element.ActualHeight() <= 0) return {};
        auto size = element.ActualSize();
        auto bounds = element.TransformToVisual(root).TransformBounds({0, 0, size.x, size.y});
        for (xaml::DependencyObject at = element; at; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            auto parent = at.try_as<Element>();
            if (!parent) continue;
            if (parent.Visibility() != xaml::Visibility::Visible) return {};
            if (auto clip = parent.Clip())
                bounds = intersect(bounds, parent.TransformToVisual(root).TransformBounds(clip.Rect()));
            if (parent.try_as<controls::ScrollView>() || parent.try_as<controls::ScrollViewer>())
                bounds = intersect(bounds, parent.TransformToVisual(root).TransformBounds(
                    {0, 0, static_cast<float>(parent.ActualWidth()), static_cast<float>(parent.ActualHeight())}));
            if (auto split = parent.try_as<controls::SplitView>(); split && parent != element) {
                const bool pane = descendant(element, split.Pane());
                // IsPaneOpen is the requested destination, not presentation.
                // The native PaneRoot keeps its moving clip/visibility until
                // the close storyboard completes. Material inherits that tree.
                auto slot = (pane ? split.Pane() : split.Content()).try_as<Element>();
                if (slot) {
                    auto room = slot.ActualSize();
                    bounds = intersect(bounds, slot.TransformToVisual(root).TransformBounds({0, 0, room.x, room.y}));
                }
            }
            if (parent == root) break;
        }
        auto room = root.ActualSize();
        return intersect(bounds, {0, 0, room.x, room.y});
    }

    Rect acrylicLayoutBounds(Element const &element, Element const &root) {
        if (!element || !root) return {};
        float x = 0, y = 0;
        xaml::DependencyObject at = element;
        for (; at && at != root; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            if (auto node = at.try_as<xaml::UIElement>()) {
                const auto offset = node.ActualOffset(); x += offset.x; y += offset.y;
            }
        }
        if (!at) return {};
        const auto size = element.ActualSize();
        return {x, y, size.x, size.y};
    }

    bool hasAcrylicScrollerInsets() noexcept {
        try {
            if (insets.empty()) return false;
            for (auto const &entry : insets) {
                auto owner = entry.owner.get();
                if (!owner) continue;
                for (auto at = xaml::Media::VisualTreeHelper::GetParent(owner); at;
                     at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                    if (at.try_as<controls::ScrollView>() || at.try_as<controls::ScrollViewer>()) return true;
                }
            }
        } catch (...) {}
        return false;
    }

    void markAcrylicMaterialDirty() noexcept { materialDirty = true; }
    bool takeAcrylicMaterialDirty() noexcept {
        const bool was = materialDirty;
        materialDirty = false;
        return was;
    }
    struct AcrylicScene : std::enable_shared_from_this<AcrylicScene> {
        winrt::weak_ref<Element> content, root, window;
        uint64_t revision = std::numeric_limits<uint64_t>::max();
        bool awaitsLayout = false;
        bool committing = false;
        xaml::FrameworkElement::LayoutUpdated_revoker layoutCommitted;
        std::vector<std::function<bool()>> observers;
        AcrylicScene(Element const &content, Element const &root)
            : content(winrt::make_weak(content)), root(winrt::make_weak(root)) {}

        void watch() {
            // One native post-layout commit per scope. LayoutUpdated runs after
            // all column/viewport placements, including the first mount. There
            // are no delayed retries, per-frontier listeners or frame polls.
            auto weak = weak_from_this();
            if (auto coordinates = root.get())
                layoutCommitted = coordinates.LayoutUpdated(winrt::auto_revoke, [weak](auto const &, auto const &) {
                    auto self = weak.lock();
                    if (!self || self->committing) return;
                    auto root = self->root.get();
                    if (!root || !root.IsLoaded()) return;
                    self->commitPresentation(true);
                });
        }

        void commitPresentation(bool afterLayout = false) {
            if (committing) return;
            committing = true;
            try {
                refresh(afterLayout);
                auto callbacks = std::move(observers);
                observers.clear();
                for (auto &callback : callbacks) if (callback()) observers.push_back(std::move(callback));
            } catch (...) { report("committing a material scope's presentation"); }
            committing = false;
        }

        void refresh(bool afterLayout = false) {
            auto source = content.get();
            if (source && (revision != generation || (afterLayout && awaitsLayout))) {
                discoverNativeScrollers(source);
                revision = generation;
                awaitsLayout = !afterLayout;
            }
        }
    };

    std::vector<Element> acrylicWindowRoots() {
        std::vector<Element> result;
        for (auto const &entry : windows) if (auto root = entry.root.get(); root && root.IsLoaded()) result.push_back(root);
        return result;
    }

    std::vector<Element> acrylicWindowColumns(Element const &root) {
        Element content{nullptr};
        for (auto const &window : windows) if (window.root.get() == root) content = window.content.get();
        if (!content) return {};
        // Only the outer NavigationSplitView partitions window chrome. A split
        // inside a column continues to use that column's shared material.
        for (auto const &group : columnGroups) {
            auto owner = group.owner.get();
            if (!owner || !descendant(owner, content)) continue;
            bool nested = false;
            for (auto const &other : columnGroups) if (auto outer = other.owner.get(); outer && outer != owner
                && descendant(outer, content) && descendant(owner, outer)) { nested = true; break; }
            if (nested) continue;
            std::vector<Element> result;
            for (auto const &entry : group.pages) if (auto page = entry.get(); page && page.IsLoaded()
                && descendant(page, owner)) result.push_back(page);
            if (!result.empty()) return result;
        }
        return {content};
    }

    controls::Panel acrylicColumnOwner(Element const &column, Element const &root) {
        for (auto at = xaml::Media::VisualTreeHelper::GetParent(column); at && at != root;
             at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            if (auto split = at.try_as<controls::SplitView>()) {
                auto slot = descendant(column, split.Pane()) ? split.Pane() : split.Content();
                return slot.try_as<controls::Panel>();
            }
        }
        return nullptr;
    }

    void presentAcrylicScenes() {
        // Called by the existing host presentation transaction. Snapshot the
        // scopes because a local marker can rebind to its newly mounted scope.
        std::vector<std::shared_ptr<AcrylicScene>> current;
        for (auto const &entry : scenes) if (auto scene = entry.lock()) current.push_back(scene);
        for (auto const &scene : current)
            if (auto root = scene->root.get(); !scene->window.get() && root && root.IsLoaded()) scene->commitPresentation();
    }

    std::shared_ptr<AcrylicScene> acrylicScene(Element const &source, Element const &target) {
        if (!source || !target.IsLoaded()) return {};
        auto xamlRoot = target.XamlRoot();
        if (!xamlRoot) return {};
        auto coordinates = xamlRoot.Content().try_as<Element>();
        if (!coordinates) return {};
        Element window{nullptr};
        Element content{nullptr};
        for (auto const &entry : windows)
            if (entry.root.get() == coordinates) { content = entry.content.get(); break; }
        Element localScope{nullptr};
        for (auto const &entry : insets) if (auto bar = entry.bar.get()) {
            // An embedded scrolling pane owns the scroll edges of its own bars.
            if (descendant(source, bar) && descendant(target, bar)
                && (!localScope || descendant(bar, localScope))) localScope = bar;
        }
        if (!localScope && content && descendant(source, content)) {
            for (auto const &entry : insets) if (auto owner = entry.owner.get()) {
                // A scrolling card owns the geometry of its moving bars.
                if (descendant(source, owner) && descendant(target, owner) && insideScroller(owner, content)
                    && (!localScope || descendant(localScope, owner))) localScope = owner;
            }
        }
        if (localScope) {
            content = coordinates = localScope;
        } else if (!content || !descendant(source, content)) {
            // Popovers and sheets have their own viewport geometry.
            content = source;
            for (auto at = xaml::Media::VisualTreeHelper::GetParent(source); at && at != coordinates;
                 at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                if (auto parent = at.try_as<Element>()) {
                    if (auto presenter = parent.try_as<controls::FlyoutPresenter>()) {
                        // The presenter owns the material behind the entire card.
                        if (auto card = presenter.Content().try_as<Element>(); card && descendant(source, card))
                            content = card;
                        break;
                    }
                    const auto tag = winrt::unbox_value_or<winrt::hstring>(parent.Tag(), L"");
                    if (tag == L"sheets" || tag == L"overlay") break;
                    content = parent;
                }
            }
            coordinates = content;
        } else {
            window = coordinates;
            for (auto const &column : acrylicWindowColumns(window))
                if (descendant(source, column)) {
                    content = column;
                    if (auto owner = acrylicColumnOwner(column, window)) coordinates = owner;
                    break;
                }
        }
        std::erase_if(scenes, [](auto const &scene) { return scene.expired(); });
        for (auto const &entry : scenes) if (auto scene = entry.lock()) {
            if (scene->content.get() == content && scene->root.get() == coordinates) {
                return scene;
            }
        }
        auto scene = std::make_shared<AcrylicScene>(content, coordinates);
        if (window) scene->window = winrt::make_weak(window);
        scenes.push_back(scene);
        scene->refresh();
        if (!window) scene->watch();
        return scene;
    }

    void commitAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, bool afterLayout) {
        scene->commitPresentation(afterLayout);
    }

    Element acrylicSceneRoot(std::shared_ptr<AcrylicScene> const &scene) { return scene->root.get(); }
    bool acrylicSceneIsWindow(std::shared_ptr<AcrylicScene> const &scene) {
        return scene && scene->window.get();
    }
    Rect acrylicSceneBounds(std::shared_ptr<AcrylicScene> const &scene) {
        if (!scene) return {};
        auto root = scene->root.get(), content = scene->content.get();
        if (!root || !content) return {};
        auto size = root.ActualSize();
        if (!acrylicSceneIsWindow(scene)) return {0, 0, size.x, size.y};
        if (!descendant(content, root)) return {};
        auto window = scene->window.get();
        const auto columns = acrylicWindowColumns(window);
        // A detached/retired scene can outlive a two/three-column switch via
        // marker observers. It must not keep its old toolbar crop alive.
        if (std::find(columns.begin(), columns.end(), content) == columns.end()) return {};
        // The native slot applies its own animated transform and clip to the toolbar effect.
        return {0, 0, size.x, size.y};
    }
    bool acrylicSceneContains(std::shared_ptr<AcrylicScene> const &scene, Element const &element) {
        return scene && element && descendant(element, scene->content.get());
    }
    std::vector<Element> acrylicMarkersForBar(Element const &target) {
        std::vector<Element> markers;
        for (auto const &entry : insets) {
            auto bar = entry.bar.get(), marker = entry.material.get();
            if (bar && marker && marker.IsLoaded() && marker.XamlRoot() == target.XamlRoot()
                && descendant(target, bar)) markers.push_back(marker);
        }
        return markers;
    }
    namespace {
        std::vector<AcrylicBand> scrollBands(Element const &source, Element const &root,
                                             Rect const &bounds, AcrylicEdge edge, bool allowsFixed = true,
                                             bool insetBar = false, bool spansViewport = false) {
            if (bounds.Width <= 0 || bounds.Height <= 0) return {};
            if (edge == AcrylicEdge::fixed) return {{bounds}};
            const bool top = edge == AcrylicEdge::top;
            bool owned = false;
            std::vector<AcrylicBand> result;
            for (auto const &entry : scrollers) {
                auto scroller = entry.element.get();
                if (!scroller || !descendant(scroller, source) || insideScroller(scroller, source)) continue;
                // A hosted list/editor owns the whole image, including its gutter.
                // Its template scroller supplies offsets but must not paint another copy.
                bool inner = false;
                for (auto at = xaml::Media::VisualTreeHelper::GetParent(scroller); at && at != source;
                     at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                    auto parent = at.try_as<Element>();
                    if (!parent || winrt::unbox_value_or<winrt::hstring>(parent.Tag(), L"") != L"acrylicViewport") continue;
                    auto direct = xaml::Media::VisualTreeHelper::GetParent(scroller);
                    inner = xaml::Media::VisualTreeHelper::GetParent(direct) != at;
                    break;
                }
                if (inner) continue;
                if (auto native = scroller.try_as<controls::ScrollView>()) {
                    if (native.VerticalScrollMode() == controls::ScrollingScrollMode::Disabled) continue;
                } else if (auto native = scroller.try_as<controls::ScrollViewer>()) {
                    if (native.VerticalScrollMode() == controls::ScrollMode::Disabled) continue;
                }
                // Scroll views in the controls (for example, toolbar tabs) do
                // not supply the edge effect for the page behind those controls.
                if (std::any_of(insets.begin(), insets.end(), [&](auto const &inset) {
                    auto bar = inset.bar.get();
                    return inset.owner.get() && bar && !descendant(source, bar) && descendant(scroller, bar);
                })) continue;
                auto viewport = acrylicVisibleBounds(scroller, root);
                if (viewport.Height <= 0 || (!spansViewport && viewport.Width <= 0)) continue;
                auto size = scroller.ActualSize();
                const float inset = static_cast<float>(top ? entry.insets.Top : entry.insets.Bottom);
                const float depth = std::clamp(inset, 0.0f, size.y);
                auto transform = scroller.TransformToVisual(root);
                auto edgePoint = transform.TransformPoint({0, top ? depth : size.y - depth});
                const auto end = viewport.Y + viewport.Height;
                const float boundary = std::clamp(edgePoint.Y, viewport.Y, end);
                auto strip = top ? Rect{viewport.X, viewport.Y, viewport.Width, boundary - viewport.Y}
                                 : Rect{viewport.X, boundary, viewport.Width, end - boundary};
                // The safe geometry and native inset writes commit separately.
                // The viewport itself still identifies a bar flush to its edge.
                if (insetBar || spansViewport) {
                    // The marker already gives the reserved bar rectangle.
                    // Its viewport can extend above several nested bars before
                    // the accumulated scrollbar insets have reached WinUI.
                    strip = viewport;
                } else if (depth <= edgeTolerance) {
                    const auto viewportEdge = top ? viewport.Y : end;
                    if (viewportEdge < bounds.Y - edgeTolerance
                        || viewportEdge > bounds.Y + bounds.Height + edgeTolerance) continue;
                    strip = viewport;
                }
                auto rect = intersect(bounds, strip);
                if (!spansViewport && rect.Width <= edgeTolerance) continue;
                if (rect.Height <= edgeTolerance) {
                    if (depth <= edgeTolerance && rect.Width > edgeTolerance) owned = true;
                    continue;
                }
                if (rect.Width > edgeTolerance) owned = true;
                // The blur is a live backdrop for the edge area. It must stay
                // present at the resting edge too. Toggling this bit while
                // scrolling races the native offset and leaves a transparent
                // frame during pane transitions.
                result.push_back({rect, true, scroller, spansViewport, edge});
            }
            if (!owned && allowsFixed) result.push_back({bounds});
            return result;
        }
    }
    AcrylicChromeMode acrylicTitleBarMode(Element const &titleBar) {
        auto value = titleBar.Resources().TryLookup(winrt::box_value(L"swiftomniuiTitleBarMaterial"));
        return static_cast<AcrylicChromeMode>(winrt::unbox_value_or<int32_t>(
            value, static_cast<int32_t>(AcrylicChromeMode::automatic)));
    }
    void setAcrylicTitleBarMode(Element const &titleBar, AcrylicChromeMode mode) {
        if (acrylicTitleBarMode(titleBar) == mode) return;
        titleBar.Resources().Insert(winrt::box_value(L"swiftomniuiTitleBarMaterial"),
            winrt::box_value(static_cast<int32_t>(mode)));
        queueMaterialCommit(titleBar);
    }
    std::vector<AcrylicBand> acrylicChromeRegions(std::shared_ptr<AcrylicScene> const &scene, Rect const &bounds,
                                                  AcrylicChromeMode mode) {
        if (mode == AcrylicChromeMode::hidden) return {};
        auto root = scene->root.get();
        if (!root) return {};
        // A title-bar material belongs to the whole native column. The
        // caller may already have split the window-wide bar into a column
        // slice, so checking against the window width would disable this
        // during sidebar transitions.
        const bool fullWidth = mode != AcrylicChromeMode::safeBar;
        auto bands = scrollBands(scene->content.get(), root, bounds,
            AcrylicEdge::top, mode != AcrylicChromeMode::automatic, mode == AcrylicChromeMode::safeBar, fullWidth);
        if (mode == AcrylicChromeMode::visible) {
            if (bands.empty()) return {{bounds}};
            for (auto &band : bands) band.active = true;
        }
        return bands;
    }
    std::vector<AcrylicBand> acrylicColumnInsets(std::shared_ptr<AcrylicScene> const &scene) {
        std::vector<AcrylicBand> result;
        auto root = scene->root.get(), column = scene->content.get();
        if (!root || !column) return result;
        for (auto const &inset : insets) {
            auto owner = inset.owner.get(), bar = inset.bar.get();
            if (!inset.localMaterial || inset.edge == AcrylicEdge::fixed || !owner || !bar
                || (!descendant(owner, column) && !descendant(column, owner))
                || !descendant(bar, owner) || insideScroller(owner, column)) continue;
            // The controls already have their final layout even when the optional
            // background marker hasn't been arranged. Include its padding when available.
            auto strip = acrylicVisibleBounds(bar, root);
            if (strip.Width <= 0 || strip.Height <= 0) continue;
            auto lane = acrylicVisibleBounds(owner, root);
            strip.X = lane.X;
            strip.Width = lane.Width;
            if (auto marker = inset.material.get(); marker && marker.IsLoaded()) {
                auto bounds = acrylicVisibleBounds(marker, root);
                if (bounds.Width > 0 && bounds.Height > 0) {
                    const float end = std::max(strip.Y + strip.Height, bounds.Y + bounds.Height);
                    strip.Y = std::min(strip.Y, bounds.Y);
                    strip.Height = end - strip.Y;
                }
            }
            for (auto band : scrollBands(owner, root, strip, inset.edge, false, true)) {
                // Only submit to the shared viewport. Independent backgrounds are
                // drawn locally, in their own stacking order.
                if (!band.viewport || !descendant(band.viewport, column)) continue;
                auto parent = xaml::Media::VisualTreeHelper::GetParent(band.viewport);
                if (!parent) continue;
                auto host = xaml::Media::VisualTreeHelper::GetParent(parent).try_as<Element>();
                if (host && winrt::unbox_value_or<winrt::hstring>(host.Tag(), L"") == L"acrylicViewport")
                    result.push_back(band);
            }
        }
        return result;
    }
    std::vector<AcrylicBand> acrylicLocalRegions(Element const &marker, Rect const &bounds) {
        for (auto const &entry : insets) if (entry.material.get() == marker) {
            auto owner = entry.owner.get();
            if (!owner) return {};
            // Both the viewport and the marker move with the inset owner.
            // Calculate the mask there, even when that subtree is sliding into the window.
            auto transform = marker.TransformToVisual(owner);
            auto inverse = transform.Inverse();
            if (!inverse) return {};
            auto bands = scrollBands(owner, owner, transform.TransformBounds(bounds), entry.edge, true, true);
            for (auto &band : bands) band.rect = inverse.TransformBounds(band.rect);
            return bands;
        }
        return {};
    }

    std::vector<Rect> acrylicMaterialRegions(std::vector<AcrylicBand> const &bands) {
        std::vector<float> edges;
        std::vector<Rect> active;
        for (auto const &band : bands) {
            const auto &rect = band.rect;
            if (rect.Width <= 0 || rect.Height <= 0) continue;
            edges.push_back(rect.X);
            edges.push_back(rect.X + rect.Width);
            if (band.active) active.push_back(rect);
        }
        std::sort(edges.begin(), edges.end());
        edges.erase(std::unique(edges.begin(), edges.end()), edges.end());
        std::sort(active.begin(), active.end(), [](Rect const &a, Rect const &b) { return a.Y < b.Y; });

        // Every horizontal boundary stays in place, including those of
        // transparent lanes. Within a lane, union only the covered intervals
        // so a narrower bar can join a wider one without widening its mask.
        std::vector<Rect> regions;
        for (size_t i = 1; i < edges.size(); ++i) {
            const auto left = edges[i - 1], right = edges[i];
            const auto start = regions.size();
            for (auto const &rect : active) {
                if (rect.X > left || rect.X + rect.Width < right) continue;
                if (regions.size() > start && rect.Y <= regions.back().Y + regions.back().Height) {
                    auto &last = regions.back();
                    last.Height = std::max(last.Y + last.Height, rect.Y + rect.Height) - last.Y;
                } else {
                    regions.push_back({left, rect.Y, right - left, rect.Height});
                }
            }
        }
        return regions;
    }
    void observeAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, std::function<bool()> observer) {
        scene->observers.push_back(std::move(observer));
    }
    void registerAcrylicScroller(Element const &scroller) {
        std::erase_if(scrollers, [](auto const &entry) { return !entry.element.get(); });
        for (auto const &entry : scrollers) if (entry.element.get() == scroller) return;
        scrollers.push_back({winrt::make_weak(scroller)});
        observeNativeScroller(scrollers.back(), scroller);
        updateAcrylicScroller(scroller);
    }
    void updateAcrylicScroller(Element const &scroller, std::optional<xaml::Thickness> region) {
        auto found = std::find_if(scrollers.begin(), scrollers.end(),
            [&](auto const &entry) { return entry.element.get() == scroller; });
        if (found == scrollers.end()) return;
        const auto insets = region.value_or(found->insets);
        double offset = 0, range = 0;
        if (auto scroll = scroller.try_as<controls::ScrollView>()) {
            offset = scroll.VerticalOffset(); range = scroll.ScrollableHeight();
        } else if (auto viewer = scroller.try_as<controls::ScrollViewer>()) {
            offset = viewer.VerticalOffset(); range = viewer.ScrollableHeight();
        }
        const bool top = offset > 0.5, bottom = range - offset > 0.5;
        if (found->insets == insets && found->underTop == top && found->underBottom == bottom) return;
        found->underTop = top;
        found->underBottom = bottom;
        found->insets = insets;
        // Crossing an edge changes the tint and separator. The blur stays attached.
        queueMaterialCommit(scroller);
    }

    void acrylicStructureChanged(Element const &element) noexcept {
        try {
            for (auto const &entry : scenes) if (auto scene = entry.lock()) {
                auto source = scene->content.get();
                if (!source || !descendant(element, source) || insideScroller(element, source)) continue;
                // Discover new viewports after a structural change outside a scrolling document.
                scene->revision = std::numeric_limits<uint64_t>::max();
                queueMaterialCommit(element);
            }
        } catch (...) { report("invalidating an acrylic content scene"); }
    }

    void setAcrylicContentRoot(Element const &root, Element const &content) {
        std::erase_if(windows, [](auto const &entry) { return !entry.root.get(); });
        for (auto &entry : windows) if (entry.root.get() == root) {
            if (entry.content.get() == content) return;
            entry.content = content ? winrt::make_weak(content) : winrt::weak_ref<Element>{};
            ++generation;
            queueMaterialCommit(root);
            return;
        }
        windows.push_back({winrt::make_weak(root), content ? winrt::make_weak(content) : winrt::weak_ref<Element>{}});
        ++generation;
        queueMaterialCommit(root);
    }
}

extern "C" void swiftomniui_winui_material_columns(
    SwiftOmniUIObjectRef owner, SwiftOmniUIObjectRef const *columns, int32_t count
) {
    using namespace swiftomniui;
    try {
        auto element = as<xaml::FrameworkElement>(owner);
        std::erase_if(columnGroups, [](auto const &entry) { return !entry.owner.get(); });
        auto found = std::find_if(columnGroups.begin(), columnGroups.end(), [&](auto const &entry) {
            return entry.owner.get() == element;
        });
        if (count == 0) {
            if (found != columnGroups.end()) { columnGroups.erase(found); ++generation; queueMaterialCommit(element); }
            return;
        }
        if (found != columnGroups.end() && found->pages.size() == static_cast<size_t>(count)) {
            bool same = true;
            for (int32_t i = 0; i < count; ++i) if (found->pages[i].get() != as<xaml::FrameworkElement>(columns[i])) same = false;
            if (same) return;
        }
        Columns next{winrt::make_weak(element), {}};
        for (int32_t i = 0; i < count; ++i) next.pages.push_back(winrt::make_weak(as<xaml::FrameworkElement>(columns[i])));
        if (found == columnGroups.end()) columnGroups.push_back(std::move(next));
        else *found = std::move(next);
        ++generation;
        // A retained page can change native slots while its scroll offset
        // stays put. Resolve its material after the reparenting settles.
        queueMaterialCommit(element);
    } catch (...) { report("registering navigation material columns"); }
}

extern "C" void swiftomniui_winui_safe_area_register(
    SwiftOmniUIObjectRef owner, SwiftOmniUIObjectRef bar, SwiftOmniUIObjectRef material, int32_t verticalEdge, bool localMaterial
) {
    using namespace swiftomniui;
    try {
        auto element = as<xaml::FrameworkElement>(owner);
        auto controls = bar ? as<xaml::FrameworkElement>(bar) : xaml::FrameworkElement{nullptr};
        auto surface = material ? as<xaml::FrameworkElement>(material) : xaml::FrameworkElement{nullptr};
        const auto edge = static_cast<AcrylicEdge>(verticalEdge);
        std::erase_if(insets, [](auto const &entry) { return !entry.owner.get(); });
        for (auto &entry : insets) if (entry.owner.get() == element) {
            if (entry.bar.get() == controls && entry.material.get() == surface && entry.edge == edge && entry.localMaterial == localMaterial) return;
            if (!bar) {
                entry.owner = {};
            } else {
                entry.bar = winrt::make_weak(controls);
                entry.material = surface ? winrt::make_weak(surface) : winrt::weak_ref<xaml::FrameworkElement>{};
                entry.edge = edge;
                entry.localMaterial = localMaterial;
            }
            ++generation;
            queueMaterialCommit(element);
            return;
        }
        if (bar) {
            insets.push_back({winrt::make_weak(element), winrt::make_weak(controls),
                surface ? winrt::make_weak(surface) : winrt::weak_ref<xaml::FrameworkElement>{}, edge, localMaterial});
            ++generation;
            queueMaterialCommit(element);
        }
    } catch (...) { report("registering a safe bar's scroll edge"); }
}

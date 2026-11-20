// SPDX-License-Identifier: Apache-2.0
#include "AcrylicScene.h"
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.UI.h>
#include <algorithm>
#include <limits>
#include <cmath>
#include <unordered_set>
#include <utility>
#include <vector>

namespace swiftomniui {
    namespace composition = winrt::Microsoft::UI::Composition;
    using Rect = winrt::Windows::Foundation::Rect;
    using Element = xaml::FrameworkElement;

    namespace {
        struct Inset {
            winrt::weak_ref<Element> owner, bar, material;
            AcrylicEdge edge = AcrylicEdge::fixed;
        };
        std::vector<Inset> insets;
        struct WindowRoot { winrt::weak_ref<Element> root, content; xaml::Media::SystemBackdrop backdrop{nullptr}; };
        std::vector<WindowRoot> windows;
        struct Columns {
            winrt::weak_ref<Element> owner;
            std::vector<winrt::weak_ref<Element>> pages;
        };
        std::vector<Columns> columnGroups;
        struct Scroller {
            winrt::weak_ref<Element> element;
            xaml::Thickness insets{};
            bool top = false, bottom = false;
            winrt::event_token viewChanged{};
        };
        std::vector<Scroller> scrollers;
        std::vector<std::weak_ptr<AcrylicScene>> scenes;
        std::unordered_set<void *> localPresentations;
        uint64_t generation = 0;
        bool materialDirty = true;
        bool materialCommitPending = false;
        constexpr float edgeTolerance = 0.5f;

        constexpr bool showsScrollEdge(double distance, bool wasVisible) {
            return distance > (wasVisible ? edgeTolerance : 2 * edgeTolerance);
        }

        // A document can have zero resting range and still overpan.
        static_assert(showsScrollEdge(12, false) && !showsScrollEdge(-12, false));
        static_assert(showsScrollEdge(0.75, true) && !showsScrollEdge(0.75, false));
        static_assert(!showsScrollEdge(0, true));

        void *identity(IInspectable const &value) { return value ? value.as<::IUnknown>().get() : nullptr; }
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
            if (materialCommitPending) return;
            if (auto queue = element.DispatcherQueue()) {
                materialCommitPending = queue.TryEnqueue(winrt::Microsoft::UI::Dispatching::DispatcherQueuePriority::Low, [] {
                    materialCommitPending = false;
                    swiftomniui_winui_material_present_if_needed();
                });
            }
        }

        double verticalOffset(Element const &element) {
            if (auto scroller = element.try_as<controls::ScrollView>()) return scroller.VerticalOffset();
            if (auto viewer = element.try_as<controls::ScrollViewer>()) return viewer.VerticalOffset();
            return 0;
        }

        double scrollableHeight(Element const &element) {
            if (auto scroller = element.try_as<controls::ScrollView>()) return scroller.ScrollableHeight();
            if (auto viewer = element.try_as<controls::ScrollViewer>()) return viewer.ScrollableHeight();
            return 0;
        }

        void observeNativeScroller(Scroller &state, Element const &element) {
            auto weak = winrt::make_weak(element);
            if (auto scroller = element.try_as<controls::ScrollView>()) {
                state.viewChanged = scroller.ViewChanged([weak](auto const &, auto const &) {
                    if (auto element = weak.get()) updateAcrylicScroller(element);
                });
            } else if (auto viewer = element.try_as<controls::ScrollViewer>()) {
                state.viewChanged = viewer.ViewChanged([weak](auto const &, auto const &) {
                    if (auto element = weak.get()) updateAcrylicScroller(element);
                });
            }
        }

        bool discoverNativeScrollers(xaml::DependencyObject const &node) {
            if (!node) return false;
            bool found = false;
            if (auto element = node.try_as<Element>()) {
                if (element.try_as<controls::ScrollView>() || element.try_as<controls::ScrollViewer>()) {
                    registerAcrylicScroller(element);
                    found = true;
                }
            }
            for (int32_t index = 0, count = xaml::Media::VisualTreeHelper::GetChildrenCount(node);
                 index < count; ++index)
                found = discoverNativeScrollers(xaml::Media::VisualTreeHelper::GetChild(node, index)) || found;
            return found;
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

    AcrylicPartGeometry acrylicPartGeometry(Element const &element, Element const &root) {
        if (!element || !root || !element.IsLoaded() || element.ActualWidth() <= 0 || element.ActualHeight() <= 0) return {};
        auto size = element.ActualSize();
        auto transform = element.TransformToVisual(root);
        auto bounds = transform.TransformBounds({0, 0, size.x, size.y});
        double opacity = 1;
        for (xaml::DependencyObject at = element; at; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            if (at != root) {
                if (auto ui = at.try_as<xaml::UIElement>()) opacity *= ui.Opacity();
            }
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
                auto slot = (pane ? split.Pane() : split.Content()).try_as<Element>();
                if (slot) {
                    auto room = slot.ActualSize();
                    bounds = intersect(bounds, slot.TransformToVisual(root).TransformBounds({0, 0, room.x, room.y}));
                }
            }
            if (parent == root) break;
        }
        auto room = root.ActualSize();
        auto visible = intersect(bounds, {0, 0, room.x, room.y});
        Rect localClip{};
        if (visible.Width > 0 && visible.Height > 0) {
            auto inverse = transform.Inverse();
            if (inverse) localClip = inverse.TransformBounds(visible);
        }
        auto origin = transform.TransformPoint({0, 0});
        auto x = transform.TransformPoint({1, 0});
        auto y = transform.TransformPoint({0, 1});
        winrt::Windows::Foundation::Numerics::float4x4 matrix{
            x.X - origin.X, x.Y - origin.Y, 0, 0,
            y.X - origin.X, y.Y - origin.Y, 0, 0,
            0, 0, 1, 0, origin.X, origin.Y, 0, 1};
        return {visible, localClip, matrix, static_cast<float>(std::clamp(opacity, 0.0, 1.0))};
    }

    float acrylicPresentationOpacity(Element const &element, Element const &root) {
        double opacity = 1;
        for (xaml::DependencyObject at = element; at && at != root; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            if (auto parent = at.try_as<xaml::UIElement>()) opacity *= parent.Opacity();
        }
        return static_cast<float>(std::clamp(opacity, 0.0, 1.0));
    }
    bool acrylicUsesLocalPresentation(Element const &element, Element const &root) {
        // A horizontal slide changes only the lane's position, which the
        // window scene already reads in presentation coordinates. Opacity
        // and effects that change the drawing still belong to the subtree.
        const bool hasLocalSet = !localPresentations.empty();
        for (xaml::DependencyObject at = element; at && at != root; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            auto parent = at.try_as<Element>();
            if (!parent) continue;
            if (parent.Opacity() != 1 || parent.Projection()) return true;
            if (hasLocalSet && localPresentations.contains(identity(parent))) return true;
            if (auto transform = parent.RenderTransform()) {
                if (auto composite = transform.try_as<xaml::Media::CompositeTransform>()) {
                    if (composite.TranslateY() != 0 || composite.Rotation() != 0
                        || composite.ScaleX() != 1 || composite.ScaleY() != 1
                        || composite.SkewX() != 0 || composite.SkewY() != 0) return true;
                } else {
                    auto origin = transform.TransformPoint({0, 0});
                    auto x = transform.TransformPoint({1, 0});
                    auto y = transform.TransformPoint({0, 1});
                    if (origin.Y != 0 || x.X != origin.X + 1 || x.Y != 0 || y.X != origin.X || y.Y != 1) return true;
                }
            }
        }
        return false;
    }

    void setAcrylicLocalPresentation(IInspectable const &element, bool active) noexcept {
        try {
            auto key = identity(element);
            if (!key) return;
            const bool changed = active ? localPresentations.insert(key).second : (localPresentations.erase(key) > 0);
            if (changed) materialDirty = true;
        } catch (...) {}
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
    winrt::Windows::Foundation::Numerics::float4x4 acrylicPresentationMatrix(Element const &element, Element const &root) {
        auto transform = element.TransformToVisual(root);
        auto origin = transform.TransformPoint({0, 0});
        auto x = transform.TransformPoint({1, 0});
        auto y = transform.TransformPoint({0, 1});
        return {x.X - origin.X, x.Y - origin.Y, 0, 0,
                y.X - origin.X, y.Y - origin.Y, 0, 0,
                0, 0, 1, 0, origin.X, origin.Y, 0, 1};
    }
    Rect acrylicLocalClip(Element const &element, Element const &root, Rect const &visible) {
        if (visible.Width <= 0 || visible.Height <= 0) return {};
        auto inverse = element.TransformToVisual(root).Inverse();
        return inverse ? inverse.TransformBounds(visible) : Rect{};
    }

    struct AcrylicScene : std::enable_shared_from_this<AcrylicScene> {
        winrt::weak_ref<Element> content, root, window;
        composition::ContainerVisual visual{nullptr};
        uint64_t revision = std::numeric_limits<uint64_t>::max();
        bool nativeScrollersDiscovered = false;
        bool committing = false;
        xaml::FrameworkElement::LayoutUpdated_revoker layoutCommitted;
        std::vector<std::function<bool()>> observers;
        struct Part {
            winrt::weak_ref<Element> element;
            bool background = false;
            composition::CompositionVisualSurface capture{nullptr};
            composition::CompositionSurfaceBrush brush{nullptr};
            composition::SpriteVisual sprite{nullptr};
        };
        std::vector<Part> parts;

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
                    self->commitPresentation();
                });
        }

        void commitPresentation() {
            if (committing) return;
            committing = true;
            try {
                refresh();
                auto callbacks = std::move(observers);
                observers.clear();
                for (auto &callback : callbacks) if (callback()) observers.push_back(std::move(callback));
            } catch (...) { report("committing a material scope's presentation"); }
            committing = false;
        }

        void rebuild(Element const &source, composition::Compositor const &compositor) {
            (void)discoverNativeScrollers(source);
            std::unordered_set<void *> excluded, split;
            auto path = [&](xaml::DependencyObject const &element) {
                if (!element || !descendant(element, source)) return;
                for (auto parent = xaml::Media::VisualTreeHelper::GetParent(element); parent;
                     parent = xaml::Media::VisualTreeHelper::GetParent(parent)) {
                    split.insert(identity(parent));
                    if (parent == source) break;
                }
            };
            std::erase_if(insets, [](auto const &entry) { return !entry.owner.get(); });
            for (auto const &entry : insets) {
                if (auto owner = entry.owner.get(); !owner || !descendant(owner, source) || insideScroller(owner, source)) continue;
                for (auto const &element : {entry.bar.get(), entry.material.get()}) {
                    if (!element || !descendant(element, source)) continue;
                    excluded.insert(identity(element));
                    path(element);
                }
            }
            std::erase_if(scrollers, [](auto const &entry) { return !entry.element.get(); });
            // Split only ancestors of scrollers, not their documents/rows. This
            // retains the real viewport extending outside a safe layout slot.
            for (auto const &entry : scrollers) if (auto element = entry.element.get()) {
                if (!descendant(element, source)) continue;
                bool nested = false;
                for (auto at = xaml::Media::VisualTreeHelper::GetParent(element); at;
                     at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                    if (at.try_as<controls::ScrollView>() || at.try_as<controls::ScrollViewer>()) { nested = true; break; }
                    if (at == source) break;
                }
                // An outer capture already follows every inner document's
                // motion on the compositor. Splitting at nested scrollers
                // would instead freeze their parent scroll translation.
                if (!nested) path(element);
            }

            struct Entry { Element element; bool background; };
            std::vector<Entry> frontier;
            auto visit = [&](auto &&visit, xaml::DependencyObject const &node) -> void {
                if (excluded.contains(identity(node))) return;
                auto element = node.try_as<Element>();
                if (!split.contains(identity(node)) && element) { frontier.push_back({element, false}); return; }
                // Splitting a Panel/Control to omit fixed chrome must not also
                // discard that ancestor's own fill. Capture its solid background
                // separately, below its children, without copying those children.
                if (element) frontier.push_back({element, true});
                std::vector<Element> children;
                const auto count = xaml::Media::VisualTreeHelper::GetChildrenCount(node);
                for (int32_t index = 0; index < count; ++index) {
                    auto child = xaml::Media::VisualTreeHelper::GetChild(node, index).try_as<Element>();
                    if (child) children.push_back(child);
                }
                std::stable_sort(children.begin(), children.end(), [](auto const &a, auto const &b) {
                    return controls::Canvas::GetZIndex(a) < controls::Canvas::GetZIndex(b);
                });
                for (auto const &child : children) visit(visit, child);
            };
            visit(visit, source);

            // Retained frontier elements retain their live surfaces. Never
            // recreate a capture just because another bar is mounted/removed.
            auto previous = parts;
            std::vector<Part> next;
            next.reserve(frontier.size());
            for (auto const &[element, background] : frontier) {
                auto found = std::find_if(previous.begin(), previous.end(), [&](auto const &part) {
                    return part.element.get() == element && part.background == background;
                });
                if (found != previous.end()) {
                    next.push_back(std::move(*found));
                    previous.erase(found);
                } else {
                    Part part;
                    part.element = winrt::make_weak(element);
                    part.background = background;
                    part.sprite = compositor.CreateSpriteVisual();
                    if (background) part.sprite.Brush(compositor.CreateColorBrush());
                    else {
                        part.capture = compositor.CreateVisualSurface();
                        part.brush = compositor.CreateSurfaceBrush(part.capture);
                        part.brush.Stretch(composition::CompositionStretch::None);
                        part.brush.HorizontalAlignmentRatio(0);
                        part.brush.VerticalAlignmentRatio(0);
                        part.sprite.Brush(part.brush);
                    }
                    // Root and ancestor opacity are restored together at
                    // the owning presentation commit, including removal frames.
                    next.push_back(std::move(part));
                }
            }
            // Build before changing the shared scene. A failed optional GPU
            // allocation must not empty the source used by every other strip.
            visual.Children().RemoveAll();
            for (auto const &part : next) visual.Children().InsertAtTop(part.sprite);
            parts = std::move(next);
            for (auto &part : previous) if (part.capture) part.capture.SourceVisual(nullptr);
            revision = generation;
        }

        void refresh() {
            auto source = content.get(), coordinates = root.get();
            if (!source || !coordinates) return;
            if (!nativeScrollersDiscovered)
                nativeScrollersDiscovered = discoverNativeScrollers(source);
            auto compositor = xaml::Hosting::ElementCompositionPreview::GetElementVisual(coordinates).Compositor();
            if (!visual) visual = compositor.CreateContainerVisual();
            if (revision != generation) rebuild(source, compositor);
            if (visual.Size() != coordinates.ActualSize()) visual.Size(coordinates.ActualSize());
            for (auto &part : parts) {
                auto element = part.element.get();
                if (!element || !element.IsLoaded() || !descendant(element, source)
                    || element.Visibility() != xaml::Visibility::Visible
                    || element.ActualWidth() <= 0 || element.ActualHeight() <= 0) {
                    part.sprite.IsVisible(false);
                    if (part.capture) part.capture.SourceVisual(nullptr);
                    continue;
                }
                auto size = element.ActualSize();
                const auto geometry = acrylicPartGeometry(element, coordinates);
                const auto &clipped = geometry.localClip;
                const auto opacity = geometry.opacity;
                const bool shown = clipped.Width > 0 && clipped.Height > 0 && opacity > 0;
                if (part.sprite.Opacity() != opacity) part.sprite.Opacity(opacity);
                if (part.sprite.IsVisible() != shown) part.sprite.IsVisible(shown);
                if (part.background) {
                    xaml::Media::Brush background{nullptr};
                    if (auto panel = element.try_as<controls::Panel>()) background = panel.Background();
                    else if (auto border = element.try_as<controls::Border>()) background = border.Background();
                    else if (auto control = element.try_as<controls::Control>()) background = control.Background();
                    winrt::Windows::UI::Color color{};
                    if (auto fill = background.try_as<xaml::Media::SolidColorBrush>()) {
                        color = fill.Color();
                        color.A = static_cast<uint8_t>(color.A * std::clamp(fill.Opacity(), 0.0, 1.0));
                    }
                    auto brush = part.sprite.Brush().as<composition::CompositionColorBrush>();
                    if (brush.Color() != color) brush.Color(color);
                } else {
                    auto live = xaml::Hosting::ElementCompositionPreview::GetElementVisual(element);
                    if (part.capture.SourceVisual() != live) part.capture.SourceVisual(live);
                    if (part.capture.SourceSize() != size) part.capture.SourceSize(size);
                }
                const auto &matrix = geometry.matrix;
                if (part.sprite.TransformMatrix() != matrix) part.sprite.TransformMatrix(matrix);
                if (part.sprite.Size() != size) part.sprite.Size(size);
                auto clip = part.sprite.Clip().try_as<composition::InsetClip>();
                if (!clip) { clip = compositor.CreateInsetClip(); part.sprite.Clip(clip); }
                const float left = std::max(0.0f, clipped.X);
                const float top = std::max(0.0f, clipped.Y);
                const float right = std::max(0.0f, size.x - clipped.X - clipped.Width);
                const float bottom = std::max(0.0f, size.y - clipped.Y - clipped.Height);
                if (clip.LeftInset() != left) clip.LeftInset(left);
                if (clip.TopInset() != top) clip.TopInset(top);
                if (clip.RightInset() != right) clip.RightInset(right);
                if (clip.BottomInset() != bottom) clip.BottomInset(bottom);
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
            if (auto root = scene->root.get(); root && root.IsLoaded()) scene->commitPresentation();
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
            // A bar may itself contain an independent scrolling pane (the Git
            // history panel). Its inner bars sample that pane, not the page
            // behind the outer bar. This also keeps the graph acyclic.
            if (descendant(source, bar) && descendant(target, bar)
                && (!localScope || descendant(bar, localScope))) localScope = bar;
        }
        if (!localScope && content && descendant(source, content)) {
            for (auto const &entry : insets) if (auto owner = entry.owner.get()) {
                // A scrolling card's own bars move with it. Keep those in a
                // card-local scene so the outer viewport can be captured whole.
                if (descendant(source, owner) && descendant(target, owner) && insideScroller(owner, content)
                    && (!localScope || descendant(localScope, owner))) localScope = owner;
            }
        }
        if (localScope) {
            content = coordinates = localScope;
        } else if (!content || !descendant(source, content)) {
            // Popovers/sheets retain their own sampling scope; a local bar
            // must never capture the material painting that same bar.
            content = source;
            for (auto at = xaml::Media::VisualTreeHelper::GetParent(source); at && at != coordinates;
                 at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                if (auto parent = at.try_as<Element>()) {
                    if (auto presenter = parent.try_as<controls::FlyoutPresenter>()) {
                        // The presenter already paints beneath the whole popover.
                        // Filter only its content, so the bar never resamples its acrylic.
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
        scene->watch();
        return scene;
    }

    Element acrylicSceneRoot(std::shared_ptr<AcrylicScene> const &scene) { return scene->root.get(); }
    composition::Visual acrylicSceneVisual(std::shared_ptr<AcrylicScene> const &scene) { return scene->visual; }
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
        // Capture in native slot coordinates, BEFORE its animated ancestors.
        // An offscreen opening frame must not freeze an empty window crop for
        // the rest of an independent system animation. Visibility and moving
        // clips apply once, when the native column presents the result.
        return {0, 0, size.x, size.y};
    }
    bool acrylicSceneContains(std::shared_ptr<AcrylicScene> const &scene, Element const &element) {
        return scene && element && descendant(element, scene->content.get());
    }
    xaml::Media::SystemBackdrop acrylicFoundationBackdrop(Element const &target) {
        auto root = target.XamlRoot();
        if (root) for (auto const &entry : windows)
            if (entry.root.get() == root.Content() && entry.backdrop) return entry.backdrop;
        // Independent popup XamlRoots use the same native material family.
        auto owner = root ? root.Content().try_as<Element>() : target;
        if (!owner) owner = target;
        auto key = winrt::box_value(L"safeBarMicaBackdrop");
        auto resource = owner.Resources().TryLookup(key).try_as<xaml::Media::SystemBackdrop>();
        if (!resource) {
            resource = xaml::Media::MicaBackdrop();
            owner.Resources().Insert(key, resource);
        }
        return resource;
    }
    xaml::Media::Brush acrylicFoundationFill(Element const &target) {
        auto xamlRoot = target.XamlRoot();
        if (xamlRoot) for (auto const &entry : windows)
            if (entry.root.get() == xamlRoot.Content())
                if (auto grid = entry.root.get().try_as<controls::Grid>()) return grid.Background();
        return nullptr;
    }
    void setAcrylicWindowBackdrop(Element const &root, xaml::Media::SystemBackdrop const &backdrop) {
        std::erase_if(windows, [](auto const &entry) { return !entry.root.get(); });
        for (auto &entry : windows) if (entry.root.get() == root) { entry.backdrop = backdrop; return; }
        windows.push_back({winrt::make_weak(root), {}, backdrop});
    }
    std::vector<Element> acrylicSceneBars(std::shared_ptr<AcrylicScene> const &scene) {
        std::vector<Element> result;
        if (!scene) return result;
        auto source = scene->content.get();
        if (!source) return result;
        for (auto const &entry : insets) {
            auto owner = entry.owner.get(), bar = entry.bar.get();
            if (!owner || !bar || !bar.IsLoaded() || !descendant(bar, source)
                || bar.Visibility() != xaml::Visibility::Visible
                || bar.ActualWidth() <= 0 || bar.ActualHeight() <= 0) continue;
            auto marker = entry.material.get();
            if (acrylicUsesLocalPresentation(marker ? marker : owner, scene->root.get())) continue;
            if (acrylicScene(owner, bar) == scene) result.push_back(bar);
        }
        return result;
    }
    namespace {
        std::vector<AcrylicBand> scrollBands(Element const &source, Element const &root,
                                             Rect const &bounds, AcrylicEdge edge, bool allowsFixed = true) {
            if (bounds.Width <= 0 || bounds.Height <= 0) return {};
            if (edge == AcrylicEdge::fixed) return {{bounds}};
            const bool top = edge == AcrylicEdge::top;
            bool owned = false;
            std::vector<AcrylicBand> result;
            for (auto const &entry : scrollers) {
                auto scroller = entry.element.get();
                if (!scroller || !descendant(scroller, source) || insideScroller(scroller, source)) continue;
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
                if (viewport.Width <= 0 || viewport.Height <= 0) continue;
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
                if (depth <= edgeTolerance) {
                    const auto viewportEdge = top ? viewport.Y : end;
                    if (viewportEdge < bounds.Y - edgeTolerance
                        || viewportEdge > bounds.Y + bounds.Height + edgeTolerance) continue;
                    strip = viewport;
                }
                auto rect = intersect(bounds, strip);
                if (rect.Width <= edgeTolerance) continue;
                if (rect.Height <= edgeTolerance) {
                    if (depth <= edgeTolerance) owned = true;
                    continue;
                }
                owned = true;
                result.push_back({rect, top ? entry.top : entry.bottom});
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
        auto bands = scrollBands(scene->content.get(), scene->root.get(), bounds,
            AcrylicEdge::top, mode != AcrylicChromeMode::automatic);
        if (mode == AcrylicChromeMode::visible) {
            if (bands.empty()) return {{bounds}};
            for (auto &band : bands) band.active = true;
        }
        return bands;
    }
    std::vector<AcrylicBand> acrylicLocalRegions(std::shared_ptr<AcrylicScene> const &scene,
                                                Element const &marker, Rect const &bounds) {
        auto root = scene->root.get();
        if (!root) return {};
        for (auto const &entry : insets) if (entry.material.get() == marker) {
            if (auto owner = entry.owner.get()) return scrollBands(owner, root, bounds, entry.edge);
        }
        return {};
    }
    std::vector<AcrylicBand> acrylicSceneRegions(std::shared_ptr<AcrylicScene> const &scene) {
        std::vector<AcrylicBand> result;
        if (!scene) return result;
        auto root = scene->root.get();
        if (!root) return result;
        for (auto const &entry : insets) {
            auto owner = entry.owner.get(), marker = entry.material.get();
            if (!owner || !marker || !marker.IsLoaded() || marker.Visibility() != xaml::Visibility::Visible
                || marker.ActualWidth() <= 0 || marker.ActualHeight() <= 0) continue;
            // Resolve actual ownership after native parenting has settled.
            // This includes trailing detail bars as well as nested sidebar bars.
            if (acrylicScene(owner, marker) != scene || acrylicUsesLocalPresentation(marker, root)) continue;
            auto bands = scrollBands(owner, root, acrylicVisibleBounds(marker, root), entry.edge);
            result.insert(result.end(), bands.begin(), bands.end());
        }
        return result;
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
        const auto reach = std::max(0.0, scrollableHeight(scroller));
        // WinUI reports the live overpan in VerticalOffset. In a short
        // document the resting range is zero, but the drag can still move
        // content beneath either bar before the viewport springs back.
        const auto offset = verticalOffset(scroller);
        // Keep subpixel motion near a resting edge from toggling material.
        const bool top = showsScrollEdge(offset, found->top);
        const bool bottom = showsScrollEdge(reach - offset, found->bottom);
        const auto insets = region.value_or(found->insets);
        if (found->top == top && found->bottom == bottom && found->insets == insets) return;
        found->top = top;
        found->bottom = bottom;
        found->insets = insets;
        // ViewChanged already follows every compositor scroll. Only crossing
        // an edge or changing insets needs geometry and brush work.
        queueMaterialCommit(scroller);
    }

    void acrylicStructureChanged(Element const &element) noexcept {
        try {
            for (auto const &entry : scenes) if (auto scene = entry.lock()) {
                auto source = scene->content.get();
                if (!source || !descendant(element, source) || insideScroller(element, source)) continue;
                // New outer viewports can change a capture boundary even
                // within an otherwise live branch. Lazy row mutations inside
                // a viewport returned above and never rebuild this frontier.
                scene->revision = std::numeric_limits<uint64_t>::max();
                materialDirty = true;
            }
        } catch (...) { report("invalidating an acrylic content scene"); }
    }

    void setAcrylicContentRoot(Element const &root, Element const &content) {
        std::erase_if(windows, [](auto const &entry) { return !entry.root.get(); });
        for (auto &entry : windows) if (entry.root.get() == root) {
            if (entry.content.get() == content) return;
            entry.content = content ? winrt::make_weak(content) : winrt::weak_ref<Element>{};
            ++generation;
            materialDirty = true;
            return;
        }
        windows.push_back({winrt::make_weak(root), content ? winrt::make_weak(content) : winrt::weak_ref<Element>{}});
        ++generation;
        materialDirty = true;
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
    SwiftOmniUIObjectRef owner, SwiftOmniUIObjectRef bar, SwiftOmniUIObjectRef material, int32_t verticalEdge
) {
    using namespace swiftomniui;
    try {
        auto element = as<xaml::FrameworkElement>(owner);
        auto controls = bar ? as<xaml::FrameworkElement>(bar) : xaml::FrameworkElement{nullptr};
        auto surface = material ? as<xaml::FrameworkElement>(material) : xaml::FrameworkElement{nullptr};
        const auto edge = static_cast<AcrylicEdge>(verticalEdge);
        std::erase_if(insets, [](auto const &entry) { return !entry.owner.get(); });
        for (auto &entry : insets) if (entry.owner.get() == element) {
            if (entry.bar.get() == controls && entry.material.get() == surface && entry.edge == edge) return;
            if (!bar) {
                entry.owner = {};
            } else {
                entry.bar = winrt::make_weak(controls);
                entry.material = surface ? winrt::make_weak(surface) : winrt::weak_ref<xaml::FrameworkElement>{};
                entry.edge = edge;
            }
            ++generation;
            markAcrylicMaterialDirty();
            return;
        }
        if (bar) {
            insets.push_back({winrt::make_weak(element), winrt::make_weak(controls),
                surface ? winrt::make_weak(surface) : winrt::weak_ref<xaml::FrameworkElement>{}, edge});
            ++generation;
            markAcrylicMaterialDirty();
        }
    } catch (...) { report("registering a safe bar's content-only sampling boundary"); }
}

extern "C" bool swiftomniui_winui_window_acrylic_samples(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef element) {
    using namespace swiftomniui;
    try {
        auto root = borrow<xaml::Window>(window).Content().as<xaml::FrameworkElement>();
        auto source = as<xaml::FrameworkElement>(element);
        for (auto const &entry : scenes) if (auto scene = entry.lock(); scene && (scene->window.get() == root || scene->root.get() == root)) {
            for (auto const &part : scene->parts)
                if (auto ancestor = part.element.get(); !part.background && ancestor && descendant(source, ancestor)) return true;
        }
        return false;
    } catch (...) { report("reading the acrylic content sampling boundary"); return false; }
}

extern "C" bool swiftomniui_winui_window_acrylic_captures_viewport(SwiftOmniUIObjectRef window, SwiftOmniUIObjectRef viewport) {
    using namespace swiftomniui;
    try {
        auto root = borrow<xaml::Window>(window).Content().as<Element>();
        auto element = as<Element>(viewport);
        // Read the retained scene, never create/refresh one while diagnosing
        // first-load readiness (that would hide the missing notification).
        for (auto const &entry : scenes) if (auto scene = entry.lock(); scene && (scene->window.get() == root || scene->root.get() == root)) {
            for (auto const &part : scene->parts) {
                if (part.background || part.element.get() != element || !part.capture || !part.sprite.IsVisible()) continue;
                auto size = part.capture.SourceSize();
                return element.IsLoaded() && part.capture.SourceVisual() && size.x > 0 && size.y > 0;
            }
        }
        return false;
    } catch (...) { report("reading the retained acrylic viewport capture"); return false; }
}

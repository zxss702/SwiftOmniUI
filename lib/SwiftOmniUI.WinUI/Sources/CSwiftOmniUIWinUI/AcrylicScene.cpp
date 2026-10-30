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
        };
        std::vector<Inset> insets;
        struct WindowRoot { winrt::weak_ref<Element> root, content; xaml::Media::SystemBackdrop backdrop{nullptr}; };
        std::vector<WindowRoot> windows;
        struct Columns {
            winrt::weak_ref<Element> owner;
            std::vector<winrt::weak_ref<Element>> pages;
        };
        std::vector<Columns> columnGroups;
        std::vector<winrt::weak_ref<Element>> scrollers;
        std::vector<std::weak_ptr<AcrylicScene>> scenes;
        uint64_t generation = 0;

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
                if (at.try_as<controls::ScrollView>()) return true;
            }
            return false;
        }
        Rect intersect(Rect const &a, Rect const &b) {
            auto x = std::max(a.X, b.X), y = std::max(a.Y, b.Y);
            return {x, y, std::max(0.0f, std::min(a.X + a.Width, b.X + b.Width) - x),
                          std::max(0.0f, std::min(a.Y + a.Height, b.Y + b.Height) - y)};
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

    float acrylicPresentationOpacity(Element const &element, Element const &root) {
        double opacity = 1;
        for (xaml::DependencyObject at = element; at && at != root; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            if (auto parent = at.try_as<xaml::UIElement>()) opacity *= parent.Opacity();
        }
        return static_cast<float>(std::clamp(opacity, 0.0, 1.0));
    }
    bool acrylicUsesLocalPresentation(Element const &element, Element const &root) {
        // During an ancestor transition, the original native subtree already
        // owns the complete opacity, transform, clipping and removal lifetime.
        // Keep its material/controls there, sharing only the filtered texture.
        for (xaml::DependencyObject at = element; at && at != root; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            auto parent = at.try_as<Element>();
            if (!parent) continue;
            if (parent.Opacity() != 1 || parent.Projection()) return true;
            auto local = parent.Resources().TryLookup(winrt::box_value(L"safeBarLocalPresentation"));
            if (local && winrt::unbox_value_or<bool>(local, false)) return true;
            if (auto transform = parent.RenderTransform()) {
                auto origin = transform.TransformPoint({0, 0});
                auto x = transform.TransformPoint({1, 0});
                auto y = transform.TransformPoint({0, 1});
                if (origin.X != 0 || origin.Y != 0 || x.X != 1 || x.Y != 0 || y.X != 0 || y.Y != 1) return true;
            }
        }
        return false;
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
            std::erase_if(scrollers, [](auto const &entry) { return !entry.get(); });
            // Split only ancestors of scrollers, not their documents/rows. This
            // retains the real viewport extending outside a safe layout slot.
            for (auto const &entry : scrollers) if (auto element = entry.get()) {
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
                const auto visible = acrylicVisibleBounds(element, coordinates);
                const auto clipped = acrylicLocalClip(element, coordinates, visible);
                const auto opacity = acrylicPresentationOpacity(element, coordinates);
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
                const auto matrix = acrylicPresentationMatrix(element, coordinates);
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
                    const auto tag = winrt::unbox_value_or<winrt::hstring>(parent.Tag(), L"");
                    if (tag == L"sheets" || tag == L"overlay") break;
                    content = parent;
                    if (parent.try_as<controls::FlyoutPresenter>()) break;
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
            if (acrylicUsesLocalPresentation(owner, scene->root.get())) continue;
            if (acrylicScene(owner, bar) == scene) result.push_back(bar);
        }
        return result;
    }
    std::vector<Rect> acrylicSceneRegions(std::shared_ptr<AcrylicScene> const &scene) {
        std::vector<Rect> result;
        if (!scene) return result;
        auto root = scene->root.get();
        if (!root) return result;
        for (auto const &entry : insets) {
            auto owner = entry.owner.get(), marker = entry.material.get();
            if (!owner || !marker || !marker.IsLoaded() || marker.Visibility() != xaml::Visibility::Visible
                || marker.ActualWidth() <= 0 || marker.ActualHeight() <= 0) continue;
            // Resolve actual ownership after native parenting has settled.
            // This includes trailing detail bars as well as nested sidebar bars.
            if (acrylicScene(owner, marker) != scene || acrylicUsesLocalPresentation(owner, root)) continue;
            auto rect = acrylicVisibleBounds(marker, root);
            if (rect.Width > 0 && rect.Height > 0) result.push_back(rect);
        }
        return result;
    }
    void observeAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, std::function<bool()> observer) {
        scene->observers.push_back(std::move(observer));
    }
    void registerAcrylicScroller(Element const &scroller) {
        std::erase_if(scrollers, [](auto const &entry) { return !entry.get(); });
        for (auto const &entry : scrollers) if (entry.get() == scroller) return;
        scrollers.push_back(winrt::make_weak(scroller));
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
            }
        } catch (...) { report("invalidating an acrylic content scene"); }
    }

    void setAcrylicContentRoot(Element const &root, Element const &content) {
        std::erase_if(windows, [](auto const &entry) { return !entry.root.get(); });
        for (auto &entry : windows) if (entry.root.get() == root) {
            if (entry.content.get() == content) return;
            entry.content = content ? winrt::make_weak(content) : winrt::weak_ref<Element>{};
            ++generation;
            return;
        }
        windows.push_back({winrt::make_weak(root), content ? winrt::make_weak(content) : winrt::weak_ref<Element>{}});
        ++generation;
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
            if (found != columnGroups.end()) { columnGroups.erase(found); ++generation; }
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
    } catch (...) { report("registering navigation material columns"); }
}

extern "C" void swiftomniui_winui_safe_area_register(
    SwiftOmniUIObjectRef owner, SwiftOmniUIObjectRef bar, SwiftOmniUIObjectRef material
) {
    using namespace swiftomniui;
    try {
        auto element = as<xaml::FrameworkElement>(owner);
        auto controls = bar ? as<xaml::FrameworkElement>(bar) : xaml::FrameworkElement{nullptr};
        auto surface = material ? as<xaml::FrameworkElement>(material) : xaml::FrameworkElement{nullptr};
        std::erase_if(insets, [](auto const &entry) { return !entry.owner.get(); });
        for (auto &entry : insets) if (entry.owner.get() == element) {
            if (entry.bar.get() == controls && entry.material.get() == surface) return;
            if (!bar) {
                entry.owner = {};
            } else {
                entry.bar = winrt::make_weak(controls);
                entry.material = surface ? winrt::make_weak(surface) : winrt::weak_ref<xaml::FrameworkElement>{};
            }
            ++generation;
            return;
        }
        if (bar) {
            insets.push_back({winrt::make_weak(element), winrt::make_weak(controls),
                surface ? winrt::make_weak(surface) : winrt::weak_ref<xaml::FrameworkElement>{}});
            ++generation;
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

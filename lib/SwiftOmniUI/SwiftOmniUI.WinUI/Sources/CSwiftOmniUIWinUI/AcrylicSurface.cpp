// SPDX-License-Identifier: Apache-2.0
#include "AcrylicSurface.h"
#include <chrono>

namespace swiftomniui {
    using Element = xaml::FrameworkElement;
    namespace {
        using Preview = xaml::Hosting::ElementCompositionPreview;
        void appendRect(std::vector<double> &path, MaterialRect const &r) {
            path.insert(path.end(), {0, r.X, r.Y, 1, r.X + r.Width, r.Y, 1, r.X + r.Width, r.Y + r.Height,
                1, r.X, r.Y + r.Height, 4});
        }
        composition::CompositionGeometricClip materialClip(composition::Compositor const &compositor,
            std::vector<double> const &path, bool evenOdd) {
            auto geometry = pathGeometry(path.data(), static_cast<int32_t>(path.size()), evenOdd);
            return compositor.CreateGeometricClip(compositor.CreatePathGeometry(
                compositionPath(geometry.as<ID2D1Geometry>(), evenOdd)));
        }
        composition::SpriteVisual overlay(composition::ContainerVisual const &parent, winrt::Windows::UI::Color color) {
            auto compositor = parent.Compositor();
            auto sprite = compositor.CreateSpriteVisual();
            sprite.RelativeSizeAdjustment({1, 1});
            sprite.Brush(compositor.CreateColorBrush(color));
            sprite.IsHitTestVisible(false);
            parent.Children().InsertAtTop(sprite);
            return sprite;
        }

        template<class T> std::pair<bool, bool> underBar(T const &scroller) {
            const double offset = scroller.VerticalOffset();
            return {offset > 0.5, scroller.ScrollableHeight() - offset > 0.5};
        }
    }

    void AcrylicEdgeOverlay::update(composition::ContainerVisual const &tints, composition::ContainerVisual const &lines,
        std::vector<MaterialRect> next, bool upper, bool show, float lineHeight, bool scaleChanged) {
        if (next.empty()) {
            if (tint) { tints.Children().Remove(tint); lines.Children().Remove(line); }
            *this = {};
            return;
        }
        auto compositor = tints.Compositor();
        if (!tint) {
            tint = overlay(tints, {255, 255, 255, 255});
            line = overlay(lines, {255, 255, 255, 255});
            tint.Opacity(0);
            // Both layers share the same compositor progress, even if a scroll reverses mid-fade.
            auto progress = compositor.CreateExpressionAnimation(L"edge.Opacity");
            progress.SetReferenceParameter(L"edge", tint);
            line.StartAnimation(L"Opacity", progress);
        }
        if (regions != next || scaleChanged) {
            std::vector<double> fillPath, linePath;
            for (auto rect : next) {
                appendRect(fillPath, rect);
                const float height = std::min(rect.Height, lineHeight);
                if (upper) rect.Y += rect.Height - height;
                rect.Height = height;
                appendRect(linePath, rect);
            }
            tint.Clip(materialClip(compositor, fillPath, false));
            line.Clip(materialClip(compositor, linePath, false));
            regions = std::move(next);
        }
        if (visible == show) return;
        if (swiftomniui_winui_animations_enabled()) {
            if (!tint.ImplicitAnimations()) {
                auto fade = compositor.CreateScalarKeyFrameAnimation();
                fade.Target(L"Opacity");
                fade.Duration(std::chrono::milliseconds(220));
                fade.InsertExpressionKeyFrame(1, L"this.FinalValue",
                    compositor.CreateCubicBezierEasingFunction({0.25f, 0.1f}, {0.25f, 1}));
                auto animations = compositor.CreateImplicitAnimationCollection();
                animations.Insert(L"Opacity", fade);
                tint.ImplicitAnimations(animations);
            }
        } else {
            tint.ImplicitAnimations(nullptr);
            tint.StopAnimation(L"Opacity");
        }
        tint.Opacity(show ? 1.0f : 0.0f);
        visible = show;
    }

    void ViewportAcrylic::clear(controls::Grid const &sharp, controls::Border const &surface) {
        if (output) {
            Preview::GetElementVisual(sharp).Clip(nullptr);
            Preview::SetElementChildVisual(surface, nullptr);
            output = nullptr;
        }
        if (source) { source.SourceVisual(nullptr); source = nullptr; }
        upper = {}; lower = {};
        tints = nullptr; lines = nullptr;
        scrollSource = {};
        requestsChanged = true;
        displayed.clear();
        size = {};
    }

    void ViewportAcrylic::paint(Element const &scroller, controls::Grid const &sharp, controls::Border const &surface) {
        const auto extent = scroller.ActualSize();
        auto root = scroller.XamlRoot();
        if (requests.empty() || !root || extent.x <= 0 || extent.y <= 0) { clear(sharp, surface); return; }
        std::pair<bool, bool> under{};
        if (auto scroll = scroller.try_as<controls::ScrollView>()) under = underBar(scroll);
        else if (auto viewer = scroller.try_as<controls::ScrollViewer>()) under = underBar(viewer);
        else {
            auto native = scrollSource.get();
            if (!native || !native.IsLoaded()) {
                if (auto list = scroller.try_as<controls::ItemsView>()) native = list.ScrollView();
                else native = first<controls::ScrollView>(scroller);
                if (!native) native = first<controls::ScrollViewer>(scroller);
                if (native) {
                    scrollSource = winrt::make_weak(native);
                    registerAcrylicScroller(native);
                }
            }
            if (auto scroll = native.try_as<controls::ScrollView>()) under = underBar(scroll);
            else if (auto viewer = native.try_as<controls::ScrollViewer>()) under = underBar(viewer);
        }
        const bool isDark = scroller.ActualTheme() == xaml::ElementTheme::Dark;
        const double scale = root.RasterizationScale();
        if (!requestsChanged && size == extent && lastScrollEdges == under && dark == isDark && lastScale == scale) return;
        std::vector<AcrylicBand> bands, top, bottomBands;
        for (auto const &[key, rects] : requests) {
            for (auto const &section : rects) {
                const auto &rect = section.rect;
                const float x = std::max(0.f, rect.X), y = std::max(0.f, rect.Y);
                const float right = std::min(extent.x, rect.X + rect.Width);
                const float bottom = std::min(extent.y, rect.Y + rect.Height);
                if (right <= x || bottom <= y) continue;
                bands.push_back({{x, y, right - x, bottom - y}});
                if (section.edge == AcrylicEdge::top) top.push_back(bands.back());
                if (section.edge == AcrylicEdge::bottom) bottomBands.push_back(bands.back());
            }
        }
        auto next = acrylicMaterialRegions(bands);
        if (next.empty()) { clear(sharp, surface); return; }
        const bool geometryChanged = next != displayed || extent != size;
        const bool scaleChanged = lastScale != scale;
        auto raw = Preview::GetElementVisual(scroller);
        auto compositor = raw.Compositor();
        if (geometryChanged) {
            std::vector<double> path;
            for (auto const &rect : next) appendRect(path, rect);
            auto blurredClip = materialClip(compositor, path, false);
            // Regions are disjoint after union. Even-odd fill makes their exact
            // complement inside the viewport, including holes between separate bars.
            appendRect(path, {0, 0, extent.x, extent.y});
            auto sharpClip = materialClip(compositor, path, true);
            if (!output) {
                auto live = compositor.CreateVisualSurface();
                live.SourceVisual(raw);
                live.SourceSize(extent);
                auto input = compositor.CreateSurfaceBrush(live);
                input.Stretch(composition::CompositionStretch::None);
                input.HorizontalAlignmentRatio(0);
                input.VerticalAlignmentRatio(0);
                auto sprite = compositor.CreateSpriteVisual();
                sprite.IsHitTestVisible(false);
                sprite.Brush(viewportBlur(compositor, input));
                Preview::SetElementChildVisual(surface, sprite);
                source = live;
                output = sprite;
            }
            if (size != extent) {
                source.SourceSize(extent);
                output.Size(extent);
            }
            output.Clip(blurredClip);
            // Clip the parent of the source, so the live source retains the glyphs
            // while the normal sharp pass stops exactly at the material boundary.
            Preview::GetElementVisual(sharp).Clip(sharpClip);
            displayed = std::move(next);
            size = extent;
        }
        const bool createLayers = !tints;
        if (createLayers) {
            // Apply the tint strength once, including where upper and lower bars overlap.
            tints = compositor.CreateLayerVisual();
            tints.RelativeSizeAdjustment({1, 1});
            lines = compositor.CreateContainerVisual();
            lines.RelativeSizeAdjustment({1, 1});
            output.Children().InsertAtTop(tints);
            output.Children().InsertAtTop(lines);
        }
        if (createLayers || dark != isDark) tints.Opacity((isDark ? 16 : 64) / 255.0f);
        auto lineHeight = static_cast<float>(0.5 / scale);
        upper.update(tints, lines, acrylicMaterialRegions(top), true, under.first, lineHeight, scaleChanged);
        lower.update(tints, lines, acrylicMaterialRegions(bottomBands), false, under.second, lineHeight, scaleChanged);
        const uint8_t ink = isDark ? 255 : 0;
        for (auto *edge : {&upper, &lower}) {
            if (edge->line) {
                auto brush = edge->line.Brush().as<composition::CompositionColorBrush>();
                winrt::Windows::UI::Color color{55, ink, ink, ink};
                if (brush.Color() != color) brush.Color(color);
            }
        }
        lastScrollEdges = under;
        lastScale = scale;
        requestsChanged = false;
        dark = isDark;
    }

    struct AcrylicSourceState {
        winrt::weak_ref<Element> source;
        std::shared_ptr<AcrylicScene> scene;
    };
    AcrylicSource::AcrylicSource() : state(std::make_shared<AcrylicSourceState>()) {}
    bool AcrylicSource::source(Element const &element) {
        if (state->source.get() == element) return false;
        state->source = element ? winrt::make_weak(element) : winrt::weak_ref<Element>{};
        reset();
        return true;
    }
    void AcrylicSource::reset() {
        state->scene.reset();
    }
    std::shared_ptr<AcrylicScene> AcrylicSource::scene() const {
        return state->scene;
    }
    winrt::Windows::Foundation::Rect AcrylicSource::samplingBounds() const {
        auto bounds = acrylicSceneBounds(state->scene);
        if (bounds.Width <= 0 || bounds.Height <= 0) return {};
        if (acrylicSceneIsWindow(state->scene)) {
            const auto root = acrylicSceneRoot(state->scene);
            const auto slot = acrylicLayoutBounds(root, root.XamlRoot().Content().as<Element>());
            bounds.X += slot.X; bounds.Y += slot.Y;
        }
        return bounds;
    }
    void AcrylicSource::resolve(Element const &target) {
        state->scene = acrylicScene(state->source.get(), target);
    }
}

extern "C" void swiftomniui_winui_safe_area_background_source(
    SwiftOmniUIObjectRef background, SwiftOmniUIObjectRef source
) {
    using namespace swiftomniui;
    try {
        auto local = winrt::get_self<LocalAcrylic>(as<xaml::IFrameworkElementOverrides>(background));
        local->material.source(source ? as<xaml::FrameworkElement>(source) : xaml::FrameworkElement{nullptr});
    } catch (...) { report("setting a safe bar's scroll-edge source"); }
}

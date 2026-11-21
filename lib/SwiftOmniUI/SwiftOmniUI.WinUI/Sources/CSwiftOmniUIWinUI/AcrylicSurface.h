// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "AcrylicScene.h"
#include "PathGeometry.h"
#include <algorithm>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <memory>
#include <map>
#include <utility>

namespace swiftomniui {
    struct AcrylicSourceState;
    struct AcrylicSource {
        std::shared_ptr<AcrylicSourceState> state;
        AcrylicSource();
        bool source(xaml::FrameworkElement const &element);
        void reset();
        std::shared_ptr<AcrylicScene> scene() const;
        winrt::Windows::Foundation::Rect samplingBounds() const;
        void resolve(xaml::FrameworkElement const &target);
    };

    winrt::Microsoft::UI::Composition::CompositionEffectBrush contentBlur(
        winrt::Microsoft::UI::Composition::Compositor const &compositor,
        winrt::Microsoft::UI::Composition::CompositionBrush const &source, float sigma);

    using MaterialRect = winrt::Windows::Foundation::Rect;
    namespace composition = winrt::Microsoft::UI::Composition;

    // The sharp subtree and the backdrop output are siblings. Only the original
    // scroller feeds the surface; neither the output nor the bar controls can feed it.
    struct MaterialSection {
        MaterialRect rect;
        AcrylicEdge edge;
        bool operator==(MaterialSection const &) const = default;
    };
    struct AcrylicEdgeOverlay {
        composition::SpriteVisual tint{nullptr}, line{nullptr};
        std::vector<MaterialRect> regions;
        bool visible = false;
        void update(composition::ContainerVisual const &tints, composition::ContainerVisual const &lines,
            std::vector<MaterialRect> next, bool upper, bool show, float lineHeight, bool scaleChanged);
    };
    struct ViewportAcrylic {
        std::map<void const *, std::vector<MaterialSection>> requests;
        std::vector<MaterialRect> displayed;
        winrt::Windows::Foundation::Numerics::float2 size{};
        composition::CompositionVisualSurface source{nullptr};
        composition::SpriteVisual output{nullptr};
        composition::LayerVisual tints{nullptr};
        composition::ContainerVisual lines{nullptr};
        AcrylicEdgeOverlay upper, lower;
        bool dark = false, requestsChanged = true;
        std::pair<bool, bool> lastScrollEdges{};
        double lastScale = 0;
        winrt::weak_ref<xaml::FrameworkElement> scrollSource;
        void paint(xaml::FrameworkElement const &scroller, controls::Grid const &sharp, controls::Border const &surface);
        void clear(controls::Grid const &sharp, controls::Border const &surface);
    };
    composition::CompositionEffectBrush viewportBlur(composition::Compositor const &compositor,
        composition::CompositionBrush const &content);
    bool setViewportMaterial(xaml::FrameworkElement const &viewport, void const *key,
        std::vector<MaterialSection> rects);

    // One backdrop per material, including when the visible mask has multiple lanes.
    struct AcrylicLayer {
        using Rect = winrt::Windows::Foundation::Rect;
        std::vector<Rect> regions;
        winrt::Microsoft::UI::Composition::SpriteVisual visual{nullptr};

        std::vector<winrt::weak_ref<xaml::FrameworkElement>> viewports;

        void clear() {
            for (auto const &entry : viewports)
                if (auto viewport = entry.get()) setViewportMaterial(viewport, this, {});
            viewports.clear();
            fallbackRegions.clear();
            if (visual) {
                visual.Brush(nullptr);
                visual.Clip(nullptr);
                visual = nullptr;
            }
            regions.clear();
        }
        void paint(xaml::FrameworkElement const &owner, std::vector<AcrylicBand> const &bands) {
            struct Request { xaml::FrameworkElement viewport; std::vector<AcrylicBand const *> bands; };
            std::vector<Request> requests;
            std::vector<AcrylicBand> fallback;
            for (auto const &band : bands) {
                if (!band.active) continue;
                if (!band.viewport) { fallback.push_back(band); continue; }
                auto it = std::find_if(requests.begin(), requests.end(),
                    [&](auto const &r) { return r.viewport == band.viewport; });
                if (it == requests.end()) requests.push_back({band.viewport, {&band}});
                else it->bands.push_back(&band);
            }
            std::vector<winrt::weak_ref<xaml::FrameworkElement>> nextViewports;
            for (auto const &request : requests) {
                auto mapping = owner.TransformToVisual(request.viewport);
                std::vector<MaterialSection> local;
                for (auto const *band : request.bands) {
                    auto rect = mapping.TransformBounds(band->rect);
                    // A full-width toolbar covers the incoming viewport throughout a horizontal
                    // slide. Its native parent clips the moving edge on each compositor frame.
                    if (band->spansViewport) { rect.X = 0; rect.Width = request.viewport.ActualSize().x; }
                    local.push_back({rect, band->edge});
                }
                if (setViewportMaterial(request.viewport, this, std::move(local))) {
                    nextViewports.push_back(winrt::make_weak(request.viewport));
                } else {
                    for (auto const *band : request.bands) fallback.push_back({band->rect});
                }
            }
            for (auto const &entry : viewports) if (auto viewport = entry.get()) {
                if (std::none_of(nextViewports.begin(), nextViewports.end(),
                    [&](auto const &v) { return v.get() == viewport; })) setViewportMaterial(viewport, this, {});
            }
            viewports = std::move(nextViewports);
            regions = acrylicMaterialRegions(bands);
            paintFallback(owner, acrylicMaterialRegions(fallback));
        }
    private:
        std::vector<Rect> fallbackRegions;
        void paintFallback(xaml::FrameworkElement const &owner, std::vector<Rect> next) {
            if (next == fallbackRegions) return;
            if (next.empty()) {
                if (visual) visual.IsVisible(false);
                fallbackRegions.clear();
                return;
            }
            auto compositor = xaml::Hosting::ElementCompositionPreview::GetElementVisual(owner).Compositor();
            if (!visual) {
                auto sprite = compositor.CreateSpriteVisual();
                sprite.IsHitTestVisible(false);
                sprite.IsVisible(false);
                sprite.Brush(contentBlur(compositor, compositor.CreateBackdropBrush(), 4.0f));
                xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(owner, sprite);
                visual = sprite;
            }
            auto first = next.front();
            float left = first.X, top = first.Y;
            float right = left + first.Width, bottom = top + first.Height;
            for (auto const &rect : next) {
                left = std::min(left, rect.X);
                top = std::min(top, rect.Y);
                right = std::max(right, rect.X + rect.Width);
                bottom = std::max(bottom, rect.Y + rect.Height);
            }
            if (next.size() > 1) {
                std::vector<double> commands;
                for (auto const &rect : next) {
                    const auto x = rect.X - left, y = rect.Y - top;
                    commands.insert(commands.end(), {0, x, y, 1, x + rect.Width, y,
                        1, x + rect.Width, y + rect.Height, 1, x, y + rect.Height, 4});
                }
                auto path = compositionPath(pathGeometry(commands.data(), static_cast<int32_t>(commands.size()),
                    false).as<ID2D1Geometry>(), false);
                visual.Clip(compositor.CreateGeometricClip(compositor.CreatePathGeometry(path)));
            } else if (visual.Clip()) {
                visual.Clip(nullptr);
            }
            visual.Offset({left, top, 0});
            visual.Size({right - left, bottom - top});
            visual.IsVisible(true);
            fallbackRegions = std::move(next);
        }
    };

    struct LocalAcrylic : controls::PanelT<LocalAcrylic> {
        AcrylicLayer drawing;
        AcrylicSource material;
        winrt::Windows::Foundation::Size extent{};
        std::weak_ptr<AcrylicScene> observed;
        LocalAcrylic() {
            IsHitTestVisible(false);
            UseLayoutRounding(false);
            Loaded([this](auto const &, auto const &) { refresh(); });
            Unloaded([this](auto const &, auto const &) { material.reset(); drawing.clear(); observed.reset(); });
        }
        void refresh() {
            try {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                material.resolve(self);
                auto scene = material.scene();
                if (scene && observed.lock() != scene) {
                    observed = scene;
                    auto weak = get_weak();
                    std::weak_ptr<AcrylicScene> scope = scene;
                    observeAcrylicScene(scene, [weak, scope] {
                        auto self = weak.get();
                        if (!self || !self->IsLoaded() || self->observed.lock() != scope.lock()) return false;
                        self->refresh();
                        return true;
                    });
                }
                std::vector<AcrylicBand> bands;
                if (scene && extent.Width > 0 && extent.Height > 0) {
                    bool inFlyout = false;
                    if (!acrylicSceneIsWindow(scene)) {
                        for (auto at = xaml::Media::VisualTreeHelper::GetParent(self); at;
                             at = xaml::Media::VisualTreeHelper::GetParent(at)) {
                            if (at.try_as<controls::FlyoutPresenter>()) { inFlyout = true; break; }
                        }
                    }
                    if (!inFlyout) bands = acrylicLocalRegions(self, {0, 0, extent.Width, extent.Height});
                }
                drawing.paint(self, bands);
            } catch (...) { report("updating a safe bar material"); }
        }
        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size) {
            return {0, 0};
        }
        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) {
            extent = final;
            if (IsLoaded()) refresh();
            return final;
        }
    };
}

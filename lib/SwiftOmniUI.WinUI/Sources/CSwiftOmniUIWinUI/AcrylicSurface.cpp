// SPDX-License-Identifier: Apache-2.0
#include "AcrylicSurface.h"
#include <algorithm>
#include <cmath>

namespace swiftomniui {
    namespace composition = winrt::Microsoft::UI::Composition;
    using Element = xaml::FrameworkElement;
    using Size = winrt::Windows::Foundation::Size;
    namespace {
        constexpr float reduction = 0.25f;
        constexpr float radius = 20.0f;

        struct ContentBrush : xaml::Media::XamlCompositionBrushBaseT<ContentBrush> {
            void OnConnected() {}
            void OnDisconnected() {}
            void set(composition::CompositionBrush const &brush) { CompositionBrush(brush); }
        };

        struct FilteredContent {
            std::shared_ptr<AcrylicScene> scene;
            composition::CompositionVisualSurface input{nullptr}, reduced{nullptr}, result{nullptr};
            composition::CompositionSurfaceBrush inputBrush{nullptr}, reducedBrush{nullptr};
            composition::SpriteVisual downsample{nullptr}, filtered{nullptr};
            composition::CompositionEffectBrush effect{nullptr};
            winrt::Windows::Foundation::Numerics::float2 extent{};

            explicit FilteredContent(std::shared_ptr<AcrylicScene> scope) : scene(std::move(scope)) {
                auto visual = acrylicSceneVisual(scene);
                auto compositor = visual.Compositor();
                input = compositor.CreateVisualSurface();
                input.SourceVisual(visual);
                inputBrush = compositor.CreateSurfaceBrush(input);
                inputBrush.Stretch(composition::CompositionStretch::None);
                inputBrush.HorizontalAlignmentRatio(0);
                inputBrush.VerticalAlignmentRatio(0);
                inputBrush.Scale({reduction, reduction});
                downsample = compositor.CreateSpriteVisual();
                downsample.Brush(inputBrush);
                reduced = compositor.CreateVisualSurface();
                reduced.SourceVisual(downsample);
                reducedBrush = compositor.CreateSurfaceBrush(reduced);
                reducedBrush.Stretch(composition::CompositionStretch::None);
                reducedBrush.HorizontalAlignmentRatio(0);
                reducedBrush.VerticalAlignmentRatio(0);
                // One native GPU filter per scope, at 1/16 of the pixel area.
                // No backdrop brush, tint, luminosity adjustment or frame history.
                effect = contentBlur(compositor, reducedBrush, radius * reduction);
                filtered = compositor.CreateSpriteVisual();
                filtered.Brush(effect);
                result = compositor.CreateVisualSurface();
                result.SourceVisual(filtered);
            }
            void update() {
                auto root = acrylicSceneRoot(scene);
                if (!root) return;
                auto size = root.ActualSize();
                if (size.x <= 0 || size.y <= 0 || size == extent) return;
                auto reducedSize = winrt::Windows::Foundation::Numerics::float2{
                    std::ceil(size.x * reduction), std::ceil(size.y * reduction)};
                input.SourceSize(size);
                downsample.Size(reducedSize);
                reduced.SourceSize(reducedSize);
                filtered.Size(reducedSize);
                result.SourceSize(reducedSize);
                extent = size;
            }
        };
        std::vector<std::weak_ptr<FilteredContent>> filters;
        std::shared_ptr<FilteredContent> filteredContent(std::shared_ptr<AcrylicScene> const &scene) {
            std::erase_if(filters, [](auto const &entry) { return entry.expired(); });
            for (auto const &entry : filters)
                if (auto filter = entry.lock(); filter && filter->scene == scene) return filter;
            auto filter = std::make_shared<FilteredContent>(scene);
            filters.push_back(filter);
            return filter;
        }
    }

    struct AcrylicSourceState {
        winrt::weak_ref<Element> source;
        std::shared_ptr<FilteredContent> filter;
        composition::CompositionSurfaceBrush crop{nullptr};
        winrt::com_ptr<ContentBrush> adapter = winrt::make_self<ContentBrush>();
    };
    AcrylicSource::AcrylicSource() : state(std::make_shared<AcrylicSourceState>()) {}
    bool AcrylicSource::source(Element const &element) {
        if (state->source.get() == element) return false;
        state->source = element ? winrt::make_weak(element) : winrt::weak_ref<Element>{};
        reset();
        return true;
    }
    void AcrylicSource::reset() {
        state->adapter->set(nullptr);
        state->crop = nullptr;
        state->filter.reset();
    }
    std::shared_ptr<AcrylicScene> AcrylicSource::scene() const {
        return state->filter ? state->filter->scene : nullptr;
    }
    xaml::Media::Brush AcrylicSource::update(Element const &target, Size size) {
        auto source = state->source.get();
        if (!source || !target.IsLoaded() || size.Width <= 0 || size.Height <= 0) return nullptr;
        auto scope = acrylicScene(source, target);
        if (!scope) return nullptr;
        if (!state->filter || state->filter->scene != scope) {
            auto filter = filteredContent(scope); // Build first; retain the old output on allocation failure.
            auto compositor = acrylicSceneVisual(scope).Compositor();
            auto crop = compositor.CreateSurfaceBrush(filter->result);
            crop.Stretch(composition::CompositionStretch::None);
            crop.HorizontalAlignmentRatio(0);
            crop.VerticalAlignmentRatio(0);
            state->adapter->set(crop);
            state->crop = crop;
            state->filter = std::move(filter);
        }
        state->filter->update();
        auto root = acrylicSceneRoot(scope);
        auto inverse = target.TransformToVisual(root).Inverse();
        if (!inverse) return nullptr; // A zero-scale insertion has no visible surface yet.
        auto origin = inverse.TransformPoint({0, 0});
        auto x = inverse.TransformPoint({1, 0});
        auto y = inverse.TransformPoint({0, 1});
        const winrt::Windows::Foundation::Numerics::float3x2 mapping{
            (x.X - origin.X) / reduction, (x.Y - origin.Y) / reduction,
            (y.X - origin.X) / reduction, (y.Y - origin.Y) / reduction, origin.X, origin.Y};
        if (state->crop.TransformMatrix() != mapping) state->crop.TransformMatrix(mapping);
        return state->adapter.as<xaml::Media::Brush>();
    }
}

extern "C" void swiftomniui_winui_safe_area_background_source(
    SwiftOmniUIObjectRef background, SwiftOmniUIObjectRef source
) {
    using namespace swiftomniui;
    try {
        auto local = winrt::get_self<LocalAcrylic>(as<xaml::IFrameworkElementOverrides>(background));
        local->material.source(source ? as<xaml::FrameworkElement>(source) : xaml::FrameworkElement{nullptr});
    } catch (...) { report("setting a safe bar's clean content source"); }
}

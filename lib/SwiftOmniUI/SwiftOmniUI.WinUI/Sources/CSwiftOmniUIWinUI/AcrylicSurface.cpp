// SPDX-License-Identifier: Apache-2.0
#include "AcrylicSurface.h"
#include <algorithm>
#include <cmath>

namespace swiftomniui {
    namespace composition = winrt::Microsoft::UI::Composition;
    using Element = xaml::FrameworkElement;
    using Rect = winrt::Windows::Foundation::Rect;
    using winrt::Windows::Foundation::Numerics::float2;
    namespace {
        constexpr float reduction = 0.25f;
        // The source is reduced to one quarter in each axis before the
        // Gaussian runs. A 4 DIP radius therefore stays a restrained,
        // macOS-like blur after it is expanded back to the window size.
        constexpr float radius = 4.0f;

        Rect intersect(Rect const &a, Rect const &b) {
            const auto left = std::max(a.X, b.X);
            const auto top = std::max(a.Y, b.Y);
            const auto right = std::min(a.X + a.Width, b.X + b.Width);
            const auto bottom = std::min(a.Y + a.Height, b.Y + b.Height);
            return {left, top, std::max(0.0f, right - left), std::max(0.0f, bottom - top)};
        }
    }

    struct FilteredContent {
            std::shared_ptr<AcrylicScene> scene;
            composition::CompositionVisualSurface input{nullptr}, reduced{nullptr}, result{nullptr};
            composition::CompositionSurfaceBrush inputBrush{nullptr}, reducedBrush{nullptr};
            composition::SpriteVisual downsample{nullptr}, filtered{nullptr};
            composition::CompositionEffectBrush effect{nullptr};
            Rect bounds{};
            float2 scale{};

            explicit FilteredContent(std::shared_ptr<AcrylicScene> scope) : scene(std::move(scope)) {
                auto visual = acrylicSceneVisual(scene);
                auto compositor = visual.Compositor();
                input = compositor.CreateVisualSurface();
                input.SourceVisual(visual);
                inputBrush = compositor.CreateSurfaceBrush(input);
                inputBrush.Stretch(composition::CompositionStretch::None);
                inputBrush.HorizontalAlignmentRatio(0);
                inputBrush.VerticalAlignmentRatio(0);
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
            void update(Rect capture) {
                auto next = intersect(acrylicSceneBounds(scene), capture);
                if (next.Width <= 0 || next.Height <= 0) { bounds = {}; return; }
                if (next == bounds) return;
                const float2 size{next.Width, next.Height};
                const float2 reducedSize{
                    std::ceil(size.x * reduction), std::ceil(size.y * reduction)};
                // Crop BEFORE filtering. The filter sees only the pixels
                // covered by this material strip, so content outside its hard
                // edge cannot enter the Gaussian kernel.
                input.SourceOffset({next.X, next.Y});
                input.SourceSize(size);
                scale = {reducedSize.x / size.x, reducedSize.y / size.y};
                inputBrush.Scale(scale);
                downsample.Size(reducedSize);
                reduced.SourceSize(reducedSize);
                filtered.Size(reducedSize);
                result.SourceSize(reducedSize);
                bounds = next;
            }
    };
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

    void AcrylicStrip::paint(Element const &target, std::shared_ptr<AcrylicScene> const &scene,
                            Rect const &rect) {
        auto root = acrylicSceneRoot(scene);
        if (!root) return;
        auto inverse = target.TransformToVisual(root).Inverse();
        if (!inverse) {
            if (visual) visual.IsVisible(false);
            return;
        }
        auto compositor = acrylicSceneVisual(scene).Compositor();
        if (!filter || filter->scene != scene) {
            filter = std::make_shared<FilteredContent>(scene);
            crop = compositor.CreateSurfaceBrush(filter->result);
            crop.Stretch(composition::CompositionStretch::None);
            crop.HorizontalAlignmentRatio(0);
            crop.VerticalAlignmentRatio(0);
        }
        const auto capture = target.TransformToVisual(root).TransformBounds(rect);
        filter->update(capture);
        if (!visual) {
            visual = compositor.CreateSpriteVisual();
            visual.IsHitTestVisible(false);
        }
        const auto bounds = filter->bounds;
        const bool visible = bounds.Width > 0 && bounds.Height > 0;
        if (visual.IsVisible() != visible) visual.IsVisible(visible);
        if (!visible) return;
        auto origin = inverse.TransformPoint({bounds.X, bounds.Y});
        auto x = inverse.TransformPoint({bounds.X + 1, bounds.Y});
        auto y = inverse.TransformPoint({bounds.X, bounds.Y + 1});
        const auto scale = filter->scale;
        const winrt::Windows::Foundation::Numerics::float3x2 mapping{
            (x.X - origin.X) / scale.x, (x.Y - origin.Y) / scale.x,
            (y.X - origin.X) / scale.y, (y.Y - origin.Y) / scale.y,
            origin.X - rect.X, origin.Y - rect.Y};
        if (crop.TransformMatrix() != mapping) crop.TransformMatrix(mapping);
        const winrt::Windows::Foundation::Numerics::float3 offset{rect.X, rect.Y, 0};
        const float2 size{rect.Width, rect.Height};
        if (visual.Offset() != offset) visual.Offset(offset);
        if (visual.Size() != size) visual.Size(size);
        if (visual.Brush() != crop) visual.Brush(crop);
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

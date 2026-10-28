// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "AcrylicScene.h"
#include "PathGeometry.h"
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <memory>

namespace swiftomniui {
    struct AcrylicSourceState;
    struct AcrylicSource {
        std::shared_ptr<AcrylicSourceState> state;
        AcrylicSource();
        bool source(xaml::FrameworkElement const &element);
        void reset();
        std::shared_ptr<AcrylicScene> scene() const;
        xaml::Media::Brush update(xaml::FrameworkElement const &target,
                                 winrt::Windows::Foundation::Size size);
    };

    winrt::Microsoft::UI::Composition::CompositionEffectBrush contentBlur(
        winrt::Microsoft::UI::Composition::Compositor const &compositor,
        winrt::Microsoft::UI::Composition::CompositionBrush const &source, float sigma);

    // Mica replaces the sharp drawing inside the material region. Only clean
    // content enters the transparent blur above it. The external Mica link is
    // never captured or replaced by an approximate white/grey colour.
    struct AcrylicLayer {
        controls::SystemBackdropElement foundation{nullptr};
        controls::Grid backing;
        controls::Border fill, surface;
        std::vector<winrt::Windows::Foundation::Rect> regions;
        winrt::Microsoft::UI::Composition::CompositionGeometricClip regionClip{nullptr}, controlsClip{nullptr};
        bool foundationFailed = false;

        void mount(controls::Panel const &owner) {
            try {
                foundation = controls::SystemBackdropElement();
                foundation.IsHitTestVisible(false);
                foundation.Opacity(0);
            } catch (...) {
                foundationFailed = true;
                report("creating the optional bar Mica foundation");
            }
            backing.IsHitTestVisible(false);
            fill.IsHitTestVisible(false);
            surface.IsHitTestVisible(false);
            if (foundation) backing.Children().Append(foundation);
            backing.Children().Append(fill);
            backing.Children().Append(surface);
            owner.Children().Append(backing);
        }
        void close() { if (foundation) foundation.SystemBackdrop(nullptr); }
        void measure(winrt::Windows::Foundation::Size available) { backing.Measure(available); }
        void arrange(winrt::Windows::Foundation::Size size) { backing.Arrange({0, 0, size.Width, size.Height}); }
        void paint(xaml::FrameworkElement const &self,
                   std::vector<winrt::Windows::Foundation::Rect> const &next,
                   xaml::Media::Brush const &brush) {
            namespace composition = winrt::Microsoft::UI::Composition;
            // A post-layout commit must not rewrite XAML Path.Data. If a
            // subsequent native operation fails, rewriting that Data at the
            // next LayoutUpdated creates a self-sustaining layout cycle.
            // Prepare a replacement entirely in Composition, then publish it.
            if (next != regions || !regionClip || !controlsClip) {
                std::vector<double> commands;
                for (auto const &rect : next) {
                    commands.insert(commands.end(), {0, rect.X, rect.Y,
                        1, rect.X + rect.Width, rect.Y, 1, rect.X + rect.Width, rect.Y + rect.Height,
                        1, rect.X, rect.Y + rect.Height, 4});
                }
                auto visual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(backing);
                auto compositor = visual.Compositor();
                auto path = compositionPath(pathGeometry(commands.data(), static_cast<int32_t>(commands.size()), false).as<ID2D1Geometry>(), false);
                auto geometry = compositor.CreatePathGeometry(path);
                auto materialClip = compositor.CreateGeometricClip(geometry);
                // Each visual owns its clip; the immutable geometry is shared.
                auto fixedClip = compositor.CreateGeometricClip(geometry);
                visual.Clip(materialClip);
                regionClip = materialClip;
                controlsClip = fixedClip;
                regions = next;
            }
            if (surface.Background() != brush) surface.Background(brush);
            auto background = acrylicFoundationFill(self);
            if (fill.Background() != background) fill.Background(background);
            if (!foundationFailed && self.IsLoaded() && !next.empty()) {
                try {
                    auto backdrop = acrylicFoundationBackdrop(self);
                    if (foundation.SystemBackdrop() != backdrop) foundation.SystemBackdrop(backdrop);
                } catch (...) {
                    foundationFailed = true;
                    report("connecting a bar's native Mica foundation");
                }
            }
            // Underlay stays in ordinary Measure/Arrange while empty. Opacity
            // changes rendering only and never defers its first real size.
            const double opacity = !next.empty() && !foundationFailed ? 1 : 0;
            if (foundation && foundation.Opacity() != opacity) foundation.Opacity(opacity);
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
            IInspectable self = *this;
            drawing.mount(self.as<controls::Panel>());
            Loaded([this](auto const &, auto const &) { refresh(); });
            Unloaded([this](auto const &, auto const &) { material.reset(); drawing.close(); observed.reset(); });
        }
        void refresh() {
            try {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                auto brush = material.update(self, extent);
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
                // Resting markers join the window union. A transitioning
                // ancestor owns this native layer again, so background and
                // controls move/fade together without a second animation.
                std::vector<winrt::Windows::Foundation::Rect> next;
                const bool local = scene && (!acrylicSceneIsWindow(scene)
                    || acrylicUsesLocalPresentation(self, acrylicSceneRoot(scene)));
                if (local && extent.Width > 0 && extent.Height > 0)
                    next.push_back({0, 0, extent.Width, extent.Height});
                drawing.paint(self, next, next.empty() ? nullptr : brush);
            } catch (...) { report("updating a safe bar material"); }
        }
        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size available) {
            drawing.measure(available); return {0, 0};
        }
        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) {
            extent = final; drawing.arrange(final);
            if (IsLoaded()) refresh();
            return final;
        }
    };
}

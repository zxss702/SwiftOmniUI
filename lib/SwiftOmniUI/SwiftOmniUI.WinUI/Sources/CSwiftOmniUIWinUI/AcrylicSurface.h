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
        winrt::Windows::Foundation::Rect samplingBounds() const;
        void resolve(xaml::FrameworkElement const &target);
    };

    struct FilteredContent;
    struct AcrylicStrip {
        std::shared_ptr<FilteredContent> filter;
        winrt::Microsoft::UI::Composition::CompositionSurfaceBrush crop{nullptr};
        winrt::Microsoft::UI::Composition::SpriteVisual visual{nullptr};
        void paint(xaml::FrameworkElement const &target, std::shared_ptr<AcrylicScene> const &scene,
                   winrt::Windows::Foundation::Rect const &rect);
    };

    winrt::Microsoft::UI::Composition::CompositionEffectBrush contentBlur(
        winrt::Microsoft::UI::Composition::Compositor const &compositor,
        winrt::Microsoft::UI::Composition::CompositionBrush const &source, float sigma);

    // Mica replaces the sharp drawing inside the material region. Only clean
    // content enters the transparent blur above it. The external Mica link is
    // never captured or replaced by an approximate white/grey colour.
    struct AcrylicLayer {
        controls::SystemBackdropElement foundation{nullptr};
        controls::Grid backing, base;
        controls::Border fill, surface;
        std::vector<winrt::Windows::Foundation::Rect> regions;
        winrt::Microsoft::UI::Composition::CompositionGeometricClip regionClip{nullptr}, controlsClip{nullptr};
        winrt::Microsoft::UI::Composition::ContainerVisual output{nullptr};
        std::vector<AcrylicStrip> strips;
        bool foundationFailed = false;

        bool usesFoundation = true;
        void mount(controls::Panel const &owner, bool withFoundation = true) {
            usesFoundation = withFoundation;
            try {
                if (withFoundation) {
                    foundation = controls::SystemBackdropElement();
                    foundation.IsHitTestVisible(false);
                    foundation.Opacity(0);
                }
            } catch (...) {
                foundationFailed = true;
                report("creating the optional bar Mica foundation");
            }
            backing.IsHitTestVisible(false);
            base.IsHitTestVisible(false);
            fill.IsHitTestVisible(false);
            surface.IsHitTestVisible(false);
            if (foundation) base.Children().Append(foundation);
            base.Children().Append(fill);
            backing.Children().Append(base);
            backing.Children().Append(surface);
            owner.Children().Append(backing);
        }
        void close() { if (foundation) foundation.SystemBackdrop(nullptr); }
        void clear() {
            close();
            backing.Opacity(0);
            fill.Background(nullptr);
            if (output) output.Children().RemoveAll();
            strips.clear();
            regions.clear();
            regionClip = nullptr;
            controlsClip = nullptr;
        }
        void measure(winrt::Windows::Foundation::Size available) { backing.Measure(available); }
        void arrange(winrt::Windows::Foundation::Size size) { backing.Arrange({0, 0, size.Width, size.Height}); }
        void paint(xaml::FrameworkElement const &self,
                   std::vector<AcrylicBand> const &bands,
                   std::shared_ptr<AcrylicScene> const &scene, bool useFoundation = true) {
            namespace composition = winrt::Microsoft::UI::Composition;
            auto next = acrylicMaterialRegions(bands);
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
                auto visual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(base);
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
            const bool hasFoundation = usesFoundation && useFoundation;
            // FlyoutPresenter already owns the popover's acrylic. A second
            // content blur here would sample the card below and tint the bar
            // differently from the presenter behind the rest of the card.
            if (hasFoundation && scene && !next.empty()) {
                if (!output) {
                    auto compositor = xaml::Hosting::ElementCompositionPreview::GetElementVisual(surface).Compositor();
                    output = compositor.CreateContainerVisual();
                    output.IsHitTestVisible(false);
                    xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(surface, output);
                }
                size_t index = 0;
                for (auto const &rect : next) {
                    if (index == strips.size()) strips.emplace_back();
                    auto &strip = strips[index++];
                    const bool add = !strip.visual;
                    strip.paint(self, scene, rect);
                    if (add && strip.visual) output.Children().InsertAtTop(strip.visual);
                }
                while (strips.size() > index) {
                    if (strips.back().visual) output.Children().Remove(strips.back().visual);
                    strips.pop_back();
                }
            } else if (!strips.empty()) {
                output.Children().RemoveAll();
                strips.clear();
            }
            auto background = hasFoundation ? acrylicFoundationFill(self) : nullptr;
            if (fill.Background() != background) fill.Background(background);
            if (foundation && !foundationFailed && self.IsLoaded() && (!hasFoundation || !next.empty())) {
                try {
                    auto backdrop = hasFoundation ? acrylicFoundationBackdrop(self) : nullptr;
                    if (foundation.SystemBackdrop() != backdrop) foundation.SystemBackdrop(backdrop);
                } catch (...) {
                    foundationFailed = true;
                    report("connecting a bar's native Mica foundation");
                }
            }
            // Underlay stays in ordinary Measure/Arrange while empty. Opacity
            // changes rendering only and never defers its first real size.
            const double opacity = hasFoundation && !next.empty() && !foundationFailed ? 1 : 0;
            if (foundation && foundation.Opacity() != opacity) foundation.Opacity(opacity);
            if (backing.Opacity() != 1) backing.Opacity(1);
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
                // Window markers join the shared surface unless their subtree
                // owns an effect that must also apply to the material.
                std::vector<AcrylicBand> next;
                const bool local = scene && (!acrylicSceneIsWindow(scene)
                    || acrylicUsesLocalPresentation(self, acrylicSceneRoot(scene)));
                if (local && extent.Width > 0 && extent.Height > 0) {
                    auto root = acrylicSceneRoot(scene);
                    auto mapping = self.TransformToVisual(root);
                    if (auto inverse = mapping.Inverse()) {
                        next = acrylicLocalRegions(scene, self, mapping.TransformBounds({0, 0, extent.Width, extent.Height}));
                        for (auto &band : next) {
                            band.rect = inverse.TransformBounds(band.rect);
                        }
                    }
                }
                // A popover supplies one background behind both its bar and body,
                // even though the presenter can share the window's XamlRoot.
                bool useFoundation = true;
                if (scene && !acrylicSceneIsWindow(scene)) {
                    for (auto parent = xaml::Media::VisualTreeHelper::GetParent(self); parent;
                         parent = xaml::Media::VisualTreeHelper::GetParent(parent)) {
                        if (parent.try_as<controls::FlyoutPresenter>()) {
                            useFoundation = false;
                            break;
                        }
                    }
                }
                drawing.paint(self, next, scene, useFoundation);
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

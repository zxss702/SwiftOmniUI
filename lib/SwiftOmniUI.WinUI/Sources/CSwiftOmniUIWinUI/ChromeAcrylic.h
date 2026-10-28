// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "AcrylicSurface.h"
#include <algorithm>

namespace swiftomniui {
    // One window-wide union for toolbar, promoted bars and resting page strips.
    // The system Mica underlay and the filtered content have the identical mask.
    struct ChromeAcrylic : controls::PanelT<ChromeAcrylic> {
        AcrylicLayer drawing;
        AcrylicSource material;
        winrt::Windows::Foundation::Size extent{};
        xaml::FrameworkElement::LayoutUpdated_revoker layoutCommitted;
        bool committing = false;
        winrt::Microsoft::UI::Composition::ContainerVisual fixedControls{nullptr};
        struct Bar {
            winrt::weak_ref<xaml::FrameworkElement> element;
            winrt::Microsoft::UI::Composition::CompositionVisualSurface capture{nullptr};
            winrt::Microsoft::UI::Composition::CompositionSurfaceBrush brush{nullptr};
            winrt::Microsoft::UI::Composition::SpriteVisual visual{nullptr};
        };
        std::vector<Bar> bars;
        void paintControls(xaml::FrameworkElement const &self) {
            namespace composition = winrt::Microsoft::UI::Composition;
            auto compositor = xaml::Hosting::ElementCompositionPreview::GetElementVisual(self).Compositor();
            if (!fixedControls) {
                fixedControls = compositor.CreateContainerVisual();
                xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(self, fixedControls);
            }
            auto elements = drawing.regions.empty() ? std::vector<xaml::FrameworkElement>{}
                : acrylicSceneBars(material.scene());
            auto previous = std::move(bars);
            bars.clear();
            for (auto const &element : elements) {
                auto old = std::find_if(previous.begin(), previous.end(), [&](auto const &bar) { return bar.element.get() == element; });
                Bar bar;
                if (old != previous.end()) { bar = std::move(*old); previous.erase(old); }
                else {
                    bar.element = winrt::make_weak(element);
                    bar.capture = compositor.CreateVisualSurface();
                    auto visual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(element);
                    bar.capture.SourceVisual(visual);
                    bar.brush = compositor.CreateSurfaceBrush(bar.capture);
                    bar.brush.Stretch(composition::CompositionStretch::None);
                    bar.brush.HorizontalAlignmentRatio(0);
                    bar.brush.VerticalAlignmentRatio(0);
                    bar.visual = compositor.CreateSpriteVisual();
                    bar.visual.Brush(bar.brush);
                    bar.visual.IsHitTestVisible(false);
                }
                const auto size = element.ActualSize();
                const auto visible = acrylicVisibleBounds(element, self);
                const auto clipped = acrylicLocalClip(element, self, visible);
                const auto opacity = acrylicPresentationOpacity(element, self);
                const bool shown = clipped.Width > 0 && clipped.Height > 0 && opacity > 0;
                if (bar.visual.IsVisible() != shown) bar.visual.IsVisible(shown);
                if (bar.visual.Opacity() != opacity) bar.visual.Opacity(opacity);
                auto clip = bar.visual.Clip().try_as<composition::InsetClip>();
                if (!clip) { clip = compositor.CreateInsetClip(); bar.visual.Clip(clip); }
                const float left = std::max(0.0f, clipped.X);
                const float top = std::max(0.0f, clipped.Y);
                const float right = std::max(0.0f, size.x - clipped.X - clipped.Width);
                const float bottom = std::max(0.0f, size.y - clipped.Y - clipped.Height);
                if (clip.LeftInset() != left) clip.LeftInset(left);
                if (clip.TopInset() != top) clip.TopInset(top);
                if (clip.RightInset() != right) clip.RightInset(right);
                if (clip.BottomInset() != bottom) clip.BottomInset(bottom);
                if (bar.capture.SourceSize() != size) bar.capture.SourceSize(size);
                const auto matrix = acrylicPresentationMatrix(element, self);
                if (bar.visual.TransformMatrix() != matrix) bar.visual.TransformMatrix(matrix);
                if (bar.visual.Size() != size) bar.visual.Size(size);
                bars.push_back(std::move(bar));
            }
            bool changed = fixedControls.Children().Count() != bars.size();
            if (!changed) {
                auto at = fixedControls.Children().First();
                for (auto const &bar : bars) {
                    if (!at.HasCurrent() || at.Current() != bar.visual) { changed = true; break; }
                    at.MoveNext();
                }
            }
            if (changed) {
                fixedControls.Children().RemoveAll();
                for (auto const &bar : bars) fixedControls.Children().InsertAtTop(bar.visual);
            }
            // Native controls keep input, focus and automation in their real
            // tree. Redirection draws them above the unified material only
            // inside its mask; outside it they retain their native drawing.
            if (fixedControls.Clip() != drawing.controlsClip) fixedControls.Clip(drawing.controlsClip);
            for (auto &old : previous) old.capture.SourceVisual(nullptr);
        }
        ChromeAcrylic() {
            Tag(winrt::box_value(L"chromeAcrylic"));
            IsHitTestVisible(false);
            UseLayoutRounding(false);
            IInspectable self = *this;
            drawing.mount(self.as<controls::Panel>());
            Loaded([this](auto const &, auto const &) {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                auto weak = get_weak();
                // The one region owner observes the native post-layout boundary.
                // No per-bar size/load subscriptions or presentation-frame retries.
                layoutCommitted = self.LayoutUpdated(winrt::auto_revoke, [weak](auto const &, auto const &) {
                    auto self = weak.get();
                    if (!self || self->committing) return;
                    self->committing = true;
                    self->refresh();
                    self->committing = false;
                });
            });
            Unloaded([this](auto const &, auto const &) {
                layoutCommitted.revoke(); material.reset(); drawing.close();
                for (auto &bar : bars) bar.capture.SourceVisual(nullptr);
                bars.clear();
                if (fixedControls) fixedControls.Children().RemoveAll();
            });
        }
        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size available) {
            drawing.measure(available); return {0, 0};
        }
        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) {
            extent = final; drawing.arrange(final); return final;
        }
        void refresh() {
            char const *operation = "locating the shared material's native content";
            try {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                auto grid = xaml::Media::VisualTreeHelper::GetParent(self).try_as<controls::Grid>();
                if (!grid || !self.IsLoaded()) return;
                xaml::FrameworkElement source{nullptr};
                std::vector<winrt::Windows::Foundation::Rect> next;
                auto append = [&](xaml::FrameworkElement const &element) {
                    if (!element.IsLoaded() || element.Visibility() != xaml::Visibility::Visible
                        || element.ActualWidth() <= 0 || element.ActualHeight() <= 0) return;
                    auto visible = element.Resources().TryLookup(winrt::box_value(L"safeBarAcrylic"));
                    if (visible && !winrt::unbox_value<bool>(visible)) return;
                    auto rect = acrylicVisibleBounds(element, self);
                    if (rect.Width > 0 && rect.Height > 0) next.push_back(rect);
                };
                for (auto const &child : grid.Children()) {
                    auto element = child.as<xaml::FrameworkElement>();
                    auto tag = winrt::unbox_value_or<winrt::hstring>(element.Tag(), L"");
                    if (tag == L"safeAreaBars" && element.Visibility() == xaml::Visibility::Visible) {
                        auto stack = element.as<controls::Grid>().Children().GetAt(0).as<controls::StackPanel>();
                        for (auto const &bar : stack.Children()) append(bar.as<xaml::FrameworkElement>());
                    } else if (!isLayer(element) && controls::Grid::GetRow(element) < 3) append(element);
                    else if (!isLayer(element) && controls::Grid::GetRow(element) == 3) source = element;
                }
                material.source(source);
                operation = "updating the shared material's clean content filter";
                auto brush = material.update(self, extent);
                operation = "resolving the shared material's local regions";
                auto local = acrylicSceneRegions(material.scene());
                next.insert(next.end(), local.begin(), local.end());
                operation = "publishing the shared material's composition region";
                drawing.paint(self, next, brush);
                operation = "redirecting fixed controls above the shared material";
                paintControls(self);
            } catch (...) { report(operation); }
        }
    };
    inline void refreshWindowMaterial(controls::Grid const &grid) {
        for (auto const &child : grid.Children()) {
            auto element = child.as<xaml::FrameworkElement>();
            if (winrt::unbox_value_or<winrt::hstring>(element.Tag(), L"") == L"chromeAcrylic") {
                auto layer = winrt::get_self<ChromeAcrylic>(element.as<xaml::IFrameworkElementOverrides>());
                if (element.IsLoaded()) layer->refresh();
                return;
            }
        }
    }

}

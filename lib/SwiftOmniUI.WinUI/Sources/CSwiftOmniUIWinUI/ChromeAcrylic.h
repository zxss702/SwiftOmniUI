// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "AcrylicSurface.h"
#include <algorithm>
#include <array>

namespace swiftomniui {
    // Lives INSIDE the real native column slot. SplitView's template owns its
    // visibility, translation, opacity and moving clip, including the toolbar
    // slice. No second animation or per-frame geometry mirroring is needed.
    struct ColumnAcrylic : controls::PanelT<ColumnAcrylic> {
        AcrylicLayer drawing;
        AcrylicSource material;
        winrt::weak_ref<controls::Panel> nativeOwner;
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
                fixedControls.BorderMode(composition::CompositionBorderMode::Soft);
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
                    // Fixed controls are full-detail content, not the reduced
                    // blur input. Preserve antialiased alpha during fractional
                    // placement/scaling of the captured labels and capsules.
                    bar.brush.BitmapInterpolationMode(composition::CompositionBitmapInterpolationMode::Linear);
                    bar.brush.Stretch(composition::CompositionStretch::None);
                    bar.brush.HorizontalAlignmentRatio(0);
                    bar.brush.VerticalAlignmentRatio(0);
                    bar.visual = compositor.CreateSpriteVisual();
                    bar.visual.BorderMode(composition::CompositionBorderMode::Soft);
                    bar.visual.Brush(bar.brush);
                    bar.visual.IsHitTestVisible(false);
                }
                const auto size = element.ActualSize();
                const auto owner = nativeOwner.get();
                const auto visible = owner.TransformToVisual(self).TransformBounds(acrylicVisibleBounds(element, owner));
                const auto clipped = acrylicLocalClip(element, self, visible);
                const auto opacity = acrylicPresentationOpacity(element, nativeOwner.get());
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
        ColumnAcrylic() {
            Tag(winrt::box_value(L"columnAcrylic"));
            IsHitTestVisible(false);
            UseLayoutRounding(false);
            IInspectable self = *this;
            drawing.mount(self.as<controls::Panel>());
            Unloaded([this](auto const &, auto const &) { clear(); });
        }
        void clear() {
            material.reset(); drawing.clear();
            for (auto &bar : bars) bar.capture.SourceVisual(nullptr);
            bars.clear();
            if (fixedControls) fixedControls.Children().RemoveAll();
        }
        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size available) {
            drawing.measure(available); return {0, 0};
        }
        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) {
            drawing.arrange(final); return final;
        }
        void refresh(xaml::FrameworkElement const &root, xaml::FrameworkElement const &source,
                     std::vector<winrt::Windows::Foundation::Rect> const &chrome) {
            IInspectable projected = *this;
            auto self = projected.as<xaml::FrameworkElement>();
            material.source(source);
            auto size = self.ActualSize();
            if (!self.IsLoaded() || size.x <= 0 || size.y <= 0) return;
            auto brush = material.update(self, {size.x, size.y});
            auto scope = material.scene();
            std::vector<winrt::Windows::Foundation::Rect> regions;
            if (scope) {
                const auto bounds = acrylicSceneBounds(scope);
                auto local = acrylicSceneRegions(scope);
                const auto scopeRoot = acrylicSceneRoot(scope);
                // Window toolbar geometry is layout input. Do not subtract
                // PaneTransform's current animation sample: the native parent
                // will move/clip the complete column layer itself.
                const auto slot = acrylicLayoutBounds(scopeRoot, root);
                for (auto rect : chrome) {
                    rect.X -= slot.X; rect.Y -= slot.Y;
                    local.push_back(rect);
                }
                auto mapping = scopeRoot.TransformToVisual(self);
                for (auto const &rect : local) {
                    auto x = std::max(rect.X, bounds.X), y = std::max(rect.Y, bounds.Y);
                    auto right = std::min(rect.X + rect.Width, bounds.X + bounds.Width);
                    auto bottom = std::min(rect.Y + rect.Height, bounds.Y + bounds.Height);
                    if (right > x && bottom > y) regions.push_back(mapping.TransformBounds({x, y, right - x, bottom - y}));
                }
            }
            drawing.paint(self, regions, brush);
            paintControls(self);
        }
    };

    // Coordinates registration at the existing native post-layout boundary.
    // The window overlay no longer owns column pixels or their animation.
    struct ChromeAcrylic : controls::PanelT<ChromeAcrylic> {
        std::array<winrt::com_ptr<ColumnAcrylic>, 3> columns;
        // Diagnostics are a snapshot only; never use them to draw another union.
        std::vector<winrt::Windows::Foundation::Rect> regions;
        xaml::FrameworkElement::LayoutUpdated_revoker layoutCommitted;
        bool committing = false;
        ChromeAcrylic() {
            Tag(winrt::box_value(L"chromeAcrylic"));
            IsHitTestVisible(false);
            UseLayoutRounding(false);
            for (auto &column : columns) column = winrt::make_self<ColumnAcrylic>();
            Loaded([this](auto const &, auto const &) {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                auto weak = get_weak();
                layoutCommitted = self.LayoutUpdated(winrt::auto_revoke, [weak](auto const &, auto const &) {
                    auto self = weak.get();
                    if (self) self->refresh();
                });
            });
            Unloaded([this](auto const &, auto const &) {
                layoutCommitted.revoke();
                for (auto &column : columns) unmount(*column.get());
                regions.clear();
            });
        }
        static void unmount(ColumnAcrylic &column) {
            IInspectable projected = column;
            auto element = projected.as<xaml::FrameworkElement>();
            if (auto owner = column.nativeOwner.get()) {
                uint32_t index;
                if (owner.Children().IndexOf(element, index)) owner.Children().RemoveAt(index);
            }
            column.nativeOwner = {};
            column.clear();
        }
        void mount(ColumnAcrylic &column, controls::Panel const &owner) {
            IInspectable projected = column;
            auto element = projected.as<xaml::FrameworkElement>();
            // Native slot clearing/template replacement can detach the panel
            // while the retained logical owner is unchanged.
            if (column.nativeOwner.get() == owner && xaml::Media::VisualTreeHelper::GetParent(element) == owner) return;
            unmount(column);
            controls::Grid::SetRow(element, 0);
            auto grid = owner.try_as<controls::Grid>();
            controls::Grid::SetRowSpan(element, grid ? std::max(1, static_cast<int>(grid.RowDefinitions().Size())) : 1);
            controls::Canvas::SetZIndex(element, 1);
            column.nativeOwner = winrt::make_weak(owner);
            owner.Children().Append(element);
        }
        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size available) {
            for (auto const &child : Children()) child.Measure(available);
            return {0, 0};
        }
        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) {
            for (auto const &child : Children()) child.Arrange({0, 0, final.Width, final.Height});
            return final;
        }
        void refresh() {
            if (committing) return;
            committing = true;
            try {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                auto grid = xaml::Media::VisualTreeHelper::GetParent(self).try_as<controls::Grid>();
                if (grid && self.IsLoaded()) {
                    std::vector<winrt::Windows::Foundation::Rect> chrome;
                    auto append = [&](xaml::FrameworkElement const &element) {
                        if (!element.IsLoaded() || element.Visibility() != xaml::Visibility::Visible) return;
                        auto visible = element.Resources().TryLookup(winrt::box_value(L"safeBarAcrylic"));
                        if (visible && !winrt::unbox_value<bool>(visible)) return;
                        auto rect = acrylicVisibleBounds(element, grid);
                        if (rect.Width > 0 && rect.Height > 0) chrome.push_back(rect);
                    };
                    for (auto const &child : grid.Children()) {
                        auto element = child.as<xaml::FrameworkElement>();
                        auto tag = winrt::unbox_value_or<winrt::hstring>(element.Tag(), L"");
                        if (tag == L"safeAreaBars" && element.Visibility() == xaml::Visibility::Visible) {
                            auto stack = element.as<controls::Grid>().Children().GetAt(0).as<controls::StackPanel>();
                            for (auto const &bar : stack.Children()) append(bar.as<xaml::FrameworkElement>());
                        } else if (!isLayer(element) && controls::Grid::GetRow(element) < 3) append(element);
                    }
                    const auto sources = acrylicWindowColumns(grid);
                    regions.clear();
                    for (size_t index = 0; index < columns.size(); ++index) {
                        auto &column = *columns[index].get();
                        auto source = index < sources.size() ? sources[index] : xaml::FrameworkElement{nullptr};
                        auto owner = source ? acrylicColumnOwner(source, grid) : controls::Panel{nullptr};
                        if (!owner && source) owner = projected.as<controls::Panel>(); // standalone NavigationStack
                        if (!owner) { unmount(column); continue; }
                        mount(column, owner);
                        column.refresh(grid, source, chrome);
                        if (!column.drawing.regions.empty()) {
                            IInspectable surface = column;
                            auto mapping = surface.as<xaml::FrameworkElement>().TransformToVisual(self);
                            for (auto const &rect : column.drawing.regions) regions.push_back(mapping.TransformBounds(rect));
                        }
                    }
                }
            } catch (...) { report("committing native column material ownership"); }
            committing = false;
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

// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "AcrylicSurface.h"
#include <algorithm>
#include <array>

namespace swiftomniui {
    struct ChromeMaterialRegion {
        winrt::Windows::Foundation::Rect rect{};
        AcrylicChromeMode mode = AcrylicChromeMode::safeBar;
    };
    // Lives INSIDE the real native column slot. SplitView's template owns its
    // visibility, translation, opacity and moving clip, including the toolbar
    // slice. No second animation or per-frame geometry mirroring is needed.
    struct ColumnAcrylic : controls::PanelT<ColumnAcrylic> {
        AcrylicLayer drawing;
        AcrylicSource material;
        winrt::weak_ref<controls::Panel> nativeOwner;
        ColumnAcrylic() {
            Tag(winrt::box_value(L"columnAcrylic"));
            IsHitTestVisible(false);
            UseLayoutRounding(false);
            Unloaded([this](auto const &, auto const &) { clear(); });
        }
        void clear() {
            material.reset(); drawing.clear();
        }
        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size) { return {0, 0}; }
        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) { return final; }
        void refresh(xaml::FrameworkElement const &root, xaml::FrameworkElement const &source,
                     std::vector<ChromeMaterialRegion> const &chrome, bool afterLayout) {
            IInspectable projected = *this;
            auto self = projected.as<xaml::FrameworkElement>();
            material.source(source);
            auto size = self.ActualSize();
            if (!self.IsLoaded() || size.x <= 0 || size.y <= 0) return;
            material.resolve(self);
            auto scope = material.scene();
            std::vector<AcrylicBand> regions;
            if (scope) {
                // Resolve scroll edges after the same layout used for the column bounds.
                commitAcrylicScene(scope, afterLayout);
                regions = acrylicColumnInsets(scope);
                const auto bounds = acrylicSceneBounds(scope);
                const auto scopeRoot = acrylicSceneRoot(scope);
                // Window toolbar geometry is layout input. Do not subtract
                // PaneTransform's current animation sample: the native parent
                // will move/clip the complete column layer itself.
                const auto slot = acrylicLayoutBounds(scopeRoot, root);
                for (auto const &region : chrome) {
                    auto rect = region.rect;
                    rect.X -= slot.X; rect.Y -= slot.Y;
                    auto x = std::max(rect.X, bounds.X), y = std::max(rect.Y, bounds.Y);
                    auto right = std::min(rect.X + rect.Width, bounds.X + bounds.Width);
                    auto bottom = std::min(rect.Y + rect.Height, bounds.Y + bounds.Height);
                    if (right <= x || bottom <= y) continue;
                    auto bands = acrylicChromeRegions(scope, {x, y, right - x, bottom - y}, region.mode);
                    regions.insert(regions.end(), bands.begin(), bands.end());
                }
                auto mapping = scopeRoot.TransformToVisual(self);
                for (auto &band : regions) {
                    band.rect = mapping.TransformBounds(band.rect);
                }
            }
            drawing.paint(self, regions);
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
                    if (self) self->refresh(true);
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
        void refresh(bool afterLayout = false) {
            if (committing) return;
            committing = true;
            try {
                IInspectable projected = *this;
                auto self = projected.as<xaml::FrameworkElement>();
                auto grid = xaml::Media::VisualTreeHelper::GetParent(self).try_as<controls::Grid>();
                if (grid && self.IsLoaded()) {
                    std::vector<ChromeMaterialRegion> chrome;
                    auto append = [&](xaml::FrameworkElement const &element) {
                        if (!element.IsLoaded() || element.Visibility() != xaml::Visibility::Visible) return;
                        auto visible = element.Resources().TryLookup(winrt::box_value(L"safeBarAcrylic"));
                        if (visible && !winrt::unbox_value<bool>(visible)) return;
                        const auto mode = element.try_as<controls::TitleBar>()
                            ? acrylicTitleBarMode(element) : AcrylicChromeMode::safeBar;
                        if (mode == AcrylicChromeMode::hidden) return;
                        // Use layout coordinates here. Visible bounds include
                        // the current SplitView clip, so the material briefly
                        // disappears while a sidebar is entering. The column
                        // host supplies the real clip and animation later.
                        auto rect = acrylicLayoutBounds(element, grid);
                        const auto room = grid.ActualSize();
                        const float left = std::max(0.0f, rect.X);
                        const float top = std::max(0.0f, rect.Y);
                        const float right = std::min(static_cast<float>(room.x), rect.X + rect.Width);
                        const float bottom = std::min(static_cast<float>(room.y), rect.Y + rect.Height);
                        rect = {left, top, std::max(0.0f, right - left), std::max(0.0f, bottom - top)};
                        if (rect.Width > 0 && rect.Height > 0) chrome.push_back({rect, mode});
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
                        column.refresh(grid, source, chrome, afterLayout);
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

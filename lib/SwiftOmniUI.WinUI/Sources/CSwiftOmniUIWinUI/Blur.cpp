// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#include "Relay.h"

#include <algorithm>
#include <cmath>
#include <cwchar>
#include <initguid.h>
#include <d2d1effects.h>
#include <windows.graphics.effects.interop.h>
#include <winrt/Windows.Graphics.Effects.h>
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>

using namespace swiftomniui;
namespace composition = winrt::Microsoft::UI::Composition;
namespace effects = winrt::Windows::Graphics::Effects;
namespace effectABI = ABI::Windows::Graphics::Effects;
using winrt::Windows::Foundation::Size;
using winrt::Windows::Foundation::Rect;

namespace {
    /// The documented Direct2D effect interop lets Composition consume a
    /// Gaussian blur without a Win2D package or a CPU bitmap of the view.
    struct GaussianBlur : winrt::implements<GaussianBlur, effects::IGraphicsEffect,
        effects::IGraphicsEffectSource, effectABI::IGraphicsEffectD2D1Interop> {
        winrt::hstring name = L"Blur";
        effects::IGraphicsEffectSource source = composition::CompositionEffectSourceParameter(L"Source");

        winrt::hstring Name() { return name; }
        void Name(winrt::hstring const &value) { name = value; }

        HRESULT __stdcall GetEffectId(GUID *id) noexcept override {
            if (!id) return E_POINTER;
            *id = CLSID_D2D1GaussianBlur;
            return S_OK;
        }
        HRESULT __stdcall GetNamedPropertyMapping(LPCWSTR property, UINT *index,
            effectABI::GRAPHICS_EFFECT_PROPERTY_MAPPING *mapping) noexcept override {
            if (!property || !index || !mapping) return E_POINTER;
            if (std::wcscmp(property, L"StandardDeviation") != 0) return E_INVALIDARG;
            *index = D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION;
            *mapping = effectABI::GRAPHICS_EFFECT_PROPERTY_MAPPING_DIRECT;
            return S_OK;
        }
        HRESULT __stdcall GetPropertyCount(UINT *count) noexcept override {
            if (!count) return E_POINTER;
            *count = 3;
            return S_OK;
        }
        HRESULT __stdcall GetProperty(UINT index, ABI::Windows::Foundation::IPropertyValue **value) noexcept override {
            if (!value) return E_POINTER;
            *value = nullptr;
            try {
                using winrt::Windows::Foundation::PropertyValue;
                IInspectable property{nullptr};
                switch (index) {
                case D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION: property = PropertyValue::CreateSingle(0); break;
                case D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION:
                    property = PropertyValue::CreateUInt32(D2D1_GAUSSIANBLUR_OPTIMIZATION_BALANCED); break;
                case D2D1_GAUSSIANBLUR_PROP_BORDER_MODE:
                    property = PropertyValue::CreateUInt32(D2D1_BORDER_MODE_SOFT); break;
                default: return E_INVALIDARG;
                }
                property.as<ABI::Windows::Foundation::IPropertyValue>().copy_to(value);
                return S_OK;
            } catch (...) { return winrt::to_hresult(); }
        }
        HRESULT __stdcall GetSource(UINT index, effectABI::IGraphicsEffectSource **value) noexcept override {
            if (!value) return E_POINTER;
            *value = nullptr;
            if (index != 0) return E_INVALIDARG;
            try {
                source.as<effectABI::IGraphicsEffectSource>().copy_to(value);
                return S_OK;
            } catch (...) { return winrt::to_hresult(); }
        }
        HRESULT __stdcall GetSourceCount(UINT *count) noexcept override {
            if (!count) return E_POINTER;
            *count = 1;
            return S_OK;
        }
    };

    composition::CompositionEffectFactory blurFactory(composition::Compositor const &compositor) {
        // Rows using a blur transition share the compiled effect graph. Each
        // presenter still owns its brush, radius and live source independently.
        static composition::CompositionEffectFactory held{nullptr};
        if (!held || held.Compositor() != compositor) {
            held = compositor.CreateEffectFactory(winrt::make<GaussianBlur>(), {L"Blur.StandardDeviation"});
        }
        return held;
    }

    /// The control keeps its own handle, events and native identity. Only a
    /// view asking for blur acquires this presentation boundary, retained at
    /// radius zero so animation never reparents controls frame by frame.
    struct BlurPresenter : controls::PanelT<BlurPresenter> {
        controls::Grid source;
        composition::Visual sourceVisual{nullptr};
        composition::CompositionVisualSurface surface{nullptr};
        composition::CompositionSurfaceBrush sourceBrush{nullptr};
        composition::CompositionEffectBrush brush{nullptr};
        composition::SpriteVisual output{nullptr};
        float radius = 0;
        float extent = 0;
        float writtenExtent = -1;
        Size size{0, 0};
        Size writtenSize{-1, -1};

        BlurPresenter() {
            UseLayoutRounding(false);
            HorizontalAlignment(xaml::HorizontalAlignment::Stretch);
            VerticalAlignment(xaml::VerticalAlignment::Stretch);
            source.UseLayoutRounding(false);
            Children().Append(source);
        }

        Size MeasureOverride(Size available) {
            source.Measure(available);
            return source.DesiredSize();
        }

        Size ArrangeOverride(Size final) {
            source.Arrange(Rect(0, 0, final.Width, final.Height));
            size = final;
            resizeSurface();
            return final;
        }

        void ensureEffect() {
            if (brush) return;
            sourceVisual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(source);
            auto compositor = sourceVisual.Compositor();
            surface = compositor.CreateVisualSurface();
            surface.SourceVisual(sourceVisual);
            sourceBrush = compositor.CreateSurfaceBrush(surface);
            sourceBrush.Stretch(composition::CompositionStretch::None);
            sourceBrush.HorizontalAlignmentRatio(0);
            sourceBrush.VerticalAlignmentRatio(0);
            brush = blurFactory(compositor).CreateBrush();
            brush.SetSourceParameter(L"Source", sourceBrush);
            output = compositor.CreateSpriteVisual();
            output.Brush(brush);
            output.IsHitTestVisible(false);
            IInspectable self = *this;
            xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(self.as<xaml::UIElement>(), output);
        }

        void resizeSurface() {
            if (!surface || radius == 0) return;
            if (extent == writtenExtent && size.Width == writtenSize.Width && size.Height == writtenSize.Height) return;
            // Soft borders spread alpha beyond the layout frame. Reserve the
            // Gaussian's native three-sigma extent without changing that frame.
            surface.SourceOffset({-extent, -extent});
            surface.SourceSize({size.Width + 2 * extent, size.Height + 2 * extent});
            output.Offset({-extent, -extent, 0});
            output.Size({size.Width + 2 * extent, size.Height + 2 * extent});
            writtenExtent = extent;
            writtenSize = size;
        }

        void setRadius(double value, double reserve) {
            auto next = static_cast<float>(std::isfinite(value) ? std::clamp(value, 0.0, 250.0) : 0);
            auto reach = static_cast<float>(std::isfinite(reserve) ? std::clamp(reserve, 0.0, 250.0) : 0);
            // Keep one surface window for the whole transition. Changing a
            // Gaussian's radius must not reallocate its source texture per frame.
            extent = std::max(extent, std::ceil(3 * std::max(next, reach)));
            if (next > 0) ensureEffect();
            if (brush && next != radius) brush.Properties().InsertScalar(L"Blur.StandardDeviation", next);
            radius = next;
            resizeSurface();
            if (output) output.IsVisible(next > 0);
            // As in Gallery's OpacityMaskView, VisualSurface omits only its
            // source root's opacity. Descendant opacity and input stay intact.
            if (sourceVisual) sourceVisual.Opacity(next > 0 ? 0 : 1);
        }

        void close() {
            if (!surface) return;
            IInspectable self = *this;
            xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(self.as<xaml::UIElement>(), nullptr);
            sourceVisual.Opacity(1);
            surface.SourceVisual(nullptr);
            sourceBrush.Surface(nullptr);
            output.Brush(nullptr);
            output = nullptr;
            brush = nullptr;
            surface = nullptr;
            sourceBrush = nullptr;
            sourceVisual = nullptr;
            radius = 0;
            writtenExtent = -1;
            writtenSize = Size(-1, -1);
        }
    };

    BlurPresenter *presenter(SwiftOmniUIObjectRef handle) {
        return winrt::get_self<BlurPresenter>(as<xaml::IFrameworkElementOverrides>(handle));
    }

    /// A modifier can first be added to an already mounted view. Find its
    /// owning slot before moving it, then replace that one slot atomically.
    std::function<void(xaml::UIElement const &)> slotOf(xaml::UIElement const &element) {
        auto parent = xaml::Media::VisualTreeHelper::GetParent(element);
        if (!parent) return {};
        // A templated ContentControl may insert a ContentPresenter between the
        // owner and its content. Prefer the logical owner to a template slot.
        for (auto at = parent; at; at = xaml::Media::VisualTreeHelper::GetParent(at)) {
            if (auto control = at.try_as<controls::ContentControl>(); control && control.Content() == element)
                return [control](auto const &next) { control.Content(next); };
            if (auto scroller = at.try_as<controls::ScrollView>(); scroller && scroller.Content() == element)
                return [scroller](auto const &next) { scroller.Content(next); };
            if (auto scroller = at.try_as<controls::ScrollViewer>(); scroller && scroller.Content() == element)
                return [scroller](auto const &next) { scroller.Content(next); };
            if (auto container = at.try_as<controls::ItemContainer>(); container && container.Child() == element)
                return [container](auto const &next) { container.Child(next); };
        }
        if (auto panel = parent.try_as<controls::Panel>()) {
            uint32_t index;
            if (panel.Children().IndexOf(element, index)) return [panel, index](auto const &next) {
                if (next) panel.Children().InsertAt(index, next);
                else panel.Children().RemoveAt(index);
            };
        }
        if (auto border = parent.try_as<controls::Border>(); border && border.Child() == element)
            return [border](auto const &next) { border.Child(next); };
        if (auto content = parent.try_as<controls::ContentPresenter>(); content && content.Content() == element)
            return [content](auto const &next) { content.Content(next); };
        throw winrt::hresult_error(E_NOTIMPL, L"The native parent has no replaceable blur presentation slot");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_blur_make(SwiftOmniUIObjectRef handle) {
    try {
        auto element = as<xaml::UIElement>(handle);
        auto slot = slotOf(element);
        auto made = winrt::make_self<BlurPresenter>();
        auto shown = made.as<xaml::UIElement>();
        auto placed = element.as<xaml::FrameworkElement>();
        // Copy parent-owned placement and move shared drawing to the new root.
        controls::Grid::SetRow(shown, controls::Grid::GetRow(placed));
        controls::Grid::SetColumn(shown, controls::Grid::GetColumn(placed));
        controls::Grid::SetRowSpan(shown, controls::Grid::GetRowSpan(placed));
        controls::Grid::SetColumnSpan(shown, controls::Grid::GetColumnSpan(placed));
        controls::Canvas::SetZIndex(shown, controls::Canvas::GetZIndex(element));
        shown.CanBeScrollAnchor(element.CanBeScrollAnchor());
        shown.Visibility(element.Visibility());
        shown.IsHitTestVisible(element.IsHitTestVisible());
        shown.Opacity(element.Opacity());
        shown.RenderTransform(element.RenderTransform());
        shown.Projection(element.Projection());
        if (slot) slot(nullptr);
        try {
            made->source.Children().Append(element);
            element.Opacity(1);
            element.Visibility(xaml::Visibility::Visible);
            element.IsHitTestVisible(true);
            element.CanBeScrollAnchor(false);
            element.RenderTransform(nullptr);
            element.Projection(nullptr);
            if (slot) slot(shown);
        } catch (...) {
            made->source.Children().Clear();
            element.Opacity(shown.Opacity());
            element.Visibility(shown.Visibility());
            element.IsHitTestVisible(shown.IsHitTestVisible());
            element.CanBeScrollAnchor(shown.CanBeScrollAnchor());
            element.RenderTransform(shown.RenderTransform());
            element.Projection(shown.Projection());
            if (slot) slot(element);
            throw;
        }
        return detach(shown);
    } catch (...) { report("making a blur presenter"); return nullptr; }
}

extern "C" bool swiftomniui_winui_blur_set(SwiftOmniUIObjectRef handle, double radius, double reserveRadius) {
    try { presenter(handle)->setRadius(radius, reserveRadius); return true; }
    catch (...) { report("setting a view's blur"); return false; }
}

extern "C" void swiftomniui_winui_blur_clear(SwiftOmniUIObjectRef handle) {
    try { presenter(handle)->close(); }
    catch (...) { report("releasing a view's blur"); }
}

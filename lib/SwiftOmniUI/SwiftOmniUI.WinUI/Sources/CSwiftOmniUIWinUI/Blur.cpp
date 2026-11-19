// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#include "Relay.h"
#include "AcrylicScene.h"
#include "AcrylicSurface.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cwchar>
#include <utility>
#include <vector>
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
                    property = PropertyValue::CreateUInt32(D2D1_GAUSSIANBLUR_OPTIMIZATION_SPEED); break;
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

    struct FixedEffect : winrt::implements<FixedEffect, effects::IGraphicsEffect,
        effects::IGraphicsEffectSource, effectABI::IGraphicsEffectD2D1Interop> {
        GUID id;
        winrt::hstring name;
        std::vector<winrt::Windows::Foundation::IPropertyValue> properties;
        std::vector<effects::IGraphicsEffectSource> sources;

        FixedEffect(GUID id, std::vector<winrt::Windows::Foundation::IPropertyValue> properties,
            std::vector<effects::IGraphicsEffectSource> sources)
            : id(id), properties(std::move(properties)), sources(std::move(sources)) {}

        winrt::hstring Name() { return name; }
        void Name(winrt::hstring const &value) { name = value; }

        HRESULT __stdcall GetEffectId(GUID *value) noexcept override {
            if (!value) return E_POINTER;
            *value = id;
            return S_OK;
        }
        HRESULT __stdcall GetNamedPropertyMapping(LPCWSTR, UINT *,
            effectABI::GRAPHICS_EFFECT_PROPERTY_MAPPING *) noexcept override { return E_INVALIDARG; }
        HRESULT __stdcall GetPropertyCount(UINT *count) noexcept override {
            if (!count) return E_POINTER;
            *count = static_cast<UINT>(properties.size());
            return S_OK;
        }
        HRESULT __stdcall GetProperty(UINT index, ABI::Windows::Foundation::IPropertyValue **value) noexcept override {
            if (!value) return E_POINTER;
            *value = nullptr;
            if (index >= properties.size()) return E_INVALIDARG;
            winrt::copy_to_abi(properties[index], *reinterpret_cast<void **>(value));
            return S_OK;
        }
        HRESULT __stdcall GetSourceCount(UINT *count) noexcept override {
            if (!count) return E_POINTER;
            *count = static_cast<UINT>(sources.size());
            return S_OK;
        }
        HRESULT __stdcall GetSource(UINT index, effectABI::IGraphicsEffectSource **value) noexcept override {
            if (!value) return E_POINTER;
            *value = nullptr;
            if (index >= sources.size()) return E_INVALIDARG;
            winrt::copy_to_abi(sources[index], *reinterpret_cast<void **>(value));
            return S_OK;
        }
    };

    composition::CompositionEffectFactory multiplyFactory(composition::Compositor const &compositor) {
        static composition::CompositionEffectFactory held{nullptr};
        if (held && held.Compositor() == compositor) return held;
        using winrt::Windows::Foundation::IPropertyValue;
        using winrt::Windows::Foundation::PropertyValue;

        // Multiply the premultiplied foreground by (background.rgb + 1 - background.a).
        // Keep foreground alpha so normal source-over accounts for the remaining backdrop once.
        const std::array<float, 20> matrix{
             1,  0,  0, 0,
             0,  1,  0, 0,
             0,  0,  1, 0,
            -1, -1, -1, 0,
             1,  1,  1, 1,
        };
        auto backdrop = winrt::make<FixedEffect>(CLSID_D2D1ColorMatrix,
            std::vector<IPropertyValue>{
                PropertyValue::CreateSingleArray(matrix).as<IPropertyValue>(),
                PropertyValue::CreateUInt32(D2D1_COLORMATRIX_ALPHA_MODE_STRAIGHT).as<IPropertyValue>(),
                PropertyValue::CreateBoolean(true).as<IPropertyValue>(),
            }, std::vector<effects::IGraphicsEffectSource>{composition::CompositionEffectSourceParameter(L"Backdrop")});
        const std::array<float, 4> coefficients{1, 0, 0, 0};
        auto multiply = winrt::make<FixedEffect>(CLSID_D2D1ArithmeticComposite,
            std::vector<IPropertyValue>{
                PropertyValue::CreateSingleArray(coefficients).as<IPropertyValue>(),
                PropertyValue::CreateBoolean(true).as<IPropertyValue>(),
            }, std::vector<effects::IGraphicsEffectSource>{
                winrt::make<GaussianBlur>().as<effects::IGraphicsEffectSource>(),
                backdrop.as<effects::IGraphicsEffectSource>(),
            });
        held = compositor.CreateEffectFactory(multiply, {L"Blur.StandardDeviation"});
        return held;
    }

    /// The control keeps its own handle, events and native identity. Only a
    /// view asking for blur or multiply acquires this presentation boundary.
    /// Retain the boundary so changing effects does not reparent controls.
    struct BlurPresenter : controls::PanelT<BlurPresenter> {
        controls::Grid source;
        composition::Visual sourceVisual{nullptr};
        composition::CompositionVisualSurface surface{nullptr};
        composition::CompositionSurfaceBrush sourceBrush{nullptr};
        composition::CompositionEffectBrush brush{nullptr}, blurBrush{nullptr}, multiplyBrush{nullptr};
        composition::SpriteVisual output{nullptr};
        float writtenRadius = -1;
        float extent = 0;
        Size size{0, 0};
        Rect writtenBounds{0, 0, -1, -1};
        xaml::FrameworkElement::EffectiveViewportChanged_revoker viewportChanged;
        Rect viewport{0, 0, -1, -1};
        bool active = false;

        BlurPresenter() {
            UseLayoutRounding(false);
            HorizontalAlignment(xaml::HorizontalAlignment::Stretch);
            VerticalAlignment(xaml::VerticalAlignment::Stretch);
            source.UseLayoutRounding(false);
            Children().Append(source);
        }

        ~BlurPresenter() {
            if (active && source) setAcrylicLocalPresentation(source, false);
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

        void ensureSurface() {
            if (output) return;
            sourceVisual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(source);
            auto compositor = sourceVisual.Compositor();
            surface = compositor.CreateVisualSurface();
            surface.SourceVisual(sourceVisual);
            sourceBrush = compositor.CreateSurfaceBrush(surface);
            sourceBrush.Stretch(composition::CompositionStretch::None);
            sourceBrush.HorizontalAlignmentRatio(0);
            sourceBrush.VerticalAlignmentRatio(0);
            output = compositor.CreateSpriteVisual();
            output.IsVisible(false);
            output.IsHitTestVisible(false);
            IInspectable self = *this;
            xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(self.as<xaml::UIElement>(), output);
        }

        Rect captureRoom() {
            auto root = XamlRoot();
            if (brush != multiplyBrush || !root) return Rect(0, 0, size.Width, size.Height);
            // Markdown selection can span a whole scroll document. Like the
            // native Canvas tiles, capture only the visible region of a large view.
            auto limit = static_cast<float>(8192 / std::max(root.RasterizationScale(), 1.0));
            if (size.Width <= limit && size.Height <= limit) return Rect(0, 0, size.Width, size.Height);
            if (!viewportChanged) {
                viewportChanged = EffectiveViewportChanged(winrt::auto_revoke,
                    guarded("updating the blend viewport", [weak = get_weak()](
                        xaml::FrameworkElement const &, xaml::EffectiveViewportChangedEventArgs const &args) {
                        if (auto self = weak.get()) {
                            self->viewport = args.EffectiveViewport();
                            self->resizeSurface();
                        }
                    }));
            }
            auto visible = viewport;
            if (!std::isfinite(visible.X) || !std::isfinite(visible.Y)
                || !std::isfinite(visible.Width) || !std::isfinite(visible.Height)
                || visible.Width < 0 || visible.Height < 0) {
                auto window = root.Size();
                visible = Rect(0, 0, window.Width, window.Height);
                if (auto inverse = TransformToVisual(nullptr).Inverse()) visible = inverse.TransformBounds(visible);
            }
            constexpr float quantum = 256;
            auto start = [](float edge, float size) { return std::clamp(std::floor(edge / quantum) * quantum - quantum, 0.0f, size); };
            auto end = [](float edge, float size) { return std::clamp(std::ceil(edge / quantum) * quantum + quantum, 0.0f, size); };
            auto x = start(visible.X, size.Width), y = start(visible.Y, size.Height);
            auto right = end(visible.X + visible.Width, size.Width), bottom = end(visible.Y + visible.Height, size.Height);
            return Rect(x, y, std::clamp(right - x, 0.0f, limit), std::clamp(bottom - y, 0.0f, limit));
        }

        void resizeSurface() {
            if (!surface || !active) return;
            auto room = captureRoom();
            // Soft borders spread alpha beyond the layout frame. Reserve the
            // Gaussian's native three-sigma extent without changing that frame.
            Rect bounds(room.X - extent, room.Y - extent, room.Width + 2 * extent, room.Height + 2 * extent);
            if (bounds == writtenBounds) return;
            surface.SourceOffset({bounds.X, bounds.Y});
            surface.SourceSize({bounds.Width, bounds.Height});
            output.Offset({bounds.X, bounds.Y, 0});
            output.Size({bounds.Width, bounds.Height});
            writtenBounds = bounds;
        }

        void setEffects(double value, double reserve, bool multiply) {
            auto next = static_cast<float>(std::isfinite(value) ? std::clamp(value, 0.0, 250.0) : 0);
            if (next < 0.005f) next = 0;
            auto reach = static_cast<float>(std::isfinite(reserve) ? std::clamp(reserve, 0.0, 250.0) : 0);
            const bool nowActive = next > 0 || multiply;
            if (!nowActive && !active) return;
            if (!multiply && viewportChanged) {
                viewportChanged.revoke();
                viewport = Rect(0, 0, -1, -1);
            }
            // Keep one surface window for the whole transition. Changing a
            // Gaussian's radius must not reallocate its source texture per frame.
            extent = std::max(extent, std::ceil(3 * std::max(next, reach)));
            if (nowActive) {
                ensureSurface();
                auto &selectedBrush = multiply ? multiplyBrush : blurBrush;
                if (!selectedBrush) {
                    auto compositor = sourceVisual.Compositor();
                    auto made = (multiply ? multiplyFactory(compositor) : blurFactory(compositor)).CreateBrush();
                    made.SetSourceParameter(L"Source", sourceBrush);
                    if (multiply) made.SetSourceParameter(L"Backdrop", compositor.CreateBackdropBrush());
                    selectedBrush = made;
                }
                if (brush != selectedBrush) {
                    output.Brush(selectedBrush);
                    brush = selectedBrush;
                    writtenRadius = -1;
                }
                if (!active) {
                    surface.SourceVisual(sourceVisual);
                    writtenBounds = Rect(0, 0, -1, -1);
                }
                if (writtenRadius < 0 || std::abs(next - writtenRadius) >= 0.01f) {
                    brush.Properties().InsertScalar(L"Blur.StandardDeviation", next);
                    writtenRadius = next;
                }
                if (!active) {
                    active = true;
                    resizeSurface();
                    output.IsVisible(true);
                    setAcrylicLocalPresentation(source, true);
                    // As in Gallery's OpacityMaskView, VisualSurface omits only its
                    // source root's opacity. Descendant opacity and input stay intact.
                    sourceVisual.Opacity(0);
                } else {
                    resizeSurface();
                }
            } else {
                active = false;
                writtenRadius = -1;
                if (output) output.IsVisible(false);
                if (sourceVisual) sourceVisual.Opacity(1);
                if (surface) {
                    surface.SourceVisual(nullptr);
                    surface.SourceSize({0, 0});
                }
                writtenBounds = Rect(0, 0, -1, -1);
                setAcrylicLocalPresentation(source, false);
            }
        }

        void close() {
            viewportChanged.revoke();
            viewport = Rect(0, 0, -1, -1);
            if (active) {
                active = false;
                setAcrylicLocalPresentation(source, false);
            }
            if (!surface) return;
            IInspectable self = *this;
            xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(self.as<xaml::UIElement>(), nullptr);
            sourceVisual.Opacity(1);
            surface.SourceVisual(nullptr);
            sourceBrush.Surface(nullptr);
            output.Brush(nullptr);
            output = nullptr;
            brush = nullptr;
            blurBrush = nullptr;
            multiplyBrush = nullptr;
            surface = nullptr;
            sourceBrush = nullptr;
            sourceVisual = nullptr;
            writtenRadius = -1;
            writtenBounds = Rect(0, 0, -1, -1);
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

namespace swiftomniui {
    composition::CompositionEffectBrush contentBlur(composition::Compositor const &compositor,
        composition::CompositionBrush const &source, float sigma) {
        auto brush = blurFactory(compositor).CreateBrush();
        brush.SetSourceParameter(L"Source", source);
        brush.Properties().InsertScalar(L"Blur.StandardDeviation", sigma);
        return brush;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_blur_make(SwiftOmniUIObjectRef handle) {
    try {
        auto element = as<xaml::UIElement>(handle);
        auto slot = slotOf(element);
        auto made = winrt::make_self<BlurPresenter>();
        auto shown = made.as<xaml::UIElement>();
        auto placed = element.as<xaml::FrameworkElement>();
        auto placement = shown.as<xaml::FrameworkElement>();
        // Copy parent-owned placement and move shared drawing to the new root.
        // Grid's attached properties require FrameworkElement on both sides;
        // the exported handle remains UIElement for the relay's content slots.
        controls::Grid::SetRow(placement, controls::Grid::GetRow(placed));
        controls::Grid::SetColumn(placement, controls::Grid::GetColumn(placed));
        controls::Grid::SetRowSpan(placement, controls::Grid::GetRowSpan(placed));
        controls::Grid::SetColumnSpan(placement, controls::Grid::GetColumnSpan(placed));
        controls::Canvas::SetZIndex(shown, controls::Canvas::GetZIndex(element));
        shown.CanBeScrollAnchor(element.CanBeScrollAnchor());
        shown.Visibility(element.Visibility());
        shown.IsHitTestVisible(element.IsHitTestVisible());
        shown.Opacity(element.Opacity());
        shown.RenderTransform(element.RenderTransform());
        shown.Projection(element.Projection());
        if (placed.ActualWidth() > 0 || placed.ActualHeight() > 0) {
            made->size = Size{static_cast<float>(placed.ActualWidth()), static_cast<float>(placed.ActualHeight())};
        }
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

extern "C" bool swiftomniui_winui_drawing_effects_set(
    SwiftOmniUIObjectRef handle, double radius, double reserveRadius, bool multiply) {
    try { presenter(handle)->setEffects(radius, reserveRadius, multiply); return true; }
    catch (...) { report("setting a view's drawing effects"); return false; }
}

extern "C" void swiftomniui_winui_blur_clear(SwiftOmniUIObjectRef handle) {
    try { presenter(handle)->close(); }
    catch (...) { report("releasing a view's blur"); }
}

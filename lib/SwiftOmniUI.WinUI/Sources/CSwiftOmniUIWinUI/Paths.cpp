// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Vector drawing has no native intrinsic extent. Updating its geometry during
// Arrange must not make XAML stop arranging the following content for Measure.
#include "Figure.h"
#include "PathGeometry.h"

#include <algorithm>
#include <cmath>
#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace swiftomniui;
using winrt::Windows::Foundation::Size;
namespace composition = winrt::Microsoft::UI::Composition;
namespace peers = winrt::Microsoft::UI::Xaml::Automation::Peers;

namespace {
    struct PathPanel : controls::PanelT<PathPanel> {
        explicit PathPanel(int64_t view) : view(view) {}
        int64_t view;
        composition::ShapeVisual drawing{nullptr};

        composition::CompositionSpriteShape prepareDrawing() {
            if (!drawing) {
                IInspectable self = *this;
                auto element = self.as<controls::Panel>();
                auto compositor = xaml::Hosting::ElementCompositionPreview::GetElementVisual(element).Compositor();
                drawing = compositor.CreateShapeVisual();
                drawing.Shapes().Append(compositor.CreateSpriteShape(compositor.CreatePathGeometry()));
                drawing.Size(element.ActualSize());
                xaml::Hosting::ElementCompositionPreview::SetElementChildVisual(element, drawing);
            }
            return drawing.Shapes().GetAt(0).as<composition::CompositionSpriteShape>();
        }

        peers::AutomationPeer OnCreateAutomationPeer() {
            IInspectable self = *this;
            return figurePeer(self.as<xaml::FrameworkElement>(), view);
        }

        Size MeasureOverride(Size) { return {0, 0}; }
        Size ArrangeOverride(Size final) {
            if (callbacks.arrange) callbacks.arrange(view, final.Width, final.Height);
            if (drawing) drawing.Size({final.Width, final.Height});
            return final;
        }
    };

    winrt::Windows::UI::Color color(uint32_t argb) {
        return {static_cast<uint8_t>(argb >> 24), static_cast<uint8_t>(argb >> 16),
                static_cast<uint8_t>(argb >> 8), static_cast<uint8_t>(argb)};
    }

    composition::CompositionBrush paint(composition::Compositor const &compositor, SwiftOmniUIBrush const &value) {
        if (value.kind == 0) return nullptr;
        if (value.kind == 1) return compositor.CreateColorBrush(color(value.count > 0 ? value.colors[0] : 0));
        auto const *g = value.geometry;
        composition::CompositionGradientBrush brush{nullptr};
        if (value.kind == 2) {
            auto linear = compositor.CreateLinearGradientBrush();
            linear.StartPoint({static_cast<float>(g[0]), static_cast<float>(g[1])});
            linear.EndPoint({static_cast<float>(g[2]), static_cast<float>(g[3])});
            brush = linear;
        } else if (value.kind == 3) {
            auto radial = compositor.CreateRadialGradientBrush();
            radial.EllipseCenter({static_cast<float>(g[0]), static_cast<float>(g[1])});
            radial.EllipseRadius({static_cast<float>(g[2]), static_cast<float>(g[3])});
            radial.GradientOriginOffset({0, 0});
            brush = radial;
        } else {
            throw winrt::hresult_invalid_argument();
        }
        brush.MappingMode(composition::CompositionMappingMode::Relative);
        brush.InterpolationSpace(composition::CompositionColorSpace::Rgb);
        for (int32_t index = 0; index < value.count; ++index)
            brush.ColorStops().Append(compositor.CreateColorGradientStop(
                static_cast<float>(value.offsets[index]), color(value.colors[index])));
        return brush;
    }

    winrt::com_ptr<ID2D1Geometry> rounded(double width, double height, double inset, double const *radii) {
        auto x0 = static_cast<float>(inset), y0 = x0;
        auto x1 = static_cast<float>(std::max(inset, width - inset));
        auto y1 = static_cast<float>(std::max(inset, height - inset));
        auto limit = std::max(0.0f, std::min(x1 - x0, y1 - y0) / 2);
        float r[4];
        for (int index = 0; index < 4; ++index)
            r[index] = static_cast<float>(std::clamp(std::isfinite(radii[index]) ? radii[index] : 0.0, 0.0, double(limit)));
        winrt::com_ptr<ID2D1PathGeometry> path;
        winrt::com_ptr<ID2D1GeometrySink> sink;
        winrt::check_hresult(pathFactory()->CreatePathGeometry(path.put()));
        winrt::check_hresult(path->Open(sink.put()));
        sink->BeginFigure(D2D1::Point2F(x0 + r[0], y0), D2D1_FIGURE_BEGIN_FILLED);
        auto line = [&](float x, float y) { sink->AddLine(D2D1::Point2F(x, y)); };
        auto corner = [&](float radius, float x, float y) {
            if (radius == 0) { line(x, y); return; }
            sink->AddArc(D2D1::ArcSegment(D2D1::Point2F(x, y), D2D1::SizeF(radius, radius),
                                        0, D2D1_SWEEP_DIRECTION_CLOCKWISE, D2D1_ARC_SIZE_SMALL));
        };
        line(x1 - r[1], y0); corner(r[1], x1, y0 + r[1]);
        line(x1, y1 - r[2]); corner(r[2], x1 - r[2], y1);
        line(x0 + r[3], y1); corner(r[3], x0, y1 - r[3]);
        line(x0, y0 + r[0]); corner(r[0], x0 + r[0], y0);
        sink->EndFigure(D2D1_FIGURE_END_CLOSED);
        winrt::check_hresult(sink->Close());
        return path.as<ID2D1Geometry>();
    }
}

namespace swiftomniui {
    composition::CompositionSpriteShape pathSprite(IInspectable const &object) {
        auto element = object.try_as<xaml::UIElement>();
        if (!element) return nullptr;
        auto visual = xaml::Hosting::ElementCompositionPreview::GetElementChildVisual(element);
        auto drawing = visual ? visual.try_as<composition::ShapeVisual>() : composition::ShapeVisual{nullptr};
        if (!drawing || drawing.Shapes().Size() != 1) return nullptr;
        return drawing.Shapes().GetAt(0).try_as<composition::CompositionSpriteShape>();
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_path_make(int64_t view) {
    try {
        auto held = winrt::make<PathPanel>(view).as<controls::Panel>();
        // Spacer is a clear rectangle. Keep its layout/event identity, but
        // allocate no compositor resources until it has something to paint.
        // Gesture registration owns the hit area, as for other SOUI panels.
        // A decorative vector must not acquire a rectangular input surface.
        return detach(held);
    } catch (...) { report("making a shape"); return nullptr; }
}

extern "C" void swiftomniui_winui_path_paint(
    SwiftOmniUIObjectRef handle, SwiftOmniUIBrush fill, SwiftOmniUIBrush stroke, double width, double const *dashes,
    int32_t dashCount, double dashOffset, int32_t cap, int32_t join, double miter
) {
    try {
        auto panel = as<controls::Panel>(handle);
        auto shape = winrt::get_self<PathPanel>(panel.as<xaml::IFrameworkElementOverrides>())->prepareDrawing();
        auto compositor = shape.Compositor();
        shape.FillBrush(paint(compositor, fill));
        shape.StrokeBrush(paint(compositor, stroke));
        shape.StrokeThickness(static_cast<float>(width));
        auto pattern = shape.StrokeDashArray();
        pattern.Clear();
        for (int32_t index = 0; index < dashCount; ++index) pattern.Append(static_cast<float>(dashes[index]));
        shape.StrokeDashOffset(static_cast<float>(dashOffset));
        auto ends = cap == 1 ? composition::CompositionStrokeCap::Round
            : cap == 2 ? composition::CompositionStrokeCap::Square : composition::CompositionStrokeCap::Flat;
        shape.StrokeStartCap(ends); shape.StrokeEndCap(ends); shape.StrokeDashCap(ends);
        shape.StrokeLineJoin(join == 1 ? composition::CompositionStrokeLineJoin::Bevel
            : join == 2 ? composition::CompositionStrokeLineJoin::Round : composition::CompositionStrokeLineJoin::Miter);
        shape.StrokeMiterLimit(static_cast<float>(miter * 2));
    } catch (...) { report("painting a shape"); }
}

extern "C" void swiftomniui_winui_path_bounds(double const *commands, int32_t count, double *bounds) {
    try {
        auto path = pathGeometry(commands, count, false);
        D2D1_RECT_F box{};
        winrt::check_hresult(path->GetBounds(nullptr, &box));
        // An empty D2D geometry has an inverted bound rather than a zero rect.
        bool known = std::isfinite(box.left) && std::isfinite(box.top) && std::isfinite(box.right)
            && std::isfinite(box.bottom) && box.right >= box.left && box.bottom >= box.top;
        double read[] = {known ? box.left : 0, known ? box.top : 0,
                         known ? box.right - box.left : 0, known ? box.bottom - box.top : 0};
        std::copy(read, read + 4, bounds);
    } catch (...) { report("measuring a shape"); }
}

extern "C" void swiftomniui_winui_path_draw(
    SwiftOmniUIObjectRef handle, int32_t kind, double const *radii, double const *commands, int32_t count, bool evenOdd,
    double const *placement, double width, double height, double inset
) {
    try {
        winrt::com_ptr<ID2D1Geometry> geometry;
        if (kind == 0) geometry = rounded(width, height, inset, radii);
        else if (kind == 1) {
            winrt::com_ptr<ID2D1EllipseGeometry> ellipse;
            winrt::check_hresult(pathFactory()->CreateEllipseGeometry(D2D1::Ellipse(
                D2D1::Point2F(static_cast<float>(width / 2), static_cast<float>(height / 2)),
                static_cast<float>(std::max(0.0, width / 2 - inset)),
                static_cast<float>(std::max(0.0, height / 2 - inset))), ellipse.put()));
            geometry = ellipse.as<ID2D1Geometry>();
        } else geometry = pathGeometry(commands, count, evenOdd).as<ID2D1Geometry>();
        if (placement) {
            // Bake the geometry transform before stroking, retaining the authored
            // line width through nonuniform scale, skew and reflection.
            D2D1_MATRIX_3X2_F matrix{static_cast<float>(placement[0]), static_cast<float>(placement[1]),
                static_cast<float>(placement[2]), static_cast<float>(placement[3]),
                static_cast<float>(placement[4]), static_cast<float>(placement[5])};
            winrt::com_ptr<ID2D1TransformedGeometry> transformed;
            winrt::check_hresult(pathFactory()->CreateTransformedGeometry(geometry.get(), &matrix, transformed.put()));
            geometry = transformed.as<ID2D1Geometry>();
        }
        auto panel = as<controls::Panel>(handle);
        auto shape = winrt::get_self<PathPanel>(panel.as<xaml::IFrameworkElementOverrides>())->prepareDrawing();
        shape.Geometry().as<composition::CompositionPathGeometry>().Path(compositionPath(geometry, evenOdd));
    } catch (...) { report("drawing a shape"); }
}

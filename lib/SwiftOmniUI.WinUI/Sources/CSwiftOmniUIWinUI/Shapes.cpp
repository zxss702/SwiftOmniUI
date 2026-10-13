// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The shape a layout's box is, and the brushes it is painted with, built from
// the parts the host hands over; and a ColorBox, a figure of one colour.
// Design: docs/design/platforms/winui/drawing.md#a-box-and-its-brush

#include "Figure.h"

#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace shapes = winrt::Microsoft::UI::Xaml::Shapes;

namespace {
    winrt::Windows::UI::Color color(uint32_t argb) {
        return {static_cast<uint8_t>(argb >> 24), static_cast<uint8_t>(argb >> 16), static_cast<uint8_t>(argb >> 8),
                static_cast<uint8_t>(argb)};
    }

    winrt::Windows::Foundation::Point point(double x, double y) {
        return {static_cast<float>(x), static_cast<float>(y)};
    }

    template <typename Stops>
    void addStops(Stops const &stops, SwiftOmniUIBrush const &brush) {
        for (int32_t index = 0; index < brush.count; ++index) {
            media::GradientStop stop;
            stop.Color(color(brush.colors[index]));
            stop.Offset(brush.offsets[index]);
            stops.Append(stop);
        }
    }
}

namespace swiftomniui {
    media::Brush brush(SwiftOmniUIBrush const &brush) {
        auto const *g = brush.geometry;
        switch (brush.kind) {
        case 1:
            return media::SolidColorBrush(color(brush.count > 0 ? brush.colors[0] : 0));
        case 2: {
            media::LinearGradientBrush linear;
            linear.StartPoint(point(g[0], g[1]));
            linear.EndPoint(point(g[2], g[3]));
            addStops(linear.GradientStops(), brush);
            return linear;
        }
        case 3: {
            media::RadialGradientBrush radial;
            radial.Center(point(g[0], g[1]));
            radial.GradientOrigin(point(g[0], g[1]));
            radial.RadiusX(g[2]);
            radial.RadiusY(g[3]);
            addStops(radial.GradientStops(), brush);
            return radial;
        }
        default:
            return nullptr;
        }
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_shape_make(SwiftOmniUIOutline outline) {
    try {
        if (outline == SwiftOmniUIOutlineEllipse) return detach(shapes::Ellipse());
        return detach(shapes::Rectangle());
    } catch (...) {
        report("making a shape");
        return nullptr;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_divider_make(void) {
    try {
        // Keep the ThemeResource expression on Fill: a one-time resource lookup would freeze the brush to the
        // startup theme. XAML owns light/dark and high-contrast updates for this native separator.
        auto line = xaml::Markup::XamlReader::Load(
            LR"(<Rectangle xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                           Fill="{ThemeResource DividerStrokeColorDefaultBrush}" />)").as<shapes::Rectangle>();
        return detach(line);
    } catch (...) {
        report("making a divider");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_shape_set(
    SwiftOmniUIObjectRef handle, double radius, SwiftOmniUIBrush fill, SwiftOmniUIBrush stroke, double strokeWidth
) {
    try {
        auto shape = as<shapes::Shape>(handle);
        shape.Fill(brush(fill));
        shape.Stroke(brush(stroke));
        shape.StrokeThickness(strokeWidth);
        if (auto rectangle = shape.try_as<shapes::Rectangle>()) {
            rectangle.RadiusX(radius);
            rectangle.RadiusY(radius);
        }
    } catch (...) {
        report("painting a shape");
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_color_box_make(int64_t view) {
    try {
        return detach(figure(view));
    } catch (...) {
        report("making a colour box");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_color_box_set(SwiftOmniUIObjectRef handle, uint32_t fill, double const *corners) {
    try {
        auto box = borrow<controls::Grid>(handle);
        box.Background(media::SolidColorBrush(color(fill)));
        box.CornerRadius({corners[0], corners[1], corners[2], corners[3]});
    } catch (...) {
        report("painting a colour box");
    }
}

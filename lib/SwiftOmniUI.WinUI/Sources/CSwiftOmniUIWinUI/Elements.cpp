// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What every element takes: its measure and place, which a panel's pass asks
// for, whether it shows, how opaque it is drawn, and a control's enabled state.

#include "Relay.h"
#include "CompositionClips.h"

#include <algorithm>
#include <cstring>
#include <optional>

#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Media3D.h>
#include <winrt/Windows.UI.ViewManagement.h>

using namespace swiftomniui;
using winrt::Windows::Foundation::Rect;
using winrt::Windows::Foundation::Size;

extern "C" void swiftomniui_winui_fill_place(SwiftOmniUIObjectRef handle) {
    try {
        auto element = as<xaml::FrameworkElement>(handle);
        // SwiftOmniUI measures and places in DIPs. Rounding each nested measure independently can subtract a
        // physical pixel from a text column before its final placement. Keep the layout in those same DIPs;
        // XAML still applies the window's current rasterization scale when it renders.
        element.UseLayoutRounding(false);
        element.HorizontalAlignment(xaml::HorizontalAlignment::Stretch);
        element.VerticalAlignment(xaml::VerticalAlignment::Stretch);
    } catch (...) {
        report("filling a place");
    }
}

extern "C" void swiftomniui_winui_measure(SwiftOmniUIObjectRef handle, double width, double height, double *size) {
    try {
        auto element = as<xaml::UIElement>(handle);
        element.Measure(Size(static_cast<float>(width), static_cast<float>(height)));
        auto desired = element.DesiredSize();
        size[0] = desired.Width;
        size[1] = desired.Height;
    } catch (...) {
        report("measuring");
    }
}

extern "C" void swiftomniui_winui_desired_size(SwiftOmniUIObjectRef handle, double *size) {
    try {
        auto desired = as<xaml::UIElement>(handle).DesiredSize();
        size[0] = desired.Width;
        size[1] = desired.Height;
    } catch (...) {
        report("reading the measured size");
    }
}

extern "C" void swiftomniui_winui_arrange(SwiftOmniUIObjectRef handle, double x, double y, double width, double height) {
    try {
        as<xaml::UIElement>(handle).Arrange(Rect(
            static_cast<float>(x), static_cast<float>(y), static_cast<float>(width), static_cast<float>(height)));
    } catch (...) {
        report("arranging");
    }
}

extern "C" void swiftomniui_winui_invalidate_measure(SwiftOmniUIObjectRef handle) {
    try {
        as<xaml::UIElement>(handle).InvalidateMeasure();
    } catch (...) {
        report("invalidating a measure");
    }
}

extern "C" void swiftomniui_winui_set_shown(SwiftOmniUIObjectRef handle, bool shown) {
    try {
        as<xaml::UIElement>(handle).Visibility(shown ? xaml::Visibility::Visible : xaml::Visibility::Collapsed);
    } catch (...) {
        report("showing");
    }
}

extern "C" void swiftomniui_winui_set_opacity(SwiftOmniUIObjectRef handle, double opacity) {
    try {
        as<xaml::UIElement>(handle).Opacity(opacity);
    } catch (...) {
        report("setting the opacity");
    }
}

extern "C" void swiftomniui_winui_set_tooltip(SwiftOmniUIObjectRef handle, char const *utf8) {
    try {
        auto element = as<xaml::UIElement>(handle);
        if (utf8 == nullptr) {
            controls::ToolTipService::SetToolTip(element, nullptr);
        } else {
            controls::ToolTipService::SetToolTip(element, winrt::box_value(text(utf8)));
        }
    } catch (...) {
        report("setting a tip");
    }
}

extern "C" void swiftomniui_winui_frame(SwiftOmniUIObjectRef handle, double *frame) {
    try {
        auto element = as<xaml::UIElement>(handle);
        auto offset = element.ActualOffset();
        auto size = element.ActualSize();
        frame[0] = offset.x;
        frame[1] = offset.y;
        frame[2] = size.x;
        frame[3] = size.y;
    } catch (...) {
        report("reading a frame");
    }
}

extern "C" bool swiftomniui_winui_is_attached(SwiftOmniUIObjectRef handle) {
    try {
        auto element = as<xaml::FrameworkElement>(handle);
        return element.IsLoaded() && element.XamlRoot();
    } catch (...) {
        report("reading an element's attachment");
        return false;
    }
}

extern "C" void swiftomniui_winui_origin(SwiftOmniUIObjectRef handle, double *origin) {
    origin[0] = origin[1] = 0;
    try {
        auto element = as<xaml::UIElement>(handle);
        if (!element.XamlRoot()) return;
        auto corner = element.TransformToVisual(nullptr).TransformPoint({0, 0});
        origin[0] = corner.X;
        origin[1] = corner.Y;
    } catch (...) {
        report("finding where an element stands in its window");
    }
}

extern "C" bool swiftomniui_winui_layout_offset(
    SwiftOmniUIObjectRef handle, SwiftOmniUIObjectRef ancestor, double *offset
) {
    try {
        auto target = as<xaml::DependencyObject>(ancestor);
        auto current = as<xaml::DependencyObject>(handle);
        double x = 0, y = 0;
        while (current && current != target) {
            if (auto element = current.try_as<xaml::UIElement>()) {
                auto at = element.ActualOffset();
                x += at.x;
                y += at.y;
            }
            current = xaml::Media::VisualTreeHelper::GetParent(current);
        }
        if (!current) return false;
        offset[0] = x;
        offset[1] = y;
        return true;
    } catch (...) {
        report("reading a relative layout offset");
        return false;
    }
}

extern "C" void swiftomniui_winui_invalidate_arrange(SwiftOmniUIObjectRef handle) {
    try {
        as<xaml::UIElement>(handle).InvalidateArrange();
    } catch (...) {
        report("invalidating an arrangement");
    }
}

extern "C" void swiftomniui_winui_on_size_changed(
    SwiftOmniUIObjectRef handle, int64_t view, void (*changed)(int64_t, double, double)
) {
    try {
        as<xaml::FrameworkElement>(handle).SizeChanged(guarded("observing a native allocation",
            [view, changed](IInspectable const &, xaml::SizeChangedEventArgs const &args) {
                auto size = args.NewSize();
                changed(view, size.Width, size.Height);
            }));
    } catch (...) {
        report("observing a native allocation");
    }
}

extern "C" void swiftomniui_winui_on_height_changed(
    SwiftOmniUIObjectRef handle, int64_t view, void (*changed)(int64_t)
) {
    try {
        as<xaml::FrameworkElement>(handle).SizeChanged(guarded("observing a native height",
            [view, changed](IInspectable const &, xaml::SizeChangedEventArgs const &args) {
                if (args.NewSize().Height != args.PreviousSize().Height) changed(view);
            }));
    } catch (...) {
        report("observing a native height");
    }
}

extern "C" void swiftomniui_winui_set_clip(
    SwiftOmniUIObjectRef handle, bool cuts, SwiftOmniUIOutline outline, double radius, double width, double height
) {
    try {
        auto element = as<xaml::UIElement>(handle);
        if (!cuts) {
            setElementCompositionClip(element, nullptr);
            return;
        }
        auto visual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(element);
        auto compositor = visual.Compositor();
        auto w = static_cast<float>(width), h = static_cast<float>(height);
        if (outline == SwiftOmniUIOutlineEllipse || outline == SwiftOmniUIOutlineCircle) {
            auto ellipse = compositor.CreateEllipseGeometry();
            auto radius = outline == SwiftOmniUIOutlineEllipse ? winrt::Windows::Foundation::Numerics::float2{w / 2, h / 2}
                : winrt::Windows::Foundation::Numerics::float2{std::min(w, h) / 2, std::min(w, h) / 2};
            ellipse.Center({w / 2, h / 2});
            ellipse.Radius(radius);
            setElementCompositionClip(element, compositor.CreateGeometricClip(ellipse));
        } else {
            auto rectangle = compositor.CreateRoundedRectangleGeometry();
            auto r = outline == SwiftOmniUIOutlineRounded ? std::min(static_cast<float>(radius), std::min(w, h) / 2)
                : outline == SwiftOmniUIOutlineCapsule ? std::min(w, h) / 2 : 0.0f;
            rectangle.Size({w, h});
            rectangle.CornerRadius({r, r});
            setElementCompositionClip(element, compositor.CreateGeometricClip(rectangle));
        }
    } catch (...) {
        report("cutting an element to its outline");
    }
}

extern "C" void swiftomniui_winui_set_hit_testable(SwiftOmniUIObjectRef handle, bool testable) {
    try {
        as<xaml::UIElement>(handle).IsHitTestVisible(testable);
    } catch (...) {
        report("letting clicks through");
    }
}

extern "C" void swiftomniui_winui_set_z_index(SwiftOmniUIObjectRef handle, int32_t z) {
    try {
        controls::Canvas::SetZIndex(as<xaml::UIElement>(handle), z);
    } catch (...) {
        report("ordering an element among its panel's children");
    }
}

extern "C" void swiftomniui_winui_set_flow_direction(SwiftOmniUIObjectRef handle, bool rightToLeft) {
    try {
        as<xaml::FrameworkElement>(handle).FlowDirection(
            rightToLeft ? xaml::FlowDirection::RightToLeft : xaml::FlowDirection::LeftToRight);
    } catch (...) {
        report("turning an element's direction");
    }
}

extern "C" void swiftomniui_winui_update_layout(SwiftOmniUIObjectRef handle) {
    try {
        as<xaml::UIElement>(handle).UpdateLayout();
    } catch (...) {
        report("laying out");
    }
}

extern "C" void swiftomniui_winui_set_projection(SwiftOmniUIObjectRef handle, double const *matrix) {
    try {
        auto element = as<xaml::UIElement>(handle);
        if (!matrix) {
            element.Projection(nullptr);
            return;
        }
        xaml::Media::Media3D::Matrix3D held{
            matrix[0], matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6], matrix[7],
            matrix[8], matrix[9], matrix[10], matrix[11], matrix[12], matrix[13], matrix[14], matrix[15]};
        auto projection = element.Projection().try_as<xaml::Media::Matrix3DProjection>();
        if (!projection) {
            projection = xaml::Media::Matrix3DProjection();
            element.Projection(projection);
        }
        projection.ProjectionMatrix(held);
    } catch (...) {
        report("tipping an element");
    }
}

extern "C" bool swiftomniui_winui_projection(SwiftOmniUIObjectRef handle, double *matrix) {
    try {
        auto projection = as<xaml::UIElement>(handle).Projection().try_as<xaml::Media::Matrix3DProjection>();
        if (!projection) return false;
        auto held = projection.ProjectionMatrix();
        double const read[] = {held.M11, held.M12, held.M13, held.M14, held.M21, held.M22, held.M23, held.M24,
                               held.M31, held.M32, held.M33, held.M34, held.OffsetX, held.OffsetY, held.OffsetZ,
                               held.M44};
        std::memcpy(matrix, read, sizeof read);
        return true;
    } catch (...) {
        report("reading an element's tip");
        return false;
    }
}

extern "C" void swiftomniui_winui_set_transform(
    SwiftOmniUIObjectRef handle, double translationX, double translationY, double rotation, double scaleX,
    double scaleY, double centerX, double centerY
) {
    try {
        // A composite render transform, which an element whose visual a cut has taken still takes: WinUI refuses
        // such an element its Translation, Rotation, Scale and CenterPoint.
        auto element = as<xaml::UIElement>(handle);
        auto transform = element.RenderTransform().try_as<xaml::Media::CompositeTransform>();
        if (!transform) {
            transform = xaml::Media::CompositeTransform();
            element.RenderTransform(transform);
        }
        transform.CenterX(centerX);
        transform.CenterY(centerY);
        transform.TranslateX(translationX);
        transform.TranslateY(translationY);
        transform.Rotation(rotation);
        transform.ScaleX(scaleX);
        transform.ScaleY(scaleY);
    } catch (...) {
        report("transforming");
    }
}

extern "C" void swiftomniui_winui_transform(SwiftOmniUIObjectRef handle, double *values) {
    try {
        double read[] = {0, 0, 0, 1, 1, 0, 0};
        if (auto t = as<xaml::UIElement>(handle).RenderTransform().try_as<xaml::Media::CompositeTransform>()) {
            double const held[] = {t.TranslateX(), t.TranslateY(), t.Rotation(), t.ScaleX(), t.ScaleY(), t.CenterX(),
                                   t.CenterY()};
            std::memcpy(read, held, sizeof read);
        }
        std::memcpy(values, read, sizeof read);
    } catch (...) {
        report("reading a transform");
    }
}

extern "C" double swiftomniui_winui_opacity(SwiftOmniUIObjectRef handle) {
    try {
        return as<xaml::UIElement>(handle).Opacity();
    } catch (...) {
        report("reading the opacity");
        return 1;
    }
}

extern "C" bool swiftomniui_winui_is_shown(SwiftOmniUIObjectRef handle) {
    try {
        return as<xaml::UIElement>(handle).Visibility() == xaml::Visibility::Visible;
    } catch (...) {
        report("reading whether an element shows");
        return false;
    }
}

extern "C" bool swiftomniui_winui_is_enabled(SwiftOmniUIObjectRef handle) {
    try {
        auto control = as<IInspectable>(handle).try_as<controls::Control>();
        return !control || control.IsEnabled();
    } catch (...) {
        report("reading whether a control is enabled");
        return false;
    }
}

extern "C" bool swiftomniui_winui_animations_enabled(void) {
    try {
        // One, kept for the process and never destroyed: a fresh UISettings for every reading is a WinRT activation
        // each time.
        static auto &settings = **new std::optional(winrt::Windows::UI::ViewManagement::UISettings());
        return settings.AnimationsEnabled();
    } catch (...) {
        report("reading whether animations are on");
        return true;
    }
}

extern "C" void swiftomniui_winui_set_enabled(SwiftOmniUIObjectRef handle, bool enabled) {
    try {
        if (auto control = as<IInspectable>(handle).try_as<controls::Control>())
            control.IsEnabled(enabled);
    } catch (...) {
        report("enabling");
    }
}

extern "C" int32_t swiftomniui_winui_text(SwiftOmniUIObjectRef handle, char *utf8, int32_t capacity) {
    try {
        auto object = as<IInspectable>(handle);
        winrt::hstring words;
        if (auto block = wordsOf(object)) {
            // Runs of words are the block's words, in order.
            for (auto const &piece : block.Inlines())
                if (auto run = piece.try_as<winrt::Microsoft::UI::Xaml::Documents::Run>()) words = words + run.Text();
            if (!block.Inlines().Size()) words = block.Text();
        } else if (auto box = object.try_as<controls::TextBox>()) {
            words = box.Text();
        } else if (auto search = object.try_as<controls::AutoSuggestBox>()) {
            words = search.Text();
        } else if (auto content = object.try_as<controls::ContentControl>()) {
            words = winrt::unbox_value_or<winrt::hstring>(content.Content(), L"");
        }
        auto bytes = winrt::to_string(words);
        if (utf8 && capacity > 0) {
            auto count = std::min<size_t>(bytes.size(), static_cast<size_t>(capacity - 1));
            std::memcpy(utf8, bytes.data(), count);
            utf8[count] = 0;
        }
        return static_cast<int32_t>(bytes.size());
    } catch (...) {
        report("reading the words");
        return 0;
    }
}

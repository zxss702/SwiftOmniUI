// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How words look, on a text block or on any control showing them: their font,
// their colour and the room around them; and a label's lines, alignment,
// spacing and decorations.
// Design: docs/design/platforms/winui/controls.md#words

#include "Relay.h"

#include <algorithm>
#include <cmath>
#include <cwchar>
#include <cwctype>
#include <functional>
#include <iterator>
#include <memory>
#include <map>
#include <limits>
#include <optional>
#include <tuple>
#include <string>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Text.h>
#include <winrt/Microsoft.UI.Input.h>
#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace documents = winrt::Microsoft::UI::Xaml::Documents;

extern "C" void swiftomniui_winui_set_pointer_style(SwiftOmniUIObjectRef handle, int32_t style) {
    try {
        auto target = as<xaml::FrameworkElement>(handle);
        auto currentKey = winrt::box_value(L"SwiftOmniUIPointerStyle");
        auto pendingKey = winrt::box_value(L"SwiftOmniUIPointerStylePending");
        target.Resources().Insert(currentKey, winrt::box_value(style));
        auto apply = [currentKey](xaml::FrameworkElement const &target) {
            auto style = winrt::unbox_value<int32_t>(target.Resources().Lookup(currentKey));
            using winrt::Microsoft::UI::Input::InputSystemCursorShape;
            auto shape = InputSystemCursorShape::Arrow;
            switch (style) {
            case 1: case 2: case 3: case 11: shape = InputSystemCursorShape::IBeam; break;
            case 4: case 5: case 6: case 7: case 8: shape = InputSystemCursorShape::Hand; break;
            case 9: shape = InputSystemCursorShape::UniversalNo; break;
            case 10: shape = InputSystemCursorShape::Cross; break;
            case 12: shape = InputSystemCursorShape::SizeWestEast; break;
            case 13: shape = InputSystemCursorShape::SizeNorthSouth; break;
            case 14: shape = InputSystemCursorShape::SizeNorthwestSoutheast; break;
            }
            auto element = target.as<xaml::IUIElementProtected>();
            if (style < 0) element.ProtectedCursor(nullptr);
            else element.ProtectedCursor(winrt::Microsoft::UI::Input::InputSystemCursor::Create(shape));
        };
        if (target.IsLoaded()) apply(target);
        else if (!target.Resources().HasKey(pendingKey)) {
            // ProtectedCursor requires a live XamlRoot. Unsubscribe before
            // applying the latest value: style can change several times before
            // attachment, and an earlier Loaded callback must not restore it.
            target.Resources().Insert(pendingKey, winrt::box_value(true));
            auto token = std::make_shared<winrt::event_token>();
            *token = target.Loaded([weak = winrt::make_weak(target), token, pendingKey, apply](auto const &, auto const &) {
                try {
                    if (auto target = weak.get()) {
                        target.Loaded(*token);
                        target.Resources().Remove(pendingKey);
                        apply(target);
                    }
                } catch (...) { report("loaded pointer style"); }
            });
        }
    } catch (...) { report("pointer style"); }
}

extern "C" void swiftomniui_winui_text_set_selectable(SwiftOmniUIObjectRef handle, bool selectable) {
    try { labelWords(handle).IsTextSelectionEnabled(selectable); syncRichWords(handle); }
    catch (...) { report("text selectable"); }
}

namespace {
    uint64_t fontProbes = 0;
    uint64_t spacingProbes = 0;

    using SpacingDecisions = winrt::Windows::Foundation::Collections::IMap<double, double>;
    constexpr wchar_t spacingDecisionsKey[] = L"SwiftOmniUITextSpacingDecisions";

    SpacingDecisions spacingDecisions(controls::Border const &border, controls::TextBlock const &block) {
        auto resources = border.Resources();
        auto key = winrt::box_value(spacingDecisionsKey);
        if (resources.HasKey(key)) return resources.Lookup(key).as<SpacingDecisions>();
        auto decisions = winrt::single_threaded_map<double, double>();
        resources.Insert(key, decisions);
        // Observe inherited typography too. These handlers retain only the
        // small map, never the label. MaxLines/LineHeight are deliberately not
        // observed: our first-line probe temporarily changes them. Their
        // public setters explicitly discard these decisions instead.
        for (auto const &property : {
            controls::TextBlock::TextProperty(), controls::TextBlock::FontFamilyProperty(),
            controls::TextBlock::FontSizeProperty(), controls::TextBlock::FontWeightProperty(),
            controls::TextBlock::FontStyleProperty(), controls::TextBlock::FontStretchProperty(),
            controls::TextBlock::CharacterSpacingProperty(), controls::TextBlock::TextWrappingProperty(),
            controls::TextBlock::TextTrimmingProperty(), controls::TextBlock::TextLineBoundsProperty(),
            controls::TextBlock::TextAlignmentProperty(), controls::TextBlock::OpticalMarginAlignmentProperty(),
            controls::TextBlock::TextReadingOrderProperty(), controls::TextBlock::PaddingProperty(),
            controls::TextBlock::IsTextScaleFactorEnabledProperty(),
            xaml::FrameworkElement::LanguageProperty(), xaml::FrameworkElement::FlowDirectionProperty()}) {
            block.RegisterPropertyChangedCallback(property, [decisions](auto const &, auto const &) { decisions.Clear(); });
        }
        border.Loaded([decisions](auto const &, auto const &) { decisions.Clear(); });
        return decisions;
    }

    // WinUI takes an Image/Panel's bottom edge as its inline baseline; only a
    // TextBlock/RichTextBlock can report a separate baseline and descent. Keep
    // the image in a native paragraph whose baseline comes from its margin,
    // and whose minimum height retains the pixels below that baseline. Without
    // this host a negative baseline offset shortens the line's measured height.
    controls::RichTextBlock inlineHost(xaml::UIElement const &child, double height) {
        controls::RichTextBlock host;
        host.UseLayoutRounding(false);
        host.IsTextSelectionEnabled(false);
        host.IsHitTestVisible(false);
        host.FontSize(0.01);
        host.Padding({0, 0, 0, 0});
        host.TextWrapping(xaml::TextWrapping::NoWrap);
        host.MinHeight(std::max(0.0, height));
        host.Tag(child);
        documents::Paragraph paragraph;
        documents::InlineUIContainer content;
        content.Child(child);
        paragraph.Inlines().Append(content);
        host.Blocks().Append(paragraph);
        return host;
    }

    xaml::FrameworkElement inlineContent(documents::InlineUIContainer const &holder) {
        auto child = holder.Child();
        if (auto host = child.try_as<controls::RichTextBlock>())
            if (auto content = host.Tag().try_as<xaml::FrameworkElement>()) return content;
        return child.try_as<xaml::FrameworkElement>();
    }

    winrt::Windows::UI::Color color(uint32_t argb) {
        return {static_cast<uint8_t>(argb >> 24), static_cast<uint8_t>(argb >> 16), static_cast<uint8_t>(argb >> 8),
                static_cast<uint8_t>(argb)};
    }

    /// A solid brush's colour as 0xAARRGGBB; 0 for any other.
    double argb(media::Brush const &brush) {
        auto solid = brush.try_as<media::SolidColorBrush>();
        if (!solid) return 0;
        auto c = solid.Color();
        return static_cast<double>(static_cast<uint32_t>(c.A) << 24 | static_cast<uint32_t>(c.R) << 16
                                   | static_cast<uint32_t>(c.G) << 8 | c.B);
    }

    /// Runs `block` on a label's text block, or `control` on a control; the element is one or the other.
    template <typename OnBlock, typename OnControl>
    void either(SwiftOmniUIObjectRef handle, OnBlock block, OnControl control) {
        auto object = as<IInspectable>(handle);
        if (auto text = wordsOf(object)) { block(text); syncRichWords(handle); }
        else if (auto other = object.try_as<controls::Control>()) control(other);
    }

    // OptimizeApplyStyles defers applying a Style until an element enters the
    // live tree. Font lookup also serves off-tree measurement and symbol sizing:
    // read the native setters instead of depending on a detached probe's Style.
    // BasedOn is applied first, as it is by XAML; StaticResource values have
    // already been resolved by the native resource dictionary.
    bool fontSizeValue(winrt::Windows::Foundation::IInspectable const &value, double &size) {
        if (!value) return false;
        try {
            auto boxed = value.as<winrt::Windows::Foundation::IPropertyValue>();
            double resolved = 0;
            switch (boxed.Type()) {
            case winrt::Windows::Foundation::PropertyType::Double: resolved = boxed.GetDouble(); break;
            case winrt::Windows::Foundation::PropertyType::Single: resolved = boxed.GetSingle(); break;
            case winrt::Windows::Foundation::PropertyType::Int32: resolved = boxed.GetInt32(); break;
            case winrt::Windows::Foundation::PropertyType::UInt32: resolved = boxed.GetUInt32(); break;
            case winrt::Windows::Foundation::PropertyType::String: {
                auto string = boxed.GetString();
                wchar_t *end = nullptr;
                resolved = std::wcstod(string.c_str(), &end);
                if (end == string.c_str() || *end != 0) return false;
                break;
            }
            default: return false;
            }
            if (!std::isfinite(resolved) || resolved <= 0) return false;
            size = resolved;
            return true;
        } catch (...) {
            return false;
        }
    }

    bool fontWeightValue(winrt::Windows::Foundation::IInspectable const &value, uint16_t &weight) {
        if (!value) return false;
        // XAML styles can expose a boxed FontWeight, a number, or an unresolved
        // string. Query each representation separately: a mismatched WinRT
        // interface must not prevent the glyph or text from being shown.
        try {
            auto resolved = winrt::unbox_value<winrt::Windows::UI::Text::FontWeight>(value).Weight;
            if (resolved > 0 && resolved <= 1000) {
                weight = resolved;
                return true;
            }
        } catch (...) {}
        try {
            auto boxed = value.as<winrt::Windows::Foundation::IPropertyValue>();
            double resolved = 0;
            switch (boxed.Type()) {
            case winrt::Windows::Foundation::PropertyType::UInt16: resolved = boxed.GetUInt16(); break;
            case winrt::Windows::Foundation::PropertyType::Int32: resolved = boxed.GetInt32(); break;
            case winrt::Windows::Foundation::PropertyType::UInt32: resolved = boxed.GetUInt32(); break;
            case winrt::Windows::Foundation::PropertyType::String: {
                auto string = boxed.GetString();
                std::wstring name(string.c_str());
                std::transform(name.begin(), name.end(), name.begin(), [](wchar_t c) { return std::towlower(c); });
                if (name == L"thin") resolved = 100;
                else if (name == L"extralight" || name == L"ultralight") resolved = 200;
                else if (name == L"light") resolved = 300;
                else if (name == L"normal" || name == L"regular") resolved = 400;
                else if (name == L"medium") resolved = 500;
                else if (name == L"semibold" || name == L"demibold") resolved = 600;
                else if (name == L"bold") resolved = 700;
                else if (name == L"extrabold" || name == L"ultrabold") resolved = 800;
                else if (name == L"black" || name == L"heavy") resolved = 900;
                else {
                    wchar_t *end = nullptr;
                    resolved = std::wcstod(name.c_str(), &end);
                    if (end == name.c_str() || *end != 0) return false;
                }
                break;
            }
            default: return false;
            }
            if (!std::isfinite(resolved) || resolved < 1 || resolved > 1000) return false;
            weight = static_cast<uint16_t>(resolved);
            return true;
        } catch (...) {
            return false;
        }
    }

    void fontSetters(xaml::Style const &style, TextFontDefaults &font) {
        if (!style) return;
        fontSetters(style.BasedOn(), font);
        for (auto const &item : style.Setters()) {
            try {
                auto setter = item.try_as<xaml::Setter>();
                if (!setter) continue;
                if (setter.Property() == controls::TextBlock::FontSizeProperty())
                    fontSizeValue(setter.Value(), font.size);
                else if (setter.Property() == controls::TextBlock::FontWeightProperty())
                    fontWeightValue(setter.Value(), font.weight);
            } catch (...) {
                // One malformed setter must not discard the rest of the style.
            }
        }
    }
}

swiftomniui::TextFontDefaults swiftomniui::textFontDefaults(int32_t textStyle) {
    struct Probe {
        controls::TextBlock block{nullptr};
        xaml::Style style{nullptr};
        TextFontDefaults defaults{};
        TextFontDefaults font{};
    };
    static Probe probes[12];
    auto valid = textStyle >= 0 && textStyle < 11;
    auto &probe = probes[valid ? textStyle + 1 : 0];
    if (!probe.block) {
        probe.block = controls::TextBlock();
        probe.defaults = {probe.block.FontSize(), probe.block.FontWeight().Weight};
        probe.font = probe.defaults;
        ++fontProbes;
    }
    xaml::Style style{nullptr};
    if (valid) {
        wchar_t const *styles[] = {L"TitleLargeTextBlockStyle", L"TitleTextBlockStyle", L"SubtitleTextBlockStyle",
            L"BodyLargeTextBlockStyle", L"BodyStrongTextBlockStyle", L"CaptionTextBlockStyle", L"BodyTextBlockStyle",
            L"BodyTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle"};
        try {
            if (auto application = xaml::Application::Current())
                style = application.Resources().TryLookup(winrt::box_value(styles[textStyle])).try_as<xaml::Style>();
        } catch (...) {
            // An unavailable theme style falls back to the native TextBlock's
            // defaults; icon rendering must not depend on a resource lookup.
        }
    }
    // Styles can be replaced while the application runs. Resolve sealed styles
    // once per native identity. A still-editable application style must reflect
    // setter changes too, even before it has entered a tree.
    if (style != probe.style || (style && !style.IsSealed())) {
        auto font = probe.defaults;
        try { fontSetters(style, font); } catch (...) {}
        probe.font = font;
        probe.style = style;
    }
    return probe.font;
}

extern "C" uint64_t swiftomniui_winui_font_probes(void) { return fontProbes; }
extern "C" uint64_t swiftomniui_winui_text_spacing_probes(void) { return spacingProbes; }

extern "C" void swiftomniui_winui_set_font(SwiftOmniUIObjectRef handle, double size, bool bold, bool italic,
                                         char const *family, int32_t textStyle, double requestedWeight) {
    try {
        auto font = textFontDefaults(textStyle);
        auto weight = requestedWeight > 0 ? winrt::Windows::UI::Text::FontWeight{
            static_cast<uint16_t>(std::clamp(requestedWeight, 1.0, 1000.0))}
            : bold ? winrt::Microsoft::UI::Text::FontWeights::Bold() : winrt::Windows::UI::Text::FontWeight{font.weight};
        auto style = italic ? winrt::Windows::UI::Text::FontStyle::Italic : winrt::Windows::UI::Text::FontStyle::Normal;
        auto named = family && *family ? media::FontFamily(text(family)) : media::FontFamily{nullptr};
        auto apply = [&](auto const &element, auto sizeProperty, auto familyProperty) {
            if (size > 0) element.FontSize(size);
            else if (textStyle >= 0) element.FontSize(font.size);
            else element.ClearValue(sizeProperty);
            element.FontWeight(weight);
            element.FontStyle(style);
            if (named) element.FontFamily(named);
            else element.ClearValue(familyProperty);
        };
        either(handle,
            [&](controls::TextBlock const &block) {
                apply(block, controls::TextBlock::FontSizeProperty(), controls::TextBlock::FontFamilyProperty());
            },
            [&](controls::Control const &control) {
                apply(control, controls::Control::FontSizeProperty(), controls::Control::FontFamilyProperty());
            });
    } catch (...) {
        report("setting a font");
    }
}

extern "C" void swiftomniui_winui_set_foreground(SwiftOmniUIObjectRef handle, bool has, uint32_t argb) {
    try {
        auto brush = has ? media::SolidColorBrush(color(argb)) : media::SolidColorBrush{nullptr};
        either(handle,
            [&](controls::TextBlock const &block) {
                auto previous = block.Foreground();
                if (has) block.Foreground(brush);
                else block.ClearValue(controls::TextBlock::ForegroundProperty());
                // A background run without its own colour shares the label's
                // brush. Keep that inheritance when the label changes colour;
                // an explicit run owns a different brush, even for the same ARGB.
                auto foreground = block.Foreground();
                for (auto const &highlighter : block.TextHighlighters()) {
                    if (highlighter.Foreground() == previous) highlighter.Foreground(foreground);
                }
                if (auto rich = richWords(handle)) {
                    for (auto const &highlighter : rich.TextHighlighters())
                        if (highlighter.Foreground() == previous) highlighter.Foreground(foreground);
                    for (auto const &value : rich.Blocks()) if (auto paragraph = value.try_as<documents::Paragraph>())
                        for (auto const &inlineValue : paragraph.Inlines())
                            if (auto holder = inlineValue.try_as<documents::InlineUIContainer>())
                                if (auto child = inlineContent(holder).try_as<controls::TextBlock>()) {
                                    auto key = winrt::box_value(L"SwiftOmniUIInlineInheritsForeground");
                                    if (child.Resources().HasKey(key) && winrt::unbox_value<bool>(child.Resources().Lookup(key)))
                                        child.Foreground(foreground);
                                }
                }
            },
            [&](controls::Control const &control) {
                if (has) control.Foreground(brush);
                else control.ClearValue(controls::Control::ForegroundProperty());
                // A button's template draws its words in its own colour under the pointer and pressed.
                auto resources = control.Resources();
                auto keep = [&](wchar_t const *key) {
                    auto name = winrt::box_value(key);
                    if (resources.HasKey(name)) resources.Remove(name);
                    if (has) resources.Insert(name, brush);
                };
                if (control.try_as<controls::Primitives::ToggleButton>()) {
                    // A toggle names every state it can sit in.
                    for (auto state : {L"", L"PointerOver", L"Pressed", L"Checked", L"CheckedPointerOver",
                                       L"CheckedPressed", L"Indeterminate", L"IndeterminatePointerOver",
                                       L"IndeterminatePressed"}) {
                        keep((std::wstring(L"ToggleButtonForeground") + state).c_str());
                    }
                    return;
                }
                if (!control.try_as<controls::Button>()) return;
                for (auto key : {L"ButtonForeground", L"ButtonForegroundPointerOver", L"ButtonForegroundPressed"}) {
                    keep(key);
                }
            });
    } catch (...) {
        report("colouring words");
    }
}

extern "C" void swiftomniui_winui_set_padding(SwiftOmniUIObjectRef handle, double left, double top, double right, double bottom) {
    try {
        xaml::Thickness room{left, top, right, bottom};
        either(handle,
            [&](controls::TextBlock const &block) { block.Padding(room); },
            [&](controls::Control const &control) { control.Padding(room); });
    } catch (...) {
        report("setting the room around words");
    }
}

extern "C" void swiftomniui_winui_text_set_lines(SwiftOmniUIObjectRef handle, bool wraps, int32_t lines, bool trims) {
    try {
        invalidateWordsMeasurement(handle);
        auto block = labelWords(handle);
        // A single-line limit truncates the continuous line. Wrapping first
        // can move a whole word to a hidden second line and leave unused room
        // before the ellipsis. Multiline labels keep normal wrapping.
        block.TextWrapping(wraps && lines != 1 ? xaml::TextWrapping::Wrap : xaml::TextWrapping::NoWrap);
        block.TextTrimming(trims ? xaml::TextTrimming::CharacterEllipsis : xaml::TextTrimming::None);
        block.MaxLines(std::max(0, lines));
        syncRichWords(handle);
    } catch (...) {
        report("setting a label's lines");
    }
}

extern "C" void swiftomniui_winui_text_set_alignment(SwiftOmniUIObjectRef handle, int32_t horizontal) {
    try {
        auto aligned = horizontal == 1 ? xaml::TextAlignment::Center
            : horizontal == 2 ? xaml::TextAlignment::End : xaml::TextAlignment::Start;
        labelWords(handle).TextAlignment(aligned);
        syncRichWords(handle);
    } catch (...) {
        report("aligning a label's words");
    }
}

namespace {
    struct NaturalWordsMetrics { double height, baseline; };
    NaturalWordsMetrics naturalWordsMetrics(controls::TextBlock const &block, documents::Run const &run = nullptr) {
        using Key = std::tuple<std::wstring, double, uint16_t, int32_t, int32_t, std::wstring, bool, int32_t>;
        static std::map<Key, NaturalWordsMetrics> metrics;
        auto family = run ? run.FontFamily() : block.FontFamily();
        auto size = run ? run.FontSize() : block.FontSize();
        auto weight = run ? run.FontWeight() : block.FontWeight();
        auto style = run ? run.FontStyle() : block.FontStyle();
        auto stretch = run ? run.FontStretch() : block.FontStretch();
        auto language = run ? run.Language() : block.Language();
        Key key{std::wstring(family.Source().c_str()), size, weight.Weight, static_cast<int32_t>(style),
                static_cast<int32_t>(stretch), std::wstring(language.c_str()), block.IsTextScaleFactorEnabled(),
                static_cast<int32_t>(block.TextLineBounds())};
        if (auto found = metrics.find(key); found != metrics.end()) return found->second;
        controls::TextBlock probe;
        probe.UseLayoutRounding(false);
        probe.FontFamily(family); probe.FontSize(size); probe.FontWeight(weight);
        probe.FontStyle(style); probe.FontStretch(stretch); probe.Language(language);
        probe.IsTextScaleFactorEnabled(block.IsTextScaleFactorEnabled());
        probe.TextLineBounds(block.TextLineBounds());
        probe.Text(L"Mg");
        probe.Measure({10000, 10000});
        NaturalWordsMetrics result{probe.DesiredSize().Height, probe.BaselineOffset()};
        if (result.height > 0) metrics.emplace(std::move(key), result);
        return result;
    }
}

extern "C" double swiftomniui_winui_text_natural_line_height(SwiftOmniUIObjectRef handle) {
    try { return naturalWordsMetrics(labelWords(handle)).height; }
    catch (...) { report("reading natural line height"); return 0; }
}

extern "C" void swiftomniui_winui_text_set_spacing(SwiftOmniUIObjectRef handle, int32_t characterSpacing, double baselineAdvance, double singleLineHeight) {
    try {
        invalidateWordsMeasurement(handle);
        auto block = labelWords(handle);
        block.CharacterSpacing(characterSpacing);
        auto resources = borrow<controls::Border>(handle).Resources();
        auto baseline = std::isfinite(baselineAdvance) && baselineAdvance > 0 ? baselineAdvance : 0;
        auto single = std::isfinite(singleLineHeight) && singleLineHeight > 0 ? singleLineHeight : 0;
        auto baselineKey = winrt::box_value(L"SwiftOmniUITextBaselineAdvance");
        auto singleKey = winrt::box_value(L"SwiftOmniUITextSingleLineHeight");
        if (baseline != single) {
            resources.Insert(baselineKey, winrt::box_value(baseline));
            resources.Insert(singleKey, winrt::box_value(single));
        } else {
            // A constant line height is established here once. Only additive
            // spacing needs to inspect the paragraph during every Measure.
            if (resources.HasKey(baselineKey)) resources.Remove(baselineKey);
            if (resources.HasKey(singleKey)) resources.Remove(singleKey);
        }
        block.LineStackingStrategy(xaml::LineStackingStrategy::BaselineToBaseline);
        block.LineHeight(baseline);
        syncRichWords(handle);
        borrow<controls::Border>(handle).InvalidateMeasure();
    } catch (...) { report("spacing a label's words"); }
}

void swiftomniui::invalidateWordsMeasurement(SwiftOmniUIObjectRef handle) {
    auto border = as<IInspectable>(handle).try_as<controls::Border>();
    if (!border) return;
    auto key = winrt::box_value(spacingDecisionsKey);
    auto resources = border.Resources();
    if (resources.HasKey(key)) resources.Lookup(key).as<SpacingDecisions>().Clear();
}

void swiftomniui::measureWords(SwiftOmniUIObjectRef handle, winrt::Windows::Foundation::Size available) {
    auto border = as<IInspectable>(handle).try_as<controls::Border>();
    if (!border) return;
    auto resources = border.Resources();
    auto key = winrt::box_value(L"SwiftOmniUITextBaselineAdvance");
    if (!resources.HasKey(key)) return;
    auto requested = winrt::unbox_value<double>(resources.Lookup(key));
    auto block = labelWords(handle);
    auto singleKey = winrt::box_value(L"SwiftOmniUITextSingleLineHeight");
    auto single = resources.HasKey(singleKey) ? winrt::unbox_value<double>(resources.Lookup(singleKey)) : 0;
    auto maximum = block.MaxLines();
    auto height = requested;
    SpacingDecisions decisions{nullptr};
    if (requested != single && maximum != 1) decisions = spacingDecisions(border, block);
    if (decisions && decisions.HasKey(available.Width)) {
        height = decisions.Lookup(available.Width);
    } else if (decisions) {
        ++spacingProbes;
        // Use the same native paragraph and the same width for both probes.
        // MaxLines is WinUI's own first-line measurement, including styled
        // runs and inline images. No glyph scanning, guessed font heights,
        // Arrange/UpdateLayout calls or replacement visual lines are used.
        auto probe = available;
        probe.Height = INFINITY;
        if (block.LineHeight() != requested) block.LineHeight(requested);
        syncRichWords(handle);
        border.Measure(probe);
        auto full = border.DesiredSize().Height;
        try {
            block.MaxLines(1);
            syncRichWords(handle);
            border.Measure(probe);
            if (full <= border.DesiredSize().Height) height = single;
        } catch (...) {
            block.MaxLines(maximum);
            syncRichWords(handle);
            throw;
        }
        block.MaxLines(maximum);
        // Cache the line-height decision, not DesiredSize: the final native
        // Measure still consumes the caller's actual height constraint. Keep
        // only a few proposals per paragraph, independent of document length.
        if (decisions.Size() >= 4) decisions.Remove(decisions.First().Current().Key());
        decisions.Insert(available.Width, height);
    } else if (maximum == 1) {
        height = single;
    }
    // BaselineToBaseline already trims the outer leading for multiple
    // lines. WinUI leaves trailing leading on a single line, so only that
    // case removes the additive value, before the final native Measure.
    // Text can be prepared at its animation destination while an ancestor
    // is arranging. Even an equal LineHeight write invalidates TextBlock's
    // layout, restarting that ancestor's Arrange indefinitely.
    if (block.LineHeight() != height) block.LineHeight(height);
    // A rich paragraph may still need MaxLines restored after the first-line
    // probe, even when its final line height did not change.
    if (auto rich = richWords(handle); rich && (rich.LineHeight() != height || rich.MaxLines() != maximum))
        syncRichWords(handle);
}

extern "C" void swiftomniui_winui_text_set_runs(SwiftOmniUIObjectRef handle, SwiftOmniUIWordsRun const *runs, int32_t count) {
    try {
        if (count < 0 || (count > 0 && !runs)) return;
        invalidateWordsMeasurement(handle);
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        using winrt::Windows::UI::Text::TextDecorations;
        auto block = labelWords(handle);
        bool needsRich = false;
        for (int32_t i = 0; i < count; ++i)
            needsRich = needsRich || runs[i].imagePixelWidth > 0 || (runs[i].image && *runs[i].image) || runs[i].baseline != 0;
        auto rich = richWords(handle);
        if (needsRich && !rich) {
            rich = controls::RichTextBlock(); rich.UseLayoutRounding(false);
            auto border = borrow<controls::Border>(handle); border.Tag(block); border.Child(rich);
            // InlineUIContainer's native ObjectRun returns zero metrics when
            // formatted outside its embedded-element host. Attach the loaded
            // notification to the visible paragraph as well as the Border:
            // replacing a plain label does not reload that Border.
            auto viewKey = winrt::box_value(L"SwiftOmniUITextLoadedView");
            auto callbackKey = winrt::box_value(L"SwiftOmniUITextLoadedCallback");
            if (border.Resources().HasKey(viewKey) && border.Resources().HasKey(callbackKey)) {
                auto view = winrt::unbox_value<int64_t>(border.Resources().Lookup(viewKey));
                auto ready = reinterpret_cast<void (*)(int64_t)>(static_cast<uintptr_t>(
                    winrt::unbox_value<uint64_t>(border.Resources().Lookup(callbackKey))));
                rich.Loaded(guarded("completing an attached rich label's measurement",
                    [view, ready, weak = winrt::make_weak(border)](IInspectable const &sender, xaml::RoutedEventArgs const &) {
                        if (auto border = weak.get()) {
                            auto key = winrt::box_value(spacingDecisionsKey);
                            if (border.Resources().HasKey(key))
                                border.Resources().Lookup(key).as<SpacingDecisions>().Clear();
                        }
                        sender.as<xaml::UIElement>().InvalidateMeasure();
                        if (ready) ready(view);
                    }));
            }
            syncRichWords(handle);
        } else if (!needsRich && rich) {
            auto border = borrow<controls::Border>(handle); border.Child(block); border.Tag(nullptr); rich = nullptr;
        }
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        if (rich) {
            rich.Blocks().Clear(); documents::Paragraph paragraph;
            paragraph.TextDecorations(block.TextDecorations());
            rich.Blocks().Append(paragraph); inlines = paragraph.Inlines(); highlighters = rich.TextHighlighters();
        }
        inlines.Clear();
        highlighters.Clear();
        int32_t at = 0;
        winrt::hstring plainText;
        auto paintBackground = [&](SwiftOmniUIWordsRun const &run, int32_t length) {
            if (!run.hasBackground || length <= 0) return;
            documents::TextHighlighter highlighter;
            highlighter.Background(media::SolidColorBrush(color(run.background)));
            highlighter.Foreground(run.hasColor ? media::SolidColorBrush(color(run.color)) : block.Foreground());
            highlighter.Ranges().Append(documents::TextRange{at, length});
            highlighters.Append(highlighter);
        };
        for (int32_t index = 0; index < count; ++index) {
            auto const &run = runs[index];
            // Symbols are font glyphs, so retain TextBlock's native Run path.
            // Image-bearing text uses RichTextBlock's native paragraph layout.
            if (run.glyph && *run.glyph && run.baseline == 0) {
                documents::Run mark;
                auto glyph = text(run.glyph);
                mark.Text(glyph);
                mark.FontFamily(media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
                if (run.size > 0) mark.FontSize(run.size);
                if (run.hasColor) mark.Foreground(media::SolidColorBrush(color(run.color)));
                inlines.Append(mark);
                auto length = static_cast<int32_t>(glyph.size());
                paintBackground(run, length);
                at += length;
                plainText = plainText + glyph;
                continue;
            }
            auto hasImage = run.imagePixelWidth > 0 || (run.image && *run.image);
            if (hasImage || run.baseline != 0) {
                documents::InlineUIContainer holder;
                if (hasImage) {
                    controls::Image picture;
                    if (run.imagePixelWidth > 0) {
                        if (!std::isfinite(run.imageWidth) || !std::isfinite(run.imageHeight)
                            || run.imageWidth <= 0 || run.imageHeight <= 0) winrt::throw_hresult(E_INVALIDARG);
                        auto source = memoryPicture(run.imageRGBA, run.imagePixelWidth, run.imagePixelHeight);
                        if (!source) winrt::throw_hresult(E_INVALIDARG);
                        picture.Width(run.imageWidth); picture.Height(run.imageHeight);
                        setMemoryPicture(picture, source);
                    } else {
                        auto file = pictureFile(run.image);
                        if (!file.empty()) picture.Source(pictureSource(file));
                    }
                    picture.Stretch(media::Stretch::Fill);
                    picture.Margin({0, 0, 0, run.baseline});
                    picture.Measure({INFINITY, INFINITY});
                    auto height = std::max(0.0, static_cast<double>(picture.DesiredSize().Height) - run.baseline);
                    if (run.baseline == 0) holder.Child(picture);
                    else holder.Child(inlineHost(picture, height));
                    plainText = plainText + L"\uFFFC";
                } else {
                    controls::TextBlock part;
                    auto symbol = run.glyph && *run.glyph;
                    part.Text(text(symbol ? run.glyph : run.text));
                    // InlineUIContainer does not inherit text formatting into
                    // its child. Apply the label's resolved look first.
                    part.FontFamily(block.FontFamily()); part.FontSize(block.FontSize());
                    part.FontWeight(block.FontWeight()); part.FontStyle(block.FontStyle());
                    part.FontStretch(block.FontStretch()); part.Foreground(block.Foreground());
                    part.UseLayoutRounding(false);
                    part.Resources().Insert(winrt::box_value(L"SwiftOmniUIInlineInheritsForeground"), winrt::box_value(!run.hasColor));
                    if (symbol) part.FontFamily(media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
                    if (run.hasColor) part.Foreground(media::SolidColorBrush(color(run.color)));
                    if (run.size > 0) part.FontSize(run.size);
                    if (run.bold) part.FontWeight(winrt::Microsoft::UI::Text::FontWeights::Bold());
                    if (run.italic) part.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);
                    if (!symbol && run.family && *run.family) part.FontFamily(media::FontFamily(text(run.family)));
                    part.CharacterSpacing(run.spacing);
                    auto decorations = TextDecorations::None;
                    if (run.underline) decorations = decorations | TextDecorations::Underline;
                    if (run.strikethrough) decorations = decorations | TextDecorations::Strikethrough;
                    part.TextDecorations(decorations);
                    part.Measure({INFINITY, INFINITY});
                    auto height = static_cast<double>(part.DesiredSize().Height);
                    controls::Border room;
                    room.Child(part);
                    // A Border uses its desired bottom edge as its baseline.
                    // Its native margin supplies the requested ascent while
                    // the RichTextBlock keeps the complete text height.
                    room.Margin({0, 0, 0, part.BaselineOffset() + run.baseline - height});
                    auto host = inlineHost(room, height);
                    host.Tag(part);
                    holder.Child(host);
                    plainText = plainText + part.Text();
                }
                inlines.Append(holder);
                auto length = (run.glyph && *run.glyph) || hasImage ? 1
                    : static_cast<int32_t>(text(run.text).size());
                paintBackground(run, length);
                at += length;
                continue;
            }
            documents::Run piece;
            auto words = text(run.text);
            piece.Text(words);
            plainText = plainText + words;
            if (run.hasColor) piece.Foreground(media::SolidColorBrush(color(run.color)));
            if (run.size > 0) piece.FontSize(run.size);
            if (run.bold) piece.FontWeight(winrt::Microsoft::UI::Text::FontWeights::Bold());
            if (run.italic) piece.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);
            auto lines = TextDecorations::None;
            if (run.underline) lines = lines | TextDecorations::Underline;
            if (run.strikethrough) lines = lines | TextDecorations::Strikethrough;
            if (lines != TextDecorations::None) piece.TextDecorations(lines);
            if (run.family && *run.family) piece.FontFamily(media::FontFamily(text(run.family)));
            piece.CharacterSpacing(run.spacing);
            inlines.Append(piece);

            // A run's background is a highlighter over its part of the words; its own colour stays on them.
            auto length = static_cast<int32_t>(words.size());
            paintBackground(run, length);
            at += length;
        }
        // The detached TextBlock remains the label's style/readback object.
        // Do not leave its previous document alive when RichTextBlock owns the
        // visible inlines, or generic text/automation reads see stale words.
        if (rich) block.Text(plainText);
    } catch (...) {
        report("setting a label's runs of words");
    }
}

extern "C" bool swiftomniui_winui_text_recolor_runs(
    SwiftOmniUIObjectRef handle, SwiftOmniUIWordsRun const *runs, int32_t count
) {
    try {
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        auto block = labelWords(handle);
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        if (auto rich = richWords(handle)) {
            if (rich.Blocks().Size() != 1) return false;
            inlines = rich.Blocks().GetAt(0).as<documents::Paragraph>().Inlines();
            highlighters = rich.TextHighlighters();
        }
        if (count < 0 || inlines.Size() != static_cast<uint32_t>(count)) return false;
        std::vector<documents::Run> pieces;
        std::vector<controls::TextBlock> children;
        std::vector<int32_t> lengths;
        pieces.reserve(count);
        children.reserve(count);
        lengths.reserve(count);
        // Validate before changing anything. A paint-only update keeps native
        // paragraphs and image objects, including their already uploaded pixels.
        for (int32_t index = 0; index < count; ++index) {
            auto piece = inlines.GetAt(index).try_as<documents::Run>();
            auto const &run = runs[index];
            auto symbol = run.glyph && *run.glyph;
            auto image = run.imagePixelWidth > 0 || (run.image && *run.image);
            auto words = text(symbol ? run.glyph : run.text);
            controls::TextBlock child{nullptr};
            if (piece) {
                if (image || run.baseline != 0 || piece.Text() != words) return false;
            } else {
                auto holder = inlines.GetAt(index).try_as<documents::InlineUIContainer>();
                if (!holder) return false;
                auto content = inlineContent(holder);
                child = content.try_as<controls::TextBlock>();
                if (image) {
                    if (!content.try_as<controls::Image>()) return false;
                } else if (!child || child.Text() != words) return false;
            }
            pieces.push_back(piece);
            children.push_back(child);
            lengths.push_back(image ? 1 : static_cast<int32_t>(words.size()));
        }
        uint32_t painted = 0;
        int32_t at = 0;
        for (int32_t index = 0; index < count; ++index) {
            auto const &piece = pieces[index];
            auto const &run = runs[index];
            if (piece) {
                auto property = documents::TextElement::ForegroundProperty();
                auto local = piece.ReadLocalValue(property) != xaml::DependencyProperty::UnsetValue();
                if (run.hasColor) {
                    if (!local || argb(piece.Foreground()) != run.color)
                        piece.Foreground(media::SolidColorBrush(color(run.color)));
                } else if (local) {
                    piece.ClearValue(property);
                }
            } else if (auto child = children[index]) {
                child.Foreground(run.hasColor ? media::SolidColorBrush(color(run.color)) : block.Foreground());
                child.Resources().Insert(winrt::box_value(L"SwiftOmniUIInlineInheritsForeground"), winrt::box_value(!run.hasColor));
            }
            auto length = lengths[index];
            if (run.hasBackground && length > 0) {
                auto highlighter = painted < highlighters.Size()
                    ? highlighters.GetAt(painted) : documents::TextHighlighter();
                if (!highlighter.Background() || argb(highlighter.Background()) != run.background)
                    highlighter.Background(media::SolidColorBrush(color(run.background)));
                if (run.hasColor) {
                    // An explicit colour must own its brush even if it equals
                    // the inherited colour, so later parent changes leave it alone.
                    if (!highlighter.Foreground() || highlighter.Foreground() == block.Foreground()
                        || argb(highlighter.Foreground()) != run.color)
                        highlighter.Foreground(media::SolidColorBrush(color(run.color)));
                } else if (highlighter.Foreground() != block.Foreground()) {
                    highlighter.Foreground(block.Foreground());
                }
                auto ranges = highlighter.Ranges();
                if (ranges.Size() != 1 || ranges.GetAt(0).StartIndex != at || ranges.GetAt(0).Length != length) {
                    ranges.Clear();
                    ranges.Append(documents::TextRange{at, length});
                }
                if (painted == highlighters.Size()) highlighters.Append(highlighter);
                ++painted;
            }
            at += length;
        }
        while (highlighters.Size() > painted) highlighters.RemoveAtEnd();
        return true;
    } catch (...) {
        // The caller retains a complete description and can restore it.
        return false;
    }
}

extern "C" int32_t swiftomniui_winui_text_runs(SwiftOmniUIObjectRef handle, double *values, int32_t capacity) {
    try {
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        using winrt::Windows::UI::Text::TextDecorations;
        auto block = labelWords(handle);
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        if (auto rich = richWords(handle); rich && rich.Blocks().Size() == 1) {
            inlines = rich.Blocks().GetAt(0).as<documents::Paragraph>().Inlines();
            highlighters = rich.TextHighlighters();
        }
        int32_t count = 0, at = 0;
        for (auto const &piece : inlines) {
            auto run = piece.try_as<documents::Run>();
            controls::TextBlock child{nullptr};
            if (auto holder = piece.try_as<documents::InlineUIContainer>())
                child = inlineContent(holder).try_as<controls::TextBlock>();
            auto length = run ? static_cast<int32_t>(run.Text().size())
                : child ? static_cast<int32_t>(child.Text().size()) : 1;
            double background = 0;
            for (auto const &highlighter : highlighters)
                for (auto const &range : highlighter.Ranges())
                    if (range.StartIndex == at && range.Length == length) background = argb(highlighter.Background());
            if (6 * (count + 1) <= capacity) {
                auto *slot = values + 6 * count;
                slot[0] = run ? (run.ReadLocalValue(documents::TextElement::ForegroundProperty()) == xaml::DependencyProperty::UnsetValue()
                    ? 0 : argb(run.Foreground())) : child ? argb(child.Foreground()) : 0;
                slot[1] = run ? (run.ReadLocalValue(documents::TextElement::FontSizeProperty()) == xaml::DependencyProperty::UnsetValue()
                    ? 0 : run.FontSize()) : child ? child.FontSize() : 0;
                slot[2] = run ? run.FontWeight().Weight : child ? child.FontWeight().Weight : block.FontWeight().Weight;
                auto style = run ? run.FontStyle() : child ? child.FontStyle() : block.FontStyle();
                slot[3] = style == winrt::Windows::UI::Text::FontStyle::Italic ? 1 : 0;
                auto lines = run ? run.TextDecorations() : child ? child.TextDecorations() : TextDecorations::None;
                slot[4] = ((lines & TextDecorations::Underline) == TextDecorations::Underline ? 1 : 0)
                    + ((lines & TextDecorations::Strikethrough) == TextDecorations::Strikethrough ? 2 : 0);
                slot[5] = background;
            }
            ++count;
            at += length;
        }
        return count;
    } catch (...) {
        report("reading a label's runs");
        return 0;
    }
}

extern "C" void swiftomniui_winui_text_set_decorations(SwiftOmniUIObjectRef handle, bool underline, bool strikethrough) {
    try {
        using winrt::Windows::UI::Text::TextDecorations;
        auto lines = TextDecorations::None;
        if (underline) lines = lines | TextDecorations::Underline;
        if (strikethrough) lines = lines | TextDecorations::Strikethrough;
        labelWords(handle).TextDecorations(lines);
        if (auto rich = richWords(handle))
            for (auto const &value : rich.Blocks())
                if (auto paragraph = value.try_as<documents::Paragraph>()) paragraph.TextDecorations(lines);
    } catch (...) {
        report("decorating a label's words");
    }
}

extern "C" void swiftomniui_winui_text_style(SwiftOmniUIObjectRef handle, double *style) {
    try {
        either(handle,
            [&](controls::TextBlock const &block) {
                style[0] = block.FontSize();
                style[1] = block.FontWeight().Weight;
                style[2] = block.MaxLines();
                style[3] = static_cast<double>(block.TextAlignment());
                style[4] = argb(block.Foreground());
            },
            [&](controls::Control const &control) {
                style[0] = control.FontSize();
                style[1] = control.FontWeight().Weight;
                style[2] = 0;
                style[3] = 0;
                style[4] = argb(control.Foreground());
            });
    } catch (...) {
        report("reading how words look");
    }
}

extern "C" double swiftomniui_winui_text_baseline(SwiftOmniUIObjectRef handle, double height) {
    try {
        auto block = labelWords(handle);
        if (auto rich = richWords(handle)) {
            auto extra = std::max(0.0, height - static_cast<double>(rich.DesiredSize().Height));
            auto shift = rich.VerticalAlignment() == xaml::VerticalAlignment::Center ? extra / 2
                : rich.VerticalAlignment() == xaml::VerticalAlignment::Bottom ? extra : 0;
            return rich.BaselineOffset() + shift;
        }
        auto extra = std::max(0.0, height - static_cast<double>(block.DesiredSize().Height));
        auto shift = block.VerticalAlignment() == xaml::VerticalAlignment::Center ? extra / 2
            : block.VerticalAlignment() == xaml::VerticalAlignment::Bottom ? extra : 0;
        return block.BaselineOffset() + shift;
    } catch (...) { report("reading the first text baseline"); return -1; }
}

extern "C" double swiftomniui_winui_text_whitespace_width(SwiftOmniUIObjectRef handle) {
    try {
        auto block = labelWords(handle);
        auto words = block.Text();
        auto family = block.FontFamily().Source();
        auto size = block.FontSize();
        auto weight = block.FontWeight().Weight;
        auto style = block.FontStyle();
        auto spacing = block.CharacterSpacing();
        if (block.Inlines().Size()) {
            // Attributed Text stores even a standalone space in a Run.
            if (block.Inlines().Size() != 1) return 0;
            auto run = block.Inlines().GetAt(0).try_as<documents::Run>();
            if (!run) return 0;
            words = run.Text();
            family = run.FontFamily().Source(); size = run.FontSize();
            weight = run.FontWeight().Weight; style = run.FontStyle(); spacing = run.CharacterSpacing();
        }
        if (words.empty() || !std::all_of(words.begin(), words.end(), [](wchar_t ch) { return ch == L' ' || ch == L'\t'; }))
            return 0;
        auto key = std::make_tuple(std::wstring(family.c_str(), family.size()), size, weight,
                                   static_cast<int32_t>(style), spacing,
                                   std::wstring(words.c_str(), words.size()));
        static std::map<decltype(key), double> widths;
        if (auto found = widths.find(key); found != widths.end()) return found->second;
        double extent[2] = {};
        if (!swiftomniui_winui_measure_text(winrt::to_string(words).c_str(), winrt::to_string(family).c_str(),
                size, weight, style != winrt::Windows::UI::Text::FontStyle::Normal, 0, extent)) return 0;
        auto width = extent[0] + std::max<int32_t>(0, static_cast<int32_t>(words.size()) - 1)
            * spacing * size / 1000;
        if (widths.size() >= 256) widths.clear();
        widths.emplace(key, width);
        return width;
    } catch (...) { report("measuring whitespace in a text flow"); return 0; }
}

static int32_t readCharacterGeometry(SwiftOmniUIObjectRef handle, double *rectangles, int32_t capacity,
                                     int32_t *lineCount, bool reuseLeadingCarets);

extern "C" int32_t swiftomniui_winui_text_character_rects(
    SwiftOmniUIObjectRef handle, double *rectangles, int32_t capacity
) {
    // Keep the compatibility reader's two-affinity path as a geometry reference.
    return readCharacterGeometry(handle, rectangles, capacity, nullptr, false);
}

extern "C" int32_t swiftomniui_winui_text_character_geometry(
    SwiftOmniUIObjectRef handle, double *rectangles, int32_t capacity, int32_t *lineCount
) {
    return readCharacterGeometry(handle, rectangles, capacity, lineCount, true);
}

static int32_t readCharacterGeometry(SwiftOmniUIObjectRef handle, double *rectangles, int32_t capacity,
                                     int32_t *lineCount, bool reuseLeadingCarets) {
    if (lineCount) *lineCount = 0;
    try {
        auto block = labelWords(handle);
        auto coordinates = as<xaml::UIElement>(handle);
        int32_t at = 0;
        auto rich = richWords(handle);
        auto visual = rich ? rich.as<xaml::UIElement>() : block.as<xaml::UIElement>();
        auto transform = visual.TransformToVisual(coordinates);
        // The text normally sits in its Border with only a vertical alignment
        // offset. Snapshot that translation once instead of invoking XAML's
        // GeneralTransform for every glyph. Other transforms retain the native path.
        std::optional<winrt::Windows::Foundation::Point> translation;
        if (reuseLeadingCarets) if (auto matrix = transform.try_as<xaml::Media::MatrixTransform>()) {
            auto value = matrix.Matrix();
            if (value.M11 == 1 && value.M12 == 0 && value.M21 == 0 && value.M22 == 1)
                translation = winrt::Windows::Foundation::Point{
                    static_cast<float>(value.OffsetX), static_cast<float>(value.OffsetY)};
        }
        auto advance = rich ? rich.LineHeight() : block.LineHeight();
        struct Row {
            double ascent = 0, descent = 0;
            void include(NaturalWordsMetrics const &metrics) {
                ascent = std::max(ascent, metrics.baseline);
                descent = std::max(descent, metrics.height - metrics.baseline);
            }
            double height() const { return ascent + descent; }
        };
        struct Glyph { winrt::Windows::Foundation::Rect rect; float row; bool ownBounds; };
        std::map<float, Row> rows;
        std::vector<Glyph> glyphs;
        glyphs.reserve(std::max(0, capacity));
        // For a unidirectional LTR document, the next leading caret is the
        // current trailing caret except at a line/run boundary. Read it once
        // and reuse it for the following character. Mixed bidi documents keep
        // both native affinities; guessing at their run boundaries is unsafe.
        auto plain = block.Text();
        bool leadingCarets = reuseLeadingCarets && block.FlowDirection() == xaml::FlowDirection::LeftToRight && !plain.empty();
        if (leadingCarets) {
            std::vector<WORD> directions(plain.size());
            std::vector<WORD> clusters(plain.size());
            leadingCarets = GetStringTypeW(CT_CTYPE2, plain.c_str(), static_cast<int>(plain.size()), directions.data());
            leadingCarets = leadingCarets && GetStringTypeW(CT_CTYPE3, plain.c_str(), static_cast<int>(plain.size()), clusters.data());
            for (size_t i = 0; leadingCarets && i < plain.size(); ++i) {
                auto ch = plain[i];
                if (directions[i] == C2_RIGHTTOLEFT || directions[i] == C2_ARABICNUMBER
                    || (clusters[i] & (C3_NONSPACING | C3_DIACRITIC | C3_VOWELMARK | C3_HIGHSURROGATE | C3_LOWSURROGATE))
                    || (ch >= 0x202a && ch <= 0x202e) || (ch >= 0x2066 && ch <= 0x2069)) leadingCarets = false;
            }
        }
        bool valid = true;
        auto rowAt = [&](winrt::Windows::Foundation::Rect const &rect, NaturalWordsMetrics metrics) {
            if (rect.Height <= 0) return rect.Y; // A trimmed character has no visible bounds.
            auto found = rows.lower_bound(rect.Y - 0.5f);
            if (found == rows.end() || std::abs(found->first - rect.Y) >= 0.5f)
                found = rows.emplace(rect.Y, Row{}).first;
            found->second.include(metrics);
            return found->first;
        };
        auto append = [&](documents::TextPointer const &start, std::wstring_view string, NaturalWordsMetrics metrics,
                          xaml::UIElement const &owner = nullptr, documents::TextPointer const &parent = nullptr) {
            auto position = start;
            auto local = owner ? owner.TransformToVisual(visual) : nullptr;
            auto parentRect = parent ? parent.GetCharacterRect(documents::LogicalDirection::Forward)
                                     : winrt::Windows::Foundation::Rect{};
            std::optional<winrt::Windows::Foundation::Rect> nextLeading;
            float lastRowY = std::numeric_limits<float>::quiet_NaN(), lastRow = 0;
            for (int32_t i = 0; i < static_cast<int32_t>(string.size()) && at < capacity; ++i, ++at) {
                if (!position) { valid = false; return; }
                auto rect = nextLeading ? *nextLeading : position.GetCharacterRect(documents::LogicalDirection::Forward);
                nextLeading.reset();
                auto rowRect = parent ? parentRect : rect;
                if (rowRect.Height <= 0 || rowRect.Y != lastRowY) {
                    lastRow = rowAt(rowRect, metrics);
                    lastRowY = rowRect.Height > 0 ? rowRect.Y : std::numeric_limits<float>::quiet_NaN();
                }
                auto row = lastRow;
                auto next = position.GetPositionAtOffset(1, documents::LogicalDirection::Forward);
                // X comes from native caret affinities, including bidi and soft
                // wraps. No second typesetter is used to choose line breaks.
                if (next) {
                    if (leadingCarets && i + 1 < static_cast<int32_t>(string.size()))
                        nextLeading = next.GetCharacterRect(documents::LogicalDirection::Forward);
                    auto end = nextLeading && nextLeading->Height > 0 && std::abs(rect.Y - nextLeading->Y) < 0.5f
                        ? *nextLeading : next.GetCharacterRect(documents::LogicalDirection::Backward);
                    if (rect.Height > 0 && end.Height > 0 && std::abs(rect.Y - end.Y) < 0.5f) {
                        auto left = std::min(rect.X, end.X);
                        rect.Width = std::abs(end.X - rect.X); rect.X = left;
                    }
                }
                if (local) rect = local.TransformBounds(rect);
                glyphs.push_back({rect, row, owner != nullptr});
                position = next;
            }
            // A trailing explicit newline creates a native empty final line.
            if (!string.empty() && (string.back() == L'\n' || string.back() == L'\r') && position && !parent)
                rowAt(position.GetCharacterRect(documents::LogicalDirection::Forward), metrics);
        };
        auto metricsFor = [&](controls::TextBlock const &owner, documents::Run const &run = nullptr) {
            return advance > 0 ? naturalWordsMetrics(owner, run) : NaturalWordsMetrics{};
        };
        if (!rich && block.Inlines().Size() == 0) {
            auto words = block.Text();
            append(block.ContentStart(), std::wstring_view(words.c_str(), words.size()), metricsFor(block));
        } else {
            std::function<void(documents::Inline const &)> visit = [&](documents::Inline const &inlineValue) {
                if (auto run = inlineValue.try_as<documents::Run>()) {
                    auto words = run.Text();
                    append(run.ContentStart(), std::wstring_view(words.c_str(), words.size()), metricsFor(block, run));
                } else if (auto span = inlineValue.try_as<documents::Span>()) {
                    for (auto const &child : span.Inlines()) visit(child);
                } else if (auto holder = inlineValue.try_as<documents::InlineUIContainer>()) {
                    auto content = inlineContent(holder);
                    if (auto child = content.try_as<controls::TextBlock>()) {
                        auto words = child.Text();
                        append(child.ContentStart(), std::wstring_view(words.c_str(), words.size()), metricsFor(child),
                               child, holder.ContentStart());
                    } else if (content && at < capacity) {
                        auto height = content.ActualHeight();
                        auto baseline = height;
                        if (auto paragraph = holder.Child().try_as<controls::RichTextBlock>()) baseline = paragraph.BaselineOffset();
                        auto row = rowAt(holder.ContentStart().GetCharacterRect(documents::LogicalDirection::Forward),
                                         {height, baseline});
                        auto rect = content.TransformToVisual(visual).TransformBounds(
                            {0, 0, static_cast<float>(content.ActualWidth()), static_cast<float>(height)});
                        glyphs.push_back({rect, row, true}); ++at;
                    } else if (at < capacity) {
                        append(inlineValue.ContentStart(), L"\uFFFC", metricsFor(block));
                    }
                } else if (inlineValue.try_as<documents::LineBreak>()) {
                    append(inlineValue.ContentStart(), L"\n", metricsFor(block));
                } else {
                    append(inlineValue.ContentStart(), L"\uFFFC", metricsFor(block));
                }
            };
            if (rich) {
                for (auto const &value : rich.Blocks()) if (auto paragraph = value.try_as<documents::Paragraph>())
                    for (auto const &inlineValue : paragraph.Inlines()) visit(inlineValue);
            } else {
                for (auto const &inlineValue : block.Inlines()) visit(inlineValue);
            }
        }
        if (!valid || (at > 0 && rows.empty())) return 0; // Native Arrange has not supplied visible positions.
        if (lineCount) *lineCount = static_cast<int32_t>(std::max<size_t>(1, rows.size()));
        NaturalWordsMetrics defaults{};
        if (advance > 0) defaults = naturalWordsMetrics(block);
        // Plain TextBlock can keep XAML's DirectWrite fast path. Its caret
        // tops already follow the baseline interval. Rich text's first-line
        // advance is trimmed instead; observe that native geometry rather
        // than assuming every TextBlock uses the same internal formatter.
        bool caretTopsFollowBaselines = false;
        if (advance > 0 && rows.size() > 1) {
            auto first = rows.begin(), second = std::next(first);
            caretTopsFollowBaselines = std::abs(second->first - first->first - advance) < 0.5
                && std::abs(advance - first->second.height()) > 0.5;
        }
        for (size_t i = 0; i < glyphs.size(); ++i) {
            auto rect = glyphs[i].rect;
            if (advance > 0 && rect.Height > 0 && !glyphs[i].ownBounds) {
                // XAML's caret rectangles describe the full line advance,
                // including the gap. Adapt them to the natural text alignment
                // box using the same font metrics as the native baseline rule.
                // This changes selection geometry, never text layout or drawing.
                auto const &row = rows.at(glyphs[i].row);
                auto height = row.height();
                if (height > 0 && defaults.height > 0) {
                    if (!caretTopsFollowBaselines && glyphs[i].row != rows.begin()->first)
                        rect.Y += static_cast<float>((advance - height) * defaults.baseline / defaults.height);
                    rect.Height = static_cast<float>(height);
                }
            }
            if (translation) {
                rect.X += translation->X; rect.Y += translation->Y;
            } else {
                rect = transform.TransformBounds(rect);
            }
            rectangles[i * 4] = rect.X; rectangles[i * 4 + 1] = rect.Y;
            rectangles[i * 4 + 2] = rect.Width; rectangles[i * 4 + 3] = rect.Height;
        }
        return at;
    } catch (...) { report("reading native text geometry"); return 0; }
}

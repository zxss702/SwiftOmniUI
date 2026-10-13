// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How words look, on a text block or on any control showing them: their font,
// their colour and the room around them; and a label's lines, alignment,
// spacing and decorations.
// Design: docs/design/platforms/winui/controls.md#words

#include "Relay.h"

#include <algorithm>
#include <string>

#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Text.h>
#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;

namespace {
    uint64_t fontProbes = 0;
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
        if (auto text = wordsOf(object)) block(text);
        else if (auto other = object.try_as<controls::Control>()) control(other);
    }
}

swiftomniui::TextFontDefaults swiftomniui::textFontDefaults(int32_t textStyle) {
    struct Probe {
        controls::TextBlock block{nullptr};
        xaml::Style style{nullptr};
    };
    static Probe probes[12];
    auto valid = textStyle >= 0 && textStyle < 11;
    auto &probe = probes[valid ? textStyle + 1 : 0];
    if (!probe.block) { probe.block = controls::TextBlock(); ++fontProbes; }
    xaml::Style style{nullptr};
    if (valid) {
        wchar_t const *styles[] = {L"TitleLargeTextBlockStyle", L"TitleTextBlockStyle", L"SubtitleTextBlockStyle",
            L"BodyLargeTextBlockStyle", L"BodyStrongTextBlockStyle", L"CaptionTextBlockStyle", L"BodyTextBlockStyle",
            L"BodyTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle"};
        if (auto application = xaml::Application::Current())
            style = application.Resources().TryLookup(winrt::box_value(styles[textStyle])).try_as<xaml::Style>();
    }
    // Resources can be replaced while the application runs. Reuse the native
    // reader, while still taking the current system/application Style object.
    if (style != probe.style) {
        if (style) probe.block.Style(style);
        else probe.block.ClearValue(xaml::FrameworkElement::StyleProperty());
        probe.style = style;
    }
    return {probe.block.FontSize(), probe.block.FontWeight().Weight};
}

extern "C" uint64_t swiftomniui_winui_font_probes(void) { return fontProbes; }

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
        auto block = labelWords(handle);
        block.TextWrapping(wraps ? xaml::TextWrapping::Wrap : xaml::TextWrapping::NoWrap);
        block.TextTrimming(trims ? xaml::TextTrimming::CharacterEllipsis : xaml::TextTrimming::None);
        block.MaxLines(std::max(0, lines));
    } catch (...) {
        report("setting a label's lines");
    }
}

extern "C" void swiftomniui_winui_text_set_alignment(SwiftOmniUIObjectRef handle, int32_t horizontal) {
    try {
        auto aligned = horizontal == 1 ? xaml::TextAlignment::Center
            : horizontal == 2 ? xaml::TextAlignment::End : xaml::TextAlignment::Start;
        labelWords(handle).TextAlignment(aligned);
    } catch (...) {
        report("aligning a label's words");
    }
}

extern "C" void swiftomniui_winui_text_set_spacing(SwiftOmniUIObjectRef handle, int32_t characterSpacing, double lineHeight) {
    try {
        auto block = labelWords(handle);
        block.CharacterSpacing(characterSpacing);
        block.LineStackingStrategy(lineHeight > 0 ? xaml::LineStackingStrategy::BlockLineHeight
                                                  : xaml::LineStackingStrategy::MaxHeight);
        block.LineHeight(lineHeight > 0 ? lineHeight : 0);
    } catch (...) {
        report("spacing a label's words");
    }
}

extern "C" void swiftomniui_winui_text_set_runs(SwiftOmniUIObjectRef handle, SwiftOmniUIWordsRun const *runs, int32_t count) {
    try {
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        using winrt::Windows::UI::Text::TextDecorations;
        auto block = labelWords(handle);
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        inlines.Clear();
        highlighters.Clear();
        int32_t at = 0;
        for (int32_t index = 0; index < count; ++index) {
            auto const &run = runs[index];
            // A picture or a glyph in the line stands as an inline element; a run raised on its baseline is a
            // block of its words shifted up in one too.
            if ((run.glyph && *run.glyph) || (run.image && *run.image) || run.baseline != 0) {
                documents::InlineUIContainer holder;
                if (run.glyph && *run.glyph) {
                    controls::TextBlock mark;
                    mark.FontFamily(media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
                    mark.Text(text(run.glyph));
                    if (run.size > 0) mark.FontSize(run.size);
                    if (run.hasColor) mark.Foreground(media::SolidColorBrush(color(run.color)));
                    holder.Child(mark);
                } else if (run.image && *run.image) {
                    controls::Image picture;
                    auto file = pictureFile(run.image);
                    if (!file.empty()) picture.Source(pictureSource(file));
                    holder.Child(picture);
                } else {
                    controls::TextBlock part;
                    part.Text(text(run.text));
                    if (run.hasColor) part.Foreground(media::SolidColorBrush(color(run.color)));
                    if (run.size > 0) part.FontSize(run.size);
                    if (run.bold) part.FontWeight(winrt::Microsoft::UI::Text::FontWeights::Bold());
                    if (run.italic) part.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);
                    if (run.family && *run.family) part.FontFamily(media::FontFamily(text(run.family)));
                    part.CharacterSpacing(run.spacing);
                    media::TranslateTransform shift;
                    shift.Y(-run.baseline);
                    part.RenderTransform(shift);
                    holder.Child(part);
                }
                inlines.Append(holder);
                at += (run.glyph && *run.glyph) || (run.image && *run.image) ? 1
                    : static_cast<int32_t>(text(run.text).size());
                continue;
            }
            documents::Run piece;
            auto words = text(run.text);
            piece.Text(words);
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
            if (run.hasBackground && length > 0) {
                documents::TextHighlighter highlighter;
                highlighter.Background(media::SolidColorBrush(color(run.background)));
                highlighter.Foreground(run.hasColor ? media::SolidColorBrush(color(run.color)) : block.Foreground());
                highlighter.Ranges().Append(documents::TextRange{at, length});
                highlighters.Append(highlighter);
            }
            at += length;
        }
    } catch (...) {
        report("setting a label's runs of words");
    }
}

extern "C" int32_t swiftomniui_winui_text_runs(SwiftOmniUIObjectRef handle, double *values, int32_t capacity) {
    try {
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        using winrt::Windows::UI::Text::TextDecorations;
        auto block = labelWords(handle);
        int32_t count = 0, at = 0;
        for (auto const &piece : block.Inlines()) {
            auto run = piece.try_as<documents::Run>();
            if (!run) continue;
            auto length = static_cast<int32_t>(run.Text().size());
            double background = 0;
            for (auto const &highlighter : block.TextHighlighters())
                for (auto const &range : highlighter.Ranges())
                    if (range.StartIndex == at && range.Length == length) background = argb(highlighter.Background());
            if (6 * (count + 1) <= capacity) {
                auto *slot = values + 6 * count;
                slot[0] = run.ReadLocalValue(documents::TextElement::ForegroundProperty()) == xaml::DependencyProperty::UnsetValue()
                    ? 0 : argb(run.Foreground());
                slot[1] = run.ReadLocalValue(documents::TextElement::FontSizeProperty()) == xaml::DependencyProperty::UnsetValue()
                    ? 0 : run.FontSize();
                slot[2] = run.FontWeight().Weight;
                slot[3] = run.FontStyle() == winrt::Windows::UI::Text::FontStyle::Italic ? 1 : 0;
                auto lines = run.TextDecorations();
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

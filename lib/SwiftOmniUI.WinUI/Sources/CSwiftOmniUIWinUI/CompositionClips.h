// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "Relay.h"
#include <winrt/Microsoft.UI.Composition.h>

namespace swiftomniui {
    /// Only clips authored by SOUI. Reading this must not acquire an element's
    /// handout Visual: that prevents its native owner from using XAML facades.
    winrt::Microsoft::UI::Composition::CompositionClip elementCompositionClip(xaml::UIElement const &element);

    /// Acquires the handout Visual only when installing or removing our clip.
    /// The element retains the clip record for exactly its own lifetime.
    void setElementCompositionClip(xaml::UIElement const &element,
                                  winrt::Microsoft::UI::Composition::CompositionClip const &clip);
}

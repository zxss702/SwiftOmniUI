// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include "Relay.h"
#include <d2d1.h>
#include <winrt/Microsoft.UI.Composition.h>

namespace swiftomniui {
    // Device-independent geometry shared by shape drawing and path clips.
    ID2D1Factory *pathFactory();
    winrt::com_ptr<ID2D1PathGeometry> pathGeometry(double const *commands, int32_t count, bool evenOdd);
    winrt::Microsoft::UI::Composition::CompositionPath compositionPath(
        winrt::com_ptr<ID2D1Geometry> const &path, bool evenOdd);
}

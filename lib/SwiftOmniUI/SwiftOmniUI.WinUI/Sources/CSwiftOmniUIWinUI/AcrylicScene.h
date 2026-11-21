// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "Relay.h"
#include <winrt/Microsoft.UI.Composition.h>
#include <memory>
#include <functional>
#include <optional>
#include <vector>

namespace swiftomniui {
    struct AcrylicScene;
    void commitAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, bool afterLayout);
    // Geometry and scroll-edge state for an attached column or local inset.
    std::shared_ptr<AcrylicScene> acrylicScene(xaml::FrameworkElement const &source,
                                             xaml::FrameworkElement const &target);
    xaml::FrameworkElement acrylicSceneRoot(std::shared_ptr<AcrylicScene> const &scene);
    winrt::Windows::Foundation::Rect acrylicVisibleBounds(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    bool hasAcrylicScrollerInsets() noexcept;
    void markAcrylicMaterialDirty() noexcept;
    bool takeAcrylicMaterialDirty() noexcept;
    void presentAcrylicScenes();
    std::vector<xaml::FrameworkElement> acrylicWindowRoots();
    bool acrylicSceneIsWindow(std::shared_ptr<AcrylicScene> const &scene);
    // Navigation columns never share captures or filters. Bounds are native
    // slot-local, including the column's slice of window chrome.
    std::vector<xaml::FrameworkElement> acrylicWindowColumns(xaml::FrameworkElement const &root);
    controls::Panel acrylicColumnOwner(xaml::FrameworkElement const &column, xaml::FrameworkElement const &root);
    winrt::Windows::Foundation::Rect acrylicSceneBounds(std::shared_ptr<AcrylicScene> const &scene);
    winrt::Windows::Foundation::Rect acrylicLayoutBounds(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    bool acrylicSceneContains(std::shared_ptr<AcrylicScene> const &scene, xaml::FrameworkElement const &element);
    std::vector<xaml::FrameworkElement> acrylicMarkersForBar(xaml::FrameworkElement const &target);
    enum class AcrylicEdge { fixed, top, bottom };
    struct AcrylicBand {
        winrt::Windows::Foundation::Rect rect{};
        bool active = true;
        xaml::FrameworkElement viewport{nullptr};
        bool spansViewport = false;
        AcrylicEdge edge = AcrylicEdge::fixed;
    };
    std::vector<winrt::Windows::Foundation::Rect> acrylicMaterialRegions(std::vector<AcrylicBand> const &bands);
    std::vector<AcrylicBand> acrylicColumnInsets(std::shared_ptr<AcrylicScene> const &scene);
    std::vector<AcrylicBand> acrylicLocalRegions(xaml::FrameworkElement const &marker, winrt::Windows::Foundation::Rect const &bounds);
    enum class AcrylicChromeMode { safeBar, automatic, visible, hidden };
    AcrylicChromeMode acrylicTitleBarMode(xaml::FrameworkElement const &titleBar);
    void setAcrylicTitleBarMode(xaml::FrameworkElement const &titleBar, AcrylicChromeMode mode);
    std::vector<AcrylicBand> acrylicChromeRegions(std::shared_ptr<AcrylicScene> const &scene,
        winrt::Windows::Foundation::Rect const &bounds, AcrylicChromeMode mode);
    void observeAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, std::function<bool()> observer);
    void registerAcrylicScroller(xaml::FrameworkElement const &scroller);
    void updateAcrylicScroller(xaml::FrameworkElement const &scroller, std::optional<xaml::Thickness> insets = {});
    void setAcrylicContentRoot(xaml::FrameworkElement const &root, xaml::FrameworkElement const &content);
    void acrylicStructureChanged(xaml::FrameworkElement const &element) noexcept;
}

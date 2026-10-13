<!-- Rendered by ControlDictionaryTests from the contracts and the verdicts each host's runs of its tests wrote under exports/marks: SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests writes it again. -->

# Layout

What every layout has: the screen's unsafe strips it keeps clear of, and whether its children are clipped or let input through.

Wears: [View](View.md) · [PaddingElement](PaddingElement.md) · [BorderElement](BorderElement.md)

Worn by: [CustomLayout](../CustomLayout.md) · [Grid](../Grid.md) · [GridRow](../GridRow.md) · [HStack](../HStack.md) · [LazyHGrid](../LazyHGrid.md) · [LazyHStack](../LazyHStack.md) · [LazyVGrid](../LazyVGrid.md) · [LazyVStack](../LazyVStack.md) · [Masked](../Masked.md) · [ScrollView](../ScrollView.md) · [VStack](../VStack.md) · [ZStack](../ZStack.md)

Declared in `lib/SwiftOmniUI/Sources/Contracts/Tiers/LayoutContract.swift`.

How each of them realizes these members is on its own page.

| Member | Kind | Value | Layer |
| --- | --- | --- | --- |
| `ignoresSafeArea` | property | `SafeAreaEdges` | adaptive |
| `clipsContent` | property | `Bool` | native |
| `letsInputThrough` | property | `Bool` | native |
| `hitShape` | property | `ContainerShape` | native |
| `scrollTargetLayout` | property | `Bool` | adaptive |
| `clipPath` | property | `[Double]` | native |
| `clipFillRule` | property | `FillRule` | native |

# StateUI 内核同步

共同祖先：StateUI `0.4.0`，`55fb6b132ff3e009aea1fb61184960158824e300`。
迁入终点：StateUI `0.7.1`，`1e760e941bbdb6d476b76b5c0b2b1750bc408dbb`。
Gallery 不在同步范围内。

优先沿用上游内部实现，每个独立批次验证后单独提交，不推送。

## 保留的 SOUI 语义

- public View API、身份、状态与动画事务遵循 SwiftUI。
- Apple 门面直接导出原生 SwiftUI；非 Apple 才接入自有内核。
- Observation、Preferences、Text.Layout、自定义 Layout 和 JsonData 桥接继续生效。
- SafeAreaBar、Toolbar 和导航分栏的原生布局、Acrylic 采样关系保留。
- 根 Package 通过 `#if os(...)` 选择平台，内部依赖使用 Target。
- 非 SwiftUI 的实现细节放在内部或 SPI；动画后端也属于上游同步范围。

## 批次

1. 目录对齐：核心放在 `lib/SwiftOmniUI/Core`，host 与扩展集中在
   `lib/SwiftOmniUI/SwiftOmniUI.*`，契约导出放在同级 `exports`。
2. 基础支持层：上游 Foundation 改名为内部 `SwiftOmniUIBase`，既有
   `SwiftOmniUIFoundation` 保持 SwiftUI 兼容扩展职责。
3. 数字契约键、身份、路径与状态遍历。
4. 每层 body 的依赖与派生状态、差分和生命周期修复。
5. executor、Cycle、动画后端、Host 更新和集合合批。
6. 控件、窗口、绘制及平台 backend 的其余适用修复。

对应回归随实现迁入。上游工作量基准用于检查重复工作，Windows 原生绘制与
像素检查仍用于验证 LazyStack；ItemsView 的改进不等于 LazyStack 已无白屏。

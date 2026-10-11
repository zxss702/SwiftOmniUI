# SwiftUI-subset migration — plan & handoff

把 SwiftOmniUI 从「自写引擎 + 每平台原生 host」翻转为「**SwiftUI 兼容子集的门面**」：
`import SwiftOmniUI` 在 Apple 平台等价于 `import SwiftUI`，在非 Apple 平台等价于
今天的 `import DefaultUI`（引擎 + Foundation + JsonData 三件 re-export）。

参照对象：LogorythiaUI 的 `Sources/DefaultUI/DefaultUI.swift` —— 这次迁移就是把
那个文件搬进 SOUI 本体，让 `import DefaultUI` 这个中间层消失。

## 目标形态

```
app code                import SwiftOmniUI        // 唯一 UI import
                              │
                ┌─────────────┴─────────────┐
        #if canImport(SwiftUI)          #else
                │                           │
        @_exported import         @_spi(Host) @_exported import SwiftOmniUICore
          SwiftUI + Foundation    @_exported import SwiftOmniUIFoundation
                                  @_exported import SwiftOmniUIJsonData
                │                           │
        Apple 真 SwiftUI            SOUI 引擎（GTK / WinUI / Android / Web）
```

- `SwiftOmniUICore`：原 `SwiftOmniUI` target 改名而来，`lib/SwiftOmniUI/Sources`
  路径不动。全平台编译，macOS 上继续跑 core 测试。
- `SwiftOmniUI`：新单文件门面 target。产品名 `SwiftOmniUI` 指向它。
- `SwiftOmniUIHost` / `Conformance` / `Foundation` / `JsonData` / `Head` / 各
  backend / 全部测试 target：依赖与 `import` 一律改指 `SwiftOmniUICore`。

约束与推论：

- **内部代码不可再 `import SwiftOmniUI`**——在 Apple 平台上它会拿到 SwiftUI 而
  不是引擎。凡在 macOS 上参与编译的 target（core Tests、Host、Conformance、
  Foundation、JsonData）都必须改；backend 源文件虽然能靠门面的 re-export 侥幸
  编译，但统一改指 `SwiftOmniUICore`，不依赖 `@_spi` 透传的未验证行为。
- 字符串层面只有两处写死模块名：`App.swift` 的 `"SwiftOmniUI.Page(\(kind))"`
  节点类型名，GTK/WinUI 各一处 `SwiftOmniUI.Size` 限定名 → `SwiftOmniUICore.*`。
  exports/marks 是 contract token，不含模块名，不受影响。
- Apple 端会链进死引擎（依赖无条件保留：Linux `host == nil` 时门面仍需三件
  依赖在场）。体积代价接受。
- `SwiftOmniUIFoundation` / `SwiftOmniUIJsonData` 产品保留：非 Apple 端经门面
  re-export；Apple 端不引它们（与 DefaultUI 现状一致——`@Query` 等在 macOS 上
  由 `import JsonData` → SwiftData 提供）。

## 移除清单（Phase 2）

Apple 已有 SwiftUI 实现的 host 实现整体删除：

- `lib/SwiftOmniUI.AppKit/`、`lib/SwiftOmniUI.UIKit/`（Sources + Tests）
- `.scripts/AppKit/`、`.scripts/UIKit/`
- `exports/appkit.txt`、`exports/uikit.txt`、`exports/marks/appkit/`、
  `exports/marks/uikit/`
- `docs/hosts/appkit.md`、`docs/hosts/uikit.md`、`docs/design/platforms/appkit/`、
  `docs/design/platforms/uikit/`
- `Package.swift`：host 数组删 `AppKit`/`UIKit`，两个 `case` 分支
- `lib/SwiftOmniUI.Head/Sources/SwiftOmniUIHead.swift`：删 `#if APPKIT` /
  `#elseif UIKIT` 两支
- `apps/Gallery/Platforms/{AppKit,UIKit}`、`apps/HelloWorld/Platforms/{AppKit,UIKit}`
- `test-native.sh`、`new-app.sh`、`lib/SwiftOmniUI.VSCode` 的 host 列表
- `docs/platform-contract.md`、`docs/controls/*.md` 走既有
  `SWIFTOMNIUI_UPDATE_EXPORTS` / `SWIFTOMNIUI_UPDATE_DOCS` 流程重生成

**已接受的代价**：macOS 上不再有任何真·host 端到端回归（core/Host/Conformance
单测仍在；真实 host 验证只有 GTK VM / Windows / Android / Web）。决议：直接删。

## Gallery 重做（Phase 3-4）

定位改为「**SwiftUI 兼容子集的活样本**」：同一份 Sources 在真 SwiftUI 与 SOUI
引擎上都编译，能编译的就是子集内 API——它本身成为子集覆盖度的验收器。

- **零 SPI**：共享 Sources 不出现任何 `@_spi` import。
  - `stateUIUseApp` → `App.main()`（public，SPI 调用在 core 内部）；
    `@_cdecl("swiftomniui_app_register")` 壳保留（Android/Web 按符号名找它），
    函数体改为 `GalleryApp.main()`。
  - `.hidesWhenInactive` / `.floatsOnTop`（SPI modifier）从样品中删除。
  - Interop 机制（`GalleryContract`/`GalleryElements`/`InteropHost`、各端
    `GalleryControls/Acts/EventSources` 注册、`Platforms/*/Relay|OpenGL|GLES|
    Java` 原生控件）**整套删除**——它是 host 扩展性演示，不是 API 演示。各
    head 缩为 ~5 行 `main.swift`（`GalleryApp.main()` + GTK/WinUI 的 WebView
    backend 注册）。
- **入口双端同形**：

  ```swift
  import SwiftOmniUI
  #if canImport(SwiftUI)
  @main
  #endif
  struct GalleryApp: App {
      var body: some Scene {
          WindowGroup { MainPage() }
          Window("Fonts", id: "fonts") { FontsWindow() }
      }
  }
  ```

  `Scene` 级 `@State`（nav/style/bar/log）改为 `@Observable` 类 +
  `.environment(object)`——`@Observable`/`@Bindable` 两边都通（SOUI 用真
  Observation）。
- **缺的 API 补进 SOUI**，不在 app 侧做假 API。已确认缺口：`WindowGroup` 缺
  `init(_:id:,content:)`（View-content 形式）；改写中陆续发现陆续补。
- **样品分档**：可写成真子集的改写（方言 modifier → 标准拼写）；SOUI-only
  概念（driven/engine、acts、DeviceInfo/Battery/Connectivity、Ticker/Poll、
  PageSession 等）`#if !canImport(SwiftUI)` 整组隐藏。
- `Platforms/{AppKit,UIKit}` 删除，新增 `Platforms/AppKit` **Xcode 工程**（照
  LUI：`@main extension GalleryApp {}`），只做 macOS；GTK/WinUI/Android/Web
  head 保留。
- `Tests/` 引擎相关用例 `#if !canImport(SwiftUI)`。HelloWorld 同法处理。

## LUI 收尾（Phase 5）

- 133 处 `import DefaultUI` → `import SwiftOmniUI`；删 `Sources/DefaultUI`
  target；manifest 移除对 `SwiftOmniUIFoundation`/`SwiftOmniUIJsonData` 的显式
  product 依赖。`import JsonData` / `import Observation` 不动。
- `#if canImport(SwiftUI)` 语义不变，仍是「是否在真 SwiftUI 上」的判断。
- 纪律红利：Apple 端 `import SwiftOmniUI` 只等于 SwiftUI，SCE 代码在 macOS
  碰不到 SOUI 内部，子集约束由编译器强制。

## 决议记录

| 问题 | 决议 |
|---|---|
| 引擎模块改名 | `SwiftOmniUICore` |
| macOS 失去真·host 端到端测试 | 接受，直接删 AppKit/UIKit |
| Gallery SOUI-only 样品在 Apple 端 | `#if` 隐藏，目录不含 |
| Apple head 范围 | 只 macOS（Xcode 工程，照 LUI） |
| Gallery 共享代码 SPI | 零容忍；interop 整套删除 |

## 每阶段验证

1. macOS 本机：`swift build && swift test --filter SwiftOmniUITests`（+ Host /
   Conformance / Foundation / JsonData 套件）。
2. Linux：`orb -m stateui-noble bash -c 'export PATH=/home/zhiyang/swift-6.4/usr/bin:$PATH
   && cd /Volumes/Develop/Packges/SwiftOmniUI && SWIFTOMNIUI_HOST=gtk xvfb-run -a
   swift test --filter SwiftOmniUIGTKTests'`。
3. Windows：tar-over-ssh 同步（禁 git），`.scripts/WinUI/test-winui.ps1` 经
   schtasks 派进交互会话，轮询 `artifacts\suite.log` 的 `EXIT=`。
4. Gallery / LUI 各端 `swift build`（LUI macOS 端用 Xcode toolchain）。

铁律不变：不做任何 git 写操作；每步最小修改；缺 API 补 SOUI；`#if` 只用于真
平台差异。

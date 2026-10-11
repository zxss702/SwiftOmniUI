# Upstream selective port — progress & handoff

摘取式合并（不做整体 merge，见 AGENTS.md「Upstream merges are cherry-picks, not merges」）。
全部工作已提交于 `8e765f394`（另加未提交的 `lib/SwiftOmniUI.Web/Package.swift` floor 降级）。

## 已完成

### 六端 WebView

| 端 | 状态 |
|---|---|
| GTK | `lib/Backends/WebView.GTK` 从上游整包落地；**真机验证**：OrbStack VM 中 WebKitGTK 13/13 成员、7 个 conformance session 全过 |
| WinUI | `lib/Backends/WebView.WinUI` 整包落地（C++/WinRT relay + `SwiftOmniUIWebViewWinUI.register()`），`unrealized` 摘除；**待 Windows 实机验证** |
| Web | `SwiftOmniUIWeb` 内 WebView=iframe，随 Web 宿主落地 |
| Android | 宿主内建，exports 已有成员（端口工作暂停，见下） |

### Core/Host（文件对话框）

`ChosenFile`/`FileType`/`FileToolkit`/`HostFileDialog` + `AppContract` 五 act
（`openFiles`/`saveFile`/`readFile`/`launchFile`/`launchLink`，token 与上游一致，
`chooseFiles` 保留）+ `PropValue.bytes` + conformance。Host 308 测试绿。
`.fileImporter` public API 未变。⚠️ `Dialogs.openFiles`/`saveFile` 等上游词表目前 public，
按「SwiftUI 子集」原则应降为 internal/`@_spi(Host)` —— 待审。

### GTK 附带修复

scroll/list 60 帧 settle、`place(of:)`/`focused`/`scrollHolds` driver acts、
`hideOnScreenKeyboard` 上游语义、样式表 `collection` 类。

### `.scripts/` 全量同步

新增 `deploy.sh`/`deploy.ps1`/`.scripts/Web/`；`tools.ps1` 含 SelfContained backend 钩子
+ Swift runtime 跨架构部署，路径已适配本地布局。

### WinUI `Files.cpp` 修复

5 个裸 `.Completed` lambda 已包 `guarded()`（防 C++ 异常逃出回调终结进程），
`testNoCppExceptionLeavesARelaysHandler` 绿。

## 已暂停 / 待续（SCE 不挡路）

### Android 成员缺口（部分 Java 已落地）

- 已落：`SwiftOmniUIScrollView`/`SwiftOmniUIHorizontalScrollView`（`scrollable`→`isScrollDisabled`）、
  `SwiftOmniUIViewGroup`（`letsInputThrough`/`hitShape`）、`SwiftOmniUIViews.blur`（RenderEffect 31+）、
  `SwiftOmniUIMenus.popup`、`JavaAPI.swift` 全套 JNI 绑定。
- 待做：Swift 侧成员接线 + **Map/Pin 全家** + acts
  （`localizedString`/`moveToRegion`/`scrollToDescendant`/`persistSceneValue`/文件 acts）
  + Lazy 成员注册管线核查（`exports/android.txt` 可能是旧快照）。

### Web 宿主未覆盖项（我们的增量，上游没有）

- Lazy 全家（0 注册）；全元素特效 `blur`/`shadow`/`transition`/animation/
  `matchedGeometry`/`symbolEffect`/`controlSize`/`flex`/`tag`
  （Web 的 `VisualElementContract` 只覆盖 7 个成员）；
  `Masked`/`CustomLayout`/`ModalStack`/`Popover`/`Sheet`/`FileImporter` 等 → 进 `unrealized` 报告。
- WASM 编译未验证（Swift SDK 已装：`swift build --swift-sdk` in `lib/SwiftOmniUI.Web`）。

## 验证待办

- [ ] Windows 同步 + WinUI 套件（`.scripts/WinUI/test-winui.ps1`，交互会话计划任务）
- [ ] GTK exports 再生后复测（VM: `SWIFTOMNIUI_UPDATE_EXPORTS=1 xvfb-run -a swift test`）
- [ ] `SWIFTOMNIUI_UPDATE_DOCS=1 swift test --filter ControlDictionaryTests`（core）
- [ ] GTK VM 环境需 `libwebkitgtk-6.0-dev` + `fonts-ubuntu` + `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`（webview 测试）
- [ ] `exports/`、`exports/marks/`、`docs/controls/` 再生产物提交

## 后续（明确排在迁移之后）

改名 SwiftOmniUI + remote 重指 + 署名 + VSCode 插件重装 → 等 SCE→LogorythiaUI 迁移指示。

# rename app to Fl PiCraft

## Goal

把面向用户的"应用名称"统一改成 **Fl PiCraft**，并把 **macOS** 构建产物从
`fl_picraft.app` 改成 `Fl PiCraft.app`。仅触及"展示名"层级的字段，不动 Dart package
name、Android applicationId、iOS / macOS bundle id 等技术标识符，确保 52 个测试 import
不变、Android 升级路径不破裂。

## Requirements

### R1. 跨平台 display name 改为 `Fl PiCraft`

| Platform | File | Field | Before | After |
|---|---|---|---|---|
| iOS | `ios/Runner/Info.plist` | `CFBundleDisplayName` | `Fl Picraft` | `Fl PiCraft` |
| iOS | `ios/Runner/Info.plist` | `CFBundleName` | `fl_picraft` | `Fl PiCraft` |
| Android | `android/app/src/main/AndroidManifest.xml` | `android:label` | `fl_picraft` | `Fl PiCraft` |
| macOS | `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME` | `fl_picraft` | `Fl PiCraft` |
| Linux | `linux/runner/my_application.cc` (L48 / L52) | `gtk_*_set_title` | `"fl_picraft"` | `"Fl PiCraft"` |
| Windows | `windows/runner/Runner.rc` (L93 / L98) | `FileDescription` / `ProductName` | `fl_picraft` | `Fl PiCraft` |
| Windows | `windows/runner/main.cpp` (L30) | `window.Create(L"...")` | `L"fl_picraft"` | `L"Fl PiCraft"` |
| Web | `web/index.html` (L26 / L32) | `apple-mobile-web-app-title` / `<title>` | `fl_picraft` | `Fl PiCraft` |
| Web | `web/manifest.json` | `name` / `short_name` | `fl_picraft` | `Fl PiCraft` |

### R2. macOS .app 文件名同步重命名

`PRODUCT_NAME` 改了之后，下列硬编码 `fl_picraft.app` 字符串必须同步：

- `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` —— 4 处 `BuildableName="fl_picraft.app"` → `BuildableName="Fl PiCraft.app"`
- `macos/Runner.xcodeproj/project.pbxproj`：
  - 3 处 `fl_picraft.app` 路径 → `Fl PiCraft.app`
  - 3 处 `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/fl_picraft.app/.../fl_picraft"` → `Fl PiCraft.app/.../Fl PiCraft`

### R3. 保留不动的技术标识符

- `pubspec.yaml` 的 `name: fl_picraft` 保持不变
- `package:fl_picraft/...` 这 52 个测试 import 不动
- Android `namespace` / `applicationId = com.mallotec.reb.fl_picraft` 不变
- iOS / macOS bundle identifier 不变
- Linux `BINARY_NAME = fl_picraft` / Windows `BINARY_NAME = fl_picraft` 保持小写无空格（CLI 友好）
- Windows `windows/CMakeLists.txt` 顶部 `project(fl_picraft ...)` 不变

### R4. 文档同步

- `README.md` L1 `# fl_picraft` → `# Fl PiCraft`

## Acceptance Criteria

- [ ] AC1. iOS 模拟器桌面图标下方 / 系统设置应用列表显示 `Fl PiCraft`
- [ ] AC2. Android 模拟器启动器显示 `Fl PiCraft`
- [ ] AC3. `flutter clean && flutter build macos --debug` 产物为 `build/macos/Build/Products/Debug/Fl PiCraft.app`
- [ ] AC4. macOS 应用启动后菜单栏与窗口标题显示 `Fl PiCraft`
- [ ] AC5. Linux 应用窗口标题显示 `Fl PiCraft`（如本机有 Linux 环境则验证；否则人工 review my_application.cc）
- [ ] AC6. Windows 资源 ProductName / 窗口标题字符串为 `Fl PiCraft`（人工 review .rc / main.cpp 即可）
- [ ] AC7. Web 端 `<title>` / PWA `manifest.json` 中 `name` 均为 `Fl PiCraft`
- [ ] AC8. `flutter analyze` 0 warning，`flutter test` 全部通过
- [ ] AC9. README 顶部为 `# Fl PiCraft`
- [ ] AC10. `package:fl_picraft/...` 这 52 个 import 在测试中保持不变

## Definition of Done

- 所有 AC 勾选完成
- `dart format .`、`flutter analyze`、`flutter test` 三件套均干净
- 本地验证 `flutter build macos --debug`（至少 Debug 构建）产生 `Fl PiCraft.app`
- 提交前 review：`rg "fl_picraft"` 仅余下"该保留"的位置（pubspec name、applicationId、test imports、BINARY_NAME、README 之外的 Markdown 历史记录）

## Technical Approach

### 实施顺序（按平台分批，单个 commit/PR 中完成）

1. **Display name 批次**（不依赖 Xcode 元数据，先做）：
   - iOS `Info.plist`、Android `AndroidManifest.xml`、Linux `my_application.cc`、Windows `Runner.rc` + `main.cpp`、Web `index.html` + `manifest.json`、README
2. **macOS PRODUCT_NAME + .app 改名批次**（牵动 Xcode 元数据，单独成组）：
   - `AppInfo.xcconfig` 改 `PRODUCT_NAME`
   - `Runner.xcscheme` 4 处 BuildableName
   - `project.pbxproj` 3 处路径 + 3 处 TEST_HOST
3. **质量收尾**：`dart format .` → `flutter analyze` → `flutter test` → `flutter clean && flutter build macos --debug` 验证产物名

### 关键约束

- **`PRODUCT_NAME` 的传播链路**：xcconfig 改一处 → macOS `Info.plist` 的 `CFBundleName = $(PRODUCT_NAME)` 自动跟随 → `.app` 产物名自动跟随 → 但 pbxproj/xcscheme 中**硬编码**的字符串需手工同步
- **macOS 可执行文件名含空格**：`Contents/MacOS/Fl PiCraft` 合法但需 quote；目前仓库 grep 未发现 hardcoded shell 引用
- **iOS `CFBundleName` ≠ display name 但建议保持一致**：display 用 `CFBundleDisplayName`，`CFBundleName` 是短名（最多 15 字符），`Fl PiCraft`（11 字符）合法
- **Android `android:label` 直接是 display name**，无需引入 strings.xml（i18n 是后续话题）

## Decision (ADR-lite)

**Context**: 用户要求把应用名称改为 `Fl PiCraft`，macOS 产物改为 `Fl PiCraft.app`。
但 Dart pubspec name 不能含空格，且改 applicationId 会破坏未来 Android 升级路径。

**Decision**: 采用**仅改展示名**方案：

- 改：所有平台的 display name（user-visible label / window title / browser tab / PWA name）
- 改：macOS `PRODUCT_NAME` → 自动驱动 `.app` 产物名、`CFBundleName`、可执行文件名
- 改：README 标题
- 不改：pubspec.yaml `name`、Android applicationId、iOS/macOS bundle id、Linux/Windows BINARY_NAME
- 不改：52 个测试中 `package:fl_picraft/...` import

**Consequences**:

- ✅ 零侵入 Dart 代码与测试
- ✅ Android Play Store 升级路径保留
- ✅ Linux/Windows 构建产物保持小写无空格，CLI 友好
- ⚠️ 项目内部 `fl_picraft` 字符串残留较多（pubspec、applicationId、test imports），看上去"改名不彻底" —— 通过 PRD 明确这是有意的
- ⚠️ 未来若需 i18n 应用名，需要为 iOS/Android 增加本地化 strings 资源（本任务不做）

## Out of Scope

- 不改 Dart `pubspec.yaml` 的 `name`
- 不改 Android `applicationId` / `namespace`
- 不改 iOS / macOS bundle identifier
- 不改 Linux / Windows BINARY_NAME（保持 `fl_picraft` / `fl_picraft.exe`）
- 不改 `windows/CMakeLists.txt` 顶部 `project(fl_picraft ...)` 名
- 不换 App icon（已在前一个 commit 完成）
- 不动版本号
- 不引入 InfoPlist.strings / strings.xml 做 display name i18n
- 不更新 52 个测试文件的 `package:fl_picraft/...` import

## Technical Notes

### 涉及文件清单（11 个非 Xcode 源 + 2 个 Xcode 元数据 + 1 个 README = 14 个）

```
ios/Runner/Info.plist
android/app/src/main/AndroidManifest.xml
macos/Runner/Configs/AppInfo.xcconfig
macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
macos/Runner.xcodeproj/project.pbxproj
linux/runner/my_application.cc
windows/runner/Runner.rc
windows/runner/main.cpp
web/index.html
web/manifest.json
README.md
```

### 已确认不需要改的位置

- `lib/` 下零处 `package:fl_picraft` 引用
- `pubspec.yaml`（`name` 字段保留）
- `pubspec.lock`（自动生成，不手工改）

### 风险与缓解

| Risk | Mitigation |
|---|---|
| macOS Xcode index 未同步导致 build 失败 | DoD 强制 `flutter clean && flutter build macos --debug` 验证 |
| 含空格的可执行文件路径在脚本中未 quote | 已 grep 仓库无 hardcoded 引用 |
| pbxproj 改动顺序错乱破坏 plist 解析 | 使用 Edit 工具按行替换，不重写整个文件；改完后用 `plutil -lint` 或 `flutter build` 验证 |
| Web manifest 缓存 | 不在 DoD 内（用户清缓存即可） |

### 不拆 subtask 的理由

本任务是 mechanical 重命名 14 个文件的极小变更，每个文件 1–3 行修改。拆 subtask 会
显著增加管理成本而无收益。在 Technical Approach 中按平台分 **2 个 commit 批次**即可：

- Commit 1：display name 批次（除 macOS xcode 元数据外的全部）
- Commit 2：macOS `PRODUCT_NAME` + Xcode 元数据 + 构建验证

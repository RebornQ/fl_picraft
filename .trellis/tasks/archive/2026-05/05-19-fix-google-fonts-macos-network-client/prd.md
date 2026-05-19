# fix(platform): 给 macOS 沙盒补 network.client + Android main manifest 补 INTERNET，修复 google_fonts 运行时 fetch 警告

## Goal

`google_fonts` 在运行时从 `fonts.gstatic.com` 下载 Inter 字体。多个平台
都缺少出站网络授权：

1. **macOS 沙盒**默认只放行入站 `network.server`，缺 `network.client`，
   出站连接被拒（`SocketException: Operation not permitted, errno = 1`）。
2. **Android `main/AndroidManifest.xml`**（release 构建合并源）**没声明
   `android.permission.INTERNET`**，debug/profile manifest 才有 —— 一旦出
   release apk 上架，google_fonts 同样会失败，且无 debug log 告警。

本任务给两个平台同时补齐出站网络授权，并把这类"runtime-fetch 依赖
需要 platform-level 网络授权"沉淀进 spec。

## What I already know

- `lib/app/theme/app_theme.dart:69,81,91` 使用 `GoogleFonts.interTextTheme()`
  与 `GoogleFonts.inter()`，触发运行时 HTTP fetch。
- `pubspec.yaml:72` `google_fonts: ^8.1.0`，无本地字体资源声明。
- `macos/Runner/DebugProfile.entitlements` 当前键：
  `app-sandbox`, `cs.allow-jit`, `network.server`,
  `files.user-selected.read-write`, `files.downloads.read-write`。
- `macos/Runner/Release.entitlements` 当前键：`app-sandbox`,
  `files.user-selected.read-write`, `files.downloads.read-write`
  （**没有** `cs.allow-jit`、**没有** `network.server`、**没有** `network.client`）。
- **Android Manifest 三连**（audit 结果）：
  - `android/app/src/debug/AndroidManifest.xml`：含 `INTERNET`（Flutter 默认注入）
  - `android/app/src/profile/AndroidManifest.xml`：含 `INTERNET`（Flutter 默认注入）
  - `android/app/src/main/AndroidManifest.xml`：**未声明 `INTERNET`** ←
    这是 release 合并源，导致 release apk 没有出站权限
- spec `dependencies-and-platforms.md` "macOS: Edit BOTH entitlements
  files" 章节（line 188-212）已经强调双文件铁律，但**只覆盖了
  `files.*`**，没覆盖 outbound 网络场景。"Android: API-versioned
  permission split" 章节覆盖了 `READ_MEDIA_IMAGES`/`CAMERA`，但
  **没覆盖 `INTERNET`**。
- 其它平台 baseline：iOS 默认 outbound 网络开放（除非 ATS）；Web 由
  浏览器接管；Linux/Windows 无沙盒。

## Assumptions (temporary)

- 改 macOS 两个 entitlements + Android main manifest 即可根除警告（其
  它平台不复现）。
- 用户接受运行时 fetch 姿势（不要求本地烤入字体）。
- 用户接受离线首启 fallback 到系统字体的视觉降级（不崩溃）。
- Release 配置不需要单独配 iOS ATS / NSAppTransportSecurity（HTTPS 直连
  fonts.gstatic.com 不在 ATS 黑名单）。

## Requirements (evolving)

- **macOS**：`macos/Runner/DebugProfile.entitlements` 与
  `macos/Runner/Release.entitlements` 同时添加：
  ```xml
  <key>com.apple.security.network.client</key>
  <true/>
  ```
- **Android**：`android/app/src/main/AndroidManifest.xml` 在已有
  `<uses-permission>` 列表里添加：
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  ```
  （注释说明为 google_fonts 等 runtime-fetch 依赖所需，与 debug/profile
  manifest 对齐）
- **spec 沉淀**：`dependencies-and-platforms.md` 同时补两段：
  1. macOS 章节追加 "runtime network fetch needs network.client"
  2. Android 章节追加 "INTERNET must be declared in `main/` manifest for
     release builds, not just debug/profile"
  两段都引用本任务 ID 作为 captured-from。
- **离线 fallback 显式接受**：在 PRD Decision 与 spec 中明确，
  离线/首启网络失败时 google_fonts 自动 fallback 到平台默认字体，app
  不崩溃；这是可接受降级，不属于 bug。
- 运行 `flutter analyze` 保持绿。
- 在 macOS 上运行一次 app（`flutter run -d macos`），确认控制台不再出
  现 `Failed to load font with url ...` 警告。

## Acceptance Criteria (evolving)

- [ ] `macos/Runner/DebugProfile.entitlements` 含
      `com.apple.security.network.client=true`
- [ ] `macos/Runner/Release.entitlements` 含
      `com.apple.security.network.client=true`
- [ ] Debug 与 Release entitlements 的 `network.client` 键完全一致（不
      存在 Debug-only 差异）
- [ ] `android/app/src/main/AndroidManifest.xml` 含
      `<uses-permission android:name="android.permission.INTERNET" />`
- [ ] `flutter run -d macos` 启动后，控制台无 `google_fonts was unable
      to load font` 异常
- [ ] `flutter analyze` 绿
- [ ] `spec/frontend/dependencies-and-platforms.md` 补充：
  - macOS runtime-fetch network.client 说明
  - Android main-manifest INTERNET 说明
  - 离线 fallback 行为说明
- [ ] journal 记录本次修复与决策

## Definition of Done

- 修改后 macOS Debug + Release 两个 build configuration 都能正常加载字体
- spec 沉淀完成，未来再加 NetworkImage / dio / http 等出站请求时能查到
- 不破坏 Android / iOS / Web / Linux / Windows 任何平台行为
- journal 记录修复过程与决策

## Out of Scope (explicit)

- 本地烤入 Inter 字体到 `assets/`（曾作为方案 A 讨论，用户选 B）。
- 关闭 `GoogleFonts.config.allowRuntimeFetching`（与本地烤入是一对，
  暂不引入）。
- iOS NSAppTransportSecurity 配置（HTTPS 直连 fonts.gstatic.com 不需要
  额外 ATS 例外）。
- Android `usesCleartextTraffic`（google_fonts 走 HTTPS，无需）。
- App Store / Mac App Store 上架审查的隐私权限说明文案（出包时再单
  独评估；本任务只在 spec 留 future-note）。

## Technical Approach

1. **改两个 macOS entitlements 文件**：Debug + Release 都补
   `com.apple.security.network.client=true`。位置紧邻现有
   `network.server`（DebugProfile）/ 文件访问键（Release）。
2. **改 Android main manifest**：
   `android/app/src/main/AndroidManifest.xml` 在 `<uses-permission>` 块
   里追加 `INTERNET`，与 debug/profile manifest 对齐。加注释说明触发
   包（google_fonts 等 runtime-fetch）。
3. **保持键一致性**：除了 Debug-only 的 `cs.allow-jit` 与
   `network.server`（这两个是 Flutter 调试期需求），其它键 Debug 与
   Release 必须一致。本次只在两个 entitlements 文件都加
   `network.client`，不动其它键。
4. **spec 沉淀**：在 `dependencies-and-platforms.md` 同时补：
   - macOS 章节：`network.client` 与 google_fonts / NetworkImage /
     dio / http 等 runtime-fetch 场景关联起来；
   - Android 章节：`INTERNET` 必须显式声明在 `main/` manifest，因为
     debug/profile 注入的权限不会进入 release 合并清单；
   - 离线 fallback 行为说明（google_fonts 自动降级到系统字体）；
   - Mac App Store 上架隐私说明的 future-note。
   引用本任务 ID 作为 captured-from。
5. **验证**：`flutter analyze` + `flutter run -d macos` 实跑，无字体警告。

## Decision (ADR-lite)

**Context**: macOS 沙盒拒绝 google_fonts 运行时 fetch，控制台刷出
ClientException；audit Android Manifest 时发现 release 合并清单也漏
了 INTERNET，是潜伏 bug。两种修复方向：(A) 本地烤入 Inter 字体到 assets
+ 关闭 runtime fetch；(B) 给两个平台开 outbound 网络授权。

**Decision**: 方案 B —— 给 macOS Debug + Release entitlements 加
`com.apple.security.network.client=true`，给 Android main manifest 加
`INTERNET`。**显式接受离线 fallback 行为**：网络失败时 google_fonts
自动降级到平台默认字体，不视为 bug。

**Consequences**:
- ✅ 改动最小（macOS 两行 XML + Android 一行 XML），不增加包体积。
- ✅ 顺手修了 Android release 的潜伏 bug，避免上架后才发现。
- ✅ 与 iOS / Web 行为对齐（它们都依赖 runtime fetch + 缓存）。
- ⚠️ 仍依赖网络：首次冷启动需要联网下载（~600KB Inter 字体），离
  线/弱网环境下首启会 fallback 到系统字体（不崩溃但视觉不一致）。
  **这是显式接受的降级行为**，写入 spec。
- ⚠️ Mac App Store 上架时，沙盒包含 `network.client` 会触发隐私权限
  说明审查；上架前需要在 Privacy → Network 一栏写出口。spec 留
  future-note，不在本任务处理。
- 未来如要彻底离线，可走 google_fonts 官方"bundling fonts"姿势（assets
  烤入 + `allowRuntimeFetching=false`），届时新建任务，本任务结论
  不需要 revert。

## Research References

- google_fonts pub.dev README（已知，无需子代理研究）：runtime fetch
  + 本地缓存是默认行为，`allowRuntimeFetching` 控制开关；fetch 失败
  时自动 fallback 到平台默认字体。
- 既有 spec `dependencies-and-platforms.md` line 188-212："macOS:
  Edit BOTH entitlements files" 已是本仓约定；line 132-160 "Android:
  API-versioned permission split" 是 Android manifest 约定的姊妹章节。

## Technical Notes

- 受影响文件清单：
  - `macos/Runner/DebugProfile.entitlements`（加 network.client）
  - `macos/Runner/Release.entitlements`（加 network.client）
  - `android/app/src/main/AndroidManifest.xml`（加 INTERNET）
  - `.trellis/spec/frontend/dependencies-and-platforms.md`（spec 沉淀）
- 不受影响：
  - `lib/app/theme/app_theme.dart`（代码不动，继续用 `GoogleFonts.inter*`）
  - `pubspec.yaml`（不动 google_fonts 版本）
  - iOS / Web / Linux / Windows 任一平台配置
- 跨平台风险评估：
  - macOS Debug 模式：当前观察到的警告
  - Android Release：潜伏 bug，本任务一并修
  - 其它平台：无复现条件，不动配置

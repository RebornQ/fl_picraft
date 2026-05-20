# Subtask: macOS 原生窗口策略（80% 默认 / 最小 1280×800 / frameAutosaveName）

**Parent**: [`.trellis/tasks/05-20-desktop-window-mgmt-and-menu`](../05-20-desktop-window-mgmt-and-menu/prd.md)

## Scope

在 `macos/Runner/MainFlutterWindow.swift` 中：

- 首次启动默认窗口尺寸 = `NSScreen.visibleFrame` × 80%，居中。
- 最小尺寸 = 1280×800（用 `contentMinSize`，**不含**标题栏）。
- 持久化 / 恢复 = `setFrameAutosaveName("fl_picraft.main")`，AppKit 自动写入 UserDefaults。

## Detail（节选自父 PRD §B 与 ADR-lite §D-B / §D-C）

### 改动文件

| File | Action |
|---|---|
| `macos/Runner/MainFlutterWindow.swift` | `awakeFromNib` 中：① 设 `contentMinSize = NSSize(width: 1280, height: 800)`；② 计算 80% 居中 `defaultFrame` 并 `setFrame(defaultFrame, display: true)`；③ 调 `_ = self.setFrameAutosaveName("fl_picraft.main")` |

**唯一改动文件**（不动 AppDelegate / Info.plist / entitlements / CMakeLists / pubspec）。

### 80% Default Frame 计算

```swift
let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first!
let visible = screen.visibleFrame  // 已排除 dock / menu bar / 刘海
let w = max(floor(visible.width  * 0.80), 1280)
let h = max(floor(visible.height * 0.80), 800)
let x = visible.minX + (visible.width  - w) / 2
let y = visible.minY + (visible.height - h) / 2
self.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
```

### 顺序至关重要

1. `contentViewController = FlutterViewController()`
2. `contentMinSize = NSSize(width: 1280, height: 800)`
3. `setFrame(defaultFrame, display: true)`  — `setFrame(_:display:)` 不受 minSize 约束（这是 AppKit 文档明确说的特例）
4. `setFrameAutosaveName("fl_picraft.main")` — 若 UserDefaults 已有保存值，AppKit 立即覆盖刚设的 default frame；若无，则保留 default。**顺序倒了就实现不了「首次 80%、后续恢复」**。
5. `RegisterGeneratedPlugins(...)` + 其他既有逻辑

## Acceptance Criteria

- [ ] 清空 `~/Library/Preferences/com.example.flPicraft.plist`（autosave 落点）后启动，窗口 ≈ 主屏 visibleFrame 80% 居中。
- [ ] 拖拽 resize → 退出 → 再启动 → 恢复到退出时的尺寸 + 位置。
- [ ] 拖窗口边角缩小至任一维度 < 1280 或 800 → 卡住。
- [ ] 主屏分辨率变化（外接屏拔/插）→ 重启 → 窗口仍在可见屏上（AppKit `constrainFrameRect:to:` 自动 clamp）。
- [ ] M 系列 MacBook Pro 上窗口顶部不被刘海挡住（`visibleFrame` 已排除刘海）。
- [ ] `flutter analyze` clean；`flutter build macos` 成功。

## Out of Scope

- 多窗口支持。
- 全屏 / maximized 状态持久化（仅持久化 normal frame）。
- 自定义「rect 不可见时居中」回退（信任 AppKit `constrainFrameRect:to:`）。

## Smoke Verify Script

```bash
# 清空 autosave（具体 plist 名取决于 Bundle Identifier）
rm -f ~/Library/Preferences/com.example.flPicraft.plist 2>/dev/null
defaults delete com.example.flPicraft 2>/dev/null
flutter run -d macos
# 期望：80% 居中
# 然后 resize 并退出，再 flutter run → 期望恢复尺寸
```

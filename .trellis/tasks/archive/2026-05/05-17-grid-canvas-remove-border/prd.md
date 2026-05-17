# fix: remove border from GridPreviewCanvas

## Goal

移除 `GridPreviewCanvas` 外层 `Container` 装饰中的 `border` 字段（line 65: `Border.all(color: colorScheme.outlineVariant)`），让画布外缘不再画一圈描边。背景色 (`surfaceContainer`)、`clipBehavior: Clip.antiAlias` 保留；阴影 (`boxShadow`) 是否一并移除待用户确认。

## What I already know

`lib/features/grid/presentation/widgets/grid_preview_canvas.dart:61-78`:

```dart
return Container(
  decoration: BoxDecoration(
    color: colorScheme.surfaceContainer,                  // ← 保留：画布背景色
    borderRadius: BorderRadius.zero,                       // ← 保留（虽然是 zero，删了语义不变）
    border: Border.all(color: colorScheme.outlineVariant), // ← 本任务移除
    boxShadow: const [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ],                                                     // ← 待确认是否一并移除
  ),
  clipBehavior: Clip.antiAlias,                            // ← 保留
  child: state.hasSource ? _PreviewSurface(...) : _EmptyState(...),
);
```

### Survey of similar borders in the codebase

| 文件 | 用途 | 本任务影响 |
|---|---|---|
| `grid_preview_canvas.dart:65` | 画布外缘描边 | **✅ 本任务移除** |
| `grid_editor_screen.dart:94` | 控制面板 chrome 边框 | ❌ 不动 |
| `grid_editor_screen.dart:438` | （tintedBorder 用途）| ❌ 不动 |
| `grid_type_selector.dart:115` | 选中态的 grid type 卡片边框 | ❌ 不动 |
| `grid_controls_panel.dart:92` | 控制面板容器边框 | ❌ 不动 |

## Open Questions

（已全部解决，见 Decision）

## Requirements

- 删除 `GridPreviewCanvas.build` 中 `BoxDecoration.border` 字段
- 保留 `color: colorScheme.surfaceContainer`（gap fill 路径依赖此为背景色）
- 保留 `clipBehavior: Clip.antiAlias`（确保画布内子组件不溢出）
- 不影响其他文件的 border 使用

## Acceptance Criteria

- [ ] `GridPreviewCanvas` 渲染时画布外缘无 outlineVariant 颜色描边线
- [ ] 画布背景色保持 surfaceContainer（gap fill 视觉效果依赖此一致性）
- [ ] 子组件（`_PreviewSurface` / `_EmptyState`）裁剪行为不变
- [ ] `flutter analyze` / `dart format .` / `flutter test` 全绿
- [ ] 现有 widget 测试（`grid_preview_canvas_drag_test.dart` / `grid_preview_canvas_gap_fill_test.dart`）保持通过

## Definition of Done

- 单文件改动（`grid_preview_canvas.dart`）
- 三红线全绿
- 不创建 git commit（除非用户主动要求）

## Technical Approach

直接删除 `BoxDecoration` 中的 `border` 字段。无需引入新依赖、无需重构。

### 备选保留范围

| 选项 | 保留 | 移除 |
|---|---|---|
| **A (推荐)** | `color`, `clipBehavior`, `boxShadow` | `border` |
| **B** | `color`, `clipBehavior` | `border`, `boxShadow`（视觉更扁平） |

## Decision (ADR-lite)

**Context**: 笨蛋想去掉宫格切图画布外缘的描边线，让画布视觉更轻。boxShadow（轻微投影）是否一并移除会改变画布"代入感 vs 与背景融合"的取舍。

**Decision**: **Approach A — 仅移除 `border` 字段，保留 `boxShadow`**。
- 删除 `BoxDecoration.border: Border.all(color: colorScheme.outlineVariant)` 单行
- 保留 `color: colorScheme.surfaceContainer`（gap fill 路径依赖）
- 保留 `borderRadius: BorderRadius.zero`（语义上是无圆角；删除也等效，但保留更明确）
- 保留 `boxShadow`（轻微 12dp blur + 4dp y-offset 投影，让画布与 chrome 仍有视觉层次）
- 保留 `clipBehavior: Clip.antiAlias`

**Consequences**:
- ✅ 画布外缘干净，视觉重量减轻
- ✅ 保留投影维持画布的层级感（与底层 chrome 区分）
- ✅ 不影响其他模块的 border 使用
- ✅ 不影响刚完成的 gap-spacing-color-fix 任务的 surfaceContainer 视觉契约
- ⚠️ 单点装饰改动，无需新增 spec

## Out of Scope

- 其他位置的 `Border.all(...)` 使用（grid_editor_screen / grid_type_selector / grid_controls_panel）
- 长图拼接 / 字幕拼图等其他模式的画布
- 主题 token (`outlineVariant`) 本身的调整
- 新增 spec 约定（border 是单点装饰，无 cross-file pattern）

## Technical Notes

### Affected files

- `lib/features/grid/presentation/widgets/grid_preview_canvas.dart` (line 65 删除)

### Related historic context

- 05-17-grid-spacing-color-fix（刚完成）依赖 `surfaceContainer` 作为画布背景色 — 本任务删除 border 时**绝不能**删除 `color: surfaceContainer`，否则 gap fill 视觉会失效

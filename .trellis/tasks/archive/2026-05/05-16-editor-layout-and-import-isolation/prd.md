# Editor Layout + Per-Mode Import Isolation

## Goal

把编辑器交互在两个独立维度上同步改进：

1. **布局**：所有 screen（不仅是编辑器）随窗口宽度自适应铺满，去掉 1200 dp 上限带来的「拉宽窗口内容反而被居中」现象；编辑器侧边面板用 min 380 / max 480 的弹性宽度，让画布拿到剩余空间。
2. **隔离**：图片导入会话从全局共享改为「按顶级编辑模式（stitch / grid / 未来 …）一份」，互不串扰，并为未来新增编辑模式留好枚举位。

> 两件事独立性强、影响重叠面有限，已 **拆分为两个 subtask** 各自交付，本任务作为母任务持有共同决策与 acceptance gate。

## Decisions (ADR-lite)

### D1 — 全部 screen 都铺满，删除 `maxContentWidth` 容器帽

- **Context**: 拉宽窗口时内容停留在 1200 dp 居中，超宽屏空白多。
- **Decision**: 移除 `Center + ConstrainedBox(maxWidth: 1200)` 三连模板，让 Home / Stitch Editor / Grid Editor / Export Screen 都直接铺满 SafeArea。Settings 暂无超宽体验问题，但同步处理保持一致性。
- **Consequences**:
  - `Breakpoints.maxContentWidth` 常量与 `responsive-layout.md` 中「Cap content with maxContentWidth」约定都要删/改。
  - 4K 屏下 home 的 feature cards 会被 `Expanded(flex:1)` 拉宽 — 用户已确认接受。
  - 后续若需要某个特定 screen 加帽，再单独决定。

### D2 — 侧边控制面板：min 380 / max 480

- **Context**: 当前 `_kStitchControlsPanelWidth = 380` 是写死常量。铺满后画布拿到剩余空间，但若窗口超宽，面板比例会失衡。
- **Decision**: 把面板宽度改为 `clamp(380, container * 0.25, 480)`（或等效 `LayoutBuilder` 结合 SizedBox.fromConstraints）。下限 380 保读性，上限 480 防过宽。
- **Consequences**: spec 中「side panel is 380 dp wide」约定要改为「[380, 480]」并解释 why。

### D3 — 解除 stitch_preview_canvas 内部 360/480 锁

- **Context**: 预览画布内部还有 `ConstrainedBox(maxWidth: 360, maxHeight: 480)`，即便外层放开也卡在 360。
- **Decision**: 用 `LayoutBuilder` 让预览图按可用区域 + 画布原始比例计算；维持 `FittedBox` 缩放行为不变。
- **Consequences**: 预览渲染逻辑要重写一小段，但 export 渲染管线不动（layout 计算函数 `computeStitchLayout` 完全无关）。

### D4 — 导入会话按顶级编辑模式隔离

- **Context**: 现在 stitch 和 grid 共享 `imageImportControllerProvider`，导致跨 tab 串图。
- **Decision**:
  - 新增枚举 `ImageImportSessionKind { stitch, grid }`（放在 `lib/features/image_import/domain/entities/` 下，独立于 `ExportSourceKind` 以保持关注点分离）。
  - 把 `imageImportControllerProvider` 改造为 `AsyncNotifierProviderFamily<ImageImportController, List<ImportedImage>, ImageImportSessionKind>`。
  - `importedImagesProvider` 同步改为 `.family`。
  - `ImageDropZone` 通过新参数 `sessionKind` 显式接收当前模式（screen 在 mount 时传入），不依赖 export source kind。
  - `StitchEditorController` / `GridEditorController` 各自 watch / 写回对应 kind 的 family provider。
- **Consequences**:
  - 所有调用点都要改签名（family 要带参）。
  - 测试需要把 `.overrideWith` 改成 `.overrideWith((ref) => controller, kind)` 形式。
  - `lastWarning` / SnackBar 自然落到对应 screen 上。
  - nine-grid-social 中心图保持原有「绕过全局 session」逻辑（直接 repo.pickFromGallery）。
  - 全局单例 instance 彻底废除（KISS / YAGNI — 不保留向后兼容 alias）。

### D5 — Movie-subtitle 仍然走 stitch session

- **Context**: stitch 内部还有 subtitle-only flag。
- **Decision**: subtitle-only 只是 stitch session 的一个 flag，**共享** stitch 的 session 图片列表。
- **Consequences**: 不需要再细分 `stitchVertical` / `stitchSubtitle` 等枚举值。

## Subtasks

| ID | Title | 范围 | 优先级 |
|----|-------|------|--------|
| `05-16-editor-fill-container-width` | 编辑器与所有顶级 screen 自适应铺满 | D1, D2, D3 | 先做（更直观，先回归 UI 视觉） |
| `05-16-per-mode-import-isolation` | 按模式隔离图片导入 session | D4, D5 | 后做（架构层，需要更多回归测试） |

两个 subtask 互不阻塞，可并行；推荐顺序：先做布局（视觉可见、回滚成本低），再做隔离（架构面更大）。

## Requirements (final)

- **R1**: 见 subtask `editor-fill-container-width/prd.md`。
- **R2**: 见 subtask `per-mode-import-isolation/prd.md`。

## Acceptance Criteria (final)

母任务在两个 subtask 都关闭后 **整体 hand-off**，验收要求：

- [ ] 两个 subtask 各自 `status: completed`。
- [ ] 跨 subtask 集成回归（手动 smoke）：在 stitch 导入 3 张图 + 拖宽窗口 + 切到 grid + 再切回 → 布局正确铺满、stitch 图片仍在、grid 图片为空。
- [ ] `flutter analyze` / `dart format .` / `flutter test` 全绿。
- [ ] spec 同步更新（responsive-layout.md + state-management.md）。

## Definition of Done

继承自每个 subtask；母任务额外要求：

- 集成 smoke 测试覆盖跨 subtask 的耦合点。
- 母任务的 PRD 在收尾时附 GIF 或截图链接（subtask 内或 PR 描述均可）。

## Out of Scope (explicit)

- 持久化 import session（重启后保留）。
- 未来「拼贴」「社交模板」等模式的 UI 实现（架构留好枚举扩展位即可）。
- Design token、颜色、字体的任何调整。
- Settings screen 的额外响应式优化（现在没问题）。
- Export screen 的非铺满相关重构。

## Technical Notes

### 关键文件清单

布局相关：
- `lib/core/constants/breakpoints.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart`
- `lib/features/grid/presentation/screens/grid_editor_screen.dart`
- `lib/features/long_stitch/presentation/widgets/stitch_preview_canvas.dart`
- `lib/features/export/presentation/screens/export_screen.dart`

隔离相关：
- `lib/features/image_import/domain/entities/`（新增 `image_import_session_kind.dart`）
- `lib/features/image_import/presentation/providers/image_import_provider.dart`
- `lib/features/image_import/presentation/widgets/image_drop_zone.dart`
- `lib/features/long_stitch/presentation/providers/stitch_editor_provider.dart`
- `lib/features/grid/presentation/providers/grid_editor_provider.dart`
- `lib/features/export/presentation/providers/export_dispatch.dart`（可能需要 read 对应 kind）
- 所有相关测试（`test/features/image_import/...` + 两个编辑器 widget tests）

### Spec 影响

- `.trellis/spec/frontend/responsive-layout.md` 需更新「Cap content」「380 dp 面板」约定。
- `.trellis/spec/frontend/state-management.md` 需新增「按模式隔离 session 的 .family 范式」。


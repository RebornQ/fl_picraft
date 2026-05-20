# 长图拼接：导入图片数量上限 20 张 + 添加按钮置灰

## Goal

在长图拼接编辑器中，当已导入图片数达到上限（20 张）时：
1. 「添加」按钮**视觉置灰**且**不可点击**（`onPressed: null`）
2. 拖拽落入图片也被拒绝并通过 snackbar 反馈
3. 用户得到清晰、对称、一致的「已达上限」反馈

> 注：底层 20 上限已在 `kMaxImportSessionImages = 20`、`ImageImportController._isSessionFull()`、`_appendCapped()` 等位置实现；本任务**只缺 UI 侧的可见性与入口的对称封锁**。

## What I already know

### 上限的底层实现（domain / data / state 层）
- `lib/features/image_import/domain/repositories/image_import_repository.dart:9` — `const int kMaxImportSessionImages = 20;`（PRD §5.2 的单一来源）
- `lib/features/image_import/data/repositories/image_import_repository_impl.dart:100-135` — `_normalizeAndPackage` 用 `limit.clamp(1, kMaxImportSessionImages)` 截断 + 标记 `partial=true`
- `lib/features/image_import/presentation/providers/image_import_provider.dart:63-69` — `pickFromGallery` 已检查 `_isSessionFull()` 并传 `limit: _remainingCapacity()` 给 native picker
- `lib/features/image_import/presentation/providers/image_import_provider.dart:178-189` — `_isSessionFull` / `_flagSessionFull` 已设置 `lastWarning = TooManyImages(...)`

### UI 层现状（问题所在）
- `lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart:80-92` — header「添加」按钮 `onPressed` 永远非空，**没有根据 count 置灰**
- `lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart:190-200` — 大屏布局的「添加」按钮同上
- `lib/features/long_stitch/presentation/screens/stitch_editor_screen.dart:41,125` — 整个 stitch editor body 被 `ImageDropZone` 包裹，拖拽落入会调用 `addFromDrop`
- `lib/features/image_import/presentation/widgets/image_drop_zone.dart:79` — `addFromDrop` 直接调 `_runImport(_repo.importRawBytes(raw))`，**不预先检查 session-full**

### 入口盘点（已确认）
| 入口 | UI 暴露？ | 当前行为 | 本任务处理 |
|---|---|---|---|
| header「添加」按钮（strip 横向版） | ✅ | 永远可点 | 置灰 |
| header「添加」按钮（vertical 纵向版） | ✅ | 永远可点 | 置灰 |
| 外部拖入新图片（`ImageDropZone`，desktop/web） | ✅ | 静默截断 / `_appendCapped` 兜底 | 拒绝 + snackbar |
| **内部拖拽排序**（`ReorderableRow`，已选图片重排） | ✅ | 任何 count 下都可用 | **保持不变**（不属于「新增图片」入口） |
| 空状态「从相册」「剪贴板」按钮 | 仅 count=0 时显示 | 不会在 count=20 时出现 | 无需改 |
| 相机入口 | ❌ stitch UI 未暴露 | n/a | 无需改 |

### 已有的 platform 行为
- `image_picker ^1.1.2` 的 `pickMultiImage(limit: limit)` 在 Android 13+ Photo Picker / iOS PHPickerViewController 上会显式限制选择数；旧版 Android 系统图库为 best-effort。
- native picker 超返时由 `_normalizeAndPackage` 兜底截断 + 触发 `TooManyImages` warning。

### 非长图拼接的对比
- `grid_split` 走「单图源」语义，不存在 N 张场景，**本任务不涉及**。

## Decision (ADR-lite)

**Context**: 已选图片达 20 上限时，header「添加」按钮的行为以及其它入口（相机、剪贴板、拖拽）的行为需要统一。
**Decision**: 选择**全部入口对称封锁**。两处 header 按钮置灰 + tooltip 提示；`ImageDropZone` 在 session-full 时拒绝 drop 并 snackbar 反馈；相机入口 UI 未暴露故不涉及，空状态按钮仅 count=0 显示故不涉及。
**Consequences**:
- ✅ 用户在任何入口都得到一致的「已达上限」反馈，不会出现「操作了却没动静」的割裂体验
- ✅ 改动范围聚焦 UI 层，不破坏 domain/data 层契约
- ⚠️ `ImageDropZone` 的 session-full 判断需要新增 `isSessionFull` 的可读路径（getter 或 selector），略增一处 controller API 表面积

## Requirements

- **R-CAP-01**：当 `state.imageCount >= kMaxImportSessionImages`，`StitchImageStrip` 头部「添加」按钮 `onPressed: null`，呈现 Material 3 disabled 视觉。
- **R-CAP-02**：当 `state.imageCount >= kMaxImportSessionImages`，`StitchVerticalImageList` 头部「添加」按钮 `onPressed: null`，与 R-CAP-01 行为一致。
- **R-CAP-03**：R-CAP-01 / R-CAP-02 置灰状态需要 tooltip 提示「已达上限 20 张」（或同义文案，与已有计数徽章风格一致）。
- **R-CAP-04**：当 stitch session 已达上限，`ImageDropZone`（外部拖入新图片）落入时拒绝并通过 snackbar 提示「已达上限 20 张」（与现有 `TooManyImages.toString()` 文案对齐 / 对应）。
- **R-CAP-05**：删除一张图后按钮和外部拖入应立即恢复可用（reactive，由 `ref.watch(state.imageCount)` 天然支持，仅需在测试中覆盖）。
- **R-CAP-06**：底层 picker `limit: _remainingCapacity()` 调用保持现状，本任务不改 domain/data 层。
- **R-CAP-07**（明确不改）：**内部拖拽排序**（`ReorderableRow` / `reorderables`，调用 `notifier.reorder(oldIndex, newIndex)`）属于**已选图片之间的重排**，与「新增图片」无关，**任何 count 下都必须保持可用**（包括 count = 20）。本任务**不改动**任何 reorder 路径。

## Acceptance Criteria

- [ ] **AC1** count = 0..19 时，header「添加」按钮可点（保持现状）
- [ ] **AC2** count = 20 时，header「添加」按钮置灰且 `onPressed: null`（strip 横向版）
- [ ] **AC3** count = 20 时，header「添加」按钮置灰且 `onPressed: null`（vertical 纵向版）
- [ ] **AC4** 置灰状态下 long-press / hover 显示 tooltip「已达上限 20 张」
- [ ] **AC5** count = 20 时**外部拖入**新图片，**不被追加到 session**，并显示 snackbar「已达上限 20 张」
- [ ] **AC6** 从 count = 20 删除一张后，按钮立即可点、外部拖入立即可用
- [ ] **AC7** 现有计数徽章 `已选图片 (X/20)` 在 X=20 时仍正常显示
- [ ] **AC8** widget 测试覆盖 AC2 / AC3 / AC6 的 enabled / disabled 切换
- [ ] **AC9** `flutter analyze` / `flutter test` 全绿，不破坏既有 stitch / image_import 测试
- [ ] **AC10** count = 20 时**内部拖拽排序**（`ReorderableRow` 重排已选图片）**仍正常工作**，不被本任务破坏（回归测试）

## Definition of Done

- 新增 widget 测试覆盖 enabled/disabled 切换 + 删除恢复
- 拖拽 session-full 行为的单元 / widget 测试（或在 ImageDropZone 测试中追加 case）
- Lint / typecheck / CI 全绿
- 仅触及 UI / presentation 层，**不修改** domain / data 层契约
- 不改变 `kMaxImportSessionImages` 数值

## Out of Scope

- 不调整 `kMaxImportSessionImages` 的值（保持 20）
- 不重写 `image_import_provider` 的 `_appendCapped` / `_isSessionFull` 逻辑
- 不改造 grid_split 编辑器（单图源语义）
- 不引入新的设计 token / 主题色
- 不修改 stitch 的 camera 入口（UI 本来就没暴露）
- 不修改空状态的「从相册」「剪贴板」按钮（仅 count=0 时显示，达上限场景不可达）
- **不修改 `ReorderableRow` / `notifier.reorder` 任何代码路径**：内部拖拽排序是「已选图片之间的重排」，与「新增图片」无关；count=20 时也必须能排序

## Technical Approach

1. **暴露 session-full 状态**：在 `ImageImportController` 上新增 `bool get isSessionFull` 或一个 `sessionFullProvider` selector，使 UI 可以 reactive 地 watch（避免直接在 widget 里硬编码 `>= kMaxImportSessionImages`）。
   - 替代方案：直接在 widget 里 watch `state.imageCount >= kMaxImportSessionImages`（更简单，但散落判断）→ 倾向 selector。

2. **置灰按钮**：`stitch_image_strip.dart:80-92` 与 `stitch_vertical_image_list.dart:190-200` 把 `onPressed` 改为 `isFull ? null : () => ...addFromGallery()`。

3. **Tooltip**：用 `Tooltip(message: '已达上限 20 张', child: ...)` 包裹按钮（Tooltip 在 disabled IconButton/TextButton 上仍可触发）。

4. **拖拽拒绝**：修改 `image_drop_zone.dart` 的 onDrop handler 或在 `addFromDrop` 调用前做 session-full 判断，并通过现有的 `lastWarning` snackbar 链路或新增 snackbar 提示用户。

5. **测试**：
   - `stitch_image_strip_test.dart` 增加 `count = 20` 场景断言按钮 disabled
   - `stitch_vertical_image_list_test.dart` 增加同上
   - `image_drop_zone_test.dart`（若存在）或新增测试覆盖 session-full 时的拒绝行为

## Technical Notes

### 关键文件
- `lib/features/long_stitch/presentation/widgets/stitch_image_strip.dart`
- `lib/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart`
- `lib/features/image_import/presentation/providers/image_import_provider.dart`（暴露 `isSessionFull`）
- `lib/features/image_import/presentation/widgets/image_drop_zone.dart`（拖拽拦截）

### 既有规范参考
- `.trellis/spec/frontend/` — Riverpod selector / widget test 模式
- 现有 `lastWarning` snackbar 消费方（参考 stitch editor 现有的 snackbar 监听路径，保持文案 / 触发风格一致）

### Implementation Plan
- 单 PR 完成（改动量小且强相关）：
  1. provider 暴露 `isSessionFull`
  2. 两处 header 按钮置灰 + tooltip
  3. ImageDropZone 拖拽拦截 + snackbar
  4. widget 测试

**不拆 subtask**：四步强耦合，分拆只会增加 PR 切换成本。

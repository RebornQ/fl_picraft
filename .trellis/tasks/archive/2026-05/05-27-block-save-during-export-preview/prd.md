# 导出预览完成前禁止保存

## Goal

在 `/export` 屏幕，让“保存”CTA 在预览管线真正“完成”（`PreviewState ==
PreviewReady`）之前保持禁用，避免用户在预览未就绪（loading / error / empty）时触发保存——以消除“看到的预览”与“保存到相册的产物”之间的视觉错位，并让用户明确知晓保存对象就是预览中所见。

## Requirements

* **R1**：`SaveActionButton` 的启用条件改为：

  ```
  enabled = (preview is PreviewReady) && !isSaving && canExport
  ```

  其中 `preview` 为 `previewControllerProvider` 的当前 state，
  `isSaving` 为 `ExportState.isSaving`，`canExport` 为 `canExportProvider`。
  保留 `canExport` 作为“纵深防御”冗余 guard（理论上 `PreviewReady` 蕴含
  `canExport`，但显式保留更利于阅读与测试断言）。
* **R2**：`PreviewError` 状态下保存按钮**禁用**——用户须通过预览卡片内既有的
  `_ErrorView` 重试按钮（`preview_card.dart:241-244`）恢复 `PreviewReady` 后再保存。
* **R3**：`PreviewLoading`（含 `staleBytes != null` 的“重渲染中”态）一律禁用。
* **R4**：禁用态下，FAB 仍渲染在原位、保持原图标与基础文案（label 由
  `exportSaveButtonLabelProvider` 提供，**不变**）；仅
  `onPressed: null` + 视觉灰化。**Tooltip 保持原文案**（“保存至相册” / “保存 N 张为 ZIP”），
  不按原因切换文案——disabled 视觉本身已传达不可点击信号，避免文案噪音。
* **R5**：抽一个 `canSaveProvider`（与 `canExportProvider` 同文件
  `export_dispatch.dart`），合并三条件 `(preview is PreviewReady) && !isSaving &&
  canExport`，便于单元测试与未来同主题按钮（分享、批量预设）复用。
* **R6**：测试覆盖：
  * `canSaveProvider`：枚举 5 个 PreviewState ×（isSaving true/false）×（canExport
    true/false）的关键交叉组合（不需要笛卡尔展开，覆盖等价类即可）。
  * `SaveActionButton` widget 测试：PreviewLoading / PreviewLoading(staleBytes) /
    PreviewError / PreviewEmpty / PreviewReady 时 `onPressed == null` 与可点击对照。
* **R7**：`ExportController.save()` 内部逻辑、cache 策略、isolate 渲染**不动**——
  本任务**只**修改保存按钮的可用性判定，不触碰保存管线。

## Acceptance Criteria

* [ ] 当 `PreviewState == PreviewEmpty`，`SaveActionButton.onPressed == null`。
* [ ] 当 `PreviewState == PreviewLoading()`，`SaveActionButton.onPressed == null`。
* [ ] 当 `PreviewState == PreviewLoading(staleBytes: <non-null>)`，
      `SaveActionButton.onPressed == null`。
* [ ] 当 `PreviewState == PreviewError(...)`，`SaveActionButton.onPressed == null`。
* [ ] 当 `PreviewState == PreviewReady(...)` 且 `!isSaving && canExport`，
      `SaveActionButton.onPressed` 可触发 `save()`。
* [ ] `canSaveProvider` 单元测试覆盖五个 PreviewState 与
      isSaving/canExport 的关键组合。
* [ ] `SaveActionButton` widget 测试通过——`pumpWidget` + 注入
      `previewControllerProvider.overrideWith` 验证各状态 `onPressed` 行为。
* [ ] `ExportController.save()` 行为不变（cache hit shortcut 保留，无新的入口/出口）。
* [ ] `flutter analyze` 无新增 warning；`dart format .` 无 diff；现有 567+ 测试全绿；
      新增测试通过。

## Definition of Done

* 实现 + 测试都通过 `flutter analyze` / `dart format .` / `flutter test`。
* 在 `.trellis/spec/frontend/component-guidelines.md` 沉淀一条 convention：
  “Save CTA gated by preview-ready state” —— What/Why/Example/When to apply/Required
  tests 五段，引用本任务 PRD。
* 在 `.trellis/spec/frontend/state-management.md` 的“Sealed `PreviewState` consumer
  pattern”小节追加一行 cross-reference，指向 `canSaveProvider` 的实现作为消费 sealed
  state 派生 boolean 的标准示例。
* PRD 的 Open Questions 已全部解决并写进 `## Decision (ADR-lite)`。

## Technical Approach

* **修改面（minimal surface）**：仅 2 个文件 + 测试。
  1. `lib/features/export/presentation/providers/export_dispatch.dart` —— 新增
     `canSaveProvider`（紧邻 `canExportProvider`），实现：

     ```dart
     final canSaveProvider = Provider<bool>((ref) {
       final preview = ref.watch(previewControllerProvider);
       if (preview is! PreviewReady) return false;
       if (ref.watch(exportControllerProvider.select((s) => s.isSaving))) {
         return false;
       }
       return ref.watch(canExportProvider);
     });
     ```

     文档注释要点：①“预览未完成前禁止保存”的产品语义；② `canExport` 冗余的纵深防御
     用意；③ 与 `PreviewState` sealed 的耦合点（pattern 在 state-management spec）。
  2. `lib/features/export/presentation/widgets/save_action_button.dart` —— 把
     `final enabled = !isSaving && canExport;` 替换为
     `final enabled = ref.watch(canSaveProvider);`；同时把 `isSaving` 的
     `ref.watch(...select)` 保留（图标 + label 切换仍需要 isSaving 单值）。
* **不动的部分**：
  * `ExportController.save()` 的 cache-hit shortcut 与 isolate 渲染。
  * `PreviewController` 的 build/_initialStateFromCache/_scheduleRender 逻辑。
  * `canExportProvider`、`exportSaveButtonLabelProvider` 的实现。
  * `PreviewError._ErrorView` 内既有的 `重试` 按钮。

## Decision (ADR-lite)

**Context**

  原 `SaveActionButton.enabled` 仅依赖 `!isSaving && canExport`，导致 PreviewLoading /
  PreviewError / PreviewEmpty 状态下用户仍能触发保存。`ExportController.save()` 会自己
  重新渲染并通过缓存 fast path 保存，但产物可能不是“当前看到的预览帧”——尤其是用户连续
  调参数时，存在“看到的不是保存的”视觉错位风险。

**Decision**

  1. 抽 `canSaveProvider`，把 `(preview is PreviewReady) && !isSaving && canExport`
     三条件集中表达；
  2. `PreviewError` 也禁用保存（依赖预览卡片既有“重试”按钮恢复，UI 上闭环）；
  3. 禁用态 tooltip 保持原文案，不切换原因——视觉灰化已足够传达 disabled 语义，避免
     copy 噪音。

**Consequences**

  * ✅ 视觉与产物一致：用户看到 PreviewReady 才能保存，所见即所得。
  * ✅ ExportController/Preview 控制器不被打扰；改动局限在按钮 + 一个新 Provider。
  * ⚠️ Trade-off：PreviewError 时用户必须先重试预览才能保存，无“跳过预览强行保存”逃生
       通道。已确认该决策——失败的预览管线大概率连带保存失败，禁止保存反而更安全。
  * 🚀 Future-friendly：新增的同主题 CTA（如分享、批量预设导出）可直接复用
       `canSaveProvider`，不必重新组合三条件。

## Out of Scope

* 编辑器侧（stitch / grid editor）AppBar 与 FAB 的“导出”按钮逻辑——不动。
* `ExportController.save()` 的实现路径、cache 策略、isolate 渲染——不动。
* `PreviewController` 本身的状态机、debounce、stale 帧策略——不动。
* 任何与“分享”/“导出格式新增”/“批量导出预设”相关的功能——独立 RFC。
* 禁用态 tooltip 切换 / disabled 视觉的额外动效——已明确选“不切换、保持原状”。
* 编辑器侧禁止跳转到 `/export`（在预览还没准备好的状态下）——产品流程允许，不动。

## Technical Notes

### 关键文件 / 符号

| 类型 | 路径 | 备注 |
|------|------|------|
| Provider（新增） | `lib/features/export/presentation/providers/export_dispatch.dart` | 新增 `canSaveProvider`，紧邻 `canExportProvider` |
| Widget（修改） | `lib/features/export/presentation/widgets/save_action_button.dart` | 把 enabled 判定改为 `ref.watch(canSaveProvider)`；保留 isSaving 的 select 给图标/label |
| Provider（只读） | `lib/features/export/presentation/providers/preview_controller.dart` | `previewControllerProvider`：`AutoDisposeNotifier<PreviewState>` |
| Sealed | `lib/features/export/presentation/providers/preview_state.dart` | `PreviewEmpty/Loading/Ready/Error` |
| Provider（只读） | `lib/features/export/presentation/providers/export_controller.dart` | `exportControllerProvider`、`ExportState.isSaving` |
| Widget（已有/不动） | `lib/features/export/presentation/widgets/preview_card.dart:241-244` | `_ErrorView` 已有 “重试” 按钮触发 `previewControllerProvider.notifier.refresh()` |

### 测试参考

* `test/features/export/presentation/export_controller_test.dart:201-249` 已有
  `canExportProvider` 的 group 测试模板，新建 `canSaveProvider` 测试组可仿照。
* `test/features/export/presentation/providers/preview_controller_test.dart` 已有
  `processedBytesCacheProvider` 与状态切换的 ProviderScope override 套路，
  `canSaveProvider` 测试用同样模式注入各 PreviewState。
* `SaveActionButton` 既有 widget 测试位置（待 grep 验证）——若已有，扩展；若无，新建
  `test/features/export/presentation/widgets/save_action_button_test.dart`。

### Spec 引用

* `.trellis/spec/frontend/state-management.md`
  * “Pattern: NotifierProvider<SealedState> when the sealed already owns loading/error”
    —— 派生 boolean 时遵循同模式，直接 `is PreviewReady`，不要 `AsyncValue.when`。
  * “Split lifecycle — autoDispose controller + non-autoDispose cache”——解释为何 cache
    命中时按钮能立即 enable。
* `.trellis/spec/frontend/component-guidelines.md`
  * “Expensive-preview sliders submit on onChangeEnd, not onChanged” —— 同主题先例：
    预览-保存一致性的强约束。

### 风险与缓解

* **风险 R1**：PreviewController 的 debounce（200ms 量级）可能让用户在“调参数→等预览→
  保存”三步间感觉到延迟。
  缓解：本任务不改 debounce；现有 PreviewLoading + staleBytes 体验本就是产品默认；如需
  优化属于独立任务。
* **风险 R2**：单元测试覆盖 PreviewState × isSaving × canExport 时，组合很多。
  缓解：覆盖等价类（5 PreviewState 各一例 + isSaving=true 一例 + canExport=false 一例）
  即可，不要笛卡尔展开。

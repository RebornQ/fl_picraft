# Export Page Style Tweaks (05-21)

## Goal

把导出页面两个 UI 细节修齐：
1. `FormatQualityCard._FormatButton` 选中态前景色用对的 MD3 token（修复 `primary + onPrimaryContainer` 紫底浅紫字的语义错配）。
2. 主"保存"按钮重构为 Material 3 `FloatingActionButton.extended`，让主操作更符合 MD3 视觉层级。

两项都是导出页面收尾阶段的样式微调，零功能改动，合并在 1 个 task / commit 中完成。

## Requirements

- **R1**：`lib/features/export/presentation/widgets/format_quality_card.dart:96-98` 的 `_FormatButton` 选中态前景色由 `colorScheme.onPrimaryContainer` 改为 `colorScheme.onPrimary`。同步修正 line 88-95 注释里"已经写对但实现未对齐"的描述，保证注释与代码一致。
- **R2**：`lib/features/export/presentation/widgets/save_action_button.dart` 重构为 `FloatingActionButton.extended`：
  - 显式声明 `heroTag: 'export-save-fab'`（遵守 `.trellis/spec/frontend/component-guidelines.md:967` Gotcha 约定）
  - 保留 `isSaving` / `canExport` 状态语义：disabled (`onPressed: null`)、in-flight (icon 替换为 `CircularProgressIndicator`、label 显示 "保存中…")
  - 文案仍由 `exportSaveButtonLabelProvider` 提供
  - 保留 `_onSavePressed` / `_snackBarFor` 私有方法，逻辑零改动
- **R3**：`lib/features/export/presentation/screens/export_screen.dart` 的 `Scaffold` 增加 `floatingActionButton: const SaveActionButton()` + `floatingActionButtonLocation: FloatingActionButtonLocation.endFloat`；body 中的 `SaveActionButton` 移除。
- **R4**：body 末尾追加 `SizedBox(height: 88)` 防止 FAB 遮挡 `SaveDisclaimer`（56 dp FAB + 16 dp endFloat margin + 16 dp 留白）。`SaveDisclaimer` 仍保留在 body 末尾。
- **R5**：删除 `test/features/export/presentation/export_screen_responsive_test.dart:93-110` 的 "SaveActionButton stays full-width on every size class" 测试（FAB 后不再 full-width，断言失效）。同文件其它 `find.byType(SaveActionButton)` 断言保留（widget 包装类型不变，FAB 仍可被定位）。

## Acceptance Criteria

- [ ] `_FormatButton` 选中态前景色为 `colorScheme.onPrimary`，代码注释与实现一致
- [ ] `SaveActionButton` 以 `FloatingActionButton.extended` 形态渲染，带 `heroTag: 'export-save-fab'`
- [ ] FAB disabled 态由 `onPressed: null` 触发（`!isSaving && canExport` 为 false 时）
- [ ] FAB in-flight 态正确显示 spinner + "保存中…" label
- [ ] `export_screen.dart` Scaffold 通过 `floatingActionButton` + `endFloat` 槽位承载 FAB；body 末尾追加 88dp 占位防遮挡
- [ ] `SaveDisclaimer` 仍在 body 末尾，不被 FAB 遮挡
- [ ] 失效的响应式测试已删除；其它 size class 断言保持绿
- [ ] `dart format .` 干净
- [ ] `flutter analyze` 无 warning
- [ ] `flutter test` 全绿

## Definition of Done

- 上述 Acceptance Criteria 全部勾选
- `dart format .` / `flutter analyze` / `flutter test` 三件套通过
- PRD 中记录 ADR-lite 决策
- 不引入新依赖

## Technical Approach

### 实现顺序

1. **Pre-flight**: 加载 spec/component-guidelines.md 的 MD3 token + FAB heroTag 段落（已完成，见 Technical Notes）
2. **R1 (单行修正)**: 改 `format_quality_card.dart:96-98` 的 fg token + 同步注释
3. **R2 (FAB 重构)**: 重写 `save_action_button.dart`，保留状态依赖 + 私有方法，外壳替换为 `FloatingActionButton.extended`
4. **R3 + R4 (Scaffold 布局)**: `export_screen.dart` 把 `SaveActionButton` 从 body 移到 `floatingActionButton` 槽位，body 末尾追加 `SizedBox(height: 88)`
5. **R5 (测试更新)**: 删除 `export_screen_responsive_test.dart` 的 full-width 测试，其它保持
6. **Check**: `dart format .` → `flutter analyze` → `flutter test`

### FAB 状态映射

| 业务态 | onPressed | icon | label |
|---|---|---|---|
| idle, canExport=true, isSaving=false | `_onSavePressed` | `Icons.save_outlined` | `exportSaveButtonLabelProvider` 文案 |
| in-flight (isSaving=true) | `null` | `CircularProgressIndicator(strokeWidth: 2)` 18×18 | `'保存中…'` |
| nothing to export (canExport=false) | `null` | `Icons.save_outlined` | `exportSaveButtonLabelProvider` 文案 (visually disabled by MD3) |

## Decision (ADR-lite)

**Context**：导出页面已经 GA，但发现两处 UI 细节问题：(a) FormatQualityCard 选中态紫底紫字对比度问题（上次 05-19 任务只改对了一半，注释/实现漂移）；(b) 主保存按钮目前是 inline FilledButton，缺乏 MD3 主操作的视觉权重。

**Decision**：
- 改动 1 用 `onPrimary` 对齐 MD3 token 配对规则
- 改动 2 用 `FloatingActionButton.extended` + `endFloat`，保留文案语义（grid 模式的 "保存 N 张" 数量提示）
- 两个改动合并为 1 个 task / commit（同主题 + 小范围 + 不需要独立回滚）

**Consequences**：
- 失去 inline 按钮的滚动可达性 — 但 FAB 默认 endFloat 始终可见，反而提升了长内容时的可达性
- body 需要 88dp bottom padding 让位，轻微浪费空间（仅 disclaimer 区域）— 接受
- 新增 1 个 heroTag 命名 `export-save-fab`，与 `stitch-export-fab` / `grid-export-fab` 形成命名族
- 测试需要删除 1 个 full-width 断言 — 不再有意义

## Out of Scope (explicit)

- 其它色彩 token 一致性的全面 review（仅修这一处）
- 修改保存按钮的核心交互逻辑（`save()` 方法、`SaveResult` 处理、snackbar 文案）
- WatermarkCard / FormatQualityCard 其它视觉调整
- 暗色模式重新调色（沿用 `ColorScheme.fromSeed` 派生方案）
- 引入 `BottomAppBar` / `bottomNavigationBar` / `persistentFooterButtons` 槽位
- 拆分 subtasks（合并 1 task）

## Technical Notes

- MD3 token 配对规则参考 `.trellis/spec/frontend/component-guidelines.md` "Design Tokens" 段
- FAB heroTag 强制约定参考 `.trellis/spec/frontend/component-guidelines.md:967-1023` Gotcha
- `app_colors.dart` 是 MD3 token 唯一权威源，禁止在其它地方写死十六进制
- 现存 FAB heroTag：`stitch-export-fab` / `grid-export-fab`，本次取名 `export-save-fab` 不冲突
- 上次相关任务背景：`.trellis/tasks/archive/2026-05/05-19-fix-export-screen-back-anim-and-format-contrast/prd.md`

## Files likely impacted

- `lib/features/export/presentation/widgets/format_quality_card.dart` (R1)
- `lib/features/export/presentation/widgets/save_action_button.dart` (R2)
- `lib/features/export/presentation/screens/export_screen.dart` (R3, R4)
- `test/features/export/presentation/export_screen_responsive_test.dart` (R5)

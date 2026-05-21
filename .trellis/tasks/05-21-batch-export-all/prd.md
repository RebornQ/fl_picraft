# 多图批量一键导出

## Goal

让 **Grid 拆分**导出场景从「一张确认一次」改成「一次操作搞定全部」：桌面端的 N 次「另存为」对话框收敛成一次「选择文件夹」对话框；Web 端的 N 次浏览器下载收敛成一次 ZIP 单文件下载；移动端 `gal` 相册写入保持现状（已经基本无感）。三端通过统一的 `BatchPersistAdapter` pull-based 流式接口实现，避免一次性把 N 张图都驻留内存。

## Glossary（在本任务里的精确用法）

| 术语 | 含义 |
|------|------|
| **Grid 多图导出** | `GridExportSource(cells: List<Uint8List>)` 路径，`cells.length ∈ {2, 3, 4, 6, 9}`（由 `GridType` 枚举决定，无 1×1） |
| **Batch persist** | 一次用户操作对应多张图的"持久化阶段"统称；与"process 阶段"（watermark + encode）相对 |
| **Pull-based 流式接口** | Adapter 通过 `Future<Uint8List?> Function(int) next` 回调主动 pull 第 i 张处理后字节；Adapter 决定何时拿下一张，自然支持"边 process 边写入"（桌面）和"全 buffer 后打包"（Web） |
| **Partial-save accounting** | 中途失败时仍能上报"已保存 X/Y 张"的语义，复用现有 `partialSaveFailureMessage` |

## Requirements

1. **桌面端**：Grid 导出弹一次 `FilePicker.platform.getDirectoryPath()` 让用户选目标文件夹，之后按 `flpicraft_<yyyyMMdd_HHmmss>_<index>.<ext>` 批量写入到该文件夹，**零额外对话框**。中途任一张写失败时，已写入的文件**保留**（与现有 partial-save accounting 一致）。
2. **Web 端**：Grid 导出把所有 cell 处理后的字节流打包成一个 ZIP，触发一次 `<a>.click()` 下载。ZIP 外层文件名 `flpicraft_<yyyyMMdd_HHmmss>.zip`，**内部顶层子目录** `flpicraft_<yyyyMMdd_HHmmss>/`，下放 N 张 `flpicraft_<yyyyMMdd_HHmmss>_<index>.<ext>`。
3. **移动端**：Grid 导出维持 `Gal.putImageBytes` 循环写相册行为（首次权限弹窗 1 次，之后无感）；但代码路径迁移到 `MobileGalleryPersistAdapter` 内部，三端走统一接口。
4. **Stitch 单图路径完全不动**（包括 cache hit 后 `persistOnly(processed.length == 1)` 仍走单文件 `saveFile` shortcut）。
5. 保留现有 `SaveResult` 三态语义（`SaveSuccess(location, count)` / `SaveFailure(message)` / `SaveCancelled`），且 `SaveSuccess.count` 反映"实际落盘"张数。
6. `ExportController.save()` 内部的 `processedBytesCacheProvider` 命中分支 (`persistOnly`) 同步适配：`processed.length == 1` 仍走 single-cell shortcut；`processed.length ≥ 2`（grid cache hit）走 `BatchPersistAdapter`。
7. UI 进度反馈维持现状：`SaveActionButton` 的 loading + 完成 snackbar，不新增进度 dialog。
8. **Web 端 button label**：`exportSaveButtonLabelProvider` 在 `kIsWeb && kind == grid` 时输出「保存 N 张为 ZIP」（替换"到本地"），其他平台维持原文案。
9. 引入 `archive` 包，仅 Web ZIP composer 路径通过 conditional import 引用；非 Web 构建图保持干净。
10. **不**对 Web ZIP 添加内存阈值告警 / 拦截 —— MVP 业务场景最多 g3x3（9 张），现实峰值远低于浏览器堆上限；若 OOM 由 `try/catch` 兜底走 `SaveFailure`。

## Acceptance Criteria

- [ ] 桌面端：导出 N≥2 张 cell 时，用户**仅看到 1 次**「选择文件夹」对话框，剩余 cell 自动写入；写入文件名遵循 `flpicraft_<yyyyMMdd_HHmmss>_<index>.<ext>`。
- [ ] 桌面端：用户在文件夹选择对话框点取消 → 返回 `SaveCancelled`，**无残留文件**（什么都没开始写）。
- [ ] 桌面端：选了文件夹但第 K 张写失败 → 返回 `SaveFailure(partialSaveFailureMessage(saved: K-1, total: N, cause: ...))`；已写入的 K-1 张**保留在文件夹中**。
- [ ] Web 端：导出 N≥2 张 cell **仅触发 1 次**浏览器下载；下载文件为 `flpicraft_<ts>.zip`；解压后存在顶层文件夹 `flpicraft_<ts>/`，内含 N 张 `flpicraft_<ts>_<index>.<ext>`；浏览器无"允许多个下载"权限弹窗。
- [ ] Web 端：`exportSaveButtonLabelProvider` 在 `kIsWeb && grid` 时返回「保存 N 张为 ZIP」；非 Web 或 stitch 路径维持原文案；FAB 在 compact/medium 三种 size class 下都不截断。
- [ ] 移动端：Grid 导出 N≥2 张 cell 与本任务前一致（首次权限弹窗后无对话框），`SaveSuccess.count` 反映写入张数；现有 grid + stitch 移动端测试零回归。
- [ ] Stitch 单图路径行为零变化（`_exportSingle` 测试通过、cache hit 的 `persistOnly` 单 byte 路径仍走 single-cell shortcut）。
- [ ] `BatchPersistAdapter` 接口可注入 fake，使 grid path 单元测试无需真实 plugin channel。

## Definition of Done

- 单元 / Widget 测试覆盖：
  - `BatchPersistAdapter` pull-based 接口契约：`next(i)` 在 Adapter 决定 pull 之前不被调用、Adapter 收到 `next` 返回 null 视为输入耗尽。
  - **桌面 Adapter**：getDirectoryPath 取消 / 全部成功 / 第 K 张写失败 三种 `SaveResult`。
  - **Web Adapter**：构造的 zip 字节用 `archive` 反向解码验证结构（顶层子目录 + N 张文件 + 命名匹配）。
  - **移动 Adapter**：包装 gal 循环后 partial-save accounting 与原行为一致。
- `flutter analyze` / `dart format .` 清洁。
- 三端各跑一次冒烟（手动 OK，记录在 PR 描述）。
- 现有 stitch / grid 导出测试零回归。
- 更新 `.trellis/spec/frontend/dependencies-and-platforms.md`：「Export」段增加桌面 directory mode + Web zip 模式 + 新增 `archive` 依赖的 conditional import 拓扑说明。

## Technical Approach

### 抽象层：`BatchPersistAdapter`（pull-based 流式）

放在 `lib/features/export/data/datasources/batch_persist_adapter.dart`：

```dart
/// Pull-based batch persistence contract.
///
/// Adapter MUST call `next(i)` to obtain the i-th processed bytes
/// (0-based). Returning null signals end-of-input. The contract is
/// pull-based so the adapter decides memory shape:
///   * desktop / mobile: pull → write → discard, peak ~ 1 image
///   * web: pull all → zip in memory → blob download, peak ~ Σ bytes
abstract class BatchPersistAdapter {
  Future<SaveResult> persistMany({
    required int total,
    required Future<Uint8List?> Function(int index) next,
    required ExportFormat format,
    required DateTime at,
  });
}
```

平台实现：

| 平台 | Adapter | 行为 |
|------|---------|------|
| Web (`kIsWeb`) | `WebZipPersistAdapter` | 顺序 `await next(i)` 直到 null，把每张作为 `ArchiveFile('flpicraft_<ts>/flpicraft_<ts>_<i>.<ext>', bytes)` 加入 `Archive`；`ZipEncoder().encode(archive)` 出 bytes；复用 `downloadBlob(zipBytes, 'flpicraft_<ts>.zip', 'application/zip')` |
| Desktop | `DesktopDirectoryPersistAdapter` | 先 `FilePicker.platform.getDirectoryPath()`；null → `SaveCancelled`；否则顺序 `await next(i)` → `File(join(dir, 'flpicraft_<ts>_<i>.<ext>')).writeAsBytes(bytes)`；任一张失败立即停止 + 返回 partial `SaveFailure`；保留已写入文件 |
| Mobile | `MobileGalleryPersistAdapter` | 顺序 `await next(i)` → `_gallery.save(bytes, fileName: stripExtension(name))`；partial-save accounting 与现有 `_exportGrid` 一致 |

### `ExportRepositoryImpl._exportGrid` 重构

```dart
Future<SaveResult> _exportGrid(List<Uint8List> cells, ExportRequest req) async {
  if (cells.isEmpty) return const SaveFailure('没有可导出的内容');
  final at = DateTime.now();
  return _batchAdapter.persistMany(
    total: cells.length,
    next: (i) async => i < cells.length
        ? await _processOne(cells[i], req)  // 流式 process
        : null,
    format: req.format,
    at: at,
  );
}
```

`persistOnly` 走类似形状，但跳过 `_processOne`：

```dart
Future<SaveResult> persistOnly(List<Uint8List> processed, ExportFormat format) async {
  if (processed.isEmpty) return const SaveFailure('没有可导出的内容');
  if (processed.length == 1) {
    return _persist(processed.single, format, suggestedName(format));  // stitch cache hit
  }
  // grid cache hit — batch adapter
  return _batchAdapter.persistMany(
    total: processed.length,
    next: (i) async => i < processed.length ? processed[i] : null,
    format: format,
    at: DateTime.now(),
  );
}
```

### Adapter dispatch 工厂

`BatchPersistAdapter.dispatch()` 作为 default 工厂；ExportRepositoryImpl 构造函数注入一个 `BatchPersistAdapter?`（缺省由工厂提供，测试可注入 fake）。

```dart
BatchPersistAdapter defaultBatchPersistAdapter() {
  if (kIsWeb) return WebZipPersistAdapter();
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    return MobileGalleryPersistAdapter();
  }
  return DesktopDirectoryPersistAdapter();
}
```

### Web ZIP composer（conditional import）

```
data/datasources/web_zip_composer.dart        ← 公开入口（platform-agnostic）
data/datasources/web_zip_composer_stub.dart   ← 非 Web 构建图，throw UnsupportedError
data/datasources/web_zip_composer_web.dart    ← Web 构建图，import 'package:archive/archive.dart'
```

公开入口：

```dart
import 'web_zip_composer_stub.dart'
    if (dart.library.js_interop) 'web_zip_composer_web.dart';

Uint8List composeZip({
  required Iterable<({String name, Uint8List bytes})> entries,
  required String rootFolder,  // 'flpicraft_<ts>/'
});
```

Web adapter 仅持有公开入口，`archive` 只在 `_web.dart` 里 import → 非 Web 构建图不会拉 archive 包代码到产物。

### Web 端 button label

修改 `lib/features/export/presentation/providers/export_dispatch.dart` 的 `exportSaveButtonLabelProvider`：

```dart
case ExportSourceKind.grid:
  final count = ref.watch(gridEditorControllerProvider).gridType.cellCount;
  if (kIsWeb) return '保存 $count 张为 ZIP';
  return mobile ? '保存 $count 张至相册' : '保存 $count 张到本地';
```

### `archive` 包

- 纯 Dart 实现，跨端可用，但通过 conditional import 把 import 路径限制在 `_web.dart`。
- 仅声明在 `pubspec.yaml.dependencies`（运行时依赖），不需要 dev_dependencies。

## Decision (ADR-lite)

**Context**: Grid 多图导出在桌面 / Web 上需要用户逐张确认，体验差。三端的"持久化语义"原本耦合在 `ExportRepositoryImpl._exportGrid` 的循环里，按 cell 串行调用 `_persist`，无法表达"批量一次性"。Web Wasm 默认 JS 堆 ~2GB（移动浏览器更紧）使得"一次性把 N 张原始字节驻留"在大图场景有风险。

**Decision**:

1. 抽象 `BatchPersistAdapter` 为 **pull-based 流式接口** —— Adapter 决定内存形状（桌面流写 / Web 全 buffer），repo 层接口统一。
2. **三端都包装为 Adapter**（包括行为零变化的移动端），repo 不再 platform-switch，dispatch 推到 `defaultBatchPersistAdapter()` 工厂。
3. 桌面 = 选文件夹 + 批量写入；Web = ZIP 单文件下载（子目录结构 `flpicraft_<ts>/` 包 N 张图）；移动 = 现状 gal 循环包装。
4. 引入 `archive` 包通过 conditional import 仅在 Web 构建图引用。
5. UI 不新增格式选项；Web 端通过修改 `exportSaveButtonLabelProvider` 在 button label 直接体现"保存 N 张为 ZIP"，比 disclaimer 更 prominent。
6. 中途失败保留 partial-save accounting：已写入文件**保留**，snackbar 文案诚实告知"已保存 X/Y 张"。
7. **不**做 ZIP 内存阈值告警（YAGNI；MVP 场景最大 9 张 4K 远低于浏览器堆上限）。

**Consequences**:
- ✅ 桌面 / Web 体验从 N 次确认变为 1 次。
- ✅ Pull-based 接口让桌面 / 移动峰值 ~1 image 字节，Web 自主决定 buffer 策略。
- ✅ 抽象层为未来"批量分享到云盘 / 邮件附件" 留出扩展点（新 Adapter 即可）。
- ⚠️ 引入 `archive` 包（~40KB，纯 Dart，活跃维护）；通过 conditional import 让非 Web 构建图保持干净。
- ⚠️ 桌面端「选文件夹后中途失败」会留下已写入文件 —— 由 partial-save accounting + snackbar 文案诚实告知，用户手动决定是否清理。
- ⚠️ 文件夹中如果存在同名文件会被覆盖；现有 `suggestedName` 已含时间戳 + 索引（秒级精度），同一秒重复导出才可能碰撞，不在 MVP 内处理。
- ⚠️ Web 端极端超大输入（10x 当前峰值）可能 OOM；由 `try/catch` 兜底走 `SaveFailure`，不预先警告。

## Out of Scope

- Stitch 长拼接路径不动。
- Web 端 ZIP 分卷 / 流式下载 / 内存阈值告警（大文件场景，留给未来任务）。
- 桌面端同名文件冲突的"覆盖 / 跳过 / 重命名"对话框。
- 移动端"分享所有"分享面板入口（`share_plus`）。
- 批量导出进度 dialog / 通知栏 / 取消按钮。
- 1×1 grid（GridType 枚举不存在此值）。

## Implementation Plan（建议拆 3 个 PR）

- **PR1（抽象层 + 测试夹具）**：
  - 新增 `BatchPersistAdapter` interface + `defaultBatchPersistAdapter()` 工厂
  - `ExportRepositoryImpl` 增加 `BatchPersistAdapter?` 注入字段
  - 重构 `_exportGrid` / `persistOnly(processed.length ≥ 2)` 走 `persistMany`
  - 提供 `FakeBatchPersistAdapter`（计数 next 调用次数、可注入 SaveResult），覆盖现有 grid 路径回归 + pull-based 契约测试
- **PR2（桌面 + Web 实现）**：
  - `DesktopDirectoryPersistAdapter`：`getDirectoryPath` + `writeAsBytes` 流式
  - `archive` 依赖入 pubspec + conditional import 的 `web_zip_composer.dart` / `_stub.dart` / `_web.dart`
  - `WebZipPersistAdapter`：pull 全部 bytes → composeZip → 复用 `downloadBlob`
  - `MobileGalleryPersistAdapter`：包装现有 gal 循环 + 复用 `_stripExtension`
  - 桌面取消 / 部分失败 / 全成功 / Web zip 解码反向验证 / 移动回归 各类单元测试
- **PR3（UI 文案 + 文档 + 冒烟）**：
  - `exportSaveButtonLabelProvider` Web grid 分支返回「保存 N 张为 ZIP」
  - 更新 `.trellis/spec/frontend/dependencies-and-platforms.md` 的 Export 段（archive conditional import 拓扑、directory mode、ZIP 内部结构）
  - 更新 `.trellis/spec/frontend/directory-structure.md` 增加 `data/datasources/batch_persist_*.dart` + `web_zip_composer_*.dart` 归属示意
  - 三端冒烟 + PR 描述截图 / GIF

## Technical Notes

### 关键文件

- `lib/features/export/data/repositories/export_repository_impl.dart`（`_exportGrid` / `persistOnly` 重构、`BatchPersistAdapter` 注入点）
- `lib/features/export/data/datasources/batch_persist_adapter.dart`（**新增** interface + dispatch 工厂）
- `lib/features/export/data/datasources/desktop_directory_persist_adapter.dart`（**新增**）
- `lib/features/export/data/datasources/mobile_gallery_persist_adapter.dart`（**新增**，包装现有 `GallerySaverDataSource`）
- `lib/features/export/data/datasources/web_zip_persist_adapter.dart`（**新增**）
- `lib/features/export/data/datasources/web_zip_composer.dart` / `_stub.dart` / `_web.dart`（**新增**，conditional import 拓扑）
- `lib/features/export/data/datasources/file_dialog_save_datasource.dart`（**保留**：stitch 单文件路径仍走它）
- `lib/features/export/data/datasources/web_blob_download_datasource.dart` + `web_blob_download_web.dart`（**保留 + 复用**：Web ZIP adapter 复用 `downloadBlob`）
- `lib/features/export/data/datasources/gallery_saver_datasource.dart`（**保留**：被 mobile adapter 包装）
- `lib/features/export/presentation/providers/export_dispatch.dart`（**修改** `exportSaveButtonLabelProvider`）
- `lib/features/export/domain/usecases/suggested_name.dart`（**保留 + 扩展**：新增 `suggestedZipName()` / `suggestedZipFolderName()` helper 返回 `flpicraft_<ts>.zip` / `flpicraft_<ts>/`）

### 新增依赖

```yaml
dependencies:
  archive: ^3.6.1   # 纯 Dart ZIP 打包；仅通过 web_zip_composer_web.dart 引用，
                    # 非 Web 构建图通过 conditional import stub 隔离
```

### 平台 dispatch 决策表

| 条件 | 走的 Adapter |
|------|--------------|
| `kIsWeb` | `WebZipPersistAdapter` |
| `defaultTargetPlatform in {iOS, Android}` | `MobileGalleryPersistAdapter` |
| `defaultTargetPlatform in {macOS, Windows, Linux}` | `DesktopDirectoryPersistAdapter` |
| 其他 | `SaveFailure('当前平台暂不支持')` |

### 文件命名规约（本任务定稿）

| 位置 | 命名 | 示例 |
|------|------|------|
| 桌面端文件夹内每张 | `flpicraft_<yyyyMMdd_HHmmss>_<index>.<ext>` | `flpicraft_20260521_120607_3.jpg` |
| Web ZIP 外层 | `flpicraft_<yyyyMMdd_HHmmss>.zip` | `flpicraft_20260521_120607.zip` |
| Web ZIP 顶层子目录 | `flpicraft_<yyyyMMdd_HHmmss>/` | `flpicraft_20260521_120607/` |
| Web ZIP 内每张 | `flpicraft_<ts>/flpicraft_<ts>_<index>.<ext>` | `flpicraft_20260521_120607/flpicraft_20260521_120607_3.jpg` |
| 移动相册 | `flpicraft_<ts>_<index>`（无扩展名，gal 自动补） | `flpicraft_20260521_120607_3` |

> `index` 1-based（与现有 `suggestedName(format, at, index)` 调用约定一致：`_exportGrid` line 159 / `persistOnly` line 87 都传 `i + 1`）。

### Spec 影响

- `.trellis/spec/frontend/dependencies-and-platforms.md`：Export 段落需增加 directory mode + Web zip 模式 + `archive` conditional import 拓扑说明。
- `.trellis/spec/frontend/directory-structure.md`：新增 `data/datasources/batch_persist_*.dart` + `web_zip_composer_*.dart` 的归属示意。

## Decisions（brainstorm + grill 收敛完毕）

- ✅ **D1：MVP 范围 = 三端齐做**
- ✅ **D2：桌面端 = 选文件夹 + 批量写入**（`FilePicker.platform.getDirectoryPath()`）
- ✅ **D3：Web 端 = ZIP 单文件下载**（引入 `archive` 包）
- ✅ **D4：移动端 = 维持 gal 循环写相册行为**（但代码迁移到 `MobileGalleryPersistAdapter` 内部）
- ✅ **D5：UI 不增格式选项**
- ✅ **D6：进度反馈维持 snackbar + button loading**
- ✅ **D7：BatchPersistAdapter 接口 = pull-based 流式回调**（`Future<Uint8List?> Function(int)`）
- ✅ **D8：桌面文件夹中途失败 = 保留已写入 + partial-save accounting**（不回滚、不询问）
- ✅ **D9：cells.length == 1 不在 grid 场景**（GridType 最小 2），stitch cache hit 保留 single-cell shortcut
- ✅ **D10：Web ZIP 不加内存阈值告警 / 拦截**（YAGNI）
- ✅ **D11：ZIP 结构 = 子目录** `flpicraft_<ts>/{flpicraft_<ts>_N.<ext>}`，外层 `flpicraft_<ts>.zip`
- ✅ **D12：Web 提示 = 修改 `exportSaveButtonLabelProvider`**（Web + grid → 「保存 N 张为 ZIP」）
- ✅ **D13：移动端也包装为 `MobileGalleryPersistAdapter`** —— 三端接口统一，repo 零 platform-switch

# cleanup stale archived task paths from working tree

## Goal

清理工作目录中遗留的 12 个 `D` 状态文件——这些文件原本属于已 archive 的 task（editor-layout-and-import-isolation、per-mode-import-isolation、editor-fill-container-width 等），`task.py archive` 命令把目录 move 到 `archive/2026-05/` 时只 stage 了新位置的 add，没 stage 旧位置的 delete，导致 working tree 长期显示 dirty。用 `git rm` 一次性把这些旧路径的 deletion 提交进去，让 `git status` 干净。

## What I already know

- 受影响的 8 + 4 = 12 个文件路径（来自 `git status --porcelain`）：
  - `.trellis/tasks/05-16-editor-layout-and-import-isolation/{check,implement}.jsonl + prd.md + task.json` (4)
  - `.trellis/tasks/05-16-per-mode-import-isolation/{check,implement}.jsonl + prd.md + task.json` (4)
  - 上一轮 finish-work 又新增了 `.trellis/tasks/05-16-grid-canvas-height-first-fit/{check,implement}.jsonl + prd.md + task.json` (4) — 同样是 archive quirk
- 所有这些路径都已经在 `archive/2026-05/<slug>/` 下存在了正确副本（git ls-files 验证）。
- 受影响 commits：
  - `9b0b54e chore(task): archive 05-16-editor-layout-and-import-isolation`
  - `97290a3 chore(task): archive 05-16-per-mode-import-isolation`
  - `8356e62 chore(task): archive 05-16-grid-canvas-height-first-fit`
  - `5c11d4e chore(task): archive 05-16-rename-works-to-feature-hub`
- 实际上检查 `git status` 看 task 05-16-rename-works-to-feature-hub 已经干净了——因为它的旧目录在 commit 前是 untracked（task 1 是本会话新建的、首次 commit 时把整个目录 add 进 archive/，原位置无历史副本可删）。这次的 D 残留是 task 05-16-editor-layout / per-mode-import-isolation / grid-canvas-height-first-fit 三批。

## Requirements

- 用 `git rm` 把所有 12 个 `D` 状态路径 stage 进 deletion（git rm 等价于 stage 一个 delete）。
- 单次 chore commit 提交所有删除。
- 不动 `archive/2026-05/` 下的副本（这才是文件的现存位置）。
- 不动任何 `lib/`, `test/`, `.trellis/spec/` 等其他路径。

## Acceptance Criteria

- [ ] `git status` 干净，无任何 `D` / `M` / `??` 残留。
- [ ] `archive/2026-05/05-16-editor-layout-and-import-isolation/`、`archive/2026-05/05-16-per-mode-import-isolation/`、`archive/2026-05/05-16-grid-canvas-height-first-fit/` 三个目录仍然完整保留（用 ls 验证）。
- [ ] `flutter analyze` 与 `flutter test` 仍干净（应该完全不受影响，但跑一遍兜底）。

## Definition of Done

- 单次 chore commit 提交所有 deletion。
- working tree 完全干净。
- 三个 archive 目录完整保留。

## Technical Approach

```bash
git rm \
  .trellis/tasks/05-16-editor-layout-and-import-isolation/check.jsonl \
  .trellis/tasks/05-16-editor-layout-and-import-isolation/implement.jsonl \
  .trellis/tasks/05-16-editor-layout-and-import-isolation/prd.md \
  .trellis/tasks/05-16-editor-layout-and-import-isolation/task.json \
  .trellis/tasks/05-16-per-mode-import-isolation/check.jsonl \
  .trellis/tasks/05-16-per-mode-import-isolation/implement.jsonl \
  .trellis/tasks/05-16-per-mode-import-isolation/prd.md \
  .trellis/tasks/05-16-per-mode-import-isolation/task.json \
  .trellis/tasks/05-16-grid-canvas-height-first-fit/check.jsonl \
  .trellis/tasks/05-16-grid-canvas-height-first-fit/implement.jsonl \
  .trellis/tasks/05-16-grid-canvas-height-first-fit/prd.md \
  .trellis/tasks/05-16-grid-canvas-height-first-fit/task.json
```

然后 commit `chore(repo): remove stale archived task paths from working tree`。

## Out of Scope

- 不修复 `task.py archive` 命令本身的 quirk（让它未来用 `git mv` 而非 `os.rename`）——这是 trellis 上游工具的事情。
- 不动任何代码（lib/、test/）。
- 不动 archive/ 下任何已有副本。

## Technical Notes

- 关键风险：误删 `archive/` 下文件。`git rm` 只接受参数中显式列出的路径，不会牵连 archive/ 副本。
- 不需要 trellis 子代理（trivial chore，main agent 直接做即可）。

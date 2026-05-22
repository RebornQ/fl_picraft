# Journal - Reborn (Part 2)

> Continuation from `journal-1.md` (archived at ~2000 lines)
> Started: 2026-05-23

---



## Session 60: ST4 final + parent close: extended_image migration arc complete

**Date**: 2026-05-23
**Task**: ST4 final + parent close: extended_image migration arc complete
**Branch**: `main`

### Summary

Final subtask of 05-22-brainstorm-fullscreen-preview-extended-image. Three intertwined deliverables in one cohesive cleanup commit (43dd483): (1) Rewrote preview_full_screen_dialog_test.dart from 776→843 lines, 27→25 tests all PASS — implemented failing-tests.md hand-off spec verbatim (16 rewrites + 4 deletions); 9 surviving tests preserved byte-identical; 3 new helpers (_gestureState pins ExtendedImageGesture not ExtendedImage; _primeImageDecode runs precacheImage to swap in real ExtendedImageGesture before ImageStream resolves; _dragFromBy 16-step controlled drag mirrors real user 60fps for ScaleGestureRecognizer arena resolution) inline documented. (2) ADR double update — ADR-0001 frontmatter Superseded by [ADR-0002] (2026-05-23) + new section at file end (original preserved); ADR-0002 new (258 lines) with Context / Decision / Consequences containing Post-ST2 Revision sub-bullet recording 'keep showDialog<void> not migrate to PageRouteBuilder(opaque:false) — main decision held, sub-decision reversed via layered decision-making' / Alternatives (B/C/photo_view_gallery) / Validation / References. (3) PoC cleanup — deleted lib/_poc/extended_image_poc.dart (364 lines, dir gone); removed kDebugMode-gated debug entry from home_screen.dart (foundation.dart import only used for kDebugMode, also removed); preserved archived poc-report.md + failing-tests.md as institutional records. flutter analyze 0 / dart format 0 changed / flutter test 546 PASS / 3 skip benchmark / 0 FAIL. Net stats: 7 files / +1059 / -800 — healthy cleanup. Archived ST4 + parent brainstorm together (parent [4/4 done] after ST4 archive). Closes the entire 4-subtask extended_image migration arc started 2026-05-22. ADR-0001 (Accepted → Superseded by ADR-0002) preserved as historical record.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `43dd483` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete

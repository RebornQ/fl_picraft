# Polish & Multi-Platform Test

## Goal

After all functional features land, polish UX rough edges and verify the app meets non-functional targets on every supported platform. This is the "no new feature" lap that catches regressions, perf cliffs, and platform-specific quirks before the first release.

## Requirements

### Performance budgets (Total PRD §7)

| Metric | Target |
|--------|--------|
| 20 images stitch + export | < 5 seconds |
| Peak memory while processing large images | < 500 MB |
| App cold start to interactive | < 2 seconds (mobile) |

### Platform compatibility matrix

| Platform | Min version | Verified flows |
|----------|-------------|----------------|
| iOS | 12+ | Import (gallery + camera), stitch, grid, export to Photos |
| Android | 6+ (API 23) | Same as iOS + drag-drop disabled gracefully |
| macOS | 11+ | Drag-drop, file dialog save |
| Windows | 10+ | Drag-drop, file dialog save |
| Linux | Ubuntu 20.04+ | Drag-drop, file dialog save |
| Web | Chrome / Edge / Safari latest | Gallery picker, blob download |

### UX polish checklist

- [ ] Loading states for all async ops (import / stitch / export)
- [ ] Error toasts with actionable messages (not raw exception strings)
- [ ] Empty states (no images yet, unsupported platform fallback)
- [ ] Responsive layout: phone portrait / phone landscape / tablet / desktop
- [ ] Dark mode parity (UI design uses light theme; verify dark adaptations)
- [ ] Accessibility: semantic labels, sufficient contrast, font scaling

## Acceptance Criteria

- [ ] Performance budgets met on a mid-tier device per platform
- [ ] All flows pass on all 6 platforms with no crash
- [ ] `flutter analyze` clean across the matrix
- [ ] No `// TODO` / `// FIXME` left in shipped code
- [ ] Manual test plan executed and documented in this PRD

## Out of Scope

- Localization beyond zh-CN (i18n is post-MVP)
- Telemetry / crash reporting wiring
- App store submission assets (icons, screenshots)

## Dependencies

- Requires: all feature tasks (`02` through `05`) merged

## References

- Total PRD §7 Non-functional requirements
- Spec: `.trellis/spec/frontend/quality-guidelines.md`

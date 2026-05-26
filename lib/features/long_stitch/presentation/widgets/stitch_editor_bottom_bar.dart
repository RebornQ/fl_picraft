import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../image_import/domain/repositories/image_import_repository.dart'
    show kMaxImportSessionImages;
import '../providers/stitch_editor_provider.dart';
import 'stitch_add_action_sheet.dart';
import 'stitch_image_sheet.dart';

/// Persistent editor bottom bar surfaced under the canvas on
/// compact viewports.
///
/// Hosts three segments left-to-right:
///
/// 1. **`[+ 添加]`** — TonalButton that opens an [ActionSheet]
///    (gallery / clipboard / camera) via [showStitchAddActionSheet].
///    Always enabled.
/// 2. **`[🖼 N/20]`** — TonalButton showing the current image count
///    out of the 20-image cap. Tapping opens
///    [showStitchImageSheet] so the user can review / reorder /
///    remove images. Disabled while the session is empty (no
///    images to manage).
/// 3. **`[⚙ 参数]`** — Toggle chip that expands / collapses the
///    inline [StitchInlineControlsContainer] between the canvas and
///    this bar (PRD `05-26-compact`). When the panel is visible the
///    chip switches to a [FilledButton] (primary fill) selected
///    state; otherwise it stays a [FilledButton.tonalIcon]. Always
///    enabled.
///
/// The export CTA lives **outside** this bar — it stays in the
/// AppBar's action slot (`Icons.save_outlined`, tooltip
/// "导出拼图") on every size class, matching the muscle-memory
/// position users already learned. The bar therefore does not
/// claim a primary-CTA slot.
///
/// The bar lives in the Scaffold's `bottomNavigationBar` slot of
/// the inner editor [Scaffold] — Flutter stacks it above the
/// outer [AppShell.bottomNavigationBar] without any router /
/// shell changes. The visual chrome (`elevation: 3`,
/// `colorScheme.surface`, top `outlineVariant` divider) helps the
/// user distinguish this editor-local bar from the
/// outer-shell `NavigationBar`.
///
/// This widget is only rendered on [WindowSizeClass.compact] —
/// medium / expanded / large widths keep their existing
/// strip + sheet / row + side-panel layouts.
class StitchEditorBottomBar extends ConsumerWidget {
  const StitchEditorBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final hasImages = state.hasImages;
    final imageCount = state.imageCount;

    return Material(
      elevation: 3,
      color: colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _AddChip(
                        onPressed: () => showStitchAddActionSheet(context, ref),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ImagesChip(
                        imageCount: imageCount,
                        enabled: hasImages,
                        onPressed: () => showStitchImageSheet(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: const _ParamsChip(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `[+ 添加]` chip — TonalButton, always enabled.
class _AddChip extends StatelessWidget {
  const _AddChip({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '添加图片',
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('添加'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}

/// `[🖼 N/20]` chip — TonalButton, disabled when the session is
/// empty.
class _ImagesChip extends StatelessWidget {
  const _ImagesChip({
    required this.imageCount,
    required this.enabled,
    required this.onPressed,
  });

  final int imageCount;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? '管理已选图片' : '尚未导入图片',
      child: FilledButton.tonalIcon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.photo_library_outlined, size: 18),
        label: Text('$imageCount/$kMaxImportSessionImages'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}

/// `[⚙ 参数]` chip — toggles [stitchControlsInlineVisibleProvider].
///
/// Visual state mirrors the provider value:
///
/// * **collapsed** (`visible == false`) → [FilledButton.tonalIcon],
///   tooltip "展开参数"
/// * **expanded** (`visible == true`) → [FilledButton.icon] (primary
///   fill) selected state, tooltip "收起参数"
///
/// Always enabled — the parameter panel can be opened even when no
/// images are imported (the user may want to pre-configure border /
/// corner before adding images). Tap flips the provider; the inline
/// container in `_StitchEditorBody` animates between the two states.
class _ParamsChip extends ConsumerWidget {
  const _ParamsChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(stitchControlsInlineVisibleProvider);

    void toggle() {
      ref.read(stitchControlsInlineVisibleProvider.notifier).update((v) => !v);
    }

    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );

    return Tooltip(
      message: visible ? '收起参数' : '展开参数',
      child: visible
          ? FilledButton.icon(
              onPressed: toggle,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('参数'),
              style: buttonStyle,
            )
          : FilledButton.tonalIcon(
              onPressed: toggle,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('参数'),
              style: buttonStyle,
            ),
    );
  }
}

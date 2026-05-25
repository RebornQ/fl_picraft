import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stitch_editor_state.dart';
import '../../domain/entities/stitch_mode.dart';
import '../providers/stitch_editor_provider.dart';
import 'stitch_basic_tab_cards.dart';

/// Tabbed controls panel for the long-stitch editor.
///
/// Four logical tabs surface every parameter the editor exposes, with
/// the "电影台词" tab dynamically inserted only while
/// `subtitleOnlyMode == true` (PRD §D2). Tab order is fixed:
///
/// 1. **基础** — orientation toggle, normal / movie-subtitle picker
///    (see [StitchBasicTabCards]).
/// 2. **电影台词** *(conditional)* — subtitle band-height slider +
///    auto-trim black bars switch.
/// 3. **边框** — border width slider + 6-swatch color picker.
/// 4. **圆角 / 间距** — corner-radius slider + image-spacing slider.
///
/// The TabBarView disables horizontal swipe (per PRD §D6) so the
/// basic tab's horizontal card list never fights the TabBarView's
/// own scroll arena.
///
/// Tab persistence is intentionally absent (PRD §D3): every fresh
/// mount lands on the "基础" tab. When `subtitleOnlyMode` flips off
/// while the "电影台词" tab is active, the controller falls back to
/// "基础" rather than landing on a now-missing tab.
class StitchControlsPanel extends ConsumerStatefulWidget {
  const StitchControlsPanel({super.key});

  @override
  ConsumerState<StitchControlsPanel> createState() =>
      _StitchControlsPanelState();
}

class _StitchControlsPanelState extends ConsumerState<StitchControlsPanel>
    with TickerProviderStateMixin {
  TabController? _controller;
  bool _subtitleVisible = false;

  @override
  void initState() {
    super.initState();
    _subtitleVisible = ref
        .read(stitchEditorControllerProvider)
        .subtitleOnlyMode;
    _controller = TabController(length: _subtitleVisible ? 4 : 3, vsync: this);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncControllerLength(bool subtitleVisible) {
    if (subtitleVisible == _subtitleVisible) return;
    final old = _controller;
    final oldIndex = old?.index ?? 0;
    // Map old index → new index across the dynamic insertion.
    int newIndex;
    if (subtitleVisible) {
      // Inserted subtitle tab at position 1. Everything from old
      // position ≥ 1 shifts right by one. Initial selection on the
      // subtitle tab itself happens via the basic-tab card tap, which
      // emits state ahead of this listener — we keep the focus on
      // the basic tab so the user's eye stays anchored.
      newIndex = oldIndex == 0 ? 0 : oldIndex + 1;
    } else {
      // Removed subtitle tab (was at position 1). If we were sitting
      // on it, fall back to the basic tab (PRD §D3 first sentence).
      if (oldIndex == 0) {
        newIndex = 0;
      } else if (oldIndex == 1) {
        newIndex = 0;
      } else {
        newIndex = oldIndex - 1;
      }
    }
    final next = TabController(
      length: subtitleVisible ? 4 : 3,
      vsync: this,
      initialIndex: newIndex,
    );
    setState(() {
      _controller = next;
      _subtitleVisible = subtitleVisible;
    });
    // Dispose the old controller after the new one is wired so any
    // animation listeners on the TabBar don't read a disposed
    // controller during the swap.
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // React to subtitleOnlyMode changes without watching the entire
    // state — `setState` inside the listener keeps the TabController
    // length in lock-step with PRD §D2 (dynamic insertion).
    ref.listen<bool>(
      stitchEditorControllerProvider.select((s) => s.subtitleOnlyMode),
      (prev, next) => _syncControllerLength(next),
    );

    final state = ref.watch(stitchEditorControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final controller = _controller!;

    final tabs = <Widget>[
      const Tab(text: '基础'),
      if (_subtitleVisible) const Tab(text: '电影台词'),
      const Tab(text: '边框'),
      const Tab(text: '圆角 / 间距'),
    ];

    final tabViews = <Widget>[
      _BasicTabContent(state: state),
      if (_subtitleVisible) _SubtitleTabContent(state: state),
      _BorderTabContent(state: state),
      _CornersSpacingTabContent(state: state),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: controller,
            isScrollable: false,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
            tabs: tabs,
          ),
          const SizedBox(height: 8),
          // TabBarView needs a bounded height — give it just enough
          // room for the tallest tab body (subtitle: slider + switch;
          // border: slider + swatch wrap; corners/spacing: two
          // sliders; basic: horizontal card row + caption).
          SizedBox(
            height: 224,
            child: TabBarView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              children: tabViews,
            ),
          ),
        ],
      ),
    );
  }
}

class _BasicTabContent extends StatelessWidget {
  const _BasicTabContent({required this.state});

  final StitchEditorState state;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [StitchBasicTabCards()],
      ),
    );
  }
}

class _SubtitleTabContent extends ConsumerWidget {
  const _SubtitleTabContent({required this.state});

  final StitchEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(stitchEditorControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitleEffective = state.imageCount >= 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SliderRow(
            label: '字幕高度',
            value: state.subtitleBandHeightPercent,
            min: kMinSubtitleBandHeightPercent,
            max: kMaxSubtitleBandHeightPercent,
            valueText: '${(state.subtitleBandHeightPercent * 100).round()}%',
            onChanged: notifier.setSubtitleBandHeightPercent,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '自动剪裁黑边',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Switch(
                value: state.autoTrimBlackBars,
                onChanged: subtitleEffective
                    ? (v) => _onToggleAutoTrim(context, notifier, v)
                    : null,
              ),
            ],
          ),
          if (!subtitleEffective)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '需要至少 2 张图片才能启用电影台词效果',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onToggleAutoTrim(
    BuildContext context,
    StitchEditorController notifier,
    bool enabled,
  ) {
    notifier.setAutoTrimBlackBars(enabled);
    if (!enabled) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('已开启自动剪裁黑边，请检查预览效果')));
  }
}

class _BorderTabContent extends ConsumerWidget {
  const _BorderTabContent({required this.state});

  final StitchEditorState state;

  static const _borderSwatches = <Color>[
    Colors.black,
    Colors.white,
    Color(0xFF4F378A),
    Color(0xFF625B71),
    Color(0xFFBA1A1A),
    Color(0xFFCBC4D2),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(stitchEditorControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SliderRow(
            label: '边框宽度',
            value: state.border.width,
            min: 0,
            max: kMaxStitchBorderWidth,
            valueText: '${state.border.width.round()} px',
            onChanged: notifier.setBorderWidth,
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '边框颜色',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final swatch in _borderSwatches)
                _ColorSwatch(
                  color: swatch,
                  selected: swatch == state.border.color,
                  onTap: () => notifier.setBorderColor(swatch),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CornersSpacingTabContent extends ConsumerWidget {
  const _CornersSpacingTabContent({required this.state});

  final StitchEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(stitchEditorControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Per PRD: subtitle mode forces spacing := 0 in the layout
    // algorithm, so the slider has no effect. Disable it with a hint
    // instead of hiding (so users can see the parameter exists and
    // understand why it's inert).
    final spacingDisabled =
        state.subtitleOnlyMode && state.mode == StitchMode.vertical;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SliderRow(
            label: '圆角',
            value: state.cornerRadius,
            min: 0,
            max: kMaxStitchCornerRadius,
            valueText: '${state.cornerRadius.round()} px',
            onChanged: notifier.setCornerRadius,
          ),
          const SizedBox(height: 4),
          _SliderRow(
            label: '图片间距',
            value: state.spacing,
            min: 0,
            max: kMaxStitchSpacing,
            valueText: '${state.spacing.round()} px',
            onChanged: spacingDisabled ? null : notifier.setSpacing,
          ),
          if (spacingDisabled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '字幕模式下间距由算法控制',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disabled = onChanged == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  color: disabled
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                valueText,
                style: textTheme.labelMedium?.copyWith(
                  color: disabled
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '边框颜色',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

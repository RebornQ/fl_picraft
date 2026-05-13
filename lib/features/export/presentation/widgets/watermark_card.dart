import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/watermark_anchor.dart';
import '../../domain/entities/watermark_config.dart';
import '../providers/watermark_config_provider.dart';

/// Settings card for the export screen's watermark section.
///
/// Mirrors the layout in
/// `docs/UI Design/Fl_PiCraft_stitch_prd_ui_generator/_4_导出页面/code.html`
/// lines 170–205:
///
/// * Header row "水印" with a master toggle on the right
/// * Inner card with the text input, a 3x3 position picker, and an
///   opacity slider
class WatermarkCard extends ConsumerWidget {
  const WatermarkCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(watermarkConfigProvider);
    final notifier = ref.read(watermarkConfigProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header — title + master toggle.
        Row(
          children: [
            Expanded(
              child: Text(
                '水印',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Switch(value: config.enabled, onChanged: notifier.setEnabled),
          ],
        ),
        const SizedBox(height: 8),
        // Inner card — dimmed when disabled to telegraph that controls
        // are inert (the rasterizer also short-circuits, so flipping
        // them while OFF has no preview effect).
        Opacity(
          opacity: config.enabled ? 1.0 : 0.5,
          child: IgnorePointer(
            ignoring: !config.enabled,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TextInput(text: config.text, onChanged: notifier.setText),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _PositionPicker(
                          selected: config.anchor,
                          onChanged: notifier.setAnchor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OpacityField(
                          value: config.opacity,
                          onChanged: notifier.setOpacity,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput({required this.text, required this.onChanged});

  final String text;
  final ValueChanged<String> onChanged;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant _TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external changes (e.g. resetting to default) without
    // clobbering the user's caret while they're typing.
    if (widget.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '文字内容',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          maxLength: kMaxWatermarkTextLength,
          decoration: const InputDecoration(
            isDense: true,
            counterText: '',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }
}

class _PositionPicker extends StatelessWidget {
  const _PositionPicker({required this.selected, required this.onChanged});

  final WatermarkAnchor selected;
  final ValueChanged<WatermarkAnchor> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '位置',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 96,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final anchor in WatermarkAnchor.values)
                _AnchorCell(
                  anchor: anchor,
                  selected: anchor == selected,
                  onTap: () => onChanged(anchor),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnchorCell extends StatelessWidget {
  const _AnchorCell({
    required this.anchor,
    required this.selected,
    required this.onTap,
  });

  final WatermarkAnchor anchor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Watermark position ${anchor.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : colorScheme.surface,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class _OpacityField extends StatelessWidget {
  const _OpacityField({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final percent = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '透明度',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(kMinWatermarkOpacity, kMaxWatermarkOpacity),
                min: kMinWatermarkOpacity,
                max: kMaxWatermarkOpacity,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$percent%',
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:fl_picraft/features/grid/domain/entities/grid_editor_state.dart';
import 'package:fl_picraft/features/grid/domain/entities/grid_type.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:flutter_test/flutter_test.dart';

ImportedImage _image(int w, int h) => ImportedImage(
  bytes: Uint8List(0),
  width: w,
  height: h,
  mimeType: 'image/png',
  importedAt: DateTime(2026, 5, 14),
);

void main() {
  group('GridEditorState.initial', () {
    test('uses PRD-spec defaults (3x3, spacing 0, radius 12)', () {
      final state = GridEditorState.initial();
      expect(state.source, isNull);
      expect(state.gridType, GridType.g3x3);
      expect(state.spacing, 0);
      expect(state.cornerRadius, kDefaultGridCornerRadius);
      expect(state.cornerRadius, 12);
    });

    test('hasSource is false until a source is set', () {
      expect(GridEditorState.initial().hasSource, false);
      final withSource = GridEditorState.initial().copyWith(
        source: _image(100, 100),
      );
      expect(withSource.hasSource, true);
    });

    test('sourceTooSmall flags images smaller than the min dimension', () {
      // No source → false.
      expect(GridEditorState.initial().sourceTooSmall, false);
      // 99 < 100 on either axis → true.
      final tooSmallW = GridEditorState.initial().copyWith(
        source: _image(99, 200),
      );
      final tooSmallH = GridEditorState.initial().copyWith(
        source: _image(200, 99),
      );
      expect(tooSmallW.sourceTooSmall, true);
      expect(tooSmallH.sourceTooSmall, true);
      // 100x100 exactly → not flagged.
      final ok = GridEditorState.initial().copyWith(source: _image(100, 100));
      expect(ok.sourceTooSmall, false);
    });
  });

  group('GridEditorState.copyWith', () {
    test('preserves unspecified fields', () {
      final original = GridEditorState.initial().copyWith(
        source: _image(500, 500),
        gridType: GridType.g2x3,
        spacing: 12,
        cornerRadius: 24,
      );
      final next = original.copyWith(spacing: 30);
      expect(next.source, original.source);
      expect(next.gridType, GridType.g2x3);
      expect(next.spacing, 30);
      expect(next.cornerRadius, 24);
    });

    test('clearSource overrides source param to null', () {
      final original = GridEditorState.initial().copyWith(
        source: _image(500, 500),
      );
      final cleared = original.copyWith(clearSource: true);
      expect(cleared.source, isNull);
      expect(cleared.hasSource, false);
    });

    test('clearSource takes precedence over an explicit source argument', () {
      final original = GridEditorState.initial().copyWith(
        source: _image(500, 500),
      );
      final cleared = original.copyWith(
        clearSource: true,
        source: _image(100, 100),
      );
      expect(cleared.source, isNull);
    });
  });

  group('GridEditorState equality', () {
    test('two states with the same fields are equal', () {
      final a = GridEditorState.initial().copyWith(spacing: 10);
      final b = GridEditorState.initial().copyWith(spacing: 10);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields break equality', () {
      final a = GridEditorState.initial().copyWith(spacing: 10);
      final b = GridEditorState.initial().copyWith(spacing: 12);
      expect(a, isNot(b));
    });
  });
}

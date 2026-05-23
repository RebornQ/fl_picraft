/// Widget tests for [showStitchImageSheet].
///
/// PRD: `.trellis/tasks/05-23-mobile-canvas-redesign-for-long-image-stitching`
///
/// The image sheet wraps the existing [StitchVerticalImageList]
/// widget — the same one docked on the right column for expanded
/// / large widths — so both layouts share one source of truth for
/// image management. The sheet caps at 70% viewport height.
library;

import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_image_sheet.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_vertical_image_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

ImportedImage _stub({String tag = 'a'}) {
  return ImportedImage(
    sourcePath: tag,
    bytes: _validPng(),
    width: 100,
    height: 200,
    mimeType: 'image/png',
    importedAt: DateTime(2026, 1, 1),
  );
}

class _FakeRepo implements ImageImportRepository {
  _FakeRepo(this._pickResult);

  final List<ImportedImage> _pickResult;

  @override
  Future<ImportResult> pickFromGallery({int limit = kMaxImportSessionImages}) {
    return Future.value(ImportSuccess(_pickResult));
  }

  @override
  Future<ImportResult> captureFromCamera() async {
    return const ImportFailure(UnsupportedSource('camera disabled in test'));
  }

  @override
  Future<ImportResult> pasteFromClipboard() async {
    return const ImportSuccess([]);
  }

  @override
  Future<ImportResult> importRawBytes(List<RawImageBytes> raw) async {
    return const ImportSuccess([]);
  }
}

Future<ProviderContainer> _seedContainer(List<ImportedImage> images) async {
  final repo = _FakeRepo(images);
  final container = ProviderContainer(
    overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
  );
  await container.read(
    imageImportControllerProvider(ImageImportSessionKind.stitch).future,
  );
  if (images.isNotEmpty) {
    await container
        .read(
          imageImportControllerProvider(ImageImportSessionKind.stitch).notifier,
        )
        .pickFromGallery();
  }
  return container;
}

Future<void> _pumpSheetOpener(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showStitchImageSheet(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('showStitchImageSheet — rendering', () {
    testWidgets(
      'renders StitchVerticalImageList inside the sheet (with images)',
      (tester) async {
        final container = await _seedContainer([
          _stub(tag: 'a'),
          _stub(tag: 'b'),
        ]);
        addTearDown(container.dispose);

        await _pumpSheetOpener(tester, container: container);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(StitchVerticalImageList), findsOneWidget);
        // Header "已选图片 (2/20)" confirms the list mounted with the
        // pre-seeded images.
        expect(find.textContaining('已选图片 (2/'), findsOneWidget);
      },
    );

    testWidgets(
      'renders StitchVerticalImageList inside the sheet (empty session)',
      (tester) async {
        final container = await _seedContainer(const []);
        addTearDown(container.dispose);

        await _pumpSheetOpener(tester, container: container);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(StitchVerticalImageList), findsOneWidget);
        // Empty hint message inside the vertical list.
        expect(find.textContaining('尚未导入图片'), findsOneWidget);
      },
    );
  });
}

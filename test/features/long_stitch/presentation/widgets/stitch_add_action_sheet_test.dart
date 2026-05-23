/// Widget tests for [showStitchAddActionSheet].
///
/// PRD: `.trellis/tasks/05-23-mobile-canvas-redesign-for-long-image-stitching`
///
/// The action sheet surfaces three import sources via ListTile rows:
/// gallery / clipboard / camera. Tapping any row pops the sheet first
/// then delegates to the corresponding controller method.
library;

import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_failure.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/widgets/stitch_add_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _validPng({int width = 8, int height = 8}) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodePng(image));
}

/// Repository stub that records which trigger method was called so
/// the test can assert the action sheet wired each ListTile to the
/// right controller method without spinning up real plugin channels.
class _RecordingRepo implements ImageImportRepository {
  _RecordingRepo();

  bool pickFromGalleryCalled = false;
  bool captureFromCameraCalled = false;
  bool pasteFromClipboardCalled = false;

  @override
  Future<ImportResult> pickFromGallery({int limit = kMaxImportSessionImages}) {
    pickFromGalleryCalled = true;
    return Future.value(const ImportSuccess([]));
  }

  @override
  Future<ImportResult> captureFromCamera() async {
    captureFromCameraCalled = true;
    return const ImportSuccess([]);
  }

  @override
  Future<ImportResult> pasteFromClipboard() async {
    pasteFromClipboardCalled = true;
    return const ImportSuccess([]);
  }

  @override
  Future<ImportResult> importRawBytes(List<RawImageBytes> raw) async {
    return const ImportSuccess([]);
  }
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

/// Pump a widget tree that mounts a button which opens the action
/// sheet, then return the `ProviderContainer` used for assertions.
Future<ProviderContainer> _pumpSheetOpener(
  WidgetTester tester, {
  required ImageImportRepository repo,
}) async {
  final container = ProviderContainer(
    overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  // Pre-resolve the stitch import controller so the editor controller
  // has its initial state ready.
  await container.read(
    imageImportControllerProvider(ImageImportSessionKind.stitch).future,
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              return ElevatedButton(
                onPressed: () => showStitchAddActionSheet(context, ref),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  group('showStitchAddActionSheet — rendering', () {
    testWidgets('renders three ListTiles (从相册 / 剪贴板粘贴 / 拍照)', (tester) async {
      await _pumpSheetOpener(tester, repo: _RecordingRepo());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('从相册'), findsOneWidget);
      expect(find.text('剪贴板粘贴'), findsOneWidget);
      expect(find.text('拍照'), findsOneWidget);
      // Icons that pair with each ListTile.
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
      expect(find.byIcon(Icons.paste), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    });
  });

  group('showStitchAddActionSheet — actions', () {
    testWidgets('tapping 从相册 calls addFromGallery on the controller', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      await _pumpSheetOpener(tester, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('从相册'));
      await tester.pumpAndSettle();

      expect(repo.pickFromGalleryCalled, isTrue);
      // Sheet dismissed after tap.
      expect(find.text('从相册'), findsNothing);
    });

    testWidgets('tapping 剪贴板粘贴 calls pasteFromClipboard on the controller', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      await _pumpSheetOpener(tester, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('剪贴板粘贴'));
      await tester.pumpAndSettle();

      expect(repo.pasteFromClipboardCalled, isTrue);
      expect(find.text('剪贴板粘贴'), findsNothing);
    });

    testWidgets('tapping 拍照 calls captureFromCamera on the controller', (
      tester,
    ) async {
      final repo = _RecordingRepo();
      await _pumpSheetOpener(tester, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('拍照'));
      await tester.pumpAndSettle();

      expect(repo.captureFromCameraCalled, isTrue);
      expect(find.text('拍照'), findsNothing);
    });

    testWidgets('imported image flows through the stitch session', (
      tester,
    ) async {
      final repo = _FixedPickRepo([_stub(tag: 'a')]);
      final container = await _pumpSheetOpener(tester, repo: repo);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('从相册'));
      await tester.pumpAndSettle();

      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(1),
      );
    });
  });
}

/// Variant of _RecordingRepo that returns a fixed list of imports
/// from `pickFromGallery` so we can assert the import flow lands in
/// the stitch session.
class _FixedPickRepo implements ImageImportRepository {
  _FixedPickRepo(this._pickResult);

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

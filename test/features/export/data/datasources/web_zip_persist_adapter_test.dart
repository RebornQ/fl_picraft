import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fl_picraft/features/export/data/datasources/web_zip_composer.dart';
import 'package:fl_picraft/features/export/data/datasources/web_zip_persist_adapter.dart';
import 'package:fl_picraft/features/export/domain/entities/export_format.dart';
import 'package:fl_picraft/features/export/domain/entities/save_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures arguments passed to a fake [WebBlobDownloader] so the test
/// can decode the produced ZIP and assert on its structure without
/// touching a real browser anchor.
class _CapturedDownload {
  _CapturedDownload(this.bytes, this.fileName, this.mimeType);

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

void main() {
  group('WebZipPersistAdapter', () {
    test(
      'all-success batch produces a single ZIP download with correct structure',
      () async {
        final downloads = <_CapturedDownload>[];
        // Use the real `package:archive` ZipEncoder from the web
        // composer's _web.dart impl. Tests run on the host VM so the
        // conditional import would resolve to the stub — inject a
        // direct composer that does what the web impl does.
        final adapter = WebZipPersistAdapter(
          downloader: (bytes, fileName, mimeType) async {
            downloads.add(_CapturedDownload(bytes, fileName, mimeType));
            return const SaveSuccess(location: 'Downloads');
          },
          zipComposer: _hostComposeZip,
        );

        final cells = [
          Uint8List.fromList(const [10, 11, 12]),
          Uint8List.fromList(const [20, 21, 22]),
          Uint8List.fromList(const [30, 31, 32]),
        ];

        final result = await adapter.persistMany(
          total: cells.length,
          next: (i) async => i < cells.length ? cells[i] : null,
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveSuccess>());
        final success = result as SaveSuccess;
        expect(success.count, 3);
        expect(success.location, 'Downloads');

        expect(downloads.length, 1, reason: 'Exactly one browser download.');
        final dl = downloads.single;
        expect(dl.fileName, 'flpicraft_20260521_120607.zip');
        expect(dl.mimeType, 'application/zip');

        // Reverse-decode the ZIP and verify the on-disk structure.
        final archive = ZipDecoder().decodeBytes(dl.bytes);
        expect(archive.files, hasLength(3));

        final names = archive.files.map((f) => f.name).toList();
        expect(
          names,
          equals([
            'flpicraft_20260521_120607/flpicraft_20260521_120607_1.png',
            'flpicraft_20260521_120607/flpicraft_20260521_120607_2.png',
            'flpicraft_20260521_120607/flpicraft_20260521_120607_3.png',
          ]),
        );

        // Top-level subdirectory must be exactly the timestamped
        // folder — verifies the rootFolder argument flowed through.
        for (final name in names) {
          expect(name.startsWith('flpicraft_20260521_120607/'), isTrue);
        }

        // Round-tripped bytes are identical to the input cells.
        for (var i = 0; i < cells.length; i++) {
          expect(archive.files[i].content, equals(cells[i]));
        }
      },
    );

    test('jpg format produces `.jpg`-suffixed inner filenames', () async {
      final downloads = <_CapturedDownload>[];
      final adapter = WebZipPersistAdapter(
        downloader: (bytes, fileName, mimeType) async {
          downloads.add(_CapturedDownload(bytes, fileName, mimeType));
          return const SaveSuccess(location: 'Downloads');
        },
        zipComposer: _hostComposeZip,
      );

      await adapter.persistMany(
        total: 2,
        next: (i) async => Uint8List.fromList([i + 1]),
        format: ExportFormat.jpg,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      final archive = ZipDecoder().decodeBytes(downloads.single.bytes);
      final names = archive.files.map((f) => f.name).toList();
      expect(names[0], endsWith('flpicraft_20260521_120607_1.jpg'));
      expect(names[1], endsWith('flpicraft_20260521_120607_2.jpg'));
    });

    test(
      'total = 0 returns SaveFailure and never invokes downloader',
      () async {
        var downloadCalls = 0;
        final adapter = WebZipPersistAdapter(
          downloader: (bytes, fileName, mimeType) async {
            downloadCalls++;
            return const SaveSuccess(location: 'Downloads');
          },
          zipComposer: _hostComposeZip,
        );

        final result = await adapter.persistMany(
          total: 0,
          next: (i) async => null,
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveFailure>());
        expect(downloadCalls, 0);
      },
    );

    test(
      'next throwing during pull stops the batch and returns SaveFailure',
      () async {
        var downloadCalls = 0;
        final adapter = WebZipPersistAdapter(
          downloader: (bytes, fileName, mimeType) async {
            downloadCalls++;
            return const SaveSuccess(location: 'Downloads');
          },
          zipComposer: _hostComposeZip,
        );

        final result = await adapter.persistMany(
          total: 3,
          next: (i) async {
            if (i == 1) throw Exception('Process failed');
            return Uint8List.fromList([i + 1]);
          },
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveFailure>());
        expect((result as SaveFailure).message, contains('Process failed'));
        expect(
          downloadCalls,
          0,
          reason:
              'No partial downloads on web — the batch must abort '
              'before any browser interaction.',
        );
      },
    );

    test('downloader throwing surfaces as SaveFailure (not crash)', () async {
      final adapter = WebZipPersistAdapter(
        downloader: (bytes, fileName, mimeType) async {
          throw Exception('Browser refused download');
        },
        zipComposer: _hostComposeZip,
      );

      final result = await adapter.persistMany(
        total: 2,
        next: (i) async => Uint8List.fromList([i + 1]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      expect(result, isA<SaveFailure>());
      expect(
        (result as SaveFailure).message,
        contains('Browser refused download'),
      );
    });

    test(
      'downloader returning SaveFailure passes through verbatim (no double prefix)',
      () async {
        // Verifies the new typed-SaveResult contract: when the
        // underlying downloader returns a pre-translated SaveFailure
        // (e.g. via WebBlobDownloadDataSource.save catching a JS
        // exception), the adapter must forward the message unchanged
        // instead of wrapping it again — otherwise the snackbar would
        // double-prefix the copy with "保存失败：保存失败：…".
        final adapter = WebZipPersistAdapter(
          downloader: (bytes, fileName, mimeType) async {
            return const SaveFailure('保存失败：浏览器拒绝下载');
          },
          zipComposer: _hostComposeZip,
        );

        final result = await adapter.persistMany(
          total: 2,
          next: (i) async => Uint8List.fromList([i + 1]),
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveFailure>());
        // Single "保存失败：" prefix — the adapter did not re-wrap.
        expect((result as SaveFailure).message, '保存失败：浏览器拒绝下载');
      },
    );

    test(
      'next returning null mid-stream packages whatever was pulled so far',
      () async {
        final downloads = <_CapturedDownload>[];
        final adapter = WebZipPersistAdapter(
          downloader: (bytes, fileName, mimeType) async {
            downloads.add(_CapturedDownload(bytes, fileName, mimeType));
            return const SaveSuccess(location: 'Downloads');
          },
          zipComposer: _hostComposeZip,
        );

        final result = await adapter.persistMany(
          total: 5,
          next: (i) async {
            if (i == 2) return null;
            return Uint8List.fromList([i + 1]);
          },
          format: ExportFormat.png,
          at: DateTime(2026, 5, 21, 12, 6, 7),
        );

        expect(result, isA<SaveSuccess>());
        expect((result as SaveSuccess).count, 2);
        expect(downloads, hasLength(1));
        final archive = ZipDecoder().decodeBytes(downloads.single.bytes);
        expect(archive.files, hasLength(2));
      },
    );

    test('preserves the `at` timestamp across outer + inner names', () async {
      final downloads = <_CapturedDownload>[];
      final adapter = WebZipPersistAdapter(
        downloader: (bytes, fileName, mimeType) async {
          downloads.add(_CapturedDownload(bytes, fileName, mimeType));
          return const SaveSuccess(location: 'Downloads');
        },
        zipComposer: _hostComposeZip,
      );

      await adapter.persistMany(
        total: 2,
        next: (i) async => Uint8List.fromList([i + 1]),
        format: ExportFormat.png,
        at: DateTime(2026, 5, 21, 12, 6, 7),
      );

      // Outer ZIP name, inner folder name, and every inner file name
      // must share the same timestamp — confirms the adapter passes
      // `at` consistently to all `suggested*Name` helpers.
      expect(downloads.single.fileName, 'flpicraft_20260521_120607.zip');
      final archive = ZipDecoder().decodeBytes(downloads.single.bytes);
      for (final f in archive.files) {
        expect(f.name, startsWith('flpicraft_20260521_120607/'));
      }
    });
  });
}

/// Host-VM analogue of `composeZipImpl` in `web_zip_composer_web.dart`.
///
/// Unit tests resolve the `web_zip_composer.dart` conditional import
/// to the stub (which throws), so we inject a direct composer that
/// exercises the **same** `package:archive` API the real web build
/// uses. Keeping this byte-for-byte aligned with `_web.dart` lets the
/// reverse-decode assertions still be meaningful.
Uint8List _hostComposeZip({
  required Iterable<ZipEntry> entries,
  required String rootFolder,
}) {
  final folder = rootFolder.endsWith('/')
      ? rootFolder.substring(0, rootFolder.length - 1)
      : rootFolder;
  final archive = Archive();
  for (final entry in entries) {
    final path = folder.isEmpty ? entry.name : '$folder/${entry.name}';
    archive.addFile(ArchiveFile.bytes(path, entry.bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}

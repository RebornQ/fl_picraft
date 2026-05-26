import 'dart:typed_data';

import 'package:fl_picraft/features/image_import/domain/entities/image_import_result.dart';
import 'package:fl_picraft/features/image_import/domain/entities/image_import_session_kind.dart';
import 'package:fl_picraft/features/image_import/domain/entities/imported_image.dart';
import 'package:fl_picraft/features/image_import/domain/entities/raw_image_bytes.dart';
import 'package:fl_picraft/features/image_import/domain/repositories/image_import_repository.dart';
import 'package:fl_picraft/features/image_import/presentation/providers/image_import_provider.dart';
import 'package:fl_picraft/features/long_stitch/presentation/providers/stitch_editor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';

/// Provider-level tests for `StitchEditorController`'s **compact
/// inline parameter panel auto-expand/collapse** rule
/// (task: `05-27-stitch-auto-expand-params`, PRD R3 / R4 / R5).
///
/// The rule edge-triggers `stitchControlsInlineVisibleProvider`:
///
/// * `empty → non-empty` ⇒ visible = true   (R3)
/// * `non-empty → empty` ⇒ visible = false  (R4)
/// * "mid-session" changes (add/remove while already non-empty,
///   reorder) ⇒ NO flip — the user's `[⚙ 参数]` chip choice in the
///   "has-images" state is preserved (R5)
///
/// These run as plain `test`s, not `testWidgets`, because the
/// assertions target the provider state — no widget tree is involved.
/// See `.trellis/spec/frontend/quality-guidelines.md` → "Pattern:
/// Plain `test` over `testWidgets` for `AsyncNotifier`-only
/// assertions" for the rationale.

class _MockRepo extends Mock implements ImageImportRepository {}

ImportedImage _image(String path) {
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 1, height: 1)),
  );
  return ImportedImage(
    sourcePath: path,
    bytes: bytes,
    width: 1,
    height: 1,
    mimeType: 'image/png',
    importedAt: DateTime.utc(2026, 5, 27),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const <RawImageBytes>[]);
  });

  group('StitchEditorController compact inline-params auto-expand', () {
    late _MockRepo repo;

    setUp(() {
      repo = _MockRepo();
    });

    ProviderContainer makeContainer() {
      return ProviderContainer(
        overrides: [imageImportRepositoryProvider.overrideWithValue(repo)],
      );
    }

    Future<void> primeBoth(ProviderContainer container) async {
      // Build the editor controller so `ref.listen` is wired up
      // before any import runs.
      container.read(stitchEditorControllerProvider);
      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch).future,
      );
    }

    /// Read the visibility flag while *also* poking the controller so
    /// the derived `importedImagesProvider` (a lazy `Provider.family`)
    /// re-evaluates and fires its listener. Without this poke, a
    /// direct `container.read(stitchControlsInlineVisibleProvider)`
    /// can miss the most recent edge because no one has asked the
    /// derived provider for its new value yet — Riverpod only fires
    /// listeners during evaluation of dirty derived providers.
    bool readVisible(ProviderContainer container) {
      // Touching the controller triggers the dirty re-eval chain.
      container.read(stitchEditorControllerProvider);
      return container.read(stitchControlsInlineVisibleProvider);
    }

    test(
      'initial state: visible flag defaults to false (panel collapsed)',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        expect(
          readVisible(container),
          isFalse,
          reason:
              'Per PRD AC: editor opens with the inline parameter panel '
              'collapsed when the image list is empty.',
        );
      },
    );

    test(
      'empty → non-empty first import: visible flips to true (R3)',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('a')]));
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        expect(readVisible(container), isFalse);

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();

        expect(
          readVisible(container),
          isTrue,
          reason:
              'Empty → non-empty edge must auto-expand the inline params '
              'panel so the compact user sees the controls immediately.',
        );
      },
    );

    test(
      'non-empty → empty via clear(): visible flips to false (R4)',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('a'), _image('b')]));
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        // Bring the editor to non-empty + visible=true via R3.
        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();
        expect(readVisible(container), isTrue);

        // Clear → list goes 2 → 0 (non-empty → empty edge).
        container.read(stitchEditorControllerProvider.notifier).clear();

        expect(
          readVisible(container),
          isFalse,
          reason:
              'Non-empty → empty edge (clear / remove-all) must auto-'
              'collapse the panel to match the empty-canvas state.',
        );
      },
    );

    test(
      'non-empty → empty via remove-all one-by-one: visible flips to false',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('a'), _image('b')]));
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();
        expect(readVisible(container), isTrue);

        // Remove non-last first → list 2 → 1 (still non-empty);
        // visible must NOT flip (mid-session change).
        container.read(stitchEditorControllerProvider.notifier).removeImage(0);
        expect(
          readVisible(container),
          isTrue,
          reason:
              'Removing while still non-empty is a mid-session change — '
              'must not collapse the panel.',
        );

        // Remove the last image → list 1 → 0 (true edge).
        container.read(stitchEditorControllerProvider.notifier).removeImage(0);
        expect(
          readVisible(container),
          isFalse,
          reason:
              'Crossing into empty via remove-all must auto-collapse the '
              'panel symmetrically with clear().',
        );
      },
    );

    test('user manually collapses panel mid-session, then adds another image: '
        'visible stays false (R5)', () async {
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('a')]));
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeBoth(container);

      // First import → visible flips to true (R3).
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      expect(readVisible(container), isTrue);

      // User explicitly collapses via the [⚙ 参数] chip.
      container.read(stitchControlsInlineVisibleProvider.notifier).state =
          false;
      expect(readVisible(container), isFalse);

      // Add another image → list 1 → 2 (already non-empty); the
      // listener must NOT clobber the user's explicit collapse.
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('b')]));
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();

      expect(
        readVisible(container),
        isFalse,
        reason:
            'Mid-session add must NOT auto-expand — it would override '
            "the user's explicit collapse choice and feel intrusive "
            '(PRD R5).',
      );
    });

    test(
      'clear → import again: visible auto-expands a second time (B-mode)',
      () async {
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('a')]));
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();
        expect(readVisible(container), isTrue);

        // Clear → empty + visible=false.
        container.read(stitchEditorControllerProvider.notifier).clear();
        expect(readVisible(container), isFalse);

        // Pick again → empty → non-empty edge fires again.
        when(
          () => repo.pickFromGallery(limit: any(named: 'limit')),
        ).thenAnswer((_) async => ImportSuccess([_image('c')]));
        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();

        expect(
          readVisible(container),
          isTrue,
          reason:
              'Per the ADR for Approach B: every empty→non-empty edge '
              'auto-expands, including post-clear re-imports. This is '
              'intentional, not a regression.',
        );
      },
    );

    test(
      'reorder while non-empty: visible unchanged (mid-session no-op)',
      () async {
        when(() => repo.pickFromGallery(limit: any(named: 'limit'))).thenAnswer(
          (_) async => ImportSuccess([_image('a'), _image('b'), _image('c')]),
        );
        final container = makeContainer();
        addTearDown(container.dispose);
        await primeBoth(container);

        await container
            .read(
              imageImportControllerProvider(
                ImageImportSessionKind.stitch,
              ).notifier,
            )
            .pickFromGallery();
        // Force the lazy import→controller listener to fire so
        // `state.images` is in sync before we touch the editor —
        // otherwise `StitchEditorController.reorder` early-returns
        // on the stale empty list and the listener fires *after* our
        // manual collapse, clobbering it via R3.
        expect(readVisible(container), isTrue);

        // User collapses, then reorders — visible must stay false.
        container.read(stitchControlsInlineVisibleProvider.notifier).state =
            false;
        container.read(stitchEditorControllerProvider.notifier).reorder(0, 2);

        expect(
          readVisible(container),
          isFalse,
          reason: 'Reorder is mid-session — must not override user collapse.',
        );
      },
    );

    test('initial mount with pre-existing image list: visible NOT clobbered '
        'on listener first-fire', () async {
      // Pre-populate the import session BEFORE building the stitch
      // editor controller. Mirrors the parallel test in
      // `stitch_editor_provider_test.dart` for the subtitle-reset
      // rule — the same `stateWasEmpty` guard underpins both rules.
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('seed')]));
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(
        imageImportControllerProvider(ImageImportSessionKind.stitch).future,
      );
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();
      expect(
        container.read(importedImagesProvider(ImageImportSessionKind.stitch)),
        hasLength(1),
      );

      // Now build the stitch editor controller — `build()` sees
      // initial = [seed]. The listener wires up but does NOT fire
      // yet. visible should still be its default (false).
      container.read(stitchEditorControllerProvider);
      expect(readVisible(container), isFalse);

      // Trigger a subsequent import. Listener fires for the first
      // time with prev=null + next=[seed, more]. Because
      // `stateWasEmpty` snapshots the controller's own image-list
      // (already populated from `initial`), the auto-expand rule
      // must NOT fire — this is a mid-session add from the editor's
      // perspective.
      when(
        () => repo.pickFromGallery(limit: any(named: 'limit')),
      ).thenAnswer((_) async => ImportSuccess([_image('more')]));
      await container
          .read(
            imageImportControllerProvider(
              ImageImportSessionKind.stitch,
            ).notifier,
          )
          .pickFromGallery();

      expect(
        readVisible(container),
        isFalse,
        reason:
            'Mounting onto a pre-existing non-empty session must not '
            'auto-expand on the listener first-fire (would override the '
            "user's previous explicit choice across StatefulShellRoute "
            'tab switches).',
      );
    });
  });
}

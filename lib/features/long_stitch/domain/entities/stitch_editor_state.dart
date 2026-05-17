import '../../../image_import/domain/entities/imported_image.dart';
import 'stitch_border.dart';
import 'stitch_mode.dart';

/// Default subtitle band height expressed as a percentage of the first
/// image's scaled height (post width-normalization). ≈ 12% reproduces
/// the perceived band thickness of the legacy absolute-px default
/// (120 px on a typical ~1000 px tall first image).
const double kDefaultSubtitleBandHeightPercent = 0.12;

/// Hard limits surfaced to the UI layer for slider bounds. Centralizing
/// keeps the parameter sheet and the validation logic in agreement.
const double kMaxStitchSpacing = 50;
const double kMaxStitchBorderWidth = 10;
const double kMaxStitchCornerRadius = 48;

/// Slider bounds for the subtitle band height percent. The lower bound
/// keeps the band tall enough to read at typical viewer sizes; the
/// upper bound caps the band at half of the first image's height so
/// the "first frame fully visible" intent is preserved.
const double kMinSubtitleBandHeightPercent = 0.05;
const double kMaxSubtitleBandHeightPercent = 0.50;

/// Snapshot of every parameter the long-stitch editor exposes.
///
/// Immutable; mutate via [copyWith]. The class intentionally carries
/// fields owned by the sibling movie-subtitle subtask so that both
/// modes can share a single notifier without one task locking the
/// other out.
class StitchEditorState {
  const StitchEditorState({
    required this.images,
    required this.mode,
    required this.spacing,
    required this.border,
    required this.cornerRadius,
    required this.subtitleOnlyMode,
    required this.subtitleBandHeightPercent,
    required this.autoTrimBlackBars,
  });

  /// Default initial state. No images, vertical mode, no decorations.
  factory StitchEditorState.initial() => const StitchEditorState(
    images: [],
    mode: StitchMode.vertical,
    spacing: 0,
    border: StitchBorder.none,
    cornerRadius: 0,
    subtitleOnlyMode: false,
    subtitleBandHeightPercent: kDefaultSubtitleBandHeightPercent,
    autoTrimBlackBars: false,
  );

  /// Image list ordered top-to-bottom (vertical) or left-to-right
  /// (horizontal).
  final List<ImportedImage> images;

  /// Active layout mode.
  final StitchMode mode;

  /// Pixels of gap between adjacent images (post-scaling, in canvas
  /// coordinates). 0–[kMaxStitchSpacing].
  final double spacing;

  /// Outer border around the assembled canvas.
  final StitchBorder border;

  /// Outer corner radius applied to the assembled canvas.
  /// 0–[kMaxStitchCornerRadius].
  final double cornerRadius;

  /// Reserved for the movie-subtitle subtask. When `false` (default)
  /// the field has no effect.
  final bool subtitleOnlyMode;

  /// Subtitle band height as a fraction of the first image's scaled
  /// height (`[kMinSubtitleBandHeightPercent, kMaxSubtitleBandHeightPercent]`).
  /// Inert while [subtitleOnlyMode] is `false`. Stored as a percent
  /// (rather than absolute pixels) so the band scales naturally with
  /// different source resolutions — see PRD §B2.
  final double subtitleBandHeightPercent;

  /// When `true` and the renderer is on the movie-subtitle path, each
  /// source image is scanned for top / bottom letterbox bars before
  /// the band crop is applied. Inert outside subtitle mode.
  final bool autoTrimBlackBars;

  bool get hasImages => images.isNotEmpty;
  int get imageCount => images.length;

  StitchEditorState copyWith({
    List<ImportedImage>? images,
    StitchMode? mode,
    double? spacing,
    StitchBorder? border,
    double? cornerRadius,
    bool? subtitleOnlyMode,
    double? subtitleBandHeightPercent,
    bool? autoTrimBlackBars,
  }) {
    return StitchEditorState(
      images: images ?? this.images,
      mode: mode ?? this.mode,
      spacing: spacing ?? this.spacing,
      border: border ?? this.border,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      subtitleOnlyMode: subtitleOnlyMode ?? this.subtitleOnlyMode,
      subtitleBandHeightPercent:
          subtitleBandHeightPercent ?? this.subtitleBandHeightPercent,
      autoTrimBlackBars: autoTrimBlackBars ?? this.autoTrimBlackBars,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StitchEditorState &&
        other.mode == mode &&
        other.spacing == spacing &&
        other.border == border &&
        other.cornerRadius == cornerRadius &&
        other.subtitleOnlyMode == subtitleOnlyMode &&
        other.subtitleBandHeightPercent == subtitleBandHeightPercent &&
        other.autoTrimBlackBars == autoTrimBlackBars &&
        _imagesEqual(other.images, images);
  }

  @override
  int get hashCode => Object.hash(
    mode,
    spacing,
    border,
    cornerRadius,
    subtitleOnlyMode,
    subtitleBandHeightPercent,
    autoTrimBlackBars,
    Object.hashAll(images),
  );
}

bool _imagesEqual(List<ImportedImage> a, List<ImportedImage> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

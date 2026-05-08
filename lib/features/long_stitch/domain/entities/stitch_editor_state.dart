import '../../../image_import/domain/entities/imported_image.dart';
import 'stitch_border.dart';
import 'stitch_mode.dart';

/// Default subtitle band height (px) used by the upcoming movie-subtitle
/// mode. Defined here so the constant lives next to the field that
/// references it.
const double kDefaultSubtitleBandHeight = 120;

/// Hard limits surfaced to the UI layer for slider bounds. Centralizing
/// keeps the parameter sheet and the validation logic in agreement.
const double kMaxStitchSpacing = 50;
const double kMaxStitchBorderWidth = 10;
const double kMaxStitchCornerRadius = 48;
const double kMinSubtitleBandHeight = 50;
const double kMaxSubtitleBandHeight = 500;

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
    required this.subtitleBandHeight,
  });

  /// Default initial state. No images, vertical mode, no decorations.
  factory StitchEditorState.initial() => const StitchEditorState(
    images: [],
    mode: StitchMode.vertical,
    spacing: 0,
    border: StitchBorder.none,
    cornerRadius: 0,
    subtitleOnlyMode: false,
    subtitleBandHeight: kDefaultSubtitleBandHeight,
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

  /// Reserved for the movie-subtitle subtask. Inert while
  /// [subtitleOnlyMode] is `false`.
  final double subtitleBandHeight;

  bool get hasImages => images.isNotEmpty;
  int get imageCount => images.length;

  StitchEditorState copyWith({
    List<ImportedImage>? images,
    StitchMode? mode,
    double? spacing,
    StitchBorder? border,
    double? cornerRadius,
    bool? subtitleOnlyMode,
    double? subtitleBandHeight,
  }) {
    return StitchEditorState(
      images: images ?? this.images,
      mode: mode ?? this.mode,
      spacing: spacing ?? this.spacing,
      border: border ?? this.border,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      subtitleOnlyMode: subtitleOnlyMode ?? this.subtitleOnlyMode,
      subtitleBandHeight: subtitleBandHeight ?? this.subtitleBandHeight,
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
        other.subtitleBandHeight == subtitleBandHeight &&
        _imagesEqual(other.images, images);
  }

  @override
  int get hashCode => Object.hash(
    mode,
    spacing,
    border,
    cornerRadius,
    subtitleOnlyMode,
    subtitleBandHeight,
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

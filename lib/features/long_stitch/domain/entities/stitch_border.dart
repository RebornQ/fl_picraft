import 'dart:ui' show Color;

/// Outer-border configuration for a stitched image.
///
/// Width is in logical pixels (matches the slider scale 0–10). When
/// [width] is `0` the border is treated as absent regardless of [color].
class StitchBorder {
  const StitchBorder({this.width = 0.0, this.color = const Color(0xFF000000)});

  /// Default = no border. Sharing a single `const` instance lets the
  /// editor state stay value-equal across rebuilds.
  static const StitchBorder none = StitchBorder();

  final double width;
  final Color color;

  bool get isVisible => width > 0;

  StitchBorder copyWith({double? width, Color? color}) {
    return StitchBorder(width: width ?? this.width, color: color ?? this.color);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StitchBorder &&
        other.width == width &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(width, color);

  @override
  String toString() => 'StitchBorder(width: $width, color: $color)';
}

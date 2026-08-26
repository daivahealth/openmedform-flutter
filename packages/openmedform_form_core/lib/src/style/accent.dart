/// Accent-colour maths shared by every surface that draws a callout.
///
/// Ported from `packages/form-core/src/style/accent.ts` at form-core
/// 4ce8e4e82a7e1115212a73feb91c482a78cd0757.
///
/// A definition carries an accent as a hex string on `options.omf.accentColor`.
/// The callout washes its background with a tint of that accent, and a result
/// banner appearing in a visibly different shade on mobile than on the web is
/// exactly the cross-renderer drift the parity contract forbids — so the wash
/// lives here, next to the parsing, rather than being re-derived per renderer.
///
/// Flutter has `Color` and `withValues`, so the renderer does not need the CSS
/// strings [accentTint] and [accentTintOpaque] produce. They are ported anyway
/// because they pin the numbers the renderer *does* need — the 8% default and
/// the rounding of the opaque mix — against the TypeScript that print and the
/// web renderers use.
library;

/// `#rgb` or `#rrggbb`, with or without the hash.
final RegExp _hex =
    RegExp(r'^#?(?:([0-9a-f]{3})|([0-9a-f]{6}))$', caseSensitive: false);

/// Read a hex accent as `[r, g, b]`, or null for a colour the maths cannot
/// read.
///
/// Deliberately strict, and deliberately null rather than a guess: a definition
/// may legitimately carry a CSS variable or a named colour, and the caller then
/// keeps the accent for borders and text and simply goes without the tint.
List<int>? parseHexColor(String? color) {
  if (color == null) return null;
  final match = _hex.firstMatch(color.trim());
  if (match == null) return null;

  final short = match.group(1);
  final hex = short != null
      ? short.split('').map((char) => '$char$char').join()
      : match.group(2)!;

  return <int>[
    int.parse(hex.substring(0, 2), radix: 16),
    int.parse(hex.substring(2, 4), radix: 16),
    int.parse(hex.substring(4, 6), radix: 16),
  ];
}

/// The default callout wash: 8% of the accent over whatever is behind it.
const double accentTintAlpha = 0.08;

/// The accent washed for a callout background, as CSS `rgba(...)`.
String? accentTint(String? color, [double alpha = accentTintAlpha]) {
  final rgb = parseHexColor(color);
  if (rgb == null) return null;
  return 'rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${_num(alpha)})';
}

/// The same wash pre-mixed against white, as CSS `rgb(...)`.
///
/// Print pipelines routinely drop alpha compositing, and a callout whose
/// background vanishes takes its meaning with it.
String? accentTintOpaque(String? color, [double alpha = accentTintAlpha]) {
  final rgb = parseHexColor(color);
  if (rgb == null) return null;
  int mix(int channel) => (channel * alpha + 255 * (1 - alpha)).round();
  return 'rgb(${mix(rgb[0])}, ${mix(rgb[1])}, ${mix(rgb[2])})';
}

/// Format a double the way JavaScript would interpolate it — `0.08`, not
/// `0.080000000000000002`, and `0.2` rather than `0.2000000000000000`.
String _num(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

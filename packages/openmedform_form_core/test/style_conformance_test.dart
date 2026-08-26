/// Replays the `style` conformance fixtures against the Dart port.
///
/// The renderer paints with Flutter's own [Color] rather than the CSS strings
/// these functions return, so what is being pinned here is the arithmetic: what
/// parses, what is refused, and the 8% default alpha. A result banner rendering
/// in a visibly different shade on mobile than on the web is exactly the drift
/// the parity contract exists to catch.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

void main() {
  runConformanceModule('style', {
    'parseHexColor': (args) => parseHexColor(args[0] as String?),
    'accentTint': (args) => accentTint(
          args[0] as String?,
          args.length > 1 ? (args[1]! as num).toDouble() : accentTintAlpha,
        ),
    'accentTintOpaque': (args) => accentTintOpaque(
          args[0] as String?,
          args.length > 1 ? (args[1]! as num).toDouble() : accentTintAlpha,
        ),
  });

  group('style beyond the fixtures', () {
    test('the callout alpha is the one both web renderers use', () {
      // Named so a change to it is a deliberate edit rather than a typo that
      // quietly recolours every result banner on mobile only.
      expect(accentTintAlpha, 0.08);
    });
  });
}

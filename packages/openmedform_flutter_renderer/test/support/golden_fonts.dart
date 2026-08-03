/// Loads a real font so goldens show text rather than placeholder blocks.
///
/// `flutter test` renders with a placeholder font by default, which means a
/// golden guards boxes and colours but not a single word. Roboto is vendored
/// under `test/fonts` — it is Apache-2.0, the same licence as this repository,
/// and vendoring it keeps goldens reproducible on a machine whose Flutter cache
/// differs from the one that generated them.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

/// Register the bundled font. Safe to call from every golden test.
Future<void> loadGoldenFonts() async {
  if (_loaded) return;
  _loaded = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  // All three weights go into one family: Flutter reads the weight from each
  // font's own metadata. Registering only Regular leaves every 600-weight
  // label — which is most of them — falling back to the placeholder font.
  const weights = <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ];

  final loader = FontLoader('Roboto');
  for (final name in weights) {
    final file = File('test/fonts/$name');
    if (!file.existsSync()) {
      fail('Missing test/fonts/$name — goldens need real fonts.');
    }
    loader.addFont(
      Future<ByteData>.value(file.readAsBytesSync().buffer.asByteData()),
    );
  }

  await loader.load();
}

@Tags(<String>['live'])
/// The demo's fill screen, driven against a running API.
///
/// This is the end-to-end path the renderer exists for: a real form definition
/// fetched from the server, rendered by the real renderer, edited, autosaved,
/// completed, and replayed against the pinned version. Excluded from CI, which
/// has no API to talk to.
///
/// ```bash
/// OMF_API_URL=http://localhost:3100 \
/// OMF_EMAIL=admin@openmedform.local \
/// OMF_PASSWORD=admin123 \
/// OMF_FORM_SLUG=<a published slug> \
///   flutter test --tags live
/// ```
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';
import 'package:openmedform_demo/screens/fill_screen.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

String? _env(String key) {
  final value = Platform.environment[key];
  return value == null || value.isEmpty ? null : value;
}

void main() {
  final baseUrl = _env('OMF_API_URL') ?? 'http://localhost:3100';
  final email = _env('OMF_EMAIL');
  final password = _env('OMF_PASSWORD');
  final slug = _env('OMF_FORM_SLUG');

  if (email == null || password == null || slug == null) {
    // `testWidgets` takes a bool for skip, so the reason goes on a plain test.
    test(
      'live fill',
      () {},
      skip: 'set OMF_EMAIL, OMF_PASSWORD and OMF_FORM_SLUG',
    );
    return;
  }

  setUp(() {
    // flutter_test installs an HttpOverrides that fails every request, to stop
    // tests reaching the network by accident. This one means to.
    HttpOverrides.global = null;
  });

  testWidgets(
    'fetches, renders, autosaves and completes a real form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final client = OmfApiClient(baseUrl: baseUrl);
      addTearDown(client.close);

      await client.auth.login(email: email, password: password);
      final form = await client.forms.bySlug(slug);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[OmfTheme.defaults()],
          ),
          home: FillScreen(client: client, form: form),
        ),
      );

      // The screen creates the draft on open; give the round trip time to land.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(OmfFormRenderer).evaluate().isNotEmpty) break;
      }

      expect(
        find.byType(OmfFormRenderer),
        findsOneWidget,
        reason: 'the draft should have been created and the form rendered',
      );

      // A real published form must produce real controls — not a screen of
      // unsupported-element placeholders.
      expect(find.byType(UnknownElementWidget), findsNothing);
      expect(
        tester.widgetList(find.byType(TextField)).isNotEmpty ||
            tester.widgetList(find.byType(Checkbox)).isNotEmpty ||
            tester.widgetList(find.byType(Radio<Object?>)).isNotEmpty,
        isTrue,
        reason: 'the form should render at least one interactive control',
      );

      // Type into the first text field and let the debounce fire.
      final fields = find.byType(TextField);
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, 'entered by the live demo test');
        await tester.pump();

        expect(find.text('Unsaved changes'), findsOneWidget);

        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Saved').evaluate().isNotEmpty) break;
        }
        expect(
          find.text('Saved'),
          findsOneWidget,
          reason: 'the debounced autosave should have reached the server',
        );
      }

      // Complete: flushes any pending write, then asks the server to validate
      // and score.
      await tester.tap(find.text('Complete'));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Submitted').evaluate().isNotEmpty) break;
      }

      expect(
        find.text('Submitted'),
        findsOneWidget,
        reason: 'completing should land on the read-only replay screen',
      );
      expect(find.textContaining('Status: completed'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

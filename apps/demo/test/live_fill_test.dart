@Tags(<String>['live'])
/// Renderer, client and server together, against a running API.
///
/// Excluded from CI, which has no API to talk to.
///
/// ```bash
/// OMF_API_URL=http://localhost:3100 \
/// OMF_EMAIL=admin@openmedform.local \
/// OMF_PASSWORD=admin123 \
/// OMF_FORM_SLUG=<a published slug> \
///   flutter test --tags live
/// ```
///
/// ## Why this drives the client rather than the screen
///
/// A `testWidgets` body runs inside a fake-async zone. Real socket work
/// *started from inside that zone* — a widget calling the API from `initState`,
/// say — never completes, because the microtasks that would finish it only run
/// when the fake clock advances, and `runAsync` does not flush them. Pointing
/// this test at `FillScreen` hangs until the timeout for exactly that reason.
///
/// So every request here is issued from [WidgetTester.runAsync], and the widget
/// under test is the renderer itself. That still exercises the whole path —
/// real definition off the server, real renderer, real payload back through the
/// real client — and `FillScreen`'s own wiring of the two is covered by the
/// client's `submission_session` tests.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';
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

  // flutter_test fails every request by default, to stop tests reaching the
  // network by accident. This one means to.
  setUp(() => HttpOverrides.global = null);

  testWidgets(
    'renders a real published form and round-trips a submission',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final client = OmfApiClient(baseUrl: baseUrl);
      addTearDown(client.close);

      late final OmfForm form;
      late final OmfSubmission draft;

      await tester.runAsync(() async {
        await client.auth.login(email: email, password: password);
        form = await client.forms.bySlug(slug);
        // The server pins the version here; the client never chooses one.
        draft = await client.submissions.create(form.id);
      });

      expect(draft.formVersionId, isNotNull);

      // --- the real form, through the real renderer ------------------------

      Map<String, dynamic> current = draft.data;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[OmfTheme.defaults()],
          ),
          home: Scaffold(
            body: OmfFormRenderer(
              definition: form.definition,
              initialData: draft.data,
              onChange: (data) => current = data,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A published clinical form must produce real controls, not a screen of
      // unsupported-element placeholders.
      expect(
        find.byType(UnknownElementWidget),
        findsNothing,
        reason:
            'every element of a shipped form should be claimed by a control',
      );

      final fields = find.byType(TextField);
      final interactive =
          fields.evaluate().length +
          find.byType(Checkbox).evaluate().length +
          find.byType(Radio<Object?>).evaluate().length;
      expect(
        interactive,
        greaterThan(0),
        reason: 'the form should render interactive controls',
      );

      printOnFailure(
        'rendered $interactive interactive controls for '
        '"${form.name}"',
      );

      // --- edit, save, complete --------------------------------------------

      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, 'entered by the live test');
        await tester.pump();
        expect(current, isNotEmpty, reason: 'the edit should reach the store');
      }

      late final OmfSubmission completed;
      await tester.runAsync(() async {
        await client.submissions.save(draft.id, current);
        completed = await client.submissions.complete(draft.id);
      });

      // Scores are recomputed server-side; a client total is never accepted.
      expect(completed.status, OmfSubmissionStatus.completed);

      // --- replay, read-only, against the pinned version -------------------

      late final OmfSubmission reloaded;
      await tester.runAsync(
        () async => reloaded = await client.submissions.get(draft.id),
      );

      expect(
        reloaded.formVersion,
        isNotNull,
        reason: 'replay renders against the pinned version',
      );
      expect(reloaded.formVersionId, draft.formVersionId);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[OmfTheme.defaults()],
          ),
          home: Scaffold(
            body: OmfFormRenderer(
              definition: reloaded.formVersion!,
              initialData: reloaded.data,
              readOnly: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final replayed = tester.widgetList<TextField>(find.byType(TextField));
      expect(replayed, isNotEmpty);
      for (final field in replayed) {
        expect(field.enabled, isFalse, reason: 'replay must be read-only');
      }

      // Leave the database as we found it.
      await tester.runAsync(() => client.submissions.voidSubmission(draft.id));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

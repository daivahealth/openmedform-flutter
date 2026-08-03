@Tags(<String>['live'])

/// The full submission lifecycle against a running API.
///
/// Excluded from CI, which has no API to talk to. Run it against a local stack:
///
/// ```bash
/// OMF_API_URL=http://localhost:3100 \
/// OMF_EMAIL=admin@openmedform.local \
/// OMF_PASSWORD=admin123 \
/// OMF_FORM_SLUG=<a published slug> \
///   dart test --tags live
/// ```
///
/// It creates a submission and voids it again afterwards, so a run leaves the
/// database as it found it apart from the audit trail.
library;

import 'dart:io';

import 'package:openmedform_api_client/openmedform_api_client.dart';
import 'package:test/test.dart';

String? _env(String key) {
  final value = Platform.environment[key];
  return value == null || value.isEmpty ? null : value;
}

/// A value no enum admits and no numeric field accepts.
const String _notAValidValue = '__not_a_valid_value__';

/// The first top-level property a bad string is guaranteed to fail against.
String? _firstBreakableField(Map<String, dynamic> dataSchema) {
  final properties = dataSchema['properties'];
  if (properties is! Map) return null;

  for (final entry in properties.entries) {
    final schema = entry.value;
    if (schema is! Map) continue;
    final isEnum = schema['enum'] is List;
    final isNumeric = schema['type'] == 'integer' || schema['type'] == 'number';
    if (isEnum || isNumeric) return '${entry.key}';
  }
  return null;
}

void main() {
  final baseUrl = _env('OMF_API_URL') ?? 'http://localhost:3100';
  final email = _env('OMF_EMAIL');
  final password = _env('OMF_PASSWORD');
  final slug = _env('OMF_FORM_SLUG');

  if (email == null || password == null || slug == null) {
    test('live lifecycle', () {},
        skip: 'set OMF_EMAIL, OMF_PASSWORD and OMF_FORM_SLUG');
    return;
  }

  late OmfApiClient client;

  setUpAll(() => client = OmfApiClient(baseUrl: baseUrl));
  tearDownAll(() => client.close());

  test('signs in, fills, completes and replays', () async {
    final session = await client.auth.login(email: email, password: password);
    expect(session.accessToken, isNotEmpty);

    final form = await client.forms.bySlug(slug);
    expect(form.definition.dataSchema, isNotEmpty);
    expect(form.definition.layout['type'], isNotNull);

    // The server pins the version here; the client never chooses one.
    final draft = await client.submissions.create(form.id);
    expect(draft.status, OmfSubmissionStatus.inProgress);
    expect(draft.formVersionId, isNotNull);

    late final OmfSubmission completed;
    try {
      final serialized = OmfSubmissionSession(
        client: client,
        submissionId: draft.id,
        debounce: const Duration(milliseconds: 1),
      );

      // Whether valid data completes is form-specific — a form with no
      // `required` fields accepts an empty payload — so drive the path that is
      // always available: deliberately break the first enum or numeric field
      // and prove the rejection comes back as pointers we can map to fields.
      final bad = _firstBreakableField(form.definition.dataSchema);
      if (bad != null) {
        serialized.onChanged(<String, dynamic>{bad: _notAValidValue});
        await expectLater(
          serialized.complete(),
          throwsA(
            isA<OmfValidationException>().having(
              (error) => error.errors.map((e) => e.instancePath),
              'flagged paths',
              contains('/$bad'),
            ),
          ),
          reason: 'the server is authoritative, and its verdict must arrive as '
              'JSON Pointers a client can map onto fields',
        );
      }

      // Now clear the bad value and complete for real.
      serialized.onChanged(<String, dynamic>{});
      completed = await serialized.complete();

      await serialized.dispose();

      // Whatever the verdict, the draft must still be readable and pinned to a
      // version, which is what replay renders against.
      final reloaded = await client.submissions.get(draft.id);
      expect(reloaded.id, draft.id);
      expect(reloaded.formVersionId, draft.formVersionId);
      expect(
        reloaded.formVersion,
        isNotNull,
        reason: 'replay needs the pinned version, not the form\'s current one',
      );

      // Scores are recomputed server-side; a client total is never accepted.
      expect(completed.status, OmfSubmissionStatus.completed);
      expect(completed.scores, isA<Map<String, dynamic>>());
    } finally {
      // Leave the database as we found it.
      await client.submissions.voidSubmission(draft.id);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

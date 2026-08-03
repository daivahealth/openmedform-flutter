/// The API client, against a mocked transport.
///
/// These assert the constraints that are bugs if missed — the exact request
/// bodies, the flush-before-complete ordering, and how a 400 from `/complete`
/// is surfaced. See docs/ARCHITECTURE.md section 11.
library;

import 'package:dio/dio.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';
import 'package:test/test.dart';

/// Records requests and replays canned responses.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);

  final ResponseBody Function(RequestOptions options, String? body) handler;
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<String?> bodies = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data;
    bodies.add(data?.toString());
    return handler(options, bodies.last);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      _encode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

String _encode(Object body) {
  // Small hand-rolled encoder: the payloads here are simple and this keeps the
  // test free of a dependency on the client's own serialisation.
  if (body is String) return body;
  return const JsonLikeEncoder().convert(body);
}

/// Minimal JSON encoding for the fixtures below.
class JsonLikeEncoder {
  const JsonLikeEncoder();

  String convert(Object? value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return '$value';
    if (value is String) return '"${value.replaceAll('"', r'\"')}"';
    if (value is List) return '[${value.map(convert).join(',')}]';
    if (value is Map) {
      final entries = value.entries
          .map((entry) => '"${entry.key}":${convert(entry.value)}')
          .join(',');
      return '{$entries}';
    }
    throw ArgumentError.value(value, 'value', 'unsupported');
  }
}

({OmfApiClient client, _MockAdapter adapter}) buildClient(
  ResponseBody Function(RequestOptions options, String? body) handler,
) {
  final adapter = _MockAdapter(handler);
  final dio = Dio()..httpClientAdapter = adapter;
  final client = OmfApiClient(baseUrl: 'http://localhost:3100', dio: dio);
  return (client: client, adapter: adapter);
}

void main() {
  group('auth', () {
    test('login stores the bearer token and sends it onward', () async {
      final setup = buildClient((options, body) {
        if (options.path.endsWith('/auth/login')) {
          return _json(<String, dynamic>{
            'accessToken': 'tok-123',
            'user': <String, dynamic>{
              'id': 'u1',
              'email': 'nurse@example.org',
              'tenantId': 't1',
            },
          });
        }
        return _json(
            <String, dynamic>{'id': 'u1', 'email': 'nurse@example.org'});
      });

      final session = await setup.client.auth.login(
        email: 'nurse@example.org',
        password: 'secret',
      );

      expect(session.accessToken, 'tok-123');
      expect(session.user.tenantId, 't1');

      await setup.client.auth.me();

      // Tenancy travels inside the JWT — the only auth header is the bearer.
      final headers = setup.adapter.requests.last.headers;
      expect(headers['Authorization'], 'Bearer tok-123');
      expect(headers.keys.where((k) => k.toLowerCase().contains('tenant')),
          isEmpty);
    });

    test('a 401 clears the token and notifies the host', () async {
      var notified = false;
      final adapter = _MockAdapter(
        (options, body) =>
            _json(<String, dynamic>{'message': 'nope'}, status: 401),
      );
      final client = OmfApiClient(
        baseUrl: 'http://localhost:3100',
        dio: Dio()..httpClientAdapter = adapter,
        onUnauthorized: () => notified = true,
      )..tokens.set('stale');

      await expectLater(
        client.submissions.get('s1'),
        throwsA(isA<OmfApiException>()),
      );

      expect(client.tokens.hasToken, isFalse);
      expect(notified, isTrue);
    });
  });

  group('forms', () {
    test('bySlug renders the current version and survives null columns',
        () async {
      final setup = buildClient(
        (options, body) => _json(<String, dynamic>{
          'id': 'f1',
          'slug': 'rrt-sbar',
          'name': 'RRT SBAR',
          'currentVersion': <String, dynamic>{
            'dataSchema': <String, dynamic>{'type': 'object'},
            // uiSchema, printSchema and translations are nullable columns.
            'uiSchema': null,
            'translations': null,
          },
        }),
      );

      final form = await setup.client.forms.bySlug('rrt-sbar');

      expect(form.id, 'f1');
      // A form with no UI schema must render as an empty form, not crash.
      expect(form.definition.layout['type'], 'VerticalLayout');
      expect(form.definition.formCode, 'rrt-sbar');
    });
  });

  group('submissions', () {
    test('create sends only the whitelisted keys', () async {
      final setup = buildClient(
        (options, body) => _json(<String, dynamic>{
          'id': 's1',
          'status': 'IN_PROGRESS',
          'data': <String, dynamic>{},
        }),
      );

      await setup.client.submissions.create(
        'f1',
        patientMrn: 'MRN-1',
        patientContext: const OmfPatientContext(patientName: 'A. Patient'),
      );

      final sent = setup.adapter.bodies.single!;
      expect(sent, contains('patientMrn'));
      expect(sent, contains('patientContext'));
      // The API's global pipe rejects unknown properties outright, so an extra
      // key here is a 400 rather than something the server ignores.
      expect(sent, isNot(contains('encounterId')));
      expect(sent, isNot(contains('data')));
      expect(sent, isNot(contains('formVersionId')));
    });

    test('save sends exactly {data}', () async {
      final setup = buildClient(
        (options, body) => _json(<String, dynamic>{
          'id': 's1',
          'status': 'IN_PROGRESS',
          'data': <String, dynamic>{'situation': 'chest pain'},
        }),
      );

      await setup.client.submissions.save(
        's1',
        <String, dynamic>{'situation': 'chest pain'},
      );

      expect(setup.adapter.requests.single.method, 'PUT');
      expect(setup.adapter.bodies.single, '{data: {situation: chest pain}}');
    });

    test('complete surfaces a 400 as a validation exception with pointers',
        () async {
      final setup = buildClient(
        (options, body) => _json(
          <String, dynamic>{
            'message': 'Submission failed server-side validation',
            'errors': <dynamic>[
              <String, dynamic>{
                'instancePath': '/assessment/spo2',
                'keyword': 'maximum',
                'message': 'must be <= 100',
                'params': <String, dynamic>{'limit': 100},
              },
            ],
          },
          status: 400,
        ),
      );

      await expectLater(
        setup.client.submissions.complete('s1'),
        throwsA(
          isA<OmfValidationException>()
              .having((e) => e.errors, 'errors', hasLength(1))
              .having(
                (e) => e.byInstancePath.keys,
                'grouped paths',
                contains('/assessment/spo2'),
              ),
        ),
      );
    });

    test('replay exposes the pinned version, not the form\'s current one',
        () async {
      final setup = buildClient(
        (options, body) => _json(<String, dynamic>{
          'id': 's1',
          'status': 'COMPLETED',
          'formVersionId': 'v7',
          'data': <String, dynamic>{'situation': 'chest pain'},
          'scores': <String, dynamic>{'total': 5},
          'riskLevel': 'HIGH',
          'formVersion': <String, dynamic>{
            'dataSchema': <String, dynamic>{'type': 'object'},
            'uiSchema': <String, dynamic>{
              'schemaVersion': '1.0',
              'layout': <String, dynamic>{
                'type': 'VerticalLayout',
                'elements': <dynamic>[],
              },
            },
          },
        }),
      );

      final submission = await setup.client.submissions.get('s1');

      expect(submission.formVersionId, 'v7');
      expect(submission.formVersion, isNotNull);
      // Scores are server-computed; the client never sends them.
      expect(submission.scores['total'], 5);
      expect(submission.riskLevel, 'HIGH');
    });
  });

  group('submission session', () {
    test('debounces autosave rather than writing on every keystroke', () async {
      var saves = 0;
      final setup = buildClient((options, body) {
        if (options.method == 'PUT') saves++;
        return _json(<String, dynamic>{
          'id': 's1',
          'status': 'IN_PROGRESS',
          'data': <String, dynamic>{},
        });
      });

      final session = OmfSubmissionSession(
        client: setup.client,
        submissionId: 's1',
        debounce: const Duration(milliseconds: 40),
      );

      session
        ..onChanged(<String, dynamic>{'a': 1})
        ..onChanged(<String, dynamic>{'a': 2})
        ..onChanged(<String, dynamic>{'a': 3});

      expect(saves, 0, reason: 'nothing should be written yet');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(saves, 1, reason: 'three edits should collapse into one write');

      await session.dispose();
    });

    test('complete flushes the pending write first', () async {
      final calls = <String>[];
      final setup = buildClient((options, body) {
        calls.add('${options.method} ${options.path}');
        return _json(<String, dynamic>{
          'id': 's1',
          'status': 'COMPLETED',
          'data': <String, dynamic>{},
        });
      });

      final session = OmfSubmissionSession(
        client: setup.client,
        submissionId: 's1',
        debounce: const Duration(seconds: 30),
      )..onChanged(<String, dynamic>{'situation': 'chest pain'});

      await session.complete();

      // /complete validates the STORED data, so racing the debounce would
      // submit whatever the server last saw and silently drop the latest edits.
      expect(calls, <String>[
        'PUT /api/submissions/s1',
        'POST /api/submissions/s1/complete',
      ]);

      await session.dispose();
    });

    test('a failed autosave is reported without taking down the form',
        () async {
      final setup = buildClient(
        (options, body) =>
            _json(<String, dynamic>{'message': 'boom'}, status: 500),
      );

      final session = OmfSubmissionSession(
        client: setup.client,
        submissionId: 's1',
        debounce: const Duration(milliseconds: 20),
      )..onChanged(<String, dynamic>{'a': 1});

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(session.state, OmfSaveState.failed);
      expect(session.lastError, isA<OmfApiException>());

      await session.dispose();
    });
  });
}

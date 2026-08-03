/// The API client.
///
/// Auth is a bearer token and nothing else: tenancy travels inside the JWT, so
/// there are no tenant or facility headers to set. See ARCHITECTURE.md
/// section 11.
library;

import 'package:dio/dio.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import 'exceptions.dart';
import 'models.dart';

/// Holds the access token for the life of a session.
///
/// Deliberately in memory. Persisting a token that grants access to patient
/// data is a decision for the host app — the demo uses this as-is.
class OmfTokenStore {
  String? _token;

  String? get token => _token;
  bool get hasToken => _token != null;

  void set(String token) => _token = token;
  void clear() => _token = null;
}

class OmfApiClient {
  OmfApiClient({
    required String baseUrl,
    Dio? dio,
    OmfTokenStore? tokens,
    this.onUnauthorized,
  })  : tokens = tokens ?? OmfTokenStore(),
        _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      // The API's global pipe rejects unknown properties, so a malformed
      // request comes back as a 400 rather than hanging; short timeouts keep a
      // bad network from looking like a frozen form.
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      // Handle every status ourselves so error bodies survive to the caller.
      validateStatus: (_) => true,
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = this.tokens.token;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final OmfTokenStore tokens;

  /// Called when the API rejects the token, so a host can send the user back to
  /// a login screen.
  final void Function()? onUnauthorized;

  late final OmfAuthApi auth = OmfAuthApi(this);
  late final OmfFormsApi forms = OmfFormsApi(this);
  late final OmfSubmissionsApi submissions = OmfSubmissionsApi(this);

  /// Issue a request and unwrap it, turning any non-2xx into an exception.
  Future<T> send<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    required T Function(Object? data) parse,
  }) async {
    late final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException catch (error) {
      throw OmfApiException(
        message: error.message ?? 'The request could not be completed.',
        statusCode: error.response?.statusCode,
        body: error.response?.data,
      );
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return parse(response.data);

    if (status == 401) {
      tokens.clear();
      onUnauthorized?.call();
    }

    final data = response.data;

    // A failed `complete` carries the Ajv errors that must reach the fields.
    if (status == 400 && OmfValidationException.looksLikeValidationFailure(data)) {
      throw OmfValidationException.fromBody(Map<String, dynamic>.from(data as Map));
    }

    throw OmfApiException(
      message: _messageFrom(data) ?? 'Request failed with status $status.',
      statusCode: status,
      body: data,
    );
  }

  static String? _messageFrom(Object? data) {
    if (data is Map) {
      final message = data['message'];
      if (message is String) return message;
      if (message is List && message.isNotEmpty) return message.join(', ');
    }
    return null;
  }

  void close() => _dio.close();
}

Map<String, dynamic> _asMap(Object? data) =>
    data is Map<dynamic, dynamic>
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};

class OmfAuthApi {
  const OmfAuthApi(this._client);

  final OmfApiClient _client;

  /// Sign in with email and password.
  ///
  /// SSO is a browser-redirect flow and is out of scope for this client.
  Future<OmfSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _client.send(
      'POST',
      '/api/auth/login',
      body: <String, dynamic>{'email': email, 'password': password},
      parse: (data) => OmfSession.fromJson(_asMap(data)),
    );

    _client.tokens.set(session.accessToken);
    return session;
  }

  Future<OmfUser> me() => _client.send(
        'GET',
        '/api/auth/me',
        parse: (data) => OmfUser.fromJson(_asMap(data)),
      );

  void logout() => _client.tokens.clear();
}

class OmfFormsApi {
  const OmfFormsApi(this._client);

  final OmfApiClient _client;

  /// Fetch a published form by slug — the fill path.
  Future<OmfForm> bySlug(String slug) => _client.send(
        'GET',
        '/api/forms/slug/$slug',
        parse: (data) => OmfForm.fromJson(_asMap(data)),
      );

  Future<OmfForm> byId(String id) => _client.send(
        'GET',
        '/api/forms/$id',
        parse: (data) => OmfForm.fromJson(_asMap(data)),
      );

  Future<List<OmfForm>> list() => _client.send(
        'GET',
        '/api/forms',
        parse: (data) => data is List
            ? data
                .whereType<Map<dynamic, dynamic>>()
                .map((form) => OmfForm.fromJson(Map<String, dynamic>.from(form)))
                .toList()
            : const <OmfForm>[],
      );

  /// Fetch the self-contained export bundle.
  ///
  /// Schemas and base64 assets in one call — the shape documented for
  /// third-party renderers.
  Future<OmfFormDefinitionBundle> export(String id) => _client.send(
        'GET',
        '/api/forms/$id/export',
        parse: (data) => OmfFormDefinitionBundle.fromJson(_asMap(data)),
      );
}

/// The `GET /api/forms/:id/export` payload.
class OmfFormDefinitionBundle {
  const OmfFormDefinitionBundle({required this.definition, this.raw = const {}});

  factory OmfFormDefinitionBundle.fromJson(Map<String, dynamic> json) =>
      OmfFormDefinitionBundle(
        definition: OmfFormDefinition.fromJson(json),
        raw: json,
      );

  final OmfFormDefinition definition;
  final Map<String, dynamic> raw;
}

class OmfSubmissionsApi {
  const OmfSubmissionsApi(this._client);

  final OmfApiClient _client;

  /// Start a draft.
  ///
  /// The server pins `formVersionId` to the form's current published version —
  /// a client never chooses one. The body is whitelisted, so only these three
  /// keys may appear; anything else is a 400.
  Future<OmfSubmission> create(
    String formId, {
    String? patientMrn,
    String? encounterId,
    OmfPatientContext? patientContext,
  }) =>
      _client.send(
        'POST',
        '/api/forms/$formId/submissions',
        body: <String, dynamic>{
          if (patientMrn != null) 'patientMrn': patientMrn,
          if (encounterId != null) 'encounterId': encounterId,
          if (patientContext != null && !patientContext.isEmpty)
            'patientContext': patientContext.toJson(),
        },
        parse: (data) => OmfSubmission.fromJson(_asMap(data)),
      );

  Future<OmfSubmission> get(String id) => _client.send(
        'GET',
        '/api/submissions/$id',
        parse: (data) => OmfSubmission.fromJson(_asMap(data)),
      );

  /// Autosave. A **full replace** of `data`, not a patch, and only valid while
  /// the submission is still in progress.
  Future<OmfSubmission> save(String id, Map<String, dynamic> data) =>
      _client.send(
        'PUT',
        '/api/submissions/$id',
        body: <String, dynamic>{'data': data},
        parse: (result) => OmfSubmission.fromJson(_asMap(result)),
      );

  /// Validate and score, server-side.
  ///
  /// It validates the **stored** data, so any pending autosave must be flushed
  /// with [save] first. Throws [OmfValidationException] on a 400.
  Future<OmfSubmission> complete(String id) => _client.send(
        'POST',
        '/api/submissions/$id/complete',
        parse: (data) => OmfSubmission.fromJson(_asMap(data)),
      );

  Future<OmfSubmission> sign(String id) => _client.send(
        'POST',
        '/api/submissions/$id/sign',
        parse: (data) => OmfSubmission.fromJson(_asMap(data)),
      );

  Future<void> voidSubmission(String id) => _client.send(
        'DELETE',
        '/api/submissions/$id',
        parse: (_) {},
      );
}

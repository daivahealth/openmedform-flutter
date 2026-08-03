/// Wire types for the OpenMedForm API.
///
/// Only what a form client needs. Everything else on a payload stays available
/// through `raw`, so a host can read a field this package has not modelled
/// without a second parse.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

/// The signed-in user, as returned alongside an access token.
class OmfUser {
  const OmfUser({
    required this.id,
    required this.email,
    this.fullName,
    this.role,
    this.tenantId,
    this.tenantName,
  });

  factory OmfUser.fromJson(Map<String, dynamic> json) => OmfUser(
        id: '${json['id']}',
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String?,
        role: json['role'] as String?,
        tenantId: json['tenantId'] as String?,
        tenantName: json['tenantName'] as String?,
      );

  final String id;
  final String email;
  final String? fullName;
  final String? role;

  /// Present for information only. Tenancy travels inside the JWT, so nothing
  /// here is ever sent back as a header.
  final String? tenantId;
  final String? tenantName;
}

class OmfSession {
  const OmfSession({required this.accessToken, required this.user});

  factory OmfSession.fromJson(Map<String, dynamic> json) => OmfSession(
        accessToken: json['accessToken'] as String,
        user: OmfUser.fromJson(
          Map<String, dynamic>.from(json['user'] as Map),
        ),
      );

  final String accessToken;
  final OmfUser user;
}

/// A form plus the published version to render.
class OmfForm {
  const OmfForm({
    required this.id,
    required this.definition,
    this.name,
    this.slug,
    this.formType,
    this.raw = const <String, dynamic>{},
  });

  /// Build from `GET /api/forms/slug/:slug` or `GET /api/forms/:id`.
  ///
  /// Mirrors the web app's `toJsonFormsDefinition`: the version to render is
  /// `currentVersion`, falling back to the newest entry in `versions`. Only
  /// `dataSchema` is guaranteed by the API — `uiSchema`, `printSchema` and
  /// `translations` are nullable columns, and [OmfFormDefinition.fromJson]
  /// applies the fallbacks.
  factory OmfForm.fromJson(Map<String, dynamic> json) {
    final version = _pickVersion(json);

    return OmfForm(
      id: '${json['id']}',
      name: json['name'] as String?,
      slug: json['slug'] as String?,
      formType: json['formType'] as String?,
      definition: OmfFormDefinition.fromJson(<String, dynamic>{
        ...version,
        'formCode': json['slug'] ?? json['id'],
        'name': json['name'],
      }),
      raw: json,
    );
  }

  static Map<String, dynamic> _pickVersion(Map<String, dynamic> json) {
    final current = json['currentVersion'];
    if (current is Map) return Map<String, dynamic>.from(current);

    final versions = json['versions'];
    if (versions is List && versions.isNotEmpty && versions.first is Map) {
      return Map<String, dynamic>.from(versions.first as Map);
    }

    return <String, dynamic>{};
  }

  final String id;
  final OmfFormDefinition definition;
  final String? name;
  final String? slug;

  /// `NON_PATIENT` forms skip the patient-context step.
  final String? formType;

  final Map<String, dynamic> raw;
}

/// Where a submission sits in its lifecycle.
enum OmfSubmissionStatus {
  inProgress,
  completed,
  signed,
  voided;

  static OmfSubmissionStatus parse(Object? raw) => switch (raw) {
        'IN_PROGRESS' => OmfSubmissionStatus.inProgress,
        'COMPLETED' => OmfSubmissionStatus.completed,
        'SIGNED' => OmfSubmissionStatus.signed,
        'VOIDED' => OmfSubmissionStatus.voided,
        _ => OmfSubmissionStatus.inProgress,
      };
}

class OmfSubmission {
  const OmfSubmission({
    required this.id,
    required this.status,
    required this.data,
    this.formId,
    this.formVersionId,
    this.scores = const <String, dynamic>{},
    this.riskLevel,
    this.formVersion,
    this.raw = const <String, dynamic>{},
  });

  factory OmfSubmission.fromJson(Map<String, dynamic> json) {
    final version = json['formVersion'];
    final data = json['data'];
    final scores = json['scores'];

    return OmfSubmission(
      id: '${json['id']}',
      status: OmfSubmissionStatus.parse(json['status']),
      data: data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
      formId: json['formId'] as String?,
      formVersionId: json['formVersionId'] as String?,
      scores: scores is Map
          ? Map<String, dynamic>.from(scores)
          : const <String, dynamic>{},
      riskLevel: json['riskLevel'] as String?,
      // Replay renders against the PINNED version, never the form's current
      // one, which may have moved on since this was filled in.
      formVersion: version is Map
          ? OmfFormDefinition.fromJson(Map<String, dynamic>.from(version))
          : null,
      raw: json,
    );
  }

  final String id;
  final OmfSubmissionStatus status;
  final Map<String, dynamic> data;
  final String? formId;
  final String? formVersionId;

  /// Server-computed. Client totals are never accepted.
  final Map<String, dynamic> scores;
  final String? riskLevel;

  /// The version this submission was filled against.
  final OmfFormDefinition? formVersion;

  final Map<String, dynamic> raw;
}

/// Patient context recorded against a submission.
///
/// Every field is optional and the API does not validate the inner shape, but
/// the *outer* DTO is whitelisted — see `OmfSubmissionsApi.create`.
class OmfPatientContext {
  const OmfPatientContext({
    this.patientName,
    this.patientMrn,
    this.age,
    this.gender,
    this.encounterId,
    this.encounterType,
    this.department,
    this.consultantName,
    this.admissionDate,
  });

  final String? patientName;
  final String? patientMrn;
  final String? age;
  final String? gender;
  final String? encounterId;
  final String? encounterType;
  final String? department;
  final String? consultantName;
  final String? admissionDate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (patientName != null) 'patientName': patientName,
        if (patientMrn != null) 'patientMrn': patientMrn,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (encounterId != null) 'encounterId': encounterId,
        if (encounterType != null) 'encounterType': encounterType,
        if (department != null) 'department': department,
        if (consultantName != null) 'consultantName': consultantName,
        if (admissionDate != null) 'admissionDate': admissionDate,
      };

  bool get isEmpty => toJson().isEmpty;
}

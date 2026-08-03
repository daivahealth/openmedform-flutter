/// The form definition a renderer is handed.
///
/// Mirrors `FormDefinition` in `@openmedform/form-schema-types`. Only the parts
/// a renderer actually needs are modelled; the rest of the API payload rides
/// along in [raw] so a host can read it without a second parse.
///
/// Note which fields are nullable. The API guarantees `dataSchema` and nothing
/// else — `uiSchema`, `printSchema` and `translations` are all nullable columns,
/// so a client must apply fallbacks. See docs/ARCHITECTURE.md section 11.
library;

import '../i18n/translate.dart';
import 'json_schema.dart';

class OmfFormDefinition {
  const OmfFormDefinition({
    required this.dataSchema,
    required this.uiSchema,
    this.translations,
    this.formCode,
    this.name,
    this.version,
    this.language,
    this.raw = const <String, dynamic>{},
  });

  /// Build from an API form-version payload or an export bundle.
  ///
  /// When `uiSchema` is absent or malformed, falls back to an empty vertical
  /// layout rather than throwing: a form with no UI schema should render as an
  /// empty form, not crash the screen it was opened from.
  factory OmfFormDefinition.fromJson(Map<String, dynamic> json) {
    final rawUi = json['uiSchema'];
    final uiSchema = rawUi is Map<String, dynamic> && rawUi['layout'] is Map
        ? rawUi
        : <String, dynamic>{
            'schemaVersion': '1.0',
            'layout': <String, dynamic>{
              'type': 'VerticalLayout',
              'elements': <dynamic>[],
            },
          };

    final rawData = json['dataSchema'];
    final rawTranslations = json['translations'];

    return OmfFormDefinition(
      dataSchema: rawData is Map<String, dynamic>
          ? rawData
          : <String, dynamic>{'type': 'object'},
      uiSchema: uiSchema,
      translations: rawTranslations is Map<String, dynamic>
          ? TranslationBundle.fromJson(rawTranslations)
          : null,
      formCode: json['formCode'] as String?,
      name: json['name'] as String?,
      version: json['version']?.toString(),
      language: json['language'] as String?,
      raw: json,
    );
  }

  final JsonSchema dataSchema;

  /// The `{schemaVersion, layout}` wrapper. [layout] is the root element.
  final Map<String, dynamic> uiSchema;

  final TranslationBundle? translations;
  final String? formCode;
  final String? name;
  final String? version;
  final String? language;

  /// The untouched source payload.
  final Map<String, dynamic> raw;

  /// The root UI element to start rendering from.
  Map<String, dynamic> get layout {
    final layout = uiSchema['layout'];
    return layout is Map<String, dynamic>
        ? layout
        : <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[],
          };
  }
}

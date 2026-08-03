/// Translation resolution over a translation bundle.
///
/// Ported from `packages/form-core/src/i18n/translate.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// Display strings resolve by stable key; saved clinical data always uses
/// language-independent codes, so translation is strictly a presentation
/// concern. Resolution falls back requested language → default language →
/// caller fallback → the key itself, which means a missing string shows up as
/// a visible key rather than a blank space.
///
/// Note that no shipped renderer uses this yet: labels come from the UI schema
/// and the data schema's titles, and enum options render as raw codes. It is
/// ported so the Flutter renderer can switch it on without a second
/// implementation, but it stays off by default so display matches the web.
library;

/// A bundle of translations for one form.
class TranslationBundle {
  const TranslationBundle({
    required this.defaultLanguage,
    required this.languages,
    required this.entries,
  });

  factory TranslationBundle.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final entries = <String, Map<String, String>>{};

    if (rawEntries is Map) {
      for (final entry in rawEntries.entries) {
        final translations = entry.value;
        if (translations is! Map) continue;
        entries['${entry.key}'] = <String, String>{
          for (final translation in translations.entries)
            if (translation.value is String)
              '${translation.key}': translation.value as String,
        };
      }
    }

    final rawLanguages = json['languages'];
    return TranslationBundle(
      defaultLanguage: json['defaultLanguage'] as String? ?? 'en',
      languages: rawLanguages is List
          ? rawLanguages.whereType<String>().toList()
          : const <String>[],
      entries: entries,
    );
  }

  final String defaultLanguage;
  final List<String> languages;

  /// Key → language code → display string.
  final Map<String, Map<String, String>> entries;
}

/// Resolve one translation key for a language, with graceful fallback.
String resolveTranslation(
  TranslationBundle bundle,
  String key,
  String language, [
  String? fallback,
]) {
  final entry = bundle.entries[key];
  if (entry != null) {
    final requested = entry[language];
    if (requested != null) return requested;

    final defaulted = entry[bundle.defaultLanguage];
    if (defaulted != null) return defaulted;
  }
  return fallback ?? key;
}

/// A translator bound to a bundle and a language.
typedef Translator = String Function(String key, [String? fallback]);

/// Bind a bundle and language into a reusable translator.
Translator createTranslator(TranslationBundle bundle, String language) =>
    (key, [fallback]) => resolveTranslation(bundle, key, language, fallback);

/// Whether the bundle declares support for a language.
bool hasLanguage(TranslationBundle bundle, String language) =>
    bundle.languages.contains(language);

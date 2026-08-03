/// Design tokens as a Flutter [ThemeExtension].
///
/// Transliterated from `packages/form-design-tokens/src/tokens.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// The token package defines 21 CSS custom properties. The React and Angular
/// renderers reference **twelve more that it never defines**, relying on inline
/// `var(…, fallback)` defaults — accent, header background, danger, muted, and
/// so on. Reproducing only the documented tokens would produce visibly wrong
/// output, so all of them are first-class fields here.
///
/// Two variables are used upstream with *conflicting* fallbacks:
/// `--omf-color-section-bg` appears with both `#f7f8fa` (the token value) and
/// `#f0eaf4`, and `--omf-section-gap` with both `20px` (the token) and `16px`.
/// Because the renderers mount inside a scope that does define those variables,
/// the token value is what actually renders and the odd fallbacks are dead. The
/// token value is therefore canonical here too.
library;

import 'package:flutter/material.dart';

/// Foreground and background for a point badge.
class OmfPointColors {
  const OmfPointColors(this.foreground, this.background);

  final Color foreground;
  final Color background;
}

@immutable
class OmfTheme extends ThemeExtension<OmfTheme> {
  const OmfTheme({
    // Grid
    this.gridColumns = 12,
    this.gridGap = 12,
    // Typography
    this.fontFamily,
    this.bodySize = 14,
    this.labelSize = 13,
    this.sectionTitleSize = 15,
    this.helpSize = 12,
    this.lineHeight = 1.4,
    this.labelWeight = FontWeight.w600,
    // Spacing
    this.fieldGap = 12,
    this.sectionGap = 20,
    this.sectionPadding = 16,
    this.controlPadding = 8,
    // Controls
    this.rowMinHeight = 36,
    this.borderWidth = 1,
    this.borderRadius = 4,
    this.textareaRows = 3,
    // Documented colours
    this.border = const Color(0xFFC8CDD4),
    this.text = const Color(0xFF1C2430),
    this.label = const Color(0xFF3A4552),
    this.sectionBackground = const Color(0xFFF7F8FA),
    this.invalid = const Color(0xFFC0392B),
    // Colours the renderers use but the token package never defines
    this.accent = const Color(0xFF4A2D5C),
    this.headerBackground = const Color(0xFF4A2D5C),
    this.headerForeground = const Color(0xFFFFFFFF),
    this.danger = const Color(0xFFA3312A),
    this.muted = const Color(0xFF6B7280),
    this.help = const Color(0xFF6B7684),
    this.surface = const Color(0xFFFFFFFF),
    this.controlGap = 12,
    this.subsectionIndent = 20,
    this.tableLabelWidthFraction = 0.16,
    this.tableColumnMinWidth = 130,
    this.monoFontFamily = 'monospace',
    // Breakpoints
    this.smBreakpoint = 640,
    this.mdBreakpoint = 900,
  });

  /// The defaults, matching the web renderers pixel for pixel.
  const OmfTheme.defaults() : this();

  final int gridColumns;
  final double gridGap;

  final String? fontFamily;
  final double bodySize;
  final double labelSize;
  final double sectionTitleSize;
  final double helpSize;
  final double lineHeight;
  final FontWeight labelWeight;

  final double fieldGap;
  final double sectionGap;
  final double sectionPadding;
  final double controlPadding;

  final double rowMinHeight;
  final double borderWidth;
  final double borderRadius;
  final int textareaRows;

  final Color border;
  final Color text;
  final Color label;
  final Color sectionBackground;
  final Color invalid;

  final Color accent;
  final Color headerBackground;
  final Color headerForeground;
  final Color danger;
  final Color muted;
  final Color help;
  final Color surface;
  final double controlGap;
  final double subsectionIndent;
  final double tableLabelWidthFraction;
  final double tableColumnMinWidth;
  final String monoFontFamily;

  final double smBreakpoint;
  final double mdBreakpoint;

  /// Point-badge colours, hardcoded in both web renderers and absent from the
  /// token package. Thresholds are `>=`, evaluated highest first.
  static OmfPointColors pointColors(num points) {
    if (points >= 5) {
      return const OmfPointColors(Color(0xFFC0392B), Color(0xFFFDECEA));
    }
    if (points >= 3) {
      return const OmfPointColors(Color(0xFFB8860B), Color(0xFFFBF3E0));
    }
    if (points >= 2) {
      return const OmfPointColors(Color(0xFF1E8E5A), Color(0xFFE8F6EE));
    }
    return const OmfPointColors(Color(0xFF2D6CDF), Color(0xFFE9F0FC));
  }

  TextStyle get bodyStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: bodySize,
        height: lineHeight,
        color: text,
      );

  TextStyle get labelStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: labelSize,
        fontWeight: labelWeight,
        height: lineHeight,
        color: label,
      );

  TextStyle get sectionTitleStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: sectionTitleSize,
        fontWeight: labelWeight,
        height: lineHeight,
        color: label,
      );

  TextStyle get helpStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: helpSize,
        height: lineHeight,
        color: help,
      );

  TextStyle get errorStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: helpSize,
        height: lineHeight,
        color: invalid,
      );

  /// Resolve the theme for a context, falling back to the defaults so a control
  /// still renders correctly in a host that never installed the extension.
  static OmfTheme of(BuildContext context) =>
      Theme.of(context).extension<OmfTheme>() ?? const OmfTheme.defaults();

  @override
  OmfTheme copyWith({
    int? gridColumns,
    double? gridGap,
    String? fontFamily,
    double? bodySize,
    double? labelSize,
    double? sectionTitleSize,
    double? helpSize,
    double? lineHeight,
    FontWeight? labelWeight,
    double? fieldGap,
    double? sectionGap,
    double? sectionPadding,
    double? controlPadding,
    double? rowMinHeight,
    double? borderWidth,
    double? borderRadius,
    int? textareaRows,
    Color? border,
    Color? text,
    Color? label,
    Color? sectionBackground,
    Color? invalid,
    Color? accent,
    Color? headerBackground,
    Color? headerForeground,
    Color? danger,
    Color? muted,
    Color? help,
    Color? surface,
    double? controlGap,
    double? subsectionIndent,
    double? tableLabelWidthFraction,
    double? tableColumnMinWidth,
    String? monoFontFamily,
    double? smBreakpoint,
    double? mdBreakpoint,
  }) =>
      OmfTheme(
        gridColumns: gridColumns ?? this.gridColumns,
        gridGap: gridGap ?? this.gridGap,
        fontFamily: fontFamily ?? this.fontFamily,
        bodySize: bodySize ?? this.bodySize,
        labelSize: labelSize ?? this.labelSize,
        sectionTitleSize: sectionTitleSize ?? this.sectionTitleSize,
        helpSize: helpSize ?? this.helpSize,
        lineHeight: lineHeight ?? this.lineHeight,
        labelWeight: labelWeight ?? this.labelWeight,
        fieldGap: fieldGap ?? this.fieldGap,
        sectionGap: sectionGap ?? this.sectionGap,
        sectionPadding: sectionPadding ?? this.sectionPadding,
        controlPadding: controlPadding ?? this.controlPadding,
        rowMinHeight: rowMinHeight ?? this.rowMinHeight,
        borderWidth: borderWidth ?? this.borderWidth,
        borderRadius: borderRadius ?? this.borderRadius,
        textareaRows: textareaRows ?? this.textareaRows,
        border: border ?? this.border,
        text: text ?? this.text,
        label: label ?? this.label,
        sectionBackground: sectionBackground ?? this.sectionBackground,
        invalid: invalid ?? this.invalid,
        accent: accent ?? this.accent,
        headerBackground: headerBackground ?? this.headerBackground,
        headerForeground: headerForeground ?? this.headerForeground,
        danger: danger ?? this.danger,
        muted: muted ?? this.muted,
        help: help ?? this.help,
        surface: surface ?? this.surface,
        controlGap: controlGap ?? this.controlGap,
        subsectionIndent: subsectionIndent ?? this.subsectionIndent,
        tableLabelWidthFraction:
            tableLabelWidthFraction ?? this.tableLabelWidthFraction,
        tableColumnMinWidth: tableColumnMinWidth ?? this.tableColumnMinWidth,
        monoFontFamily: monoFontFamily ?? this.monoFontFamily,
        smBreakpoint: smBreakpoint ?? this.smBreakpoint,
        mdBreakpoint: mdBreakpoint ?? this.mdBreakpoint,
      );

  @override
  OmfTheme lerp(ThemeExtension<OmfTheme>? other, double t) {
    if (other is! OmfTheme) return this;
    return OmfTheme(
      gridColumns: t < 0.5 ? gridColumns : other.gridColumns,
      gridGap: lerpDouble(gridGap, other.gridGap, t),
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
      bodySize: lerpDouble(bodySize, other.bodySize, t),
      labelSize: lerpDouble(labelSize, other.labelSize, t),
      sectionTitleSize: lerpDouble(sectionTitleSize, other.sectionTitleSize, t),
      helpSize: lerpDouble(helpSize, other.helpSize, t),
      lineHeight: lerpDouble(lineHeight, other.lineHeight, t),
      labelWeight: t < 0.5 ? labelWeight : other.labelWeight,
      fieldGap: lerpDouble(fieldGap, other.fieldGap, t),
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t),
      sectionPadding: lerpDouble(sectionPadding, other.sectionPadding, t),
      controlPadding: lerpDouble(controlPadding, other.controlPadding, t),
      rowMinHeight: lerpDouble(rowMinHeight, other.rowMinHeight, t),
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t),
      borderRadius: lerpDouble(borderRadius, other.borderRadius, t),
      textareaRows: t < 0.5 ? textareaRows : other.textareaRows,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      label: Color.lerp(label, other.label, t)!,
      sectionBackground:
          Color.lerp(sectionBackground, other.sectionBackground, t)!,
      invalid: Color.lerp(invalid, other.invalid, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      headerBackground:
          Color.lerp(headerBackground, other.headerBackground, t)!,
      headerForeground:
          Color.lerp(headerForeground, other.headerForeground, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      help: Color.lerp(help, other.help, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      controlGap: lerpDouble(controlGap, other.controlGap, t),
      subsectionIndent: lerpDouble(subsectionIndent, other.subsectionIndent, t),
      tableLabelWidthFraction: lerpDouble(
        tableLabelWidthFraction,
        other.tableLabelWidthFraction,
        t,
      ),
      tableColumnMinWidth:
          lerpDouble(tableColumnMinWidth, other.tableColumnMinWidth, t),
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
      smBreakpoint: lerpDouble(smBreakpoint, other.smBreakpoint, t),
      mdBreakpoint: lerpDouble(mdBreakpoint, other.mdBreakpoint, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

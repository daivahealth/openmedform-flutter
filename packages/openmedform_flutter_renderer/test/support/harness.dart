/// Shared helpers for renderer tests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

/// Load a golden document from the core package's conformance fixtures.
///
/// Shared rather than copied: two divergent copies of the reference form would
/// defeat the point of having one.
Map<String, dynamic> loadGolden(String name) {
  final file = File(
    '../openmedform_form_core/test/conformance/golden/$name',
  );
  if (!file.existsSync()) {
    fail('Missing golden document ${file.absolute.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// The rrt-sbar reference form.
OmfFormDefinition goldenDefinition() =>
    OmfFormDefinition.fromJson(loadGolden('rrt-sbar.definition.json'));

/// Build a definition from a bare UI schema and data schema, for focused tests.
OmfFormDefinition definitionOf({
  required Map<String, dynamic> layout,
  Map<String, dynamic>? dataSchema,
}) =>
    OmfFormDefinition(
      dataSchema: dataSchema ?? <String, dynamic>{'type': 'object'},
      uiSchema: <String, dynamic>{'schemaVersion': '1.0', 'layout': layout},
    );

/// Pump a renderer inside a minimal app.
///
/// The surface is sized generously so layout tests are not incidentally
/// affected by the default 800x600 test window.
Future<GlobalKey<OmfFormRendererState>> pumpForm(
  WidgetTester tester, {
  required OmfFormDefinition definition,
  Map<String, dynamic>? initialData,
  void Function(Map<String, dynamic>)? onChange,
  bool readOnly = false,
  Size surface = const Size(1000, 2400),
}) async {
  final key = GlobalKey<OmfFormRendererState>();

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OmfFormRenderer(
          key: key,
          definition: definition,
          initialData: initialData,
          onChange: onChange,
          readOnly: readOnly,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return key;
}

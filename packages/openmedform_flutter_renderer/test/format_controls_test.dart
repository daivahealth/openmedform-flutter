/// String controls that carry a `format`.
///
/// Only `date` used to get a picker; `time` and `date-time` fell through to
/// free text, with no picker and no shape guard. Clinical forms lean on them —
/// the F273 transfer form alone has five `format: "time"` fields.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

Map<String, dynamic> _definition(String property, String format) =>
    <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        property: <String, dynamic>{
          'type': 'string',
          'format': format,
          'title': property,
        },
      },
    };

Map<String, dynamic> _layout(String property) => <String, dynamic>{
      'type': 'VerticalLayout',
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'Control', 'scope': '#/properties/$property'},
      ],
    };

Future<void> _pump(
  WidgetTester tester,
  String format, {
  Map<String, dynamic>? initialData,
  void Function(Map<String, dynamic>)? onChange,
  bool readOnly = false,
}) =>
    pumpForm(
      tester,
      definition: definitionOf(
        dataSchema: _definition('field', format),
        layout: _layout('field'),
      ),
      initialData: initialData,
      onChange: onChange,
      readOnly: readOnly,
    );

void main() {
  group('dispatch by format', () {
    testWidgets('date still gets the date picker', (tester) async {
      await _pump(tester, 'date');
      expect(find.byType(OmfDateControl), findsOneWidget);
    });

    testWidgets('time gets the time control, not free text', (tester) async {
      await _pump(tester, 'time');

      expect(find.byType(OmfTimeControl), findsOneWidget);
      expect(find.byType(OmfTextControl), findsNothing);
    });

    testWidgets('date-time gets the date-time control', (tester) async {
      await _pump(tester, 'date-time');

      expect(find.byType(OmfDateTimeControl), findsOneWidget);
      expect(find.byType(OmfTextControl), findsNothing);
    });

    testWidgets('email stays a text field, with an email keyboard',
        (tester) async {
      await _pump(tester, 'email');

      // Deliberately still text: the format only changes the affordance, and
      // the server remains the authority on whether an address is valid.
      expect(find.byType(OmfTextControl), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).keyboardType,
        TextInputType.emailAddress,
      );
    });

    testWidgets('an unknown format falls back to plain text', (tester) async {
      await _pump(tester, 'uri');

      expect(find.byType(OmfTextControl), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).keyboardType,
        TextInputType.text,
      );
    });
  });

  group('time', () {
    testWidgets('shows the stored value', (tester) async {
      await _pump(tester, 'time',
          initialData: <String, dynamic>{'field': '07:05'});

      expect(find.text('07:05'), findsOneWidget);
    });

    // Two different seeds on purpose. Accepting the picker untouched returns
    // whatever it opened at, so a single seed would also pass if the stored
    // value were ignored and the clock happened to agree. Both cannot agree.
    for (final stored in const <String>['09:30', '17:45']) {
      testWidgets('opens at the stored $stored and writes it back unchanged',
          (tester) async {
        Map<String, dynamic>? seen;
        await _pump(
          tester,
          'time',
          initialData: <String, dynamic>{'field': stored},
          onChange: (data) => seen = data,
        );

        await tester.tap(find.byType(InputDecorator));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        expect(seen?['field'], stored);
      });
    }

    testWidgets('writes zero-padded 24-hour text for any time', (tester) async {
      Map<String, dynamic>? seen;
      await _pump(tester, 'time', onChange: (data) => seen = data);

      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Whatever "now" is, the shape the web submits is HH:mm.
      expect(seen?['field'], matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    testWidgets('is not tappable when read-only', (tester) async {
      await _pump(
        tester,
        'time',
        initialData: <String, dynamic>{'field': '09:30'},
        readOnly: true,
      );

      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsNothing);
    });
  });

  group('date-time', () {
    testWidgets('stores local date and time with no zone suffix',
        (tester) async {
      Map<String, dynamic>? seen;
      await _pump(tester, 'date-time', onChange: (data) => seen = data);

      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the date half
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the time half
      await tester.pumpAndSettle();

      // What <input type="datetime-local"> submits. A Z or an offset here
      // would serialize the same answer differently from the web.
      expect(
        seen?['field'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$')),
      );
    });

    testWidgets('backing out of the time half leaves the value alone',
        (tester) async {
      Map<String, dynamic>? seen;
      await _pump(
        tester,
        'date-time',
        initialData: <String, dynamic>{'field': '2026-03-04T08:15'},
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // accept the date
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel')); // abandon the time
      await tester.pumpAndSettle();

      // Half a datetime is worse than none: an invented midnight would read as
      // a real recorded time.
      expect(seen, isNull);
      expect(find.text('2026-03-04T08:15'), findsOneWidget);
    });
  });
}

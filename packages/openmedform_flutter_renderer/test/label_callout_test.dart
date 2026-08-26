/// The accented `Label` callout.
///
/// A Label carrying `omf.accentColor` is the banner a paper form puts around a
/// result. What has to match the web renderers is the wash — form-core's 8% —
/// not the implementation, so that is what these assert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('accented Label callout', () {
    Map<String, dynamic> labelLayout(Map<String, dynamic>? omf) =>
        <String, dynamic>{
          'type': 'VerticalLayout',
          'elements': <dynamic>[
            <String, dynamic>{
              'type': 'Label',
              'text': 'Overall result: CAM-ICU POSITIVE',
              if (omf != null) 'options': <String, dynamic>{'omf': omf},
            },
          ],
        };

    BoxDecoration? decorationAround(WidgetTester tester, String text) {
      final container = tester.widgetList<Container>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(Container),
        ),
      );
      for (final widget in container) {
        final decoration = widget.decoration;
        if (decoration is BoxDecoration && decoration.border != null) {
          return decoration;
        }
      }
      return null;
    }

    testWidgets('an accent turns the Label into a bordered, tinted banner',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          layout: labelLayout(<String, dynamic>{'accentColor': '#b3392c'}),
        ),
      );

      const accent = Color(0xFFB3392C);
      final decoration =
          decorationAround(tester, 'Overall result: CAM-ICU POSITIVE');
      expect(decoration, isNotNull);
      expect(decoration!.border!.top.color, accent);

      // 8% of the accent, matching form-core's accentTint. A banner in a
      // different shade from the web renderer is the drift the contract bans.
      expect(decoration.color, accent.withValues(alpha: 0.08));

      final label =
          tester.widget<Text>(find.text('Overall result: CAM-ICU POSITIVE'));
      expect(label.style?.color, accent);
      expect(label.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('an unreadable accent keeps the border and drops only the wash',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          layout: labelLayout(<String, dynamic>{'accentColor': 'var(--bad)'}),
        ),
      );

      final decoration =
          decorationAround(tester, 'Overall result: CAM-ICU POSITIVE');
      expect(decoration, isNotNull);
      expect(decoration!.color, isNull);
    });

    testWidgets('a Label without an accent is unchanged plain text',
        (tester) async {
      await pumpForm(tester,
          definition: definitionOf(layout: labelLayout(null)));

      expect(
        decorationAround(tester, 'Overall result: CAM-ICU POSITIVE'),
        isNull,
      );
      final label =
          tester.widget<Text>(find.text('Overall result: CAM-ICU POSITIVE'));
      expect(label.style?.fontWeight, isNot(FontWeight.w700));
    });

    testWidgets('the callout is announced rather than read as body text',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpForm(
        tester,
        definition: definitionOf(
          layout: labelLayout(<String, dynamic>{'accentColor': '#b3392c'}),
        ),
      );

      // The web callout is role="status"; a live region is its Flutter twin.
      expect(
        tester
            .getSemantics(find.text('Overall result: CAM-ICU POSITIVE'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      handle.dispose();
    });
  });
}

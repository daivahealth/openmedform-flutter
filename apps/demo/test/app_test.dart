/// Smoke tests for the demo shell.
///
/// The screens that talk to the API are covered by the client's own tests
/// against a mocked transport; what matters here is that the app boots and
/// starts at login.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_demo/main.dart';
import 'package:openmedform_demo/screens/login_screen.dart';

void main() {
  testWidgets('starts at the login screen', (tester) async {
    await tester.pumpWidget(const OmfDemoApp());
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('OpenMedForm'), findsOneWidget);
  });

  testWidgets('shows which API it is pointed at', (tester) async {
    await tester.pumpWidget(const OmfDemoApp());
    await tester.pump();

    // Configurable with --dart-define=OMF_API_URL, and worth showing: a demo
    // silently talking to the wrong environment is a confusing hour.
    expect(find.text(defaultApiUrl), findsOneWidget);
  });
}

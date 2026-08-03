/// A demo of the OpenMedForm Flutter renderer against a live API.
///
/// Covers the whole lifecycle the renderer is meant for: sign in, fetch a
/// published form, fill it with debounced autosave, complete it and read the
/// server's scores back, then replay the submission read-only.
///
/// Point it at an API with `--dart-define=OMF_API_URL=http://host:3100`.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'screens/form_entry_screen.dart';
import 'screens/login_screen.dart';

const String defaultApiUrl = String.fromEnvironment(
  'OMF_API_URL',
  defaultValue: 'http://localhost:3100',
);

void main() => runApp(const OmfDemoApp());

class OmfDemoApp extends StatefulWidget {
  const OmfDemoApp({super.key});

  @override
  State<OmfDemoApp> createState() => _OmfDemoAppState();
}

class _OmfDemoAppState extends State<OmfDemoApp> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  late final OmfApiClient _client = OmfApiClient(
    baseUrl: defaultApiUrl,
    onUnauthorized: _returnToLogin,
  );

  OmfUser? _user;

  /// The API rejected the token, so drop back to the login screen rather than
  /// leaving a half-authenticated form on screen.
  void _returnToLogin() {
    if (!mounted) return;
    _navigator.currentState?.popUntil((route) => route.isFirst);
    setState(() => _user = null);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenMedForm demo',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4A2D5C),
        // The renderer installs its own OmfTheme; a host only themes the rest
        // of its chrome.
        extensions: const <ThemeExtension<dynamic>>[OmfTheme.defaults()],
      ),
      home: _user == null
          ? LoginScreen(
              client: _client,
              apiUrl: defaultApiUrl,
              onSignedIn: (user) => setState(() => _user = user),
            )
          : FormEntryScreen(
              client: _client,
              user: _user!,
              onSignOut: () {
                _client.auth.logout();
                setState(() => _user = null);
              },
            ),
    );
  }
}

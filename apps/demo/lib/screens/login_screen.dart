/// Sign in with email and password.
///
/// SSO is a browser-redirect flow and is out of scope; password login is what
/// the demo needs to reach a token.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.client,
    required this.apiUrl,
    required this.onSignedIn,
    super.key,
  });

  final OmfApiClient client;
  final String apiUrl;
  final void Function(OmfUser user) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final session = await widget.client.auth.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      widget.onSignedIn(session.user);
    } on OmfApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'OpenMedForm',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.apiUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  autofillHints: const <String>[AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _signIn(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

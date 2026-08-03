/// Choose a form to fill: by slug, or from the list the API returns.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';

import 'fill_screen.dart';
import 'replay_screen.dart';

class FormEntryScreen extends StatefulWidget {
  const FormEntryScreen({
    required this.client,
    required this.user,
    required this.onSignOut,
    super.key,
  });

  final OmfApiClient client;
  final OmfUser user;
  final VoidCallback onSignOut;

  @override
  State<FormEntryScreen> createState() => _FormEntryScreenState();
}

class _FormEntryScreenState extends State<FormEntryScreen> {
  final TextEditingController _slug = TextEditingController();
  final TextEditingController _submissionId = TextEditingController();

  late Future<List<OmfForm>> _forms = widget.client.forms.list();
  bool _busy = false;

  @override
  void dispose() {
    _slug.dispose();
    _submissionId.dispose();
    super.dispose();
  }

  void _report(Object error) {
    if (!mounted) return;
    final message = error is OmfApiException ? error.message : error.toString();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBySlug() async {
    final slug = _slug.text.trim();
    if (slug.isEmpty) return;

    setState(() => _busy = true);
    try {
      final form = await widget.client.forms.bySlug(slug);
      if (!mounted) return;
      await _open(form);
    } on Object catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(OmfForm form) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FillScreen(client: widget.client, form: form),
    ),
  );

  Future<void> _replay() async {
    final id = _submissionId.text.trim();
    if (id.isEmpty) return;

    setState(() => _busy = true);
    try {
      final submission = await widget.client.submissions.get(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReplayScreen(submission: submission),
        ),
      );
    } on Object catch (error) {
      _report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forms'),
        actions: <Widget>[
          TextButton(
            onPressed: widget.onSignOut,
            child: Text(widget.user.email),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _slug,
                  onSubmitted: (_) => _openBySlug(),
                  decoration: const InputDecoration(
                    labelText: 'Open a published form by slug',
                    hintText: 'rrt-sbar',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _openBySlug,
                child: const Text('Fill'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _submissionId,
                  onSubmitted: (_) => _replay(),
                  decoration: const InputDecoration(
                    labelText: 'Replay a submission by id',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _replay,
                child: const Text('Replay'),
              ),
            ],
          ),
          const Divider(height: 32),
          FutureBuilder<List<OmfForm>>(
            future: _forms,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snapshot.hasError) {
                return ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Could not list forms'),
                  subtitle: Text('${snapshot.error}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () =>
                        setState(() => _forms = widget.client.forms.list()),
                  ),
                );
              }

              final forms = snapshot.data ?? const <OmfForm>[];
              if (forms.isEmpty) {
                return const ListTile(title: Text('No forms available.'));
              }

              return Column(
                children: <Widget>[
                  for (final form in forms)
                    ListTile(
                      title: Text(form.name ?? form.id),
                      subtitle: Text(form.slug ?? form.id),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(form),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

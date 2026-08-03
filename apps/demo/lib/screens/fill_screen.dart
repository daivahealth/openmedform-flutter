/// Fill a form: create a draft, autosave, complete, read the server's scores.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'replay_screen.dart';

class FillScreen extends StatefulWidget {
  const FillScreen({required this.client, required this.form, super.key});

  final OmfApiClient client;
  final OmfForm form;

  @override
  State<FillScreen> createState() => _FillScreenState();
}

class _FillScreenState extends State<FillScreen> {
  OmfSubmission? _submission;
  OmfSubmissionSession? _session;
  OmfSaveState _saveState = OmfSaveState.idle;

  String? _startupError;
  bool _completing = false;

  /// Server-side validation failures, keyed by JSON Pointer.
  OmfValidationException? _serverErrors;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      // The server pins the form version here; the client never chooses one.
      final submission = await widget.client.submissions.create(widget.form.id);
      if (!mounted) return;

      final session = OmfSubmissionSession(
        client: widget.client,
        submissionId: submission.id,
      );
      session.states.listen((state) {
        if (mounted) setState(() => _saveState = state);
      });

      setState(() {
        _submission = submission;
        _session = session;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _startupError = error is OmfApiException
            ? error.message
            : error.toString(),
      );
    }
  }

  Future<void> _complete() async {
    final session = _session;
    if (session == null) return;

    setState(() {
      _completing = true;
      _serverErrors = null;
    });

    try {
      // Flushes the pending autosave first: /complete validates the STORED
      // data, so racing the debounce would submit whatever the server last saw.
      final completed = await session.complete();
      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReplayScreen(
            submission: completed,
            fallbackDefinition: widget.form.definition,
            celebrate: true,
          ),
        ),
      );
    } on OmfValidationException catch (error) {
      if (!mounted) return;
      setState(() => _serverErrors = error);
    } on OmfApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final submission = _submission;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.form.name ?? widget.form.slug ?? 'Form'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: _SaveChip(state: _saveState)),
          ),
        ],
      ),
      bottomNavigationBar: submission == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _completing ? null : _complete,
                  child: _completing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Complete'),
                ),
              ),
            ),
      body: _buildBody(submission),
    );
  }

  Widget _buildBody(OmfSubmission? submission) {
    if (_startupError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_startupError!, textAlign: TextAlign.center),
        ),
      );
    }

    if (submission == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        if (_serverErrors != null) _ServerErrorBanner(error: _serverErrors!),
        Expanded(
          child: OmfFormRenderer(
            definition: widget.form.definition,
            initialData: submission.data,
            onChange: (data) => _session?.onChanged(data),
          ),
        ),
      ],
    );
  }
}

class _SaveChip extends StatelessWidget {
  const _SaveChip({required this.state});

  final OmfSaveState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      OmfSaveState.idle => ('Not saved yet', Colors.grey),
      OmfSaveState.pending => ('Unsaved changes', Colors.orange),
      OmfSaveState.saving => ('Saving…', Colors.blue),
      OmfSaveState.saved => ('Saved', Colors.green),
      OmfSaveState.failed => ('Save failed', Colors.red),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// The server's verdict, mapped back onto the fields that produced it.
class _ServerErrorBanner extends StatelessWidget {
  const _ServerErrorBanner({required this.error});

  final OmfValidationException error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            error.message,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // The server is authoritative, so these are the failures that
          // actually blocked the submission. instancePath is a JSON Pointer
          // straight to the offending field.
          for (final entry in error.byInstancePath.entries)
            Text(
              '${entry.key.isEmpty ? '(form)' : entry.key}: '
              '${entry.value.map((e) => e.message).join(', ')}',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

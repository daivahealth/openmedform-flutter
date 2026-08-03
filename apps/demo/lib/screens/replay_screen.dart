/// Read-only replay of a submission.
///
/// Renders against the submission's **pinned** version, never the form's
/// current one — a form republished since this was filled in would otherwise
/// display the clinician's answers against different questions.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_api_client/openmedform_api_client.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

class ReplayScreen extends StatelessWidget {
  const ReplayScreen({
    required this.submission,
    this.fallbackDefinition,
    this.celebrate = false,
    super.key,
  });

  final OmfSubmission submission;

  /// Used when the payload carried no `formVersion` — for instance the
  /// response to `/complete`, which returns the row without its version.
  final OmfFormDefinition? fallbackDefinition;

  /// Show a "completed" banner, after a submit.
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final definition = submission.formVersion ?? fallbackDefinition;

    return Scaffold(
      appBar: AppBar(title: Text(celebrate ? 'Submitted' : 'Submission')),
      body: definition == null
          ? const Center(
              child: Text('This submission carried no form version.'),
            )
          : Column(
              children: <Widget>[
                _ScoreSummaryBanner(submission: submission),
                Expanded(
                  child: OmfFormRenderer(
                    definition: definition,
                    initialData: submission.data,
                    readOnly: true,
                  ),
                ),
              ],
            ),
    );
  }
}

/// What the server computed, which is the score that counts.
class _ScoreSummaryBanner extends StatelessWidget {
  const _ScoreSummaryBanner({required this.submission});

  final OmfSubmission submission;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scores = submission.scores;

    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Status: ${submission.status.name}',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (submission.riskLevel != null)
                Chip(label: Text(submission.riskLevel!)),
            ],
          ),
          if (scores.isEmpty)
            Text(
              'No scoring rules on this form.',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12,
              ),
            )
          else
            // Recomputed server-side on completion; a client total is never
            // accepted, so this is the authoritative figure.
            for (final entry in scores.entries)
              Text(
                '${entry.key}: ${entry.value}',
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontSize: 12,
                ),
              ),
        ],
      ),
    );
  }
}

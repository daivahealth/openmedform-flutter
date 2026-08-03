/// Drives one fill-and-submit lifecycle, including the autosave debounce.
///
/// The sequencing here is where the subtle API constraints live, so it is
/// written once rather than repeated in every host screen.
library;

import 'dart:async';

import 'models.dart';
import 'omf_api_client.dart';

enum OmfSaveState { idle, pending, saving, saved, failed }

/// Manages a draft: autosave on change, flush before completing.
class OmfSubmissionSession {
  OmfSubmissionSession({
    required this.client,
    required this.submissionId,
    this.debounce = const Duration(seconds: 3),
  });

  final OmfApiClient client;
  final String submissionId;

  /// Matches the web app, which debounces autosave at three seconds.
  final Duration debounce;

  final StreamController<OmfSaveState> _states =
      StreamController<OmfSaveState>.broadcast();

  /// Save-state transitions, for a status chip.
  Stream<OmfSaveState> get states => _states.stream;

  OmfSaveState _state = OmfSaveState.idle;
  OmfSaveState get state => _state;

  Object? lastError;

  Timer? _timer;
  Map<String, dynamic>? _pending;
  Future<void>? _inFlight;

  void _emit(OmfSaveState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Record a change. The write is debounced.
  void onChanged(Map<String, dynamic> data) {
    _pending = data;
    _emit(OmfSaveState.pending);
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_flush()));
  }

  /// Write any pending change now and wait for it.
  ///
  /// Called before completing. `/complete` validates the **stored** data, so
  /// racing the debounce timer would submit whatever the server last saw —
  /// silently dropping the clinician's most recent edits.
  Future<void> flush() async {
    _timer?.cancel();
    await _flush();
    await _inFlight;
  }

  Future<void> _flush() async {
    final data = _pending;
    if (data == null) return;
    _pending = null;

    // Serialise writes: the endpoint is a full replace, so two overlapping
    // saves could land out of order and resurrect stale data.
    final previous = _inFlight;
    _inFlight = () async {
      if (previous != null) {
        await previous;
      }
      _emit(OmfSaveState.saving);
      try {
        await client.submissions.save(submissionId, data);
        _emit(OmfSaveState.saved);
        lastError = null;
      } on Object catch (error) {
        lastError = error;
        _emit(OmfSaveState.failed);
        rethrow;
      }
    }();

    try {
      await _inFlight;
    } on Object {
      // Surfaced through [state] and [lastError]; a failed autosave must not
      // take down the form the clinician is still filling in.
    }
  }

  /// Flush, then ask the server to validate and score.
  Future<OmfSubmission> complete() async {
    await flush();
    return client.submissions.complete(submissionId);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _states.close();
  }
}

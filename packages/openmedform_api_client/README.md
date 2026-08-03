# openmedform_api_client

Typed client for the [OpenMedForm](https://github.com/daivahealth/openmedform) API: authentication,
fetching published form versions, and the submission lifecycle.

Separate from the renderer so the renderer performs no I/O and stays usable inside a host — an EMR,
say — that fetches forms its own way.

```dart
final client = OmfApiClient(baseUrl: 'http://localhost:3100');
await client.auth.login(email: email, password: password);

final form = await client.forms.bySlug('rrt-sbar');
final draft = await client.submissions.create(form.id);

final session = OmfSubmissionSession(client: client, submissionId: draft.id);
session.onChanged(data);         // debounced autosave
final done = await session.complete();  // flushes, then validates server-side
```

## Constraints this encodes

These are the ones that are bugs if missed, and each is covered by a test:

**The request bodies are exact.** The API's global pipe rejects unknown properties, so an extra key
is a 400 rather than something the server ignores. Create accepts only
`{patientMrn?, encounterId?, patientContext?}`; update accepts only `{data}`.

**Autosave is a full replace, not a patch**, and only valid while the submission is in progress.
Writes are serialised, because two overlapping saves could land out of order and resurrect stale
data.

**`/complete` validates the *stored* data.** `OmfSubmissionSession.complete` flushes the pending
write first — racing the debounce would submit whatever the server last saw and silently drop the
clinician's most recent edits.

**The client never chooses a version.** `formVersionId` is pinned server-side at create time, and
replay renders against that pinned version rather than the form's current one.

**Scores are never sent.** There is no field for them; the server recomputes from `scoringRules`.

**Auth is a bearer token and nothing else.** Tenancy travels inside the JWT, so there are no tenant
or facility headers.

## Errors

A 400 from `/complete` arrives as `OmfValidationException` carrying JSON Pointers, so a UI can map
each failure back onto the field that produced it:

```dart
try {
  await session.complete();
} on OmfValidationException catch (error) {
  for (final entry in error.byInstancePath.entries) {
    highlight(entry.key, entry.value);
  }
}
```

A 401 clears the stored token and calls `onUnauthorized`, so a host can return to its login screen.

## Testing

```bash
dart test                # unit tests, mocked transport
dart test --tags live    # against a running API; see the header of live_integration_test.dart
```

## Licence

Apache-2.0, matching the openmedform repository.

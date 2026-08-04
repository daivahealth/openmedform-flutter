# Changelog

## 0.1.0

First release.

Typed client for the OpenMedForm API: authentication, fetching published form versions, and the
submission lifecycle.

- Encodes the constraints that are otherwise silent bugs: request bodies are exact (the API rejects
  unknown properties), autosave is a full replace, and `complete` validates the *stored* data so a
  pending write must be flushed first.
- `OmfSubmissionSession` handles the debounce, serialises overlapping writes, and flushes before
  completing.
- A validation failure arrives as `OmfValidationException` carrying JSON Pointers, so a UI can map
  each failure back to the field that produced it.

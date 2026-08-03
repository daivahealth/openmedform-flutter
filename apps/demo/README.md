# OpenMedForm demo

Exercises the renderer end to end against a live API: sign in, open a published form, fill it with
debounced autosave, complete it, then replay the submission read-only against its pinned version.

Not published — it exists to prove the renderer and the API client work together, and to be the
thing you run when something looks wrong.

## Running

The API defaults to `http://localhost:3100`:

```bash
flutter run
```

Point it elsewhere with a define:

```bash
flutter run --dart-define=OMF_API_URL=http://192.168.1.20:3100
```

On a physical device, `localhost` is the device — use your machine's LAN address. The Android
emulator reaches the host at `10.0.2.2`.

## Bringing up an API to talk to

From a checkout of [daivahealth/openmedform](https://github.com/daivahealth/openmedform):

```bash
docker compose -f docker-compose.dev.yml up -d
pnpm db:migrate && pnpm db:seed
pnpm --filter @openmedform/api dev
```

Sign in with a seeded user, then open a published form by its slug.

## What each screen is for

| Screen | What it proves |
|---|---|
| Login | Bearer-token auth. Tenancy travels inside the JWT, so no tenant headers are sent. |
| Form entry | `GET /api/forms/slug/:slug` and the form list, including the nullable-column fallbacks. |
| Fill | A draft is created server-side (which pins the form version), autosave debounces at three seconds, and Complete flushes the pending write *before* asking the server to validate. |
| Replay | Renders read-only against `submission.formVersion` — the pinned version, not the form's current one — and shows the scores the server computed. |

## Things worth watching

**The save chip.** It moves through unsaved → saving → saved. If it sticks on "unsaved changes"
longer than the debounce, the write is failing.

**Completing an invalid form.** The server's 400 comes back with JSON Pointers, and the banner maps
each one to the field that produced it. That verdict is the authoritative one — the renderer's own
validation only exists to catch problems earlier.

**The scores after submitting.** They are recomputed server-side. A client total is never accepted,
so if the number differs from what `scoreSummary` showed while filling, the client is wrong.

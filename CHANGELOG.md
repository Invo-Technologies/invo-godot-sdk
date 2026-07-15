# Changelog

All notable changes to the INVO Godot SDK. Versioning follows [SemVer](https://semver.org/); the API surface tracks the INVO backend and mirrors the [web (npm)](https://www.npmjs.com/package/@invonetwork/web-sdk) and [Python (PyPI)](https://pypi.org/project/invonetwork/) SDKs (currently v2.4.1 parity).

## [0.3.0] — 2026-07-15

Second audit pass: export-time secret guard, PII redaction, idempotency-key
safety, and validation parity for the claim/confirm calls.

### Security
- **Export guard**: a new `EditorExportPlugin` raises a loud error whenever a
  build is exported while the sandbox game secret is persisted in
  `project.godot`. The release-build lockout already stopped the secret from
  being *used*, but it still *shipped* inside the PCK (extractable by any
  player) — now it can't ship silently.
- **PII redaction extended to paths**: observability signals already dropped
  query strings; the one route that carries a player email in the path
  (`/player-balances/player/by-email/…`) is now redacted too.
- Absolute-URL detection tightened to explicit `http://`/`https://` prefixes.
- The wallet overlay's "no credentials → offline mock" fallback no longer
  treats a whitespace-only secret/endpoint as configured.

### Fixed
- **Idempotency-key collisions**: the wallet panel derived
  `client_request_id` from `Time.get_ticks_msec()`, which restarts at 0 every
  run — two sessions could silently deduplicate each other's sends. New
  `InvoSandboxServer.new_client_request_id()` (128-bit CSPRNG) is used
  instead and exported for integrators.
- A failed `Invo.setup()` (bad base-URL override) no longer half-applies: the
  environment/game-id now only change after the URL passes validation.
- `claim_transfer` / `claim_currency` / `confirm_payment` now validate inputs
  before the wire (required fields, E.164 phone, target currency id) —
  closing the gap in the "method-for-method port including input validation"
  contract.
- The wallet panel no longer crashes on refresh if the SDK failed to
  configure; the dock's connection test no longer touches freed nodes when
  the plugin is disabled mid-request.
- 9 new tests (54 total).

## [0.2.0] — 2026-07-15

Correctness + security audit release.

### Fixed
- **Money validation at large magnitudes**: the ≤2-decimal-places check used a
  relative float comparison, so values like `999999.999` were wrongly accepted;
  now an absolute integer-cents comparison at any magnitude.
- IPv6 loopback (`http://[::1]`) is now correctly recognized as local in the
  base-URL check.
- Token-refresh waiters now learn whether the shared refresh actually
  succeeded, instead of misreading a stale token as success.

### Added
- **`Invo.login_via_backend(payload, endpoint?)`** — the client-mode login
  path: POSTs to YOUR backend's token endpoint
  (`invonetwork/config/player_token_endpoint`), expects `{token, identity_id?}`,
  wires automatic re-mint on expiry. Client mode is now usable end to end
  without custom code.
- `initiate_send`/`initiate_transfer` client-side validation (E.164 phones,
  plain-decimal amount, required ids) — rejected before the wire.
- Client calls without a token fail fast with `NO_PLAYER_TOKEN` instead of a
  confusing backend 401.
- `Invo.disable_mock()`.
- 10 new tests (45 total).

### Security
- **Release-build lockout**: direct (game-secret) mode and the mock transport
  are refused in non-debug builds — a sandbox secret or fake-commerce mock can
  no longer function inside an exported game.
- **`INVO_SANDBOX_SECRET` environment variable** now takes precedence over the
  project setting, so the secret need never be persisted in `project.godot`
  (which ships inside exports).
- Header values are sanitized (control characters stripped) so a hostile
  token string cannot smuggle extra headers.
- `OS.shell_open` is now gated by an https-only allowlist on checkout URLs.
- Observability signals redact query strings (player emails/phones never
  reach logs).
- https enforcement moved into `InvoHttp.configure()` itself — no code path
  can downgrade to plaintext with credentials attached.
- The wallet panel no longer hard-codes a placeholder phone number; it has a
  proper phone field for claim/send.

## [0.1.0] — 2026-07-15

Initial release.

### Added
- **Client mode** (`InvoPlayerClient`, player-token auth — safe to ship): `get_balance`, `get_destinations`, `get_pending_collect`, `recovery_begin/complete`, single-flighted token refresh on `SDK_TOKEN_EXPIRED`.
- **Direct sandbox mode** (`InvoSandboxServer`, game-secret auth — sandbox prototyping only, refused in production): full server-API port of `invonetwork` 2.4.1 — `mint_player_token`, `initiate_send/transfer`, `create_checkout`, `purchase_currency`/`confirm_payment`/`get_order_details`, `purchase_item` + history/order lookups, `get_player_balance`, `get_inbound_pending`, `get_linked_identities`, `verify_sms_send/transfer`, `claim_currency/transfer`, transfer/send/guardian status reads, `get_destinations`, and the unauthenticated phone-share OTP handshake.
- **`Invo` autoload** facade with project settings, environment switching (sandbox/production), `login_sandbox`, `open_checkout` (system browser hand-off), and signals (`logged_in`, `balance_updated`, `checkout_opened`, `request_failed`).
- **Error parity**: `InvoError` with stable-code promotion and the official classifiers (`is_insufficient_balance` gated to 400, `is_phone_share_approval_required` + `phone_share_last4`, Steam transfer-policy 409s + `steam_transferable_max`, `is_passkey_recovery_cooldown` + `retry_after_at`, `is_duplicate_request`, `is_token_expired`, …).
- **Transport parity**: idempotent-only retries (network/timeout, 429 honoring `retry_after` ≤ 20 s, 5xx), exponential backoff with full jitter, no redirect following, https enforcement (loopback exempt), explicit SDK User-Agent, request-id capture.
- **Validation parity**: plain-decimal money (≤ 2 places, $999.99 purchase cap, item-price cap, integer-cents total check), E.164 phones, required-field checks — all rejected before the wire, matching the Python/JS SDKs.
- **Drop-in UI**: `InvoWalletPanel` (balance / add funds / claim / send) and `InvoWalletOverlay` (F8-toggle CanvasLayer; `invo_wallet_toggle` action).
- **Editor integration**: INVO dock (configuration + sandbox connection test), project settings, `Invo` autoload registration.
- **Offline mock transport** (`InvoMock`) for credential-free trials and tests.
- Headless test suite (`tests/run_tests.gd`).

### Security
- The game secret is confined to the sandbox-only direct mode; production construction is refused with guidance to use the server SDKs (npm/PyPI) on your backend.

# Changelog

All notable changes to the INVO Godot SDK. Versioning follows [SemVer](https://semver.org/); the API surface tracks the INVO backend and mirrors the [web (npm)](https://www.npmjs.com/package/@invonetwork/web-sdk) and [Python (PyPI)](https://pypi.org/project/invonetwork/) SDKs (currently v2.4.1 parity).

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

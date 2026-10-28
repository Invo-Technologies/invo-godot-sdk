# INVO Network — Godot Plugin

[![CI](https://github.com/Invo-Technologies/invo-godot-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/Invo-Technologies/invo-godot-sdk/actions/workflows/ci.yml)

First-party-style **Godot 4.x** plugin for [INVO Network](https://docs.invo.network/) — cross-game virtual currency: real-money currency purchase (hosted checkout), item purchase, player-to-player **sends & transfers**, balances, pending-collect, and claim codes. The Godot counterpart of INVO's Unity, Unreal, [web (npm)](https://www.npmjs.com/package/@invonetwork/web-sdk) and [Python (PyPI)](https://pypi.org/project/invonetwork/) SDKs, ported from the v2.4.1 API surface.

## Install

**From the Asset Library:** in the Godot editor open the **AssetLib** tab, search for **INVO Network**, then download and install it (keep only `addons/invonetwork/` checked).

**Manually:**

1. Copy `addons/invonetwork/` into your project.
2. Enable **INVO Network** in *Project Settings → Plugins*. This registers the `Invo` autoload and the INVO dock.
3. Configure in the **INVO dock** (or *Project Settings → Invonetwork*): environment (`sandbox`/`production`), your game ID, and either your backend's player-token endpoint (production) or your sandbox game secret (prototyping). Sandbox keys come from [console.invo.network/test](https://console.invo.network/test) and start with `ivsdk_test_` (older `ivsdk_` keys still work). Production keys (`ivsdk_live_`) belong on your game server only, never in the game.

## The two modes — and the one security rule

**The game secret must never ship inside a game build.** It authorizes every server flow, so it lives on *your* backend (use INVO's [Python](https://pypi.org/project/invonetwork/) or [JS](https://www.npmjs.com/package/@invonetwork/web-sdk) server SDK there).

| Mode | Auth | Use |
|---|---|---|
| **Client** — `Invo.client()` | short-lived player token | Ships in your game. Balance, destinations, pending-collect. Your backend mints the token (`mint_player_token`); point `player_token_endpoint` at it and call `Invo.login_via_backend()`. |
| **Direct sandbox** — `Invo.sandbox()` | game secret | Local prototyping against the sandbox ONLY. Refused in the production environment **and in non-debug (exported) builds**. |

For the sandbox secret, prefer the **`INVO_SANDBOX_SECRET` environment variable** — it takes precedence over the project setting and never touches `project.godot` (which ships inside exported builds).

```gdscript
# Production pattern — client mode end to end:
var login := await Invo.login_via_backend({"session": my_session_id})
# your endpoint returns {"token": "...", "identity_id": "..."} by calling
# mint_player_token server-side; re-mint on expiry is wired automatically.
```

## Quick start (sandbox)

```gdscript
# Sign a sandbox player in (mints a player token via the sandbox secret):
var login := await Invo.login_sandbox("player@example.com")

# Read their balance (client mode, player token):
var balance := await Invo.client().get_balance()
if balance.ok:
    print(balance.dict()["balances"])

# Real money in — hosted checkout in the system browser:
await Invo.open_checkout("player@example.com", "4.99")

# Spend game currency on an item (direct sandbox mode):
var purchase := await Invo.sandbox().purchase_item(
    "order-123",              # client_request_id (idempotency key)
    "player@example.com", "PlayerName",
    "sword_01", "Iron Sword", 1, "10.00", "10.00")
if not purchase.ok and purchase.error.is_insufficient_balance():
    print("not enough gold")
```

Every call returns an `InvoResult` (`ok` / `data` / `error: InvoError`). `InvoError` carries the backend's stable `code`, HTTP `status`, raw `body`, `request_id`, and the same classifiers as the official SDKs (`is_insufficient_balance()`, `is_phone_share_approval_required()`, `is_steam_value_non_transferable()`, `is_token_expired()`, …).

## Drop-in UI: the INVO wallet window

The same wallet as the Unity SDK, with the same screens, copy, dark and light themes, Inter font and approval flow:

- **Store**: *Top up* (FEATURED, PACKS, DAILY DEALS from your INVO game items, paid in the browser through INVO's hosted checkout) and *Items* (your catalog, paid from the in-game balance with a confirm sheet).
- **Send**: to another player's phone, in this game or another (recent recipients, searchable game picker), then review, approve on your phone by QR, done.
- **Transfer**: move the player's own balance to another game, with the same four steps.
- **Collect**: what's waiting for the player, approved on their phone.
- **Phone**: the number that approves sends; secured accounts confirm a change from an email link.

```gdscript
var wallet: InvoWallet = preload("res://addons/invonetwork/ui/invo_wallet.tscn").instantiate()
add_child(wallet)
Invo.set_active_player(player.email, player.phone, player.name)   # once, after your login
wallet.set_item_catalog([{"item_id": "sword_01", "name": "Ember Sword", "price": 250}])
wallet.open("Store")            # or "Send", "Transfer", "Collect", "Phone"; F8 toggles
```

`light_theme = true` switches palettes; `InvoUiTheme.build(your_palette)` re-skins it. `invo_wallet_overlay.tscn` is the same window for adding as an autoload. With no credentials configured, debug builds use an **offline mock** so every flow works immediately, and in the sandbox a SANDBOX mark and a test sign-in form appear (never in release builds).

## Production integration

In production the game holds only a player token. Phone approvals (begin, poll, settle), balance, destinations and the Collect list use that token directly. Everything that needs the game secret (the store list, item purchases, starting a send or transfer, phone changes) goes through **your game server**, exactly like the Unity SDK:

- **Game Server URL** (`invonetwork/config/game_server_url`): the wallet sends INVO's own `/api/...` paths there with `Authorization: Bearer <player token>`. Your server checks the player, attaches your production key (`X-Game-Secret-Key`; for `/api/v1/game-items/list` also `game_secret` in the body), sets item prices from your own catalog (INVO charges the price it is sent), and forwards to `https://invo.network`.
- **Checkout session endpoint** (`invonetwork/config/checkout_session_endpoint`): takes `{player_email, usd_amount}` and returns `{checkout_url}` for real-money top-ups.

Your backend also needs these endpoints (sketch, Python server SDK; the JS SDK is equivalent):

```python
from invonetwork import InvoServer
server = InvoServer(game_secret=os.environ["INVO_GAME_SECRET"], environment="production")

@app.post("/invo/token")                     # <- invonetwork/config/player_token_endpoint
def mint_token():
    player = authenticate_session(request)   # YOUR session auth — never mint blind
    minted = server.mint_player_token(player.email)
    return {"token": minted["token"], "identity_id": minted["identity_id"]}

@app.post("/invo/webhook")
def webhook():                               # source of truth for crediting/granting
    event = server.verify_webhook(request.data, request.headers)  # HMAC-SHA256
    if event["type"] in ("purchase.completed", "item.purchased"):
        credit_or_grant(event)               # server-side, never off the client response
    return "", 204
```

Point `invonetwork/config/player_token_endpoint` at `/invo/token`, call `Invo.login_via_backend()`, and client mode is live — token re-mint on expiry is wired automatically.

## Not included (and why)

- **Webhook verification** — webhooks terminate on your backend; verify and credit there (see above). A game client can't hold the HMAC secret.
- **Passkey (WebAuthn) ceremonies** — a browser capability. Approve/claim ceremonies hand off to INVO's hosted pages / your web companion.
- **Production checkout/purchase/send/claim calls straight to INVO**: they need the game secret, which never ships in a build, so the wallet sends them to your game server instead (above).
- **Steam in-client purchase rail** — dedicated endpoints, not yet ported (`purchase_currency` rejects `rail="steam"` with guidance). On the roadmap.

## Transport semantics (ported from the official SDKs)

- Retries only for **idempotent** calls: network errors/timeouts, 429 (honoring `retry_after` ≤ 20 s), 5xx; exponential backoff with full jitter, 2 retries.
- Non-idempotent POSTs (claims, SMS-PIN verifies, checkout creation) are **never** auto-retried.
- Redirects are never followed (credentials would re-send); https is enforced (loopback exempt).
- Money values validated as plain decimals (≤ 2 places, > 0, purchase caps); phones must be E.164.

## Tests

```bash
godot --headless --script res://tests/run_tests.gd   # core
godot --headless --script res://tests/api_tests.gd   # wallet API calls
godot --headless --script res://tests/qr_tests.gd    # QR encoder
godot --headless res://tests/ui_tests.tscn           # wallet window, end to end on the mock
```

## Status / roadmap

- [x] Full server-API port (sandbox direct mode), player-token client mode, retry/error parity, mock transport, wallet UI, editor dock
- [x] CI (headless test suite on every push) and tagged releases
- [ ] End-to-end verification against the live sandbox (all tests currently run against the mock transport)
- [ ] Verified minimum Godot version (CI currently proves 4.7 only)
- [ ] Sample backend companion (token mint + webhook, Python/JS)
- [ ] Steam in-client purchase rail
- [ ] C# bindings
- [x] Wallet window matching the Unity SDK (Store, Send, Transfer, Collect, Phone; QR phone approval)
- [ ] Asset Library listing (submitted with 0.5.0)

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 INVO Tech Inc. The bundled Inter font is under the SIL Open Font License (`addons/invonetwork/ui/art/Inter-OFL.txt`).

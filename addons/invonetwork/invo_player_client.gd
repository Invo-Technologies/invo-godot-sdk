class_name InvoPlayerClient
extends RefCounted
## The CLIENT-MODE entry — safe to ship inside a game build.
##
## Authenticates with a short-lived, game-scoped **player token** (never the
## game secret). Your backend mints the token with the INVO Python/JS server
## SDK (`mint_player_token`) and hands it to the game; in sandbox you can also
## mint directly via [InvoSandboxServer] for prototyping.
##
## On SDK_TOKEN_EXPIRED the client re-mints once through the configured
## `token_provider` and retries — single-flighted, so concurrent expiries
## trigger one refresh (parity with the web SDK's withTokenRetry).
##
## What a player token can NOT do (INVO has no player-token route for these;
## they need the game secret, so in production YOUR backend makes the call and
## the game asks your backend): list store items, buy an item, initiate a send
## or transfer, read a send/transfer status, the "games you play" list, and
## change the player's phone. In sandbox they are on [InvoSandboxServer].

var _http: InvoHttp
var _token: String = ""
## Optional async Callable() -> String returning a fresh player token ("" on failure).
var token_provider: Callable = Callable()

var _refreshing: bool = false
var _last_refresh_ok: bool = false


func _init(http: InvoHttp, token: String = "") -> void:
	_http = http
	set_token(token)


func set_token(token: String) -> void:
	# Sanitized here as well as at the transport: a token is the one header
	# value that flows in from outside the SDK.
	_token = InvoHttp.sanitize_header_value(token.strip_edges())


func token() -> String:
	return _token


func has_token() -> bool:
	return not _token.is_empty()


func _auth() -> Dictionary:
	return {"Authorization": "Bearer %s" % _token}


## The player's balances for the token's game. An empty `balances` array is a
## player who hasn't transacted yet (show 0.00) — not an error.
func get_balance() -> InvoResult:
	var res: InvoResult = await _get_with_token_retry("/api/sdk/balance")
	if res.ok:
		return InvoResult.success(InvoMap.to_client_balance_result(res.dict()))
	return res


## Games/tenants this player can send/transfer to, with display metadata inline.
func get_destinations(direction: String = "transfer") -> InvoResult:
	var res: InvoResult = await _get_with_token_retry(
			"/api/sdk/destinations?direction=%s" % direction.uri_encode())
	if res.ok:
		return InvoResult.success(InvoMap.to_destinations_result(res.dict(), direction))
	return res


## The player's own pending items to collect. Each row's `kind` says which
## action applies: "identity_gate" (you initiated) or "receiving_confirm"
## (a peer sent to you). PII-free. The approve/confirm ceremonies themselves
## are passkey (WebAuthn) steps that must run in a browser — open your web
## companion page for them.
func get_pending_collect() -> InvoResult:
	var res: InvoResult = await _get_with_token_retry("/api/sdk/transfers/pending")
	if res.ok:
		var raw: Dictionary = res.dict()
		var rows: Variant = raw.get("pending")
		return InvoResult.success({
			"pending": rows if rows is Array else [],
			"raw": raw,
		})
	return res


## Start passkey recovery — sends a one-time code to the identity's phone/email.
## NOT idempotent (rate-limited 5/10min -> 429 rate_limited; 422 no_channel_on_file).
func recovery_begin() -> InvoResult:
	if not has_token():
		return InvoResult.failure(InvoError.make(
				"No player token set.", "NO_PLAYER_TOKEN", 0))
	var res: InvoResult = await _http.post_json("/api/sdk/device/recover/begin", null, _auth())
	if res.ok:
		var raw: Dictionary = res.dict()
		var channels: Variant = raw.get("channels")
		return InvoResult.success({
			"status": str(raw.get("status", "")),
			"channels": channels if channels is Array else [],
			"raw": raw,
		})
	return res


## Verify the recovery code. On success ("recovered") the browser should run
## the normal enrollPasskey() ceremony. NOT idempotent (attempts are counted).
## NOTE the 24h money-OUT cooldown after recovery (PASSKEY_RECOVERY_COOLDOWN).
func recovery_complete(code: String) -> InvoResult:
	if not has_token():
		return InvoResult.failure(InvoError.make(
				"No player token set.", "NO_PLAYER_TOKEN", 0))
	if not InvoValidate.is_present(code):
		return InvoResult.failure(InvoError.invalid_input("code", code, "is required"))
	var res: InvoResult = await _http.post_json(
			"/api/sdk/device/recover/complete", {"code": code}, _auth())
	if res.ok:
		var raw: Dictionary = res.dict()
		var deactivated: Variant = raw.get("deactivated_count")
		return InvoResult.success({
			"status": str(raw.get("status", "")),
			"deactivated_count": int(deactivated)
					if (deactivated is int or deactivated is float) else 0,
			"next": raw.get("next") if raw.get("next") is String else null,
			"raw": raw,
		})
	return res


# ---- Pending actions (Collect tab + the sender's own approvals) ----

## Everything awaiting the player, mapped (see InvoMap.to_pending_action):
## `identity_gate` rows they started and must approve, `receiving_confirm`
## rows addressed to them that they can collect. `receivable` is the Collect
## list (receiving_confirm only); `ready_count` excludes held rows (badge).
## Poll on open and every 30-60 s while the panel is visible. Same route as
## get_pending_collect(), which keeps returning the raw rows.
func get_pending_actions() -> InvoResult:
	var res: InvoResult = await _get_with_token_retry("/api/sdk/transfers/pending")
	if not res.ok:
		return _with_bare_code(res)
	var raw: Dictionary = res.dict()
	var rows: Variant = raw.get("pending")
	var pending: Array[Dictionary] = []
	var receivable: Array[Dictionary] = []
	var ready: int = 0
	if rows is Array:
		for r: Variant in rows:
			if not (r is Dictionary):
				continue
			var item: Dictionary = InvoMap.to_pending_action(r)
			pending.append(item)
			if item["kind"] == "receiving_confirm":
				receivable.append(item)
				if not item["held"]:
					ready += 1
	return InvoResult.success({
		"pending": pending,
		"receivable": receivable,
		"ready_count": ready,
		"raw": raw,
	})


# ---- Device approval (RFC 8628) — the QR / system-browser approval ----
#
# Replaces the SMS PIN for send, transfer and both collects. Everything runs on
# the player token; the game secret is never involved, so this is production-
# safe as-is. The loop a UI runs:
#   1. begin_device_approval(txn, flow, channel)  -> grant
#   2. show grant.verification_uri_complete as a QR (channel "qr": desktop,
#      Steam, consoles) or OS.shell_open() it (channel "app_browser": phones);
#      print grant.user_code under it for typing by hand.
#   3. poll_device_approval(grant.device_code) every `interval` seconds
#      (see next_poll_interval) until approved / access_denied / expired_token.
#      While pending, a poll may carry `enrollment` (state "awaiting_screen"):
#      show "set up INVO on <device_label>? code <match_code>" and answer with
#      confirm_device_enrollment().
#   4. on approved: settle_device_approval(txn, flow, device_code). AN APPROVED
#      POLL MOVES NOTHING — the settle call is the one that moves money.

const CHANNEL_QR: String = "qr"
const CHANNEL_APP_BROWSER: String = "app_browser"
## RFC 8628 outcomes the backend answers as HTTP 400 — returned as a result
## (status = the outcome), not an error. invalid_grant stays an error.
const POLL_OUTCOMES: Array[String] = [
	"authorization_pending", "slow_down", "access_denied", "expired_token"]
const DEFAULT_POLL_INTERVAL: int = 5
const SLOW_DOWN_INCREMENT: int = 5
## Consecutive transient poll failures (network/429/5xx) worth riding out.
const MAX_TRANSIENT_POLL_FAILURES: int = 5


## Start a device approval for ONE transaction. flow: transfer | send |
## send_receipt | transfer_receipt; channel: "qr" or "app_browser". A repeat
## begin while a grant is pending replaces it with a fresh code; one the player
## already APPROVED answers 409 DEVICE_APPROVAL_ALREADY_PENDING — settle it
## instead. NOT idempotent (each call mints a new code) — never auto-retried.
## Errors the UI branches on: DEVICE_APPROVAL_ALREADY_PENDING,
## PASSKEY_RECOVERY_COOLDOWN, DEVICE_APPROVAL_NOT_CONFIGURED,
## TENANT_NOT_MIGRATED, sdk_verification_disabled, player_not_found, 403 wrong party.
func begin_device_approval(transaction_id: String, flow: String,
		channel: String = CHANNEL_QR) -> InvoResult:
	var input_err: InvoError = _txn_flow_problem(transaction_id, flow)
	if input_err != null:
		return InvoResult.failure(input_err)
	if not (channel in [CHANNEL_QR, CHANNEL_APP_BROWSER]):
		return InvoResult.failure(InvoError.invalid_input(
				"channel", channel, 'must be "qr" or "app_browser"'))
	var res: InvoResult = await _post_with_token_retry("/api/sdk/approvals/device/begin",
			{"transaction_id": transaction_id, "flow": flow, "channel": channel})
	if not res.ok:
		return _with_bare_code(res)
	var grant: Dictionary = InvoMap.to_device_grant(res.dict())
	if str(grant["device_code"]).is_empty() or str(grant["verification_uri_complete"]).is_empty():
		return InvoResult.failure(InvoError.make(
				"The device-approval grant was incomplete.", "INVALID_RESPONSE", 0, res.dict()))
	return InvoResult.success(grant)


## One poll. Never faster than the grant's `interval`. result.data.status is
## approved | authorization_pending | slow_down | access_denied |
## expired_token (all a SUCCESS result); invalid_grant and transport failures
## are errors. Not auto-retried by the transport (extra polls earn slow_down);
## ride out is_transient_poll_failure() errors in your loop instead.
func poll_device_approval(device_code: String) -> InvoResult:
	if not InvoValidate.is_present(device_code):
		return InvoResult.failure(InvoError.invalid_input("deviceCode", "<redacted>", "is required"))
	var res: InvoResult = await _post_with_token_retry("/api/sdk/approvals/device/poll",
			{"device_code": device_code})
	if res.ok:
		var raw: Dictionary = res.dict()
		var status: String = str(raw.get("status", ""))
		return InvoResult.success(InvoMap.to_device_poll(raw,
				status if not status.is_empty() else "approved"))
	if res.error != null and res.error.status == 400 and res.error.body is Dictionary:
		var body: Dictionary = res.error.body
		var outcome: Variant = body.get("error")
		if outcome is String and (outcome as String) in POLL_OUTCOMES:
			return InvoResult.success(InvoMap.to_device_poll(body, outcome))
	return _with_bare_code(res)


## Answer the on-screen "set up INVO on this phone? code ####" prompt for a
## first-time phone. approve=false ends the whole grant (next poll:
## access_denied). Answered once; NOT retried. result.data.status is
## "confirmed" or "denied". A moot answer (is_moot_enrollment_answer) is
## harmless — the next poll reports the real state.
func confirm_device_enrollment(device_code: String, approve: bool) -> InvoResult:
	if not InvoValidate.is_present(device_code):
		return InvoResult.failure(InvoError.invalid_input("deviceCode", "<redacted>", "is required"))
	var res: InvoResult = await _post_with_token_retry(
			"/api/sdk/approvals/device/confirm-enrollment",
			{"device_code": device_code, "decision": "approve" if approve else "deny"})
	if not res.ok:
		return _with_bare_code(res)
	return InvoResult.success({"status": str(res.dict().get("status", "")), "raw": res.dict()})


## THE MONEY STEP. After a poll answered `approved`, settle the transaction
## with the grant's device_code, routed by flow:
##   transfer -> /api/sdk/transfers/{id}/approve      (status "approved", claim_code)
##   send     -> /api/sdk/send/{id}/approve           (status "approved")
##   send_receipt     -> /api/sdk/send/{id}/confirm-receipt      (status "completed", amount_received)
##   transfer_receipt -> /api/sdk/transfers/{id}/confirm-receipt (status "completed", amount_received)
## A 202 hold (is_hold, hold_reason GUARDIAN_APPROVAL_PENDING / RISK_HOLD /
## STEP_UP_REQUIRED / RECIPIENT_IDENTITY_PENDING) is success: nothing moved,
## nothing refused — poll the transaction status. TRANSACTION_NOT_PENDING comes
## back as status "not_pending" with current_status + already_settled (the
## normal answer to "did my earlier attempt land?").
## NEVER auto-retried: the device code is single use. An error here is
## AMBIGUOUS about the money — read the transaction status before telling the
## player it failed, and never start a replacement transaction.
func settle_device_approval(transaction_id: String, flow: String,
		device_code: String) -> InvoResult:
	var input_err: InvoError = _txn_flow_problem(transaction_id, flow)
	if input_err != null:
		return InvoResult.failure(input_err)
	if not InvoValidate.is_present(device_code):
		return InvoResult.failure(InvoError.invalid_input("deviceCode", "<redacted>", "is required"))
	var res: InvoResult = await _post_with_token_retry(
			settle_path(transaction_id, flow), {"device_code": device_code})
	if res.ok:
		return InvoResult.success(InvoMap.to_settle_result(res.dict()))
	if res.error != null and res.error.code == "TRANSACTION_NOT_PENDING":
		var body: Dictionary = res.error.body if res.error.body is Dictionary else {}
		var current: String = str(body.get("current_status")) \
				if body.get("current_status") is String else ""
		var mapped: Dictionary = InvoMap.to_settle_result({})
		mapped["status"] = "not_pending"
		mapped["transaction_id"] = transaction_id
		mapped["current_status"] = current
		mapped["already_settled"] = is_past_step(flow, current)
		mapped["raw"] = body
		return InvoResult.success(mapped)
	return _with_bare_code(res)


## The settle endpoint for a flow (exposed for tests/logging; no secrets in it).
static func settle_path(transaction_id: String, flow: String) -> String:
	var id: String = transaction_id.uri_encode()
	match flow:
		"transfer":
			return "/api/sdk/transfers/%s/approve" % id
		"send":
			return "/api/sdk/send/%s/approve" % id
		"send_receipt":
			return "/api/sdk/send/%s/confirm-receipt" % id
		_:
			return "/api/sdk/transfers/%s/confirm-receipt" % id


## Whether current_status (from TRANSACTION_NOT_PENDING) proves THIS flow's
## step already happened. Allow-list, fail closed: sender approvals are past
## their step from pending_claim on; receipts only at completed/distributed.
## An unknown status is never read as "the money moved".
static func is_past_step(flow: String, current_status: String) -> bool:
	var s: String = current_status.strip_edges().to_lower()
	if s.is_empty():
		return false
	var finished: bool = s == "completed" or s == "distributed"
	match flow:
		"transfer", "send":
			return finished or s in ["pending_claim", "verified", "pin_verified_awaiting_claim"]
		"send_receipt", "transfer_receipt":
			return finished
	return false


## The wait before the next poll (RFC 8628): `status` is the last poll's
## status ("" for the first wait after begin), `stated` the interval the
## server gave (0 when none).
static func next_poll_interval(current: int, status: String, stated: int) -> int:
	match status:
		"":
			return stated if stated > 0 else DEFAULT_POLL_INTERVAL
		"slow_down":
			return maxi(current + SLOW_DOWN_INCREMENT, stated)
		_:
			return stated if stated > 0 else maxi(1, current)


## A poll failure worth another poll: no response, rate limited, or 5xx.
## invalid_grant, 401s and other 4xx are final.
static func is_transient_poll_failure(err: InvoError) -> bool:
	return err != null and (err.status == 0 or err.status == 429 or err.status >= 500)


## confirm_device_enrollment refusals meaning the prompt was already moot
## (answered by the backup email, withdrawn, or outlived by its grant).
static func is_moot_enrollment_answer(err: InvoError) -> bool:
	return err != null and err.code in ["DEVICE_APPROVAL_ENROLLMENT_ALREADY_DECIDED",
			"DEVICE_APPROVAL_NO_ENROLLMENT_PENDING", "expired_token", "invalid_grant"]


## "app_browser" on phones (open the page in the system browser, never an
## embedded WebView), "qr" everywhere else.
static func default_channel() -> String:
	return CHANNEL_APP_BROWSER if OS.has_feature("mobile") else CHANNEL_QR


# ---- Internal ----

static func _txn_flow_problem(transaction_id: String, flow: String) -> InvoError:
	if not InvoValidate.is_present(transaction_id):
		return InvoError.invalid_input("transactionId", transaction_id, "is required")
	if not (flow in InvoMap.APPROVAL_FLOWS):
		return InvoError.invalid_input("flow", flow,
				"must be transfer, send, send_receipt or transfer_receipt")
	return null


## Device-approval routes answer RFC 8628 errors as a bare `error` token with
## no `code` (e.g. invalid_grant); promote it so callers can branch on code.
static func _with_bare_code(res: InvoResult) -> InvoResult:
	if not res.ok and res.error != null:
		res.error.promote_bare_error_token()
	return res


static func _no_token_failure() -> InvoResult:
	# Fail fast and clearly instead of sending "Bearer " to the backend.
	return InvoResult.failure(InvoError.make(
			"No player token set. Call Invo.set_player_token() with a token " +
			"your backend minted, Invo.login_via_backend(), or (sandbox) " +
			"Invo.login_sandbox().", "NO_PLAYER_TOKEN", 0))


## POST with the player token. Never auto-retried by the transport; one re-mint
## + resend on SDK_TOKEN_EXPIRED only — a token 401 is rejected before the
## route runs, so that one resend is safe even on the money calls.
func _post_with_token_retry(path: String, body: Variant) -> InvoResult:
	if not has_token():
		return _no_token_failure()
	var res: InvoResult = await _http.post_json(path, body, _auth())
	if res.ok or res.error == null or not res.error.is_token_expired() \
			or not token_provider.is_valid():
		return res
	if not await _refresh_token():
		return res
	return await _http.post_json(path, body, _auth())


func _get_with_token_retry(path: String) -> InvoResult:
	if not has_token():
		return _no_token_failure()
	var res: InvoResult = await _http.get_json(path, _auth())
	if res.ok or res.error == null or not res.error.is_token_expired() \
			or not token_provider.is_valid():
		return res
	if not await _refresh_token():
		return res
	return await _http.get_json(path, _auth())


## Single-flight refresh: concurrent expiries trigger one re-mint, and every
## waiter learns whether THAT refresh actually succeeded (a stale token still
## being present must not read as success).
func _refresh_token() -> bool:
	if _refreshing:
		while _refreshing:
			await _http.get_tree().create_timer(0.05).timeout
		return _last_refresh_ok
	_refreshing = true
	_last_refresh_ok = false
	var fresh: Variant = await token_provider.call()
	if fresh is String and not (fresh as String).is_empty():
		set_token(fresh)
		_last_refresh_ok = true
	_refreshing = false
	return _last_refresh_ok

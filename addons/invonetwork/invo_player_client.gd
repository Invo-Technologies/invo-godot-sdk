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

var _http: InvoHttp
var _token: String = ""
## Optional async Callable() -> String returning a fresh player token ("" on failure).
var token_provider: Callable = Callable()

var _refreshing: bool = false


func _init(http: InvoHttp, token: String = "") -> void:
	_http = http
	_token = token


func set_token(token: String) -> void:
	_token = token


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


func _get_with_token_retry(path: String) -> InvoResult:
	var res: InvoResult = await _http.get_json(path, _auth())
	if res.ok or res.error == null or not res.error.is_token_expired() \
			or not token_provider.is_valid():
		return res
	if not await _refresh_token():
		return res
	return await _http.get_json(path, _auth())


## Single-flight refresh: concurrent expiries trigger one re-mint.
func _refresh_token() -> bool:
	if _refreshing:
		while _refreshing:
			await _http.get_tree().create_timer(0.05).timeout
		return has_token()
	_refreshing = true
	var fresh: Variant = await token_provider.call()
	_refreshing = false
	if fresh is String and not (fresh as String).is_empty():
		_token = fresh
		return true
	return false

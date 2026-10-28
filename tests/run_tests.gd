extends SceneTree
## Headless test suite for the INVO Godot SDK.
## Run from the addon dev-host project:
##   godot --headless --script res://tests/run_tests.gd
## Exit code 0 = all passed.

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await process_frame
	_test_secure_base_url()
	_test_money_validation()
	_test_e164_validation()
	_test_error_mapping()
	_test_initiate_guardian_precedence()
	_test_claim_mapping()
	await _test_retry_on_idempotent()
	await _test_no_retry_on_non_idempotent()
	await _test_network_error_retry()
	await _test_purchase_item_validation()
	await _test_mock_insufficient_balance()
	await _test_mint_requires_token_field()
	await _test_token_refresh()
	await _test_empty_token_fast_fail()
	await _test_initiate_validation()
	await _test_claim_validation()
	await _test_confirm_payment_validation()
	await _test_by_email_redaction()
	await _test_setup_rejects_bad_override()
	_test_header_sanitization()
	_test_large_value_decimal_bug()
	_test_request_id_generation()
	_test_key_environment()
	_test_dock_checks()
	print("\n[tests] %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("  ok   %s" % test_name)
	else:
		_failed += 1
		printerr("  FAIL %s" % test_name)


func _make_http(transport: Callable) -> InvoHttp:
	var http: InvoHttp = InvoHttp.new()
	root.add_child(http)
	http.configure("https://sandbox.invo.network/sandbox")
	http.retry_base_delay = 0.01  # keep test backoff fast
	http.transport = transport
	return http


# ---- Validation ----

func _test_secure_base_url() -> void:
	_check(InvoHttp.secure_base_url_problem("https://invo.network").is_empty(),
			"https base url accepted")
	_check(not InvoHttp.secure_base_url_problem("http://invo.network").is_empty(),
			"plain http rejected")
	_check(InvoHttp.secure_base_url_problem("http://localhost:8080").is_empty(),
			"http localhost allowed for dev")
	_check(not InvoHttp.secure_base_url_problem("not a url").is_empty(),
			"garbage url rejected")


func _test_money_validation() -> void:
	_check(InvoValidate.money_problem("4.99", InvoValidate.MAX_USD_AMOUNT, "usd") == null,
			"plain decimal string accepted")
	_check(InvoValidate.money_problem(4.99, InvoValidate.MAX_USD_AMOUNT, "usd") == null,
			"float accepted")
	_check(InvoValidate.money_problem("0x10", InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"hex string rejected")
	_check(InvoValidate.money_problem("1e2", InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"scientific notation rejected")
	_check(InvoValidate.money_problem("-5", InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"negative rejected")
	_check(InvoValidate.money_problem(1000.0, InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"over max rejected")
	_check(InvoValidate.money_problem(1.999, InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"3 decimal places rejected")
	_check(InvoValidate.money_problem(true, InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"bool rejected")
	_check(InvoValidate.money_problem("4.99\n", InvoValidate.MAX_USD_AMOUNT, "usd") != null,
			"trailing newline rejected")


func _test_e164_validation() -> void:
	_check(InvoValidate.e164_problem("+15555550100", "phone") == null, "E.164 accepted")
	_check(InvoValidate.e164_problem("5555550100", "phone") != null, "national format rejected")
	_check(InvoValidate.e164_problem("+15555550100\n", "phone") != null,
			"E.164 with trailing newline rejected")
	_check(InvoValidate.e164_problem("+05555", "phone") != null, "leading zero cc rejected")


# ---- Error mapping ----

func _test_error_mapping() -> void:
	var err: InvoError = InvoError.from_response(400,
			{"error": "boom", "code": "SOME_CODE"}, "req-1")
	_check(err.code == "SOME_CODE" and err.message == "boom" and err.request_id == "req-1",
			"envelope with code mapped")
	var promoted: InvoError = InvoError.from_response(400, {"error": "rate_limited"})
	_check(promoted.code == "rate_limited", "known code-less error token promoted to code")
	var insufficient: InvoError = InvoError.from_response(400,
			{"error": "insufficient_balance", "required_amount": "9.00"})
	_check(insufficient.is_insufficient_balance(), "insufficient balance classified at 400")
	var throttle: InvoError = InvoError.from_response(429,
			{"error": "insufficient_balance_blocked", "retry_after": 30})
	_check(not throttle.is_insufficient_balance(),
			"429 abuse throttle NOT classified as insufficient balance")
	_check(is_equal_approx(throttle.retry_after_seconds(), 30.0), "retry_after surfaced")
	var cooldown: InvoError = InvoError.from_response(403,
			{"code": "PASSKEY_RECOVERY_COOLDOWN", "retry_after": "2026-07-16T00:00:00Z"})
	_check(cooldown.retry_after_at() == "2026-07-16T00:00:00Z",
			"ISO retry_after surfaced as retry_after_at")
	_check(cooldown.retry_after_seconds() < 0.0, "ISO retry_after not misread as seconds")


func _test_initiate_guardian_precedence() -> void:
	var with_guardian: Dictionary = InvoMap.to_initiate_result(
			{"transaction_id": "t1", "verification_method": "sms", "guardian_approval": {}})
	_check(with_guardian["verification_method"] == "" and with_guardian["guardian_approval"] != null,
			"guardian approval suppresses verification_method")
	var plain: Dictionary = InvoMap.to_initiate_result(
			{"transaction_id": "t2", "verification_method": "sms"})
	_check(plain["verification_method"] == "sms", "sms method kept without guardian")


func _test_claim_mapping() -> void:
	var claim: Dictionary = InvoMap.to_claim_result({
		"status": "needs_account_selection",
		"candidates": [{"player_id": 1}, {"player_id": 2}],
	})
	_check(claim["needs_account_selection"] == true and (claim["candidates"] as Array).size() == 2,
			"needs_account_selection mapped as normal result")


# ---- Transport semantics ----

func _test_retry_on_idempotent() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		if state["attempts"] < 3:
			return {"status": 429, "headers": {}, "body": {"retry_after": 0.01}}
		return {"status": 200, "headers": {}, "body": {"fine": true}})
	var res: InvoResult = await http.get_json("/x", {})
	_check(res.ok and state["attempts"] == 3, "idempotent GET retried through two 429s")
	http.queue_free()


func _test_no_retry_on_non_idempotent() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		return {"status": 500, "headers": {}, "body": {"error": "boom"}})
	var res: InvoResult = await http.post_json("/x", {}, {}, false)
	_check(not res.ok and state["attempts"] == 1,
			"non-idempotent POST never auto-retried")
	http.queue_free()


# ---- Server entry ----

func _test_purchase_item_validation() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		return {"status": 200, "headers": {}, "body": {}})
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	var res: InvoResult = await server.purchase_item(
			"req1", "p@example.com", "P", "sword", "Sword", 3, "2.00", "5.00")
	_check(not res.ok and res.error.code == "INVALID_INPUT" and state["attempts"] == 0,
			"item total != unit x qty rejected before the wire")
	var ok_res: InvoResult = await server.purchase_item(
			"req2", "p@example.com", "P", "sword", "Sword", 3, "2.00", "6.00")
	_check(not ok_res.ok and ok_res.error.code == "INVALID_RESPONSE" and state["attempts"] == 1,
			"valid item purchase reached the wire; empty body flagged INVALID_RESPONSE")
	http.queue_free()


func _test_mock_insufficient_balance() -> void:
	InvoMock.reset()
	var http: InvoHttp = _make_http(InvoMock.transport)
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	var res: InvoResult = await server.purchase_item(
			"req3", "p@example.com", "P", "castle", "Castle", 1, "9999.00", "9999.00")
	_check(not res.ok and res.error.is_insufficient_balance(),
			"mock over-balance purchase classified insufficient")
	var ok_res: InvoResult = await server.purchase_item(
			"req4", "p@example.com", "P", "sword", "Sword", 1, "10.00", "10.00")
	_check(ok_res.ok and str(ok_res.dict()["new_balance"]) == "110.00",
			"mock purchase debits balance")
	http.queue_free()


func _test_mint_requires_token_field() -> void:
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		return {"status": 200, "headers": {}, "body": {"expires_at": "soon"}})
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	var res: InvoResult = await server.mint_player_token("p@example.com")
	_check(not res.ok and res.error.code == "INVALID_RESPONSE",
			"missing token field on 2xx flagged INVALID_RESPONSE")
	http.queue_free()


func _test_network_error_retry() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		if state["attempts"] < 2:
			return {"network_error": true, "timeout": true}
		return {"status": 200, "headers": {}, "body": {"fine": true}})
	var res: InvoResult = await http.get_json("/x", {})
	_check(res.ok and state["attempts"] == 2, "network timeout retried on idempotent GET")
	var state2: Dictionary = {"attempts": 0}
	var http2: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state2["attempts"] += 1
		return {"network_error": true, "timeout": false, "message": "refused"})
	var res2: InvoResult = await http2.post_json("/x", {}, {}, false)
	_check(not res2.ok and state2["attempts"] == 1 and res2.error.status == 0,
			"network error on non-idempotent POST surfaces without retry")
	http.queue_free()
	http2.queue_free()


func _test_empty_token_fast_fail() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		return {"status": 200, "headers": {}, "body": {}})
	var client: InvoPlayerClient = InvoPlayerClient.new(http, "")
	var res: InvoResult = await client.get_balance()
	_check(not res.ok and res.error.code == "NO_PLAYER_TOKEN" and state["attempts"] == 0,
			"empty token fails fast without hitting the wire")
	http.queue_free()


func _test_initiate_validation() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		return {"status": 200, "headers": {}, "body": {"transaction_id": "t"}})
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	var bad_phone: InvoResult = await server.initiate_send(
			"r1", "P", "p@example.com", "5550100", "+15555550101", 7, "10.00")
	_check(not bad_phone.ok and bad_phone.error.code == "INVALID_INPUT"
			and state["attempts"] == 0, "initiate_send rejects non-E.164 sender phone")
	var bad_amount: InvoResult = await server.initiate_transfer(
			"r2", "P", "p@example.com", "+15555550100", "+15555550101", 7, "1e3")
	_check(not bad_amount.ok and bad_amount.error.code == "INVALID_INPUT"
			and state["attempts"] == 0, "initiate_transfer rejects non-plain-decimal amount")
	var good: InvoResult = await server.initiate_send(
			"r3", "P", "p@example.com", "+15555550100", "+15555550101", 7, "10.00")
	_check(good.ok and state["attempts"] == 1, "valid initiate reaches the wire")
	http.queue_free()


func _test_claim_validation() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		return {"status": 200, "headers": {}, "body": {"status": "claimed"}})
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	var no_code: InvoResult = await server.claim_currency("", "P", "p@example.com", "+15555550100")
	_check(not no_code.ok and no_code.error.code == "INVALID_INPUT" and state["attempts"] == 0,
			"claim_currency rejects empty claim code before the wire")
	var bad_phone: InvoResult = await server.claim_currency("CODE1", "P", "p@example.com", "5550100")
	_check(not bad_phone.ok and bad_phone.error.code == "INVALID_INPUT" and state["attempts"] == 0,
			"claim_currency rejects non-E.164 phone")
	var no_currency: InvoResult = await server.claim_transfer(
			"CODE1", "P", "p@example.com", "+15555550100", null)
	_check(not no_currency.ok and no_currency.error.code == "INVALID_INPUT"
			and state["attempts"] == 0, "claim_transfer rejects missing target currency id")
	var good: InvoResult = await server.claim_currency(
			"CODE1", "P", "p@example.com", "+15555550100")
	_check(good.ok and state["attempts"] == 1, "valid claim reaches the wire")
	http.queue_free()


func _test_confirm_payment_validation() -> void:
	var state: Dictionary = {"attempts": 0}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		state["attempts"] += 1
		return {"status": 200, "headers": {}, "body": {}})
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	var res: InvoResult = await server.confirm_payment("")
	_check(not res.ok and res.error.code == "INVALID_INPUT" and state["attempts"] == 0,
			"confirm_payment rejects empty payment_intent_id before the wire")
	http.queue_free()


func _test_by_email_redaction() -> void:
	var http: InvoHttp = _make_http(func(_m: String, _u: String, _h: Dictionary,
			_b: Variant) -> Dictionary:
		return {"status": 200, "headers": {}, "body": {"balances": []}})
	var seen: Dictionary = {"url": ""}
	http.request_completed.connect(func(_m: String, u: String, _s: int, _a: int) -> void:
		seen["url"] = u)
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "secret")
	await server.get_player_balance("secret-player@example.com")
	_check(not (seen["url"] as String).contains("secret-player")
			and (seen["url"] as String).ends_with("/by-email/<redacted>"),
			"player email redacted from the by-email path in signals")
	http.queue_free()


func _test_setup_rejects_bad_override() -> void:
	var invo: Node = (load("res://addons/invonetwork/invo.gd") as GDScript).new()
	root.add_child(invo)
	await process_frame  # let _ready configure the default sandbox environment
	invo.setup("production", "game-1")
	print("  (an ERROR about ftp:// below is expected)")
	invo.setup("sandbox", "game-2", "ftp://evil.example")
	_check(invo.environment == "production" and invo.game_id == "game-1",
			"failed setup() leaves the previous configuration intact")
	invo.queue_free()


func _test_request_id_generation() -> void:
	var a: String = InvoSandboxServer.new_client_request_id()
	var b: String = InvoSandboxServer.new_client_request_id()
	_check(a.begins_with("godot-") and a.length() == 6 + 32,
			"client request id is godot- + 32 hex chars")
	_check(a != b, "client request ids are unique")


func _test_header_sanitization() -> void:
	_check(InvoHttp.sanitize_header_value("abc\r\nX-Evil: 1") == "abcX-Evil: 1",
			"CR/LF stripped from header values")
	_check(InvoHttp.sanitize_header_value("token-ok_123") == "token-ok_123",
			"normal header value untouched")


func _test_large_value_decimal_bug() -> void:
	# Regression: relative-epsilon comparison accepted 3 decimals at large
	# magnitudes. Must be rejected at any magnitude.
	_check(InvoValidate.money_problem(999999.999, InvoValidate.MAX_ITEM_PRICE, "p") != null,
			"large-magnitude 3-decimal float rejected")
	_check(InvoValidate.money_problem(999999.99, InvoValidate.MAX_ITEM_PRICE, "p") == null,
			"max item price accepted")


func _test_token_refresh() -> void:
	var http: InvoHttp = _make_http(func(_m: String, _u: String, headers: Dictionary,
			_b: Variant) -> Dictionary:
		if str(headers.get("Authorization", "")).contains("fresh-token"):
			return {"status": 200, "headers": {}, "body": {"balances": [], "summary": {}}}
		return {"status": 401, "headers": {}, "body": {"code": "SDK_TOKEN_EXPIRED",
				"error": "expired"}})
	var client: InvoPlayerClient = InvoPlayerClient.new(http, "stale-token")
	var state: Dictionary = {"mints": 0}
	client.token_provider = func() -> String:
		state["mints"] += 1
		return "fresh-token"
	var res: InvoResult = await client.get_balance()
	_check(res.ok and state["mints"] == 1 and client.token() == "fresh-token",
			"SDK_TOKEN_EXPIRED triggers one re-mint and a retry")
	http.queue_free()


# ---- Key environments (0.4.0) ----

func _test_key_environment() -> void:
	var err: InvoError = InvoError.from_response(401, {"error": "Unauthorized", "code": "KEY_FOR_OTHER_ENVIRONMENT"})
	_check(err.is_key_for_other_environment(), "401 KEY_FOR_OTHER_ENVIRONMENT is classified")
	_check(err.message == InvoError.KEY_FOR_OTHER_ENVIRONMENT_MESSAGE, "wrong-environment key gets the clear message")
	_check(not InvoError.from_response(401, {"error": "bad key", "code": "INVALID_KEY"}).is_key_for_other_environment(),
			"other 401s are not wrong-environment")
	var dock: GDScript = load("res://addons/invonetwork/dock/invo_dock.gd")
	_check(dock.is_live_key("ivsdk_live_abc"), "ivsdk_live_ key is flagged as live")
	_check(not dock.is_live_key("ivsdk_test_abc") and not dock.is_live_key("ivsdk_abc"),
			"sandbox and older keys are not flagged as live")


# ---- Editor dock (0.4.0, same checks as the Unity settings window) ----

func _test_dock_checks() -> void:
	var dock: GDScript = load("res://addons/invonetwork/dock/invo_dock.gd")
	_check(dock.key_status("") == "Not set" and dock.key_status(" ivsdk_test_a") == "Has spaces"
			and dock.key_status("ivsdk_live_a") == "Live key" and dock.key_status("ivsdk_test_a") == "Looks valid"
			and dock.key_status("sk_123") == "Not ivsdk_", "dock key status matches the Unity labels")
	_check(dock.production_problems("42", "https://api.example.com/token", "").is_empty(),
			"complete production config has no problems")
	var problems: PackedStringArray = dock.production_problems("", "http://api.example.com", "ivsdk_test_a")
	_check(problems.size() == 3, "missing Game ID, http endpoint and saved key are all reported")
	_check(dock.describe_failure(InvoError.from_response(401, {"code": "KEY_FOR_OTHER_ENVIRONMENT"}))
			== InvoError.KEY_FOR_OTHER_ENVIRONMENT_MESSAGE, "test-connection failure explains a wrong-environment key")
	var invo: GDScript = load("res://addons/invonetwork/invo.gd")
	ProjectSettings.set_setting("invonetwork/config/game_id", "7")
	ProjectSettings.set_setting("invonetwork/config/sandbox_game_id", "")
	ProjectSettings.set_setting("invonetwork/config/production_game_id", "99")
	_check(invo.configured_game_id("sandbox") == "7", "sandbox falls back to the older single Game ID")
	_check(invo.configured_game_id("production") == "99", "production uses its own Game ID")
	ProjectSettings.set_setting("invonetwork/config/production_game_id", "")
	ProjectSettings.set_setting("invonetwork/config/game_id", "")

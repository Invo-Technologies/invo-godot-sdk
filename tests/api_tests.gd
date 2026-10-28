extends SceneTree
## Headless tests for the wallet-UI backend calls ported from the Unity SDK
## (device approval, pending actions, store catalog, player destinations,
## player phone) and their offline mock routes.
## Run from the addon dev-host project:
##   godot --headless --script res://tests/api_tests.gd
## Exit code 0 = all passed.

const BASE: String = "https://sandbox.invo.network/sandbox"

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await process_frame
	_test_static_helpers()
	_test_mapping()
	await _test_begin_device_approval()
	await _test_poll_device_approval()
	await _test_confirm_device_enrollment()
	await _test_settle_device_approval()
	await _test_post_token_refresh()
	await _test_pending_actions()
	await _test_get_game_items()
	await _test_get_player_destinations()
	await _test_change_player_phone()
	await _test_phone_change_requests()
	await _test_mock_collect_flow()
	await _test_mock_sender_flow()
	await _test_mock_enrollment_flow()
	await _test_mock_store_flow()
	await _test_mock_phone_flow()
	await _test_mock_via_autoload()
	print("\n[api_tests] %d passed, %d failed" % [_passed, _failed])
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
	http.configure(BASE)
	http.retry_base_delay = 0.01  # keep test backoff fast
	http.transport = transport
	return http


## A fake transport that records every request and answers from `responses`
## in order (the last one repeats). state = {http, calls: Array[Dictionary]}.
func _recorder(responses: Array) -> Dictionary:
	var state: Dictionary = {"calls": [], "responses": responses}
	state["http"] = _make_http(func(m: String, u: String, h: Dictionary,
			b: Variant) -> Dictionary:
		var calls: Array = state["calls"]
		calls.append({"method": m, "url": u, "headers": h, "body": b})
		var rs: Array = state["responses"]
		return rs[mini(calls.size() - 1, rs.size() - 1)])
	return state


func _resp(status: int, body: Variant) -> Dictionary:
	return {"status": status, "headers": {}, "body": body}


func _last(state: Dictionary) -> Dictionary:
	var calls: Array = state["calls"]
	return calls[calls.size() - 1] if not calls.is_empty() else {}


func _calls(state: Dictionary) -> int:
	return (state["calls"] as Array).size()


func _is_player_auth(call: Dictionary, token: String) -> bool:
	var h: Dictionary = call.get("headers", {})
	return h.get("Authorization") == "Bearer %s" % token and not h.has("X-Game-Secret-Key")


func _is_secret_auth(call: Dictionary, secret: String) -> bool:
	var h: Dictionary = call.get("headers", {})
	return h.get("X-Game-Secret-Key") == secret and not h.has("Authorization")


func _free(state: Dictionary) -> void:
	(state["http"] as InvoHttp).queue_free()


# ---- Pure helpers ----

func _test_static_helpers() -> void:
	_check(InvoPlayerClient.settle_path("t 1", "transfer") == "/api/sdk/transfers/t%201/approve"
			and InvoPlayerClient.settle_path("t1", "send") == "/api/sdk/send/t1/approve"
			and InvoPlayerClient.settle_path("t1", "send_receipt") == "/api/sdk/send/t1/confirm-receipt"
			and InvoPlayerClient.settle_path("t1", "transfer_receipt")
					== "/api/sdk/transfers/t1/confirm-receipt",
			"settle path routed by flow, transaction id url-encoded")
	_check(InvoPlayerClient.is_past_step("transfer", "pending_claim")
			and InvoPlayerClient.is_past_step("send", "COMPLETED")
			and not InvoPlayerClient.is_past_step("send_receipt", "pending_claim")
			and InvoPlayerClient.is_past_step("transfer_receipt", "distributed")
			and not InvoPlayerClient.is_past_step("transfer", "some_new_status")
			and not InvoPlayerClient.is_past_step("send", ""),
			"is_past_step: sender past at pending_claim, receipts only at completed, fail closed")
	_check(InvoPlayerClient.next_poll_interval(0, "", 0) == 5
			and InvoPlayerClient.next_poll_interval(0, "", 3) == 3
			and InvoPlayerClient.next_poll_interval(5, "slow_down", 0) == 10
			and InvoPlayerClient.next_poll_interval(5, "slow_down", 15) == 15
			and InvoPlayerClient.next_poll_interval(5, "authorization_pending", 7) == 7
			and InvoPlayerClient.next_poll_interval(4, "authorization_pending", 0) == 4,
			"next_poll_interval follows RFC 8628 (default 5, +5 on slow_down)")
	_check(InvoPlayerClient.is_transient_poll_failure(InvoError.make("x", "", 0))
			and InvoPlayerClient.is_transient_poll_failure(InvoError.make("x", "", 429))
			and InvoPlayerClient.is_transient_poll_failure(InvoError.make("x", "", 503))
			and not InvoPlayerClient.is_transient_poll_failure(InvoError.make("x", "invalid_grant", 400)),
			"transient poll failures: network, 429, 5xx only")
	_check(InvoPlayerClient.is_moot_enrollment_answer(
				InvoError.make("x", "DEVICE_APPROVAL_ENROLLMENT_ALREADY_DECIDED", 409))
			and not InvoPlayerClient.is_moot_enrollment_answer(InvoError.make("x", "OTHER", 409)),
			"moot enrollment answers recognised")
	_check(InvoPlayerClient.default_channel() == "qr", "desktop default channel is qr")
	_check(InvoMap.mask_phone_short("+15555550111") == "••• 0111"
			and InvoMap.mask_phone_short("") == "" and InvoMap.mask_phone_short("12") == "•••",
			"mask_phone_short shows last four digits only")
	var promoted: InvoError = InvoError.from_response(404, {"error": "player_not_found"})
	promoted.promote_bare_error_token()
	var sentence: InvoError = InvoError.from_response(400, {"error": "Something went wrong."})
	sentence.promote_bare_error_token()
	_check(promoted.code == "player_not_found" and sentence.code.is_empty(),
			"bare error token promoted to code; a sentence is not")
	_check(InvoError.from_response(409, {"code": "PHONE_CHANGE_REQUIRES_VERIFICATION"})
					.is_phone_change_requires_verification()
			and InvoError.from_response(409, {"code": "DEVICE_APPROVAL_ALREADY_PENDING"})
					.is_device_approval_already_pending()
			and InvoError.from_response(429, {"error": "slow"}).is_rate_limited(),
			"new InvoError classifiers")


func _test_mapping() -> void:
	var init: Dictionary = InvoMap.to_initiate_result(
			{"status": "pending_guardian_approval", "transaction_id": "t", "guardian_approval": {}})
	_check(init["status"] == "pending_guardian_approval", "initiate result exposes status")
	var st: Dictionary = InvoMap.to_transaction_status({"verification_state": "approved",
			"claim_code": "C1", "claim_code_expires_at": "z"})
	_check(st["claim_code"] == "C1" and st["claim_code_expires_at"] == "z",
			"transaction status exposes claim_code")
	var item: Dictionary = InvoMap.to_game_item({"item_id": "a", "price_usd": "4.99",
			"original_price_usd": 9.99, "discount_percentage": 50, "is_featured": true})
	_check(is_equal_approx(float(item["price_usd"]), 4.99) and item["is_discounted"]
			and item["discount_percentage"] == 50 and item["time_remaining_seconds"] == null
			and item["metadata"] is Dictionary, "game item mapped (string price, discount)")
	var plain: Dictionary = InvoMap.to_game_item({"item_id": "b", "price_usd": 1.0})
	_check(plain["original_price_usd"] == null and not plain["is_discounted"]
			and plain["discount_percentage"] == null and plain["is_active"],
			"game item without discount: original null, not discounted")


# ---- Player token: device approval ----

func _test_begin_device_approval() -> void:
	var rec: Dictionary = _recorder([_resp(200, {
		"device_code": "dc-1", "user_code": "ABCD-EFGH",
		"verification_uri": "https://invo.network/device",
		"verification_uri_complete": "https://invo.network/device?code=ABCD-EFGH",
		"expires_in": 600, "interval": 5, "channel": "qr"})])
	var client: InvoPlayerClient = InvoPlayerClient.new(rec["http"], "tok")
	var res: InvoResult = await client.begin_device_approval("txn-1", "send")
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST" and call.get("url") == BASE + "/api/sdk/approvals/device/begin",
			"begin: POST /api/sdk/approvals/device/begin")
	_check(call.get("body") == {"transaction_id": "txn-1", "flow": "send", "channel": "qr"},
			"begin: body {transaction_id, flow, channel}")
	_check(_is_player_auth(call, "tok"), "begin: player-token auth, no game secret")
	_check(res.ok and res.dict()["device_code"] == "dc-1" and res.dict()["interval"] == 5
			and res.dict()["user_code"] == "ABCD-EFGH" and res.dict()["expires_in"] == 600,
			"begin: grant mapped")
	var bad_flow: InvoResult = await client.begin_device_approval("txn-1", "refund")
	var bad_channel: InvoResult = await client.begin_device_approval("txn-1", "send", "popup")
	var no_txn: InvoResult = await client.begin_device_approval(" ", "send")
	_check(not bad_flow.ok and bad_flow.error.code == "INVALID_INPUT"
			and not bad_channel.ok and bad_channel.error.code == "INVALID_INPUT"
			and not no_txn.ok and no_txn.error.code == "INVALID_INPUT" and _calls(rec) == 1,
			"begin: bad flow/channel/txn rejected before the wire")
	var no_token: InvoPlayerClient = InvoPlayerClient.new(rec["http"], "")
	var nt: InvoResult = await no_token.begin_device_approval("txn-1", "send")
	_check(not nt.ok and nt.error.code == "NO_PLAYER_TOKEN" and _calls(rec) == 1,
			"begin: no token fails fast")
	_free(rec)

	var partial: Dictionary = _recorder([_resp(200, {"user_code": "X"})])
	var c2: InvoPlayerClient = InvoPlayerClient.new(partial["http"], "tok")
	var incomplete: InvoResult = await c2.begin_device_approval("txn-1", "transfer", "app_browser")
	_check(not incomplete.ok and incomplete.error.code == "INVALID_RESPONSE"
			and (_last(partial)["body"] as Dictionary)["channel"] == "app_browser",
			"begin: grant without device_code flagged INVALID_RESPONSE")
	_free(partial)

	var busy: Dictionary = _recorder([_resp(409, {"error": "already in progress",
			"code": "DEVICE_APPROVAL_ALREADY_PENDING", "expires_at": "z"})])
	var c3: InvoPlayerClient = InvoPlayerClient.new(busy["http"], "tok")
	var dup: InvoResult = await c3.begin_device_approval("txn-1", "transfer")
	_check(not dup.ok and dup.error.is_device_approval_already_pending() and _calls(busy) == 1,
			"begin: 409 DEVICE_APPROVAL_ALREADY_PENDING surfaced, not retried")
	_free(busy)


func _test_poll_device_approval() -> void:
	var rec: Dictionary = _recorder([
		_resp(400, {"error": "authorization_pending", "interval": 5, "enrollment": {
			"state": "awaiting_screen", "device_label": "Pixel 9", "match_code": "1234",
			"requested_at": "t", "recovery": true}}),
		_resp(400, {"error": "slow_down", "interval": 10}),
		_resp(200, {"status": "approved", "transaction_id": "txn-1", "flow": "send",
			"approved_at": "t2"}),
	])
	var client: InvoPlayerClient = InvoPlayerClient.new(rec["http"], "tok")
	var p1: InvoResult = await client.poll_device_approval("dc-1")
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST" and call.get("url") == BASE + "/api/sdk/approvals/device/poll"
			and call.get("body") == {"device_code": "dc-1"} and _is_player_auth(call, "tok"),
			"poll: POST /api/sdk/approvals/device/poll {device_code} with player token")
	var enrol: Variant = p1.dict().get("enrollment")
	_check(p1.ok and p1.dict()["status"] == "authorization_pending" and p1.dict()["interval"] == 5
			and enrol is Dictionary and (enrol as Dictionary)["match_code"] == "1234"
			and (enrol as Dictionary)["recovery"] == true,
			"poll: 400 authorization_pending is a result, enrollment block mapped")
	var p2: InvoResult = await client.poll_device_approval("dc-1")
	_check(p2.ok and p2.dict()["status"] == "slow_down" and p2.dict()["interval"] == 10,
			"poll: 400 slow_down is a result with the new interval")
	var p3: InvoResult = await client.poll_device_approval("dc-1")
	_check(p3.ok and p3.dict()["status"] == "approved" and p3.dict()["transaction_id"] == "txn-1"
			and p3.dict()["enrollment"] == null, "poll: approved mapped")
	_free(rec)

	var ends: Dictionary = _recorder([
		_resp(400, {"error": "access_denied"}),
		_resp(400, {"error": "expired_token"}),
		_resp(400, {"error": "invalid_grant"}),
		_resp(200, {"transaction_id": "txn-1"}),
	])
	var c2: InvoPlayerClient = InvoPlayerClient.new(ends["http"], "tok")
	var denied: InvoResult = await c2.poll_device_approval("dc-1")
	var expired: InvoResult = await c2.poll_device_approval("dc-1")
	var invalid: InvoResult = await c2.poll_device_approval("dc-1")
	var no_status: InvoResult = await c2.poll_device_approval("dc-1")
	_check(denied.ok and denied.dict()["status"] == "access_denied"
			and expired.ok and expired.dict()["status"] == "expired_token",
			"poll: access_denied / expired_token are results")
	_check(not invalid.ok and invalid.error.code == "invalid_grant" and invalid.error.status == 400,
			"poll: invalid_grant is an error with code promoted")
	_check(no_status.ok and no_status.dict()["status"] == "approved",
			"poll: 200 without status reads as approved")
	_free(ends)

	var flaky: Dictionary = _recorder([_resp(503, {"error": "down"})])
	var c3: InvoPlayerClient = InvoPlayerClient.new(flaky["http"], "tok")
	var down: InvoResult = await c3.poll_device_approval("dc-1")
	_check(not down.ok and _calls(flaky) == 1 and InvoPlayerClient.is_transient_poll_failure(down.error),
			"poll: 5xx not auto-retried by transport; classified transient for the loop")
	var empty: InvoResult = await c3.poll_device_approval("")
	_check(not empty.ok and empty.error.code == "INVALID_INPUT" and _calls(flaky) == 1
			and not empty.error.message.contains("dc-"), "poll: empty device code rejected")
	_free(flaky)


func _test_confirm_device_enrollment() -> void:
	var rec: Dictionary = _recorder([_resp(200, {"status": "confirmed"}),
			_resp(200, {"status": "denied"}),
			_resp(409, {"error": "already decided", "code": "DEVICE_APPROVAL_ENROLLMENT_ALREADY_DECIDED"})])
	var client: InvoPlayerClient = InvoPlayerClient.new(rec["http"], "tok")
	var yes: InvoResult = await client.confirm_device_enrollment("dc-1", true)
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST"
			and call.get("url") == BASE + "/api/sdk/approvals/device/confirm-enrollment"
			and call.get("body") == {"device_code": "dc-1", "decision": "approve"}
			and _is_player_auth(call, "tok") and yes.ok and yes.dict()["status"] == "confirmed",
			"confirm-enrollment: approve body, player token, status mapped")
	var no: InvoResult = await client.confirm_device_enrollment("dc-1", false)
	_check((_last(rec)["body"] as Dictionary)["decision"] == "deny" and no.dict()["status"] == "denied",
			"confirm-enrollment: deny body")
	var moot: InvoResult = await client.confirm_device_enrollment("dc-1", true)
	_check(not moot.ok and InvoPlayerClient.is_moot_enrollment_answer(moot.error) and _calls(rec) == 3,
			"confirm-enrollment: already-decided is a moot answer, not retried")
	_free(rec)


func _test_settle_device_approval() -> void:
	var rec: Dictionary = _recorder([
		_resp(200, {"status": "approved", "next": "pending_claim", "transaction_id": "t1",
			"claim_code": "CLAIM1", "claim_code_expires_at": "z"}),
		_resp(200, {"status": "approved", "next": "pending_claim", "transaction_id": "t1"}),
		_resp(200, {"status": "completed", "transaction_id": "t1", "amount_received": "24.50"}),
		_resp(202, {"status": "pending_guardian_approval", "error_code": "GUARDIAN_APPROVAL_PENDING",
			"guardian_approval": {"approval_id": "g1", "state": "pending"}}),
	])
	var client: InvoPlayerClient = InvoPlayerClient.new(rec["http"], "tok")
	var transfer: InvoResult = await client.settle_device_approval("t1", "transfer", "dc-1")
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST" and call.get("url") == BASE + "/api/sdk/transfers/t1/approve"
			and call.get("body") == {"device_code": "dc-1"} and _is_player_auth(call, "tok"),
			"settle transfer: POST /api/sdk/transfers/{id}/approve {device_code}")
	_check(transfer.ok and transfer.dict()["status"] == "approved"
			and transfer.dict()["claim_code"] == "CLAIM1" and not transfer.dict()["is_hold"],
			"settle transfer: claim_code mapped")
	var send: InvoResult = await client.settle_device_approval("t1", "send", "dc-1")
	_check(_last(rec)["url"] == BASE + "/api/sdk/send/t1/approve" and send.dict()["next"] == "pending_claim",
			"settle send: /api/sdk/send/{id}/approve")
	var receipt: InvoResult = await client.settle_device_approval("t1", "send_receipt", "dc-1")
	_check(_last(rec)["url"] == BASE + "/api/sdk/send/t1/confirm-receipt"
			and receipt.dict()["status"] == "completed" and receipt.dict()["amount_received"] == "24.50",
			"settle send_receipt: confirm-receipt, amount_received mapped")
	var hold: InvoResult = await client.settle_device_approval("t1", "transfer_receipt", "dc-1")
	_check(_last(rec)["url"] == BASE + "/api/sdk/transfers/t1/confirm-receipt"
			and hold.ok and hold.dict()["is_hold"] and hold.dict()["hold_reason"] == "GUARDIAN_APPROVAL_PENDING"
			and (hold.dict()["guardian_approval"] as Dictionary)["approval_id"] == "g1",
			"settle transfer_receipt: 202 hold is a success with is_hold + hold_reason")
	_free(rec)

	var done: Dictionary = _recorder([_resp(400, {"status": "error", "message": "not pending",
			"code": "TRANSACTION_NOT_PENDING", "current_status": "pending_claim"})])
	var c2: InvoPlayerClient = InvoPlayerClient.new(done["http"], "tok")
	var past: InvoResult = await c2.settle_device_approval("t1", "transfer", "dc-1")
	var early: InvoResult = await c2.settle_device_approval("t1", "send_receipt", "dc-1")
	_check(past.ok and past.dict()["status"] == "not_pending" and past.dict()["already_settled"]
			and past.dict()["current_status"] == "pending_claim" and past.dict()["transaction_id"] == "t1",
			"settle: TRANSACTION_NOT_PENDING past this step -> not_pending, already_settled")
	_check(early.ok and early.dict()["status"] == "not_pending" and not early.dict()["already_settled"],
			"settle: receipt landing on pending_claim is NOT already settled (fail closed)")
	_free(done)

	var boom: Dictionary = _recorder([_resp(500, {"error": "could not approve"})])
	var c3: InvoPlayerClient = InvoPlayerClient.new(boom["http"], "tok")
	var failed: InvoResult = await c3.settle_device_approval("t1", "send", "dc-1")
	_check(not failed.ok and failed.error.status == 500 and _calls(boom) == 1,
			"settle: 5xx surfaced and NEVER auto-retried (single-use device code)")
	var bad: InvoResult = await c3.settle_device_approval("t1", "send", "")
	var bad_flow: InvoResult = await c3.settle_device_approval("t1", "withdraw", "dc-1")
	_check(not bad.ok and not bad_flow.ok and _calls(boom) == 1, "settle: inputs validated before the wire")
	_free(boom)


func _test_post_token_refresh() -> void:
	var state: Dictionary = {"tokens": []}
	var http: InvoHttp = _make_http(func(_m: String, _u: String, headers: Dictionary,
			_b: Variant) -> Dictionary:
		(state["tokens"] as Array).append(str(headers.get("Authorization", "")))
		if str(headers.get("Authorization", "")).contains("fresh-token"):
			return _resp(200, {"status": "completed", "transaction_id": "t1", "amount_received": "1.00"})
		return _resp(401, {"code": "SDK_TOKEN_EXPIRED", "error": "expired"}))
	var client: InvoPlayerClient = InvoPlayerClient.new(http, "stale-token")
	var mints: Dictionary = {"n": 0}
	client.token_provider = func() -> String:
		mints["n"] += 1
		return "fresh-token"
	var res: InvoResult = await client.settle_device_approval("t1", "send_receipt", "dc-1")
	_check(res.ok and mints["n"] == 1 and (state["tokens"] as Array).size() == 2,
			"POST SDK_TOKEN_EXPIRED: one re-mint and one resend")
	http.queue_free()


func _test_pending_actions() -> void:
	var rec: Dictionary = _recorder([_resp(200, {"pending": [
		{"transfer_id": "a", "kind": "identity_gate", "flow": "transfer", "amount": "5.00"},
		{"transfer_id": "b", "kind": "receiving_confirm", "flow": "transfer", "amount": "4.00",
			"currency": "Gold", "counterparty_game": "Other"},
		{"transfer_id": "c", "kind": "receiving_confirm", "flow": "send", "held": true,
			"hold_reason": "device_requires_elevation"},
		{"transfer_id": "d", "kind": "identity_gate", "flow": "send"},
		"junk",
	]})])
	var client: InvoPlayerClient = InvoPlayerClient.new(rec["http"], "tok")
	var res: InvoResult = await client.get_pending_actions()
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "GET" and call.get("url") == BASE + "/api/sdk/transfers/pending"
			and call.get("body") == null and _is_player_auth(call, "tok"),
			"pending: GET /api/sdk/transfers/pending with player token")
	var rows: Array = res.dict().get("pending", [])
	_check(res.ok and rows.size() == 4, "pending: rows mapped, junk skipped")
	if rows.size() == 4:
		_check(rows[0]["approval_flow"] == "transfer" and rows[1]["approval_flow"] == "transfer_receipt"
				and rows[2]["approval_flow"] == "send_receipt" and rows[3]["approval_flow"] == "send",
				"pending: approval_flow derived from kind + flow")
		_check(rows[1]["counterparty_game"] == "Other" and rows[1]["currency"] == "Gold"
				and rows[2]["held"] and rows[2]["hold_reason"] == "device_requires_elevation",
				"pending: display + hold fields mapped")
	_check((res.dict()["receivable"] as Array).size() == 2 and res.dict()["ready_count"] == 1,
			"pending: receivable = receiving_confirm rows; ready_count excludes held")
	_free(rec)


# ---- Game secret (sandbox) ----

func _test_get_game_items() -> void:
	var rec: Dictionary = _recorder([_resp(200, {"status": "success", "total_items": 4, "items": [
		{"item_id": "w1", "item_category": "weekly", "price_usd": 1.0},
		{"item_id": "hero", "item_category": "weekly", "is_featured": true, "price_usd": 9.99,
			"original_price_usd": 14.99},
		{"item_id": "d1", "item_category": "Daily", "price_usd": 0.99,
			"is_limited_time": true, "time_remaining_seconds": 60, "time_remaining_display": "1m"},
		{"item_id": "s1", "item_category": "standard", "price_usd": 2.0},
	]})])
	var server: InvoSandboxServer = InvoSandboxServer.new(rec["http"], "ivsdk_test_secret")
	var res: InvoResult = await server.get_game_items()
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST" and call.get("url") == BASE + "/api/v1/game-items/list"
			and call.get("body") == {"game_secret": "ivsdk_test_secret"}
			and _is_secret_auth(call, "ivsdk_test_secret"),
			"game items: POST /api/v1/game-items/list, secret in body (route reads it there)")
	var d: Dictionary = res.dict()
	_check(res.ok and (d["items"] as Array).size() == 4 and d["total_items"] == 4,
			"game items: all items mapped")
	_check(d["featured"] is Dictionary and (d["featured"] as Dictionary)["item_id"] == "hero"
			and (d["featured"] as Dictionary)["is_discounted"],
			"game items: featured = first is_featured")
	_check((d["weekly"] as Array).size() == 1 and (d["weekly"] as Array)[0]["item_id"] == "w1",
			"game items: weekly excludes the hero")
	_check((d["daily"] as Array).size() == 1 and (d["daily"] as Array)[0]["time_remaining_seconds"] == 60,
			"game items: daily split case-insensitively, time remaining mapped")
	_free(rec)

	var retry: Dictionary = _recorder([_resp(503, {"error": "busy"}), _resp(200, {"items": []})])
	var s2: InvoSandboxServer = InvoSandboxServer.new(retry["http"], "s")
	var r2: InvoResult = await s2.get_game_items()
	_check(r2.ok and _calls(retry) == 2 and r2.dict()["featured"] == null,
			"game items: idempotent read retried on 5xx; no featured -> null")
	_free(retry)


func _test_get_player_destinations() -> void:
	var rec: Dictionary = _recorder([_resp(200, {"status": "success", "source_game_id": "1",
		"transfer_mode": "universal", "destinations": [{"game_id": "7", "game_name": "Starfall",
			"default_currency": {"currency_id": 3, "currency_name": "Shards", "currency_symbol": "SH"},
			"available_balance": "42.00", "last_active": "t"}]})])
	var server: InvoSandboxServer = InvoSandboxServer.new(rec["http"], "sec")
	var res: InvoResult = await server.get_player_destinations("p@example.com", "+15555550100")
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST" and call.get("url") == BASE + "/api/players/destinations"
			and call.get("body") == {"email": "p@example.com", "phone": "+15555550100"}
			and _is_secret_auth(call, "sec"),
			"player destinations: POST /api/players/destinations {email, phone} with game secret")
	var rows: Array = res.dict().get("destinations", [])
	_check(res.ok and rows.size() == 1 and rows[0]["available_balance"] == "42.00"
			and (rows[0]["default_currency"] as Dictionary)["currency_name"] == "Shards"
			and res.dict()["transfer_mode"] == "universal", "player destinations: mapped")
	var bad_phone: InvoResult = await server.get_player_destinations("p@example.com", "5550100")
	var no_email: InvoResult = await server.get_player_destinations("", "+15555550100")
	_check(not bad_phone.ok and not no_email.ok and _calls(rec) == 1,
			"player destinations: email + E.164 phone validated before the wire")
	_free(rec)


func _test_change_player_phone() -> void:
	var rec: Dictionary = _recorder([
		_resp(200, {"status": "updated", "identity_rekeyed": true, "identity_id": "id2",
			"player_token": "tok2", "player_token_expires_at": "z"}),
		_resp(409, {"error": "secured", "code": "PHONE_CHANGE_REQUIRES_VERIFICATION",
			"change_request_endpoint": "/api/sdk/players/phone/change-requests"}),
		_resp(404, {"error": "player_not_found"}),
	])
	var server: InvoSandboxServer = InvoSandboxServer.new(rec["http"], "sec")
	var res: InvoResult = await server.change_player_phone("p@example.com", "+15555550111")
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST" and call.get("url") == BASE + "/api/sdk/players/phone"
			and call.get("body") == {"player_email": "p@example.com", "new_phone": "+15555550111"}
			and _is_secret_auth(call, "sec"),
			"change phone: POST /api/sdk/players/phone {player_email, new_phone} with game secret")
	_check(res.ok and res.dict()["identity_rekeyed"] and res.dict()["player_token"] == "tok2",
			"change phone: re-keyed token mapped")
	var secured: InvoResult = await server.change_player_phone("p@example.com", "+15555550111")
	_check(not secured.ok and secured.error.is_phone_change_requires_verification(),
			"change phone: 409 PHONE_CHANGE_REQUIRES_VERIFICATION classified")
	var missing: InvoResult = await server.change_player_phone("p@example.com", "+15555550111")
	_check(not missing.ok and missing.error.code == "player_not_found" and _calls(rec) == 3,
			"change phone: bare player_not_found promoted to code; never retried")
	var bad: InvoResult = await server.change_player_phone("p@example.com", "555-0111")
	_check(not bad.ok and bad.error.code == "INVALID_INPUT" and _calls(rec) == 3,
			"change phone: non-E.164 rejected before the wire")
	_free(rec)


func _test_phone_change_requests() -> void:
	var rec: Dictionary = _recorder([
		_resp(202, {"change_request_id": "pcr-1", "status": "pending_confirmation",
			"expires_at": "z", "delivery": "email", "confirmation": "email_code", "message": "m"}),
		_resp(200, {"change_request_id": "pcr/1", "status": "confirmed",
			"new_phone_masked": "***-***-0111", "confirmed_via": "email_code"}),
		_resp(202, {"status": "pending_confirmation"}),
	])
	var server: InvoSandboxServer = InvoSandboxServer.new(rec["http"], "sec")
	var created: InvoResult = await server.create_phone_change_request("p@example.com", "+15555550111")
	var call: Dictionary = _last(rec)
	_check(call.get("method") == "POST"
			and call.get("url") == BASE + "/api/sdk/players/phone/change-requests"
			and call.get("body") == {"player_email": "p@example.com", "new_phone": "+15555550111"}
			and _is_secret_auth(call, "sec"),
			"change request: POST /api/sdk/players/phone/change-requests with game secret")
	_check(created.ok and created.dict()["change_request_id"] == "pcr-1" and created.dict()["is_pending"]
			and created.dict()["delivery"] == "email", "change request: 202 mapped as pending")
	var status: InvoResult = await server.get_phone_change_request("pcr/1")
	call = _last(rec)
	_check(call.get("method") == "GET"
			and call.get("url") == BASE + "/api/sdk/players/phone/change-requests/pcr%2F1"
			and _is_secret_auth(call, "sec"), "change request status: GET .../change-requests/{id} (encoded)")
	_check(status.ok and status.dict()["is_confirmed"] and not status.dict()["is_pending"]
			and status.dict()["new_phone_masked"] == "***-***-0111", "change request status: mapped")
	var no_id: InvoResult = await server.create_phone_change_request("p@example.com", "+15555550111")
	_check(not no_id.ok and no_id.error.code == "INVALID_RESPONSE",
			"change request: missing change_request_id flagged INVALID_RESPONSE")
	var blank: InvoResult = await server.get_phone_change_request("")
	_check(not blank.ok and blank.error.code == "INVALID_INPUT" and _calls(rec) == 3,
			"change request status: blank id rejected before the wire")
	_free(rec)


# ---- Mock-mode flows ----

func _test_mock_collect_flow() -> void:
	InvoMock.reset()
	var http: InvoHttp = _make_http(InvoMock.transport)
	var client: InvoPlayerClient = InvoPlayerClient.new(http, "mock-player-token")
	var pending: InvoResult = await client.get_pending_actions()
	var receivable: Array = pending.dict().get("receivable", [])
	_check(pending.ok and receivable.size() == 3 and pending.dict()["ready_count"] == 2,
			"mock: three pending collect items, one held")
	var legacy: InvoResult = await client.get_pending_collect()
	_check(legacy.ok and str((legacy.dict()["pending"] as Array)[0].get("source_game", "")) == "Starfall Arena",
			"mock: legacy get_pending_collect rows still carry source_game")
	var item: Dictionary = receivable[0]
	var grant: InvoResult = await client.begin_device_approval(item["transfer_id"], item["approval_flow"])
	_check(grant.ok and str(grant.dict()["verification_uri_complete"]).begins_with("https://")
			and grant.dict()["interval"] > 0, "mock: begin returns a grant")
	var code: String = grant.dict()["device_code"]
	var p1: InvoResult = await client.poll_device_approval(code)
	_check(p1.ok and p1.dict()["status"] == "authorization_pending", "mock: first poll pending")
	var early: InvoResult = await client.settle_device_approval(item["transfer_id"], item["approval_flow"], code)
	_check(not early.ok and early.error.code == "invalid_grant", "mock: settle before approval refused")
	var p2: InvoResult = await client.poll_device_approval(code)
	_check(p2.ok and p2.dict()["status"] == "approved", "mock: second poll approved")
	var settle: InvoResult = await client.settle_device_approval(item["transfer_id"], item["approval_flow"], code)
	_check(settle.ok and settle.dict()["status"] == "completed" and settle.dict()["amount_received"] == "25.00",
			"mock: collect settles completed with amount_received")
	var balance: InvoResult = await client.get_balance()
	_check(str((balance.dict()["balances"] as Array)[0]["available_balance"]) == "145.00",
			"mock: collect credits the balance")
	var after: InvoResult = await client.get_pending_actions()
	_check((after.dict()["receivable"] as Array).size() == 2, "mock: collected item leaves the pending list")
	var again: InvoResult = await client.settle_device_approval(item["transfer_id"], item["approval_flow"], code)
	_check(again.ok and again.dict()["status"] == "not_pending" and again.dict()["already_settled"],
			"mock: repeat settle answers not_pending, already settled")
	var bogus: InvoResult = await client.poll_device_approval("nope")
	_check(not bogus.ok and bogus.error.code == "invalid_grant", "mock: unknown device code -> invalid_grant")
	http.queue_free()


func _test_mock_sender_flow() -> void:
	InvoMock.reset()
	var http: InvoHttp = _make_http(InvoMock.transport)
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "mock-secret")
	var client: InvoPlayerClient = InvoPlayerClient.new(http, "mock-player-token")
	var init: InvoResult = await server.initiate_transfer(InvoSandboxServer.new_client_request_id(),
			"P", "p@example.com", "+15555550100", "+15555550100", 7, "10.00")
	_check(init.ok and init.dict()["status"] == "success", "mock: initiate transfer status success")
	var txn: String = init.dict()["transaction_id"]
	var grant: InvoResult = await client.begin_device_approval(txn, "transfer")
	var code: String = grant.dict()["device_code"]
	await client.poll_device_approval(code)
	await client.poll_device_approval(code)
	var settle: InvoResult = await client.settle_device_approval(txn, "transfer", code)
	_check(settle.ok and settle.dict()["status"] == "approved" and settle.dict()["claim_code"] == "MOCKCLAIM1",
			"mock: transfer approve returns the self-claim code")
	var status: InvoResult = await server.get_transfer_status(txn)
	_check(status.ok and status.dict()["verification_state"] == "approved"
			and status.dict()["claim_code"] == "MOCKCLAIM1", "mock: status reads approved after settle")
	var wrong_flow: InvoResult = await client.settle_device_approval(txn, "send", code)
	_check(not wrong_flow.ok, "mock: grant only settles its own flow")
	http.queue_free()


func _test_mock_enrollment_flow() -> void:
	InvoMock.reset()
	InvoMock.enrollment_prompt = true
	var http: InvoHttp = _make_http(InvoMock.transport)
	var client: InvoPlayerClient = InvoPlayerClient.new(http, "mock-player-token")
	var grant: InvoResult = await client.begin_device_approval("mock-out-txn", "send")
	var code: String = grant.dict()["device_code"]
	var p1: InvoResult = await client.poll_device_approval(code)
	var enrol: Variant = p1.dict().get("enrollment")
	_check(enrol is Dictionary and (enrol as Dictionary)["state"] == "awaiting_screen"
			and not str((enrol as Dictionary)["match_code"]).is_empty(),
			"mock: pending poll carries the enrollment prompt")
	var deny: InvoResult = await client.confirm_device_enrollment(code, false)
	_check(deny.ok and deny.dict()["status"] == "denied", "mock: enrollment denied on screen")
	var twice: InvoResult = await client.confirm_device_enrollment(code, true)
	_check(not twice.ok and InvoPlayerClient.is_moot_enrollment_answer(twice.error),
			"mock: second answer is moot")
	var p2: InvoResult = await client.poll_device_approval(code)
	_check(p2.ok and p2.dict()["status"] == "access_denied", "mock: denied enrollment ends the grant")
	InvoMock.reset()
	var g2: InvoResult = await client.begin_device_approval("mock-out-txn", "send")
	var none: InvoResult = await client.confirm_device_enrollment(g2.dict()["device_code"], true)
	_check(not none.ok and none.error.code == "DEVICE_APPROVAL_NO_ENROLLMENT_PENDING",
			"mock: no prompt pending -> DEVICE_APPROVAL_NO_ENROLLMENT_PENDING")
	http.queue_free()


func _test_mock_store_flow() -> void:
	InvoMock.reset()
	var http: InvoHttp = _make_http(InvoMock.transport)
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "mock-secret")
	var items: InvoResult = await server.get_game_items()
	var d: Dictionary = items.dict()
	_check(items.ok and d["featured"] is Dictionary and (d["weekly"] as Array).size() == 2
			and (d["daily"] as Array).size() == 2, "mock: catalog has featured, weekly and daily items")
	var hero: Dictionary = d["featured"]
	_check(hero["original_price_usd"] != null and hero["is_discounted"]
			and (d["daily"] as Array)[0]["is_limited_time"]
			and str((d["daily"] as Array)[0]["time_remaining_display"]) != "",
			"mock: prices with original prices; daily deals are limited-time")
	var unit: String = "%.2f" % float(hero["price_usd"])
	var bought: InvoResult = await server.purchase_item(InvoSandboxServer.new_client_request_id(),
			"p@example.com", "P", hero["item_id"], hero["item_name"], 1, unit, unit)
	_check(bought.ok and bought.dict()["status"] == "success" and bought.dict()["new_balance"] == "70.01",
			"mock: buying the featured item debits its price")
	var dests: InvoResult = await server.get_player_destinations("p@example.com", "+15555550100")
	_check(dests.ok and (dests.dict()["destinations"] as Array).size() == 2,
			"mock: games-you-play destinations")
	http.queue_free()


func _test_mock_phone_flow() -> void:
	InvoMock.reset()
	var http: InvoHttp = _make_http(InvoMock.transport)
	var server: InvoSandboxServer = InvoSandboxServer.new(http, "mock-secret")
	_check(InvoMap.mask_phone_short(InvoMock.current_phone()) == "••• 0111",
			"mock: current phone shows masked last four")
	var direct: InvoResult = await server.change_player_phone("p@example.com", "+15555550199")
	_check(not direct.ok and direct.error.is_phone_change_requires_verification(),
			"mock: secured account answers PHONE_CHANGE_REQUIRES_VERIFICATION")
	var req: InvoResult = await server.create_phone_change_request("p@example.com", "+15555550199")
	_check(req.ok and req.dict()["is_pending"], "mock: change request created pending")
	var id: String = req.dict()["change_request_id"]
	var s1: InvoResult = await server.get_phone_change_request(id)
	_check(s1.ok and s1.dict()["is_pending"] and s1.dict()["new_phone_masked"] == "***-***-0199",
			"mock: first status poll still pending, phone masked")
	var s2: InvoResult = await server.get_phone_change_request(id)
	_check(s2.ok and s2.dict()["is_confirmed"] and InvoMock.current_phone() == "+15555550199",
			"mock: second status poll confirmed; phone switched")
	var missing: InvoResult = await server.get_phone_change_request("nope")
	_check(not missing.ok and missing.error.code == "CHANGE_REQUEST_NOT_FOUND", "mock: unknown request 404")
	InvoMock.phone_secured = false
	var open: InvoResult = await server.change_player_phone("p@example.com", "+15555550222")
	_check(open.ok and open.dict()["status"] == "updated" and open.dict()["identity_rekeyed"],
			"mock: unsecured account switches at once")
	var same: InvoResult = await server.change_player_phone("p@example.com", "+15555550222")
	_check(same.ok and same.dict()["status"] == "unchanged", "mock: same number -> unchanged")
	InvoMock.reset()
	http.queue_free()


func _test_mock_via_autoload() -> void:
	InvoMock.reset()
	var invo: Node = (load("res://addons/invonetwork/invo.gd") as GDScript).new()
	root.add_child(invo)
	await process_frame
	invo.enable_mock()
	var client: InvoPlayerClient = invo.client()
	var pending: InvoResult = await client.get_pending_actions()
	var grant: InvoResult = await client.begin_device_approval("mock-txn-9002", "transfer_receipt",
			InvoPlayerClient.default_channel())
	var server: InvoSandboxServer = invo.sandbox()
	var items: InvoResult = await server.get_game_items()
	_check(pending.ok and grant.ok and items.ok,
			"Invo.enable_mock(): new client + sandbox routes answer offline")
	invo.disable_mock()
	invo.queue_free()
	InvoMock.reset()

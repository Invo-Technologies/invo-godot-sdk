class_name InvoMock
extends RefCounted
## Offline mock transport — canned sandbox-shaped responses so the UI and
## tests run with no network and no credentials. Never ship a build with the
## mock enabled.
##
## Stateful where a screen needs a sequence:
## - Device approval: begin -> first poll authorization_pending -> second poll
##   approved -> settle (a second settle answers TRANSACTION_NOT_PENDING).
##   Collecting a pending item removes it from /api/sdk/transfers/pending and
##   credits the balance.
## - Phone change: with `phone_secured` (default) the direct change answers 409
##   PHONE_CHANGE_REQUIRES_VERIFICATION; a change request then reads pending
##   once and confirmed on the next poll.

static var purchases: int = 0
static var _balance: float = 120.0

## true: change_player_phone answers 409 PHONE_CHANGE_REQUIRES_VERIFICATION
## (a secured account -> the email-confirmation path). false: it switches at once.
static var phone_secured: bool = true
## true: a grant's pending poll carries an `enrollment` block (a first-time
## phone asking the game screen to confirm its match code).
static var enrollment_prompt: bool = false

const MOCK_INTERVAL: int = 2
const MOCK_PHONE: String = "+15555550111"

static var _grant_seq: int = 0
## device_code -> {transaction_id, flow, polls, denied, enrol_decided, settled}
static var _grants: Dictionary = {}
## transaction_id -> verification_state after a settle ("approved"/"completed").
static var _settled: Dictionary = {}
## transaction ids collected through a receipt flow.
static var _collected: Dictionary = {}
static var _phone_seq: int = 0
## change_request_id -> {phone, polls}
static var _phone_requests: Dictionary = {}
static var _phone: String = MOCK_PHONE


static func reset() -> void:
	purchases = 0
	_balance = 120.0
	phone_secured = true
	enrollment_prompt = false
	_grant_seq = 0
	_grants = {}
	_settled = {}
	_collected = {}
	_phone_seq = 0
	_phone_requests = {}
	_phone = MOCK_PHONE


## The phone the mock holds for the player (show it masked with
## InvoMap.mask_phone_short — there is no INVO route that returns it).
static func current_phone() -> String:
	return _phone


static func transport(method: String, url: String, _headers: Dictionary,
		body: Variant) -> Dictionary:
	var path: String = url.split("?", true, 1)[0]
	# Route on the path suffix so any base_url works.
	if path.ends_with("/api/sdk/player-token"):
		return _ok({
			"token": "mock-player-token",
			"expires_at": "2999-01-01T00:00:00Z",
			"identity_id": "mock-identity-1",
		})
	if path.ends_with("/api/sdk/balance"):
		return _ok({
			"game_id": "mock-game",
			"game_name": "Mock Game",
			"balances": [{
				"currency_id": 1,
				"currency_name": "Gold Crowns",
				"currency_symbol": "GC",
				"available_balance": "%.2f" % _balance,
				"reserved_balance": "0.00",
				"total_balance": "%.2f" % _balance,
			}],
			"summary": {"total_value": "%.2f" % _balance, "currency_count": 1,
					"has_funds": _balance > 0.0},
		})
	if path.ends_with("/api/sdk/destinations") or path.ends_with("/available-destinations"):
		return _ok({
			"status": "ok",
			"source_game_id": "mock-game",
			"source_game_name": "Mock Game",
			"source_currency_name": "Gold Crowns",
			"transfer_mode": "linked",
			"available_games": [
				{"game_id": 7, "game_name": "Starfall Arena", "currency_name": "Shards",
					"currency_symbol": "SH", "minimum_transfer": "1.00",
					"maximum_transfer": "500.00", "accepts_steam_origin_value": true},
				{"game_id": 12, "game_name": "Harvest Lane", "currency_name": "Acorns",
					"currency_symbol": "AC", "minimum_transfer": "5.00",
					"maximum_transfer": "250.00", "accepts_steam_origin_value": false},
			],
			"total_destinations": 2,
			"direction": "transfer",
		})
	if path.ends_with("/api/players/destinations"):
		return _player_destinations()
	if path.ends_with("/api/sdk/transfers/pending"):
		return _ok({"pending": _pending_rows()})
	if path.ends_with("/api/sdk/approvals/device/begin"):
		return _device_begin(_body(body))
	if path.ends_with("/api/sdk/approvals/device/poll"):
		return _device_poll(_body(body))
	if path.ends_with("/api/sdk/approvals/device/confirm-enrollment"):
		return _device_confirm_enrollment(_body(body))
	if method == "POST" and (path.contains("/api/sdk/send/") or path.contains("/api/sdk/transfers/")) \
			and (path.ends_with("/approve") or path.ends_with("/confirm-receipt")):
		return _device_settle(path, _body(body))
	if path.ends_with("/api/v1/game-items/list"):
		return _ok(_game_items())
	if path.ends_with("/api/sdk/players/phone"):
		return _phone_change(_body(body))
	if path.ends_with("/api/sdk/players/phone/change-requests"):
		return _phone_change_request_create(_body(body))
	if method == "GET" and path.contains("/api/sdk/players/phone/change-requests/"):
		return _phone_change_request_status(path.get_file().uri_decode())
	if path.ends_with("/api/checkout/sessions"):
		var amount: String = str((body as Dictionary).get("usd_amount", "?")) \
				if body is Dictionary else "?"
		return _ok({
			"session_id": "mock-session-1",
			"checkout_url": "https://sandbox.invo.network/mock-checkout?usd=%s" % amount,
			"expires_at": "2999-01-01T00:00:00Z",
			"expires_in_seconds": 900,
		})
	if path.ends_with("/api/item-purchases/purchase-item"):
		purchases += 1
		var total: float = 0.0
		if body is Dictionary:
			var t: Variant = (body as Dictionary).get("total_price", 0.0)
			total = InvoValidate.money_value(t)
		if total > _balance:
			return {"status": 400, "headers": {}, "body": {
				"error": "insufficient_balance",
				"code": "INSUFFICIENT_BALANCE",
				"required_amount": "%.2f" % total,
				"current_balance": "%.2f" % _balance,
			}}
		var previous: float = _balance
		_balance -= total
		return _ok({
			"status": "success",
			"transaction_id": "mock-item-txn-%d" % purchases,
			"order_id": "mock-order-%d" % purchases,
			"new_balance": "%.2f" % _balance,
			"previous_balance": "%.2f" % previous,
			"currency_name": "Gold Crowns",
		})
	if path.ends_with("/claim-currency") or path.ends_with("/claim-transfer"):
		_balance += 25.0
		return _ok({
			"status": "claimed",
			"transaction_id": "mock-claim-txn",
			"new_balance": "%.2f" % _balance,
			"currency_name": "Gold Crowns",
		})
	if path.ends_with("/initiate-send") or path.ends_with("/initiate-transfer"):
		return _ok({
			"status": "success",
			"transaction_id": "mock-out-txn",
			"verification_method": "sms",
		})
	if path.contains("/api/player-balances/player/by-email/"):
		return _ok({
			"player": {"email": "mock@example.com"},
			"balances": [{
				"currency_id": 1, "currency_name": "Gold Crowns",
				"currency_symbol": "GC", "available_balance": "%.2f" % _balance,
				"reserved_balance": "0.00", "total_balance": "%.2f" % _balance,
			}],
			"summary": {"total_value": "%.2f" % _balance},
		})
	if path.contains("/api/transfers/inbound-pending"):
		return _ok({"inbound_pending": []})
	if method == "GET" and path.contains("/status"):
		return _transaction_status(path)
	return {"status": 404, "headers": {},
			"body": {"error": "mock route not found: %s" % path, "code": "NOT_FOUND"}}


static func _ok(body: Dictionary, status: int = 200) -> Dictionary:
	return {"status": status, "headers": {"x-invo-request-id": "mock-req"}, "body": body}


static func _err(status: int, body: Dictionary) -> Dictionary:
	return {"status": status, "headers": {"x-invo-request-id": "mock-req"}, "body": body}


static func _body(body: Variant) -> Dictionary:
	return body if body is Dictionary else {}


# ---- Pending actions ----

static func _pending_rows() -> Array:
	# Backend fields (transfer_id, counterparty_game, currency, ...) plus the
	# older transaction_id / source_game keys the bundled wallet panel reads.
	var rows: Array = [
		{"transfer_id": "mock-txn-9001", "transaction_id": "mock-txn-9001",
			"kind": "receiving_confirm", "flow": "send", "amount": "25.00",
			"currency": "Gold Crowns", "counterparty_game": "Starfall Arena",
			"source_game": "Starfall Arena", "expires_at": "2999-01-01T00:00:00Z",
			"step_up_required": false, "held": false, "hold_reason": null},
		{"transfer_id": "mock-txn-9002", "transaction_id": "mock-txn-9002",
			"kind": "receiving_confirm", "flow": "transfer", "amount": "40.00",
			"currency": "Gold Crowns", "counterparty_game": "Harvest Lane",
			"source_game": "Harvest Lane", "expires_at": "2999-01-01T00:00:00Z",
			"step_up_required": false, "held": false, "hold_reason": null},
		{"transfer_id": "mock-txn-9003", "transaction_id": "mock-txn-9003",
			"kind": "receiving_confirm", "flow": "send", "amount": "10.00",
			"currency": "Gold Crowns", "counterparty_game": "Starfall Arena",
			"source_game": "Starfall Arena", "expires_at": "2999-01-01T00:00:00Z",
			"step_up_required": true, "held": true,
			"hold_reason": "device_requires_elevation"},
	]
	var out: Array = []
	for r: Variant in rows:
		if not _collected.has((r as Dictionary)["transfer_id"]):
			out.append(r)
	return out


static func _pending_amount(transaction_id: String) -> String:
	for r: Variant in _pending_rows():
		if (r as Dictionary)["transfer_id"] == transaction_id:
			return str((r as Dictionary)["amount"])
	return "25.00"


# ---- Device approval ----

static func _device_begin(body: Dictionary) -> Dictionary:
	var txn: String = str(body.get("transaction_id", "")).strip_edges()
	var flow: String = str(body.get("flow", ""))
	if txn.is_empty():
		return _err(400, {"error": "transaction_id is required", "code": "INVALID_INPUT"})
	if not (flow in InvoMap.APPROVAL_FLOWS):
		return _err(400, {"error": "unknown flow", "code": "INVALID_INPUT",
				"valid_flows": InvoMap.APPROVAL_FLOWS})
	_grant_seq += 1
	var device_code: String = "mock-device-code-%d" % _grant_seq
	var user_code: String = "MOCK-%04d" % _grant_seq
	_grants[device_code] = {"transaction_id": txn, "flow": flow, "polls": 0,
			"denied": false, "enrol_decided": false, "settled": false}
	return _ok({
		"device_code": device_code,
		"user_code": user_code,
		"verification_uri": "https://sandbox.invo.network/device",
		"verification_uri_complete": "https://sandbox.invo.network/device?code=%s" % user_code,
		"expires_in": 600,
		"interval": MOCK_INTERVAL,
		"channel": str(body.get("channel", "qr")),
	})


static func _device_poll(body: Dictionary) -> Dictionary:
	var grant: Variant = _grants.get(str(body.get("device_code", "")))
	if not (grant is Dictionary):
		return _err(400, {"error": "invalid_grant"})
	var g: Dictionary = grant
	if g["denied"]:
		return _err(400, {"error": "access_denied"})
	g["polls"] = int(g["polls"]) + 1
	if int(g["polls"]) == 1:
		var pending: Dictionary = {"error": "authorization_pending", "interval": MOCK_INTERVAL}
		if enrollment_prompt and not g["enrol_decided"]:
			pending["enrollment"] = {
				"state": "awaiting_screen",
				"device_label": "iPhone (Safari)",
				"match_code": "4821",
				"requested_at": "2026-01-01T00:00:00+00:00",
				"recovery": false,
			}
		return _err(400, pending)
	return _ok({
		"status": "approved",
		"transaction_id": g["transaction_id"],
		"flow": g["flow"],
		"approved_at": "2026-01-01T00:00:05+00:00",
	})


static func _device_confirm_enrollment(body: Dictionary) -> Dictionary:
	var decision: String = str(body.get("decision", "")).to_lower()
	if not (decision in ["approve", "deny"]):
		return _err(400, {"error": "decision must be approve or deny", "code": "INVALID_INPUT"})
	var grant: Variant = _grants.get(str(body.get("device_code", "")))
	if not (grant is Dictionary):
		return _err(400, {"error": "invalid_grant"})
	var g: Dictionary = grant
	if not enrollment_prompt:
		return _err(409, {"error": "nothing to confirm: no phone has asked to enrol on this approval",
				"code": "DEVICE_APPROVAL_NO_ENROLLMENT_PENDING"})
	if g["enrol_decided"]:
		return _err(409, {"error": "this enrolment was already decided",
				"code": "DEVICE_APPROVAL_ENROLLMENT_ALREADY_DECIDED"})
	g["enrol_decided"] = true
	if decision == "deny":
		g["denied"] = true
		return _ok({"status": "denied"})
	return _ok({"status": "confirmed"})


static func _device_settle(path: String, body: Dictionary) -> Dictionary:
	var receipt: bool = path.ends_with("/confirm-receipt")
	var is_send: bool = path.contains("/api/sdk/send/")
	var flow: String
	if is_send:
		flow = "send_receipt" if receipt else "send"
	else:
		flow = "transfer_receipt" if receipt else "transfer"
	var txn: String = path.get_base_dir().get_file().uri_decode()
	var grant: Variant = _grants.get(str(body.get("device_code", "")))
	if not (grant is Dictionary) or (grant as Dictionary)["transaction_id"] != txn \
			or (grant as Dictionary)["flow"] != flow or int((grant as Dictionary)["polls"]) < 2:
		return _err(400, {"error": "invalid_grant"})
	var g: Dictionary = grant
	if g["settled"]:
		return _err(400, {"status": "error",
				"message": "Transaction not pending (current status: %s)" % (
						"completed" if receipt else "pending_claim"),
				"code": "TRANSACTION_NOT_PENDING",
				"current_status": "completed" if receipt else "pending_claim"})
	g["settled"] = true
	if receipt:
		var amount: String = _pending_amount(txn)
		_collected[txn] = true
		_balance += amount.to_float()
		_settled[txn] = "completed"
		return _ok({"status": "completed", "transaction_id": txn, "amount_received": amount})
	_settled[txn] = "approved"
	var out: Dictionary = {"status": "approved", "next": "pending_claim", "transaction_id": txn}
	if flow == "transfer":
		out["claim_code"] = "MOCKCLAIM1"
		out["claim_code_expires_at"] = "2999-01-01T00:00:00+00:00"
	return _ok(out)


static func _transaction_status(path: String) -> Dictionary:
	# .../{id}/status
	var txn: String = path.get_base_dir().get_file().uri_decode()
	if _settled.has(txn):
		var state: String = _settled[txn]
		var out: Dictionary = {"transaction_id": txn,
				"transaction_status": "completed" if state == "completed" else "pending_claim",
				"verification_state": state}
		if path.contains("/transfers/") and state == "approved":
			out["claim_code"] = "MOCKCLAIM1"
			out["claim_code_expires_at"] = "2999-01-01T00:00:00+00:00"
		return _ok(out)
	return _ok({"transaction_id": "mock-txn", "transaction_status": "completed",
			"verification_state": "verified"})


# ---- Store catalog ----

static func _game_items() -> Dictionary:
	var items: Array = [
		_item("mock-bundle-hero", "Dragon Hoard Bundle", "weekly", "bundle", 49.99, 79.99, 38,
				2000.0, 500.0, true, "legendary", "BEST VALUE", "2,000 + 500 bonus"),
		_item("mock-pack-weekly-1", "Knight's Coffer", "weekly", "currency_pack", 19.99, null, null,
				750.0, 0.0, false, "epic", "", "750"),
		_item("mock-pack-weekly-2", "Ranger's Satchel", "weekly", "currency_pack", 24.99, 29.99, 17,
				1000.0, 100.0, false, "rare", "POPULAR", "1,000 + 100 bonus"),
		_item("mock-daily-1", "Daily Gem Drop", "daily", "daily_deal", 4.99, 9.99, 50,
				150.0, 0.0, false, "rare", "-50%", "150"),
		_item("mock-daily-2", "Morning Potion Pack", "daily", "daily_deal", 2.49, 4.99, 50,
				60.0, 0.0, false, "common", "-50%", "60"),
		_item("mock-standard-1", "Starter Pouch", "standard", "currency_pack", 0.99, null, null,
				20.0, 0.0, false, "common", "", "20"),
	]
	var daily: Array = items.filter(func(i: Dictionary) -> bool:
		return i["item_category"] == "daily")
	for d: Variant in daily:
		(d as Dictionary)["is_limited_time"] = true
		(d as Dictionary)["available_until"] = "2999-01-01T00:00:00+00:00"
		(d as Dictionary)["time_remaining_seconds"] = 15 * 3600 + 30 * 60
		(d as Dictionary)["time_remaining_display"] = "15h 30m"
	(items[2] as Dictionary)["is_most_popular"] = true
	(items[0] as Dictionary)["is_best_value"] = true
	return {"status": "success", "items": items, "total_items": items.size()}


static func _item(id: String, item_name: String, category: String, item_type: String,
		price: float, original: Variant, discount: Variant, amount: float, bonus: float,
		featured: bool, rarity: String, tag: String, getting: String) -> Dictionary:
	return {
		"item_id": id,
		"game_id": "mock-game",
		"item_name": item_name,
		"display_name": item_name,
		"display_subtitle": "",
		"display_tag": tag,
		"display_getting": getting,
		"item_description": "Mock catalog item for offline UI work.",
		"item_category": category,
		"item_type": item_type,
		"image_url": "",
		"icon_url": "",
		"thumbnail_url": "",
		"item_color": "#F2B33D",
		"is_featured": featured,
		"is_most_popular": false,
		"is_best_value": false,
		"is_active": true,
		"discount_percentage": discount,
		"price_usd": price,
		"original_price_usd": original,
		"currency_amount": amount,
		"bonus_amount": bonus,
		"item_rarity": rarity,
		"is_limited_time": false,
		"available_from": null,
		"available_until": null,
		"metadata": {},
	}


# ---- Player destinations ----

static func _player_destinations() -> Dictionary:
	return _ok({
		"status": "success",
		"source_game_id": "mock-game",
		"source_game_name": "Mock Game",
		"transfer_mode": "linked",
		"destinations": [
			{"game_id": "7", "game_name": "Starfall Arena", "tenant_type": "game",
				"game_status": "active",
				"default_currency": {"currency_id": 3, "currency_name": "Shards",
					"currency_symbol": "SH"},
				"available_balance": "42.00", "last_active": "2026-10-20T18:00:00+00:00"},
			{"game_id": "12", "game_name": "Harvest Lane", "tenant_type": "game",
				"game_status": "active",
				"default_currency": {"currency_id": 5, "currency_name": "Acorns",
					"currency_symbol": "AC"},
				"available_balance": "7.50", "last_active": "2026-10-02T09:30:00+00:00"},
		],
	})


# ---- Player phone ----

static func _phone_input_problem(body: Dictionary) -> Dictionary:
	if str(body.get("player_email", "")).strip_edges().is_empty():
		return _err(400, {"error": "player_email is required", "code": "INVALID_INPUT"})
	if InvoValidate.e164_problem(body.get("new_phone"), "new_phone") != null:
		return _err(400, {"error": "new_phone is not a valid phone number", "code": "INVALID_PHONE"})
	return {}


static func _phone_change(body: Dictionary) -> Dictionary:
	var problem: Dictionary = _phone_input_problem(body)
	if not problem.is_empty():
		return problem
	var new_phone: String = str(body.get("new_phone"))
	if new_phone == _phone:
		return _ok({"status": "unchanged", "identity_rekeyed": false,
				"identity_id": "mock-identity-1", "player_token": "mock-player-token",
				"player_token_expires_at": "2999-01-01T00:00:00Z"})
	if phone_secured:
		return _err(409, {
			"error": "This player's phone is verified or secured with an approval method, " +
					"so the change needs the player's own confirmation.",
			"code": "PHONE_CHANGE_REQUIRES_VERIFICATION",
			"change_request_endpoint": "/sandbox/api/sdk/players/phone/change-requests",
		})
	_phone = new_phone
	return _ok({"status": "updated", "identity_rekeyed": true,
			"identity_id": "mock-identity-2", "player_token": "mock-player-token-2",
			"player_token_expires_at": "2999-01-01T00:00:00Z"})


static func _phone_change_request_create(body: Dictionary) -> Dictionary:
	var problem: Dictionary = _phone_input_problem(body)
	if not problem.is_empty():
		return problem
	var new_phone: String = str(body.get("new_phone"))
	if new_phone == _phone:
		return _err(409, {"error": "That is already the player's number.", "code": "PHONE_SAME"})
	_phone_seq += 1
	var id: String = "mock-pcr-%d" % _phone_seq
	# A new request replaces an earlier pending one.
	for other: Variant in _phone_requests:
		var row: Dictionary = _phone_requests[other]
		if row["status"] == "pending":
			row["status"] = "cancelled"
	_phone_requests[id] = {"phone": new_phone, "polls": 0, "status": "pending"}
	return _ok({
		"change_request_id": id,
		"status": "pending_confirmation",
		"expires_at": "2999-01-01T00:00:00+00:00",
		"delivery": "email",
		"confirmation": "email_code",
		"message": "INVO emailed the player a confirmation code and a link to a page on " +
				"INVO's site. The player confirms there; nothing changes until they do.",
	}, 202)


static func _phone_change_request_status(id: String) -> Dictionary:
	var row: Variant = _phone_requests.get(id)
	if not (row is Dictionary):
		return _err(404, {"error": "Change request not found", "code": "CHANGE_REQUEST_NOT_FOUND"})
	var r: Dictionary = row
	r["polls"] = int(r["polls"]) + 1
	if r["status"] == "pending" and int(r["polls"]) >= 2:
		r["status"] = "confirmed"
		_phone = r["phone"]
	var phone: String = r["phone"]
	var out: Dictionary = {
		"change_request_id": id,
		"status": r["status"],
		"confirmation": "email_code",
		"delivery": "email",
		"new_phone_masked": "***-***-%s" % phone.substr(phone.length() - 4),
		"created_at": "2026-01-01T00:00:00+00:00",
		"expires_at": "2999-01-01T00:00:00+00:00",
		"confirmed_at": null,
		"confirmed_via": null,
	}
	if r["status"] == "confirmed":
		out["confirmed_at"] = "2026-01-01T00:01:00+00:00"
		out["confirmed_via"] = "email_code"
	return _ok(out)

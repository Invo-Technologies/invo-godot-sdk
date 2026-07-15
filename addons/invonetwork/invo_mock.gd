class_name InvoMock
extends RefCounted
## Offline mock transport — canned sandbox-shaped responses so the UI and
## tests run with no network and no credentials. Never ship a build with the
## mock enabled.

static var purchases: int = 0
static var _balance: float = 120.0


static func reset() -> void:
	purchases = 0
	_balance = 120.0


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
	if path.ends_with("/api/sdk/transfers/pending"):
		return _ok({"pending": [{
			"kind": "receiving_confirm",
			"transaction_id": "mock-txn-9001",
			"flow": "send",
			"amount": "25.00",
			"source_game": "Starfall Arena",
		}]})
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
		_balance -= total
		return _ok({
			"status": "completed",
			"transaction_id": "mock-item-txn-%d" % purchases,
			"order_id": "mock-order-%d" % purchases,
			"new_balance": "%.2f" % _balance,
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
		return _ok({"transaction_id": "mock-txn", "transaction_status": "completed",
				"verification_state": "verified"})
	return {"status": 404, "headers": {},
			"body": {"error": "mock route not found: %s" % path, "code": "NOT_FOUND"}}


static func _ok(body: Dictionary) -> Dictionary:
	return {"status": 200, "headers": {"x-invo-request-id": "mock-req"}, "body": body}

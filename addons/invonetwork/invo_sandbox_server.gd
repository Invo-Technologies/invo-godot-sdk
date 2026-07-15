class_name InvoSandboxServer
extends RefCounted
## The DIRECT-MODE entry — the full INVO server API, authenticated with the
## game secret (X-Game-Secret-Key).
##
## ============================ SECURITY WARNING ============================
## The game secret must NEVER ship inside a game build. This mode exists for
## SANDBOX PROTOTYPING ONLY — the [Invo] autoload refuses to construct it
## against the production environment. In production your own backend holds
## the secret (INVO Python/PyPI or JS/npm server SDK) and your game talks to
## that backend, or uses the player-token [InvoPlayerClient].
## ==========================================================================
##
## Method-for-method port of the Python `InvoServer` (invonetwork 2.4.1),
## including input validation, idempotency flags, and result mapping.

var _http: InvoHttp
var _auth: Dictionary = {}


func _init(http: InvoHttp, game_secret: String) -> void:
	_http = http
	_auth = {"X-Game-Secret-Key": game_secret}


# ---- Token ----

## Mint a short-lived, game-scoped player token (a SESSION mint for a player
## who already exists — 404 if not). player_phone is optional and validated
## only if provided. Idempotent.
func mint_player_token(player_email: String, player_phone: String = "") -> InvoResult:
	if not InvoValidate.is_present(player_email):
		return _fail(InvoError.invalid_input("playerEmail", player_email, "is required"))
	var body: Dictionary = {"player_email": player_email}
	if not player_phone.is_empty():
		var phone_err: InvoError = InvoValidate.e164_problem(player_phone, "playerPhone")
		if phone_err != null:
			return _fail(phone_err)
		body["player_phone"] = player_phone
	var res: InvoResult = await _http.post_json("/api/sdk/player-token", body, _auth, true)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	var token: Variant = raw.get("token")
	if token == null or str(token).is_empty():
		return _fail(InvoError.make(
				"INVO response was missing the required `token` field.",
				"INVALID_RESPONSE", 0, raw))
	return InvoResult.success({
		"token": str(token),
		"expires_at": str(raw.get("expires_at", "")),
		"identity_id": str(raw.get("identity_id", "")),
		"raw": raw,
	})


# ---- Initiate (send / transfer) ----

## Initiate a cross-game currency SEND. Inspect result.verification_method.
## receiver_player_email may be "" (send by phone alone). Idempotent on
## client_request_id.
func initiate_send(client_request_id: String, sender_player_name: String,
		sender_player_email: String, sender_player_phone: String,
		receiver_player_phone: String, receiving_game_id: Variant, amount: Variant,
		receiver_player_email: String = "") -> InvoResult:
	var body: Dictionary = {
		"client_request_id": client_request_id,
		"sender_player_name": sender_player_name,
		"sender_player_email": sender_player_email,
		"sender_player_phone": sender_player_phone,
		"receiver_player_phone": receiver_player_phone,
		"receiving_game_id": receiving_game_id,
		"amount": amount,
	}
	if not receiver_player_email.is_empty():
		body["receiver_player_email"] = receiver_player_email
	var res: InvoResult = await _http.post_json(
			"/api/currency-sends/initiate-send", body, _auth, true)
	return InvoResult.success(InvoMap.to_initiate_result(res.dict())) if res.ok else res


## Initiate a cross-game TRANSFER. target_player_email may be "" (transfer by
## phone alone). Idempotent on client_request_id.
func initiate_transfer(client_request_id: String, source_player_name: String,
		source_player_email: String, source_player_phone: String,
		target_player_phone: String, target_game_id: Variant, amount: Variant,
		target_player_email: String = "") -> InvoResult:
	var body: Dictionary = {
		"client_request_id": client_request_id,
		"source_player_name": source_player_name,
		"source_player_email": source_player_email,
		"source_player_phone": source_player_phone,
		"target_player_phone": target_player_phone,
		"target_game_id": target_game_id,
		"amount": amount,
	}
	if not target_player_email.is_empty():
		body["target_player_email"] = target_player_email
	var res: InvoResult = await _http.post_json(
			"/api/transfers/initiate-transfer", body, _auth, true)
	return InvoResult.success(InvoMap.to_initiate_result(res.dict())) if res.ok else res


# ---- Currency purchase (real money in) ----

## Create a hosted checkout session — the recommended purchase path. Open the
## returned checkout_url in the system browser (OS.shell_open); crediting is
## server-side via the purchase.completed webhook. NOT idempotent.
func create_checkout(player_email: String, usd_amount: Variant, rail: String = "",
		success_url: String = "", cancel_url: String = "",
		metadata: Dictionary = {}) -> InvoResult:
	if not InvoValidate.is_present(player_email):
		return _fail(InvoError.invalid_input("playerEmail", player_email, "is required"))
	var money_err: InvoError = InvoValidate.money_problem(
			usd_amount, InvoValidate.MAX_USD_AMOUNT, "usdAmount")
	if money_err != null:
		return _fail(money_err)
	var body: Dictionary = {"player_email": player_email, "usd_amount": usd_amount}
	if not rail.is_empty():
		body["rail"] = rail
	if not success_url.is_empty():
		body["success_url"] = success_url
	if not cancel_url.is_empty():
		body["cancel_url"] = cancel_url
	if not metadata.is_empty():
		body["metadata"] = metadata
	var res: InvoResult = await _http.post_json("/api/checkout/sessions", body, _auth)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	var url: Variant = raw.get("checkout_url")
	if url == null or str(url).is_empty():
		return _fail(InvoError.make(
				"INVO response was missing the required `checkout_url` field.",
				"INVALID_RESPONSE", 0, raw))
	var eis: Variant = raw.get("expires_in_seconds")
	return InvoResult.success({
		"session_id": str(raw.get("session_id", "")),
		"checkout_url": str(url),
		"expires_at": str(raw.get("expires_at", "")),
		"expires_in_seconds": int(eis) if (eis is int or eis is float) else 0,
		"raw": raw,
	})


## Direct purchase via the rail selector. rail "platform" (default) may return
## status "requires_action" (client-side 3-D Secure, then confirm_payment);
## rail "game" returns "pending_payment" + payment_url; rail "steam" is NOT a
## browser flow and is rejected here. Idempotent on purchase_reference.
func purchase_currency(player_email: String, usd_amount: Variant,
		purchase_reference: String, rail: String = "", payment_method_id: String = "",
		saved_card_id: String = "", player_name: String = "", player_phone: String = "",
		metadata: Dictionary = {}) -> InvoResult:
	if not InvoValidate.is_present(player_email):
		return _fail(InvoError.invalid_input("playerEmail", player_email, "is required"))
	var money_err: InvoError = InvoValidate.money_problem(
			usd_amount, InvoValidate.MAX_USD_AMOUNT, "usdAmount")
	if money_err != null:
		return _fail(money_err)
	if purchase_reference.is_empty():
		return _fail(InvoError.make(
				"purchaseReference is required (idempotency key for the purchase).",
				"MISSING_PURCHASE_REFERENCE", 0))
	if rail == "steam":
		return _fail(InvoError.make(
				'rail "steam" is not a /purchase-currency flow — Steam uses the ' +
				"dedicated in-client Steam endpoints.", "WRONG_RAIL_ENDPOINT", 0))
	var body: Dictionary = {
		"player_email": player_email,
		"usd_amount": usd_amount,
		"purchase_reference": purchase_reference,
	}
	if not rail.is_empty():
		body["rail"] = rail
	if not payment_method_id.is_empty():
		body["payment_method_id"] = payment_method_id
	if not saved_card_id.is_empty():
		body["saved_card_id"] = saved_card_id
	if not player_name.is_empty():
		body["player_name"] = player_name
	if not player_phone.is_empty():
		body["player_phone"] = player_phone
	if not metadata.is_empty():
		body["metadata"] = metadata
	var res: InvoResult = await _http.post_json(
			"/api/currency-purchases/purchase-currency", body, _auth, true)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	return InvoResult.success({
		"status": str(raw.get("status", "")),
		"client_secret": raw.get("client_secret"),
		"payment_intent_id": raw.get("payment_intent_id"),
		"payment_url": raw.get("payment_url"),
		"transaction_id": raw.get("transaction_id"),
		"order_id": raw.get("order_id"),
		"new_balance": raw.get("new_balance"),
		"raw": raw,
	})


## Complete the card-rail 3-D Secure step. Keyed by payment_intent_id — idempotent.
func confirm_payment(payment_intent_id: String, order_id: String = "") -> InvoResult:
	var body: Dictionary = {"payment_intent_id": payment_intent_id}
	if not order_id.is_empty():
		body["order_id"] = order_id
	var res: InvoResult = await _http.post_json(
			"/api/currency-purchases/confirm-payment", body, _auth, true)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	return InvoResult.success({
		"status": str(raw.get("status", "")),
		"transaction_id": raw.get("transaction_id"),
		"new_balance": raw.get("new_balance"),
		"raw": raw,
	})


## Currency-purchase status (order + financial summary + timeline).
func get_order_details(order_id: String = "", transaction_id: String = "") -> InvoResult:
	if order_id.is_empty() and transaction_id.is_empty():
		return _fail(InvoError.make(
				"get_order_details requires an `order_id` or `transaction_id`.",
				"INVALID_INPUT", 0))
	var params: Array[String] = []
	if not order_id.is_empty():
		params.append("order_id=%s" % order_id.uri_encode())
	if not transaction_id.is_empty():
		params.append("transaction_id=%s" % transaction_id.uri_encode())
	var res: InvoResult = await _http.get_json(
			"/api/currency-purchases/order-details?%s" % "&".join(params), _auth)
	return InvoResult.success(InvoMap.to_order_details(res.dict())) if res.ok else res


# ---- Item purchase (spend existing game currency) ----

## Buy an in-game item by SPENDING game currency — a balance debit; no real
## money, no rail, no passkey. Idempotent on client_request_id (a duplicate is
## a 409, err.is_duplicate_request()); insufficient balance is a 400
## (err.is_insufficient_balance(); required_amount/current_balance on body).
## Grant the item off the item.purchased webhook, not just this response.
func purchase_item(client_request_id: String, player_email: String, player_name: String,
		item_id: String, item_name: String, item_quantity: int, unit_price: Variant,
		total_price: Variant, player_phone: String = "", item_description: String = "",
		item_category: String = "") -> InvoResult:
	var required: Dictionary = {
		"clientRequestId": client_request_id,
		"playerEmail": player_email,
		"playerName": player_name,
		"itemId": item_id,
		"itemName": item_name,
	}
	for label: String in required:
		if not InvoValidate.is_present(required[label]):
			return _fail(InvoError.invalid_input(label, required[label], "is required"))
	if item_quantity < 1 or item_quantity > 1000:
		return _fail(InvoError.invalid_input(
				"itemQuantity", item_quantity, "must be an integer 1..1000"))
	var unit_err: InvoError = InvoValidate.money_problem(
			unit_price, InvoValidate.MAX_ITEM_PRICE, "unitPrice")
	if unit_err != null:
		return _fail(unit_err)
	var total_err: InvoError = InvoValidate.money_problem(
			total_price, InvoValidate.MAX_ITEM_PRICE, "totalPrice")
	if total_err != null:
		return _fail(total_err)
	# Compare in integer cents to avoid float error at the +/-0.01 boundary.
	var unit: float = InvoValidate.money_value(unit_price)
	var total: float = InvoValidate.money_value(total_price)
	var expected_cents: int = InvoValidate.round_half_up(unit * float(item_quantity) * 100.0)
	var total_cents: int = InvoValidate.round_half_up(total * 100.0)
	if absi(total_cents - expected_cents) > 1:
		return _fail(InvoError.invalid_input("totalPrice", total_price,
				"must equal unitPrice x itemQuantity (+/-0.01): %s x %d" % [unit, item_quantity]))
	var body: Dictionary = {
		"client_request_id": client_request_id,
		"player_email": player_email,
		"player_name": player_name,
		"item_id": item_id,
		"item_name": item_name,
		"item_quantity": item_quantity,
		"unit_price": unit_price,
		"total_price": total_price,
	}
	if not player_phone.is_empty():
		body["player_phone"] = player_phone
	if not item_description.is_empty():
		body["item_description"] = item_description
	if not item_category.is_empty():
		body["item_category"] = item_category
	var res: InvoResult = await _http.post_json(
			"/api/item-purchases/purchase-item", body, _auth, true)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	for field: String in ["transaction_id", "order_id"]:
		if raw.get(field) == null or str(raw.get(field)).is_empty():
			return _fail(InvoError.make(
					"INVO response was missing the required `%s` field." % field,
					"INVALID_RESPONSE", 0, raw))
	return InvoResult.success({
		"status": str(raw.get("status", "")),
		"transaction_id": str(raw.get("transaction_id")),
		"order_id": str(raw.get("order_id")),
		"new_balance": raw.get("new_balance"),
		"previous_balance": raw.get("previous_balance"),
		"currency_name": str(raw.get("currency_name", "")),
		"financial_breakdown": raw.get("financial_breakdown"),
		"raw": raw,
	})


## Paginated item-purchase history. limit/offset < 0 means "backend default".
func get_item_purchase_history(player_email: String, limit: int = -1,
		offset: int = -1) -> InvoResult:
	if not InvoValidate.is_present(player_email):
		return _fail(InvoError.invalid_input("playerEmail", player_email, "is required"))
	var params: Array[String] = ["player_email=%s" % player_email.uri_encode()]
	if limit >= 0:
		params.append("limit=%d" % limit)
	if offset >= 0:
		params.append("offset=%d" % offset)
	var res: InvoResult = await _http.get_json(
			"/api/item-purchases/player-purchase-history?%s" % "&".join(params), _auth)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	var history: Variant = raw.get("item_purchase_history")
	return InvoResult.success({
		"history": history if history is Array else [],
		"pagination": raw.get("pagination") if raw.get("pagination") is Dictionary else {},
		"raw": raw,
	})


## Look up one item order by EXACTLY ONE of the three identifiers.
## Use client_request_id for saga/recovery: "did this purchase complete?"
func get_item_order_details(order_id: String = "", transaction_id: String = "",
		client_request_id: String = "") -> InvoResult:
	var provided: int = 0
	for v: String in [order_id, transaction_id, client_request_id]:
		if InvoValidate.is_present(v):
			provided += 1
	if provided != 1:
		return _fail(InvoError.make(
				"get_item_order_details requires EXACTLY ONE of order_id, transaction_id, " +
				"or client_request_id.", "INVALID_INPUT", 0))
	var params: Array[String] = []
	if not order_id.is_empty():
		params.append("order_id=%s" % order_id.uri_encode())
	if not transaction_id.is_empty():
		params.append("transaction_id=%s" % transaction_id.uri_encode())
	if not client_request_id.is_empty():
		params.append("client_request_id=%s" % client_request_id.uri_encode())
	var res: InvoResult = await _http.get_json(
			"/api/item-purchases/order-details?%s" % "&".join(params), _auth)
	return InvoResult.success(InvoMap.to_order_details(res.dict())) if res.ok else res


# ---- Reads ----

## A player's currency balances, by EMAIL only (there is no by-id route).
func get_player_balance(player_email: String) -> InvoResult:
	if not InvoValidate.is_present(player_email):
		return _fail(InvoError.make("get_player_balance requires a player_email.",
				"INVALID_INPUT", 0))
	var res: InvoResult = await _http.get_json(
			"/api/player-balances/player/by-email/%s" % player_email.uri_encode(), _auth)
	return InvoResult.success(InvoMap.to_player_balance_result(res.dict())) if res.ok else res


## LIVE, unclaimed inbound sends/transfers addressed to a player at YOUR game —
## the source of truth for a "you have X to collect" badge.
func get_inbound_pending(player_email: String = "", player_phone: String = "") -> InvoResult:
	var email: String = player_email.strip_edges()
	var phone: String = player_phone.strip_edges()
	if email.is_empty() and phone.is_empty():
		return _fail(InvoError.invalid_input("query",
				{"player_email": player_email, "player_phone": player_phone},
				"requires a playerEmail or playerPhone"))
	var params: Array[String] = []
	if not email.is_empty():
		params.append("player_email=%s" % email.uri_encode())
	if not phone.is_empty():
		params.append("player_phone=%s" % phone.uri_encode())
	var res: InvoResult = await _http.get_json(
			"/api/transfers/inbound-pending?%s" % "&".join(params), _auth)
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	var rows: Variant = raw.get("inbound_pending")
	var items: Array[Dictionary] = []
	if rows is Array:
		for r: Variant in rows:
			if r is Dictionary:
				items.append(InvoMap.to_inbound_pending_item(r))
	return InvoResult.success({"inbound_pending": items, "raw": raw})


## Linked wallet identities (PII — server-only; never show raw emails/phones
## to other players). A 404 maps to {not_found: true}, not an error.
func get_linked_identities(player_email: String = "", player_phone: String = "") -> InvoResult:
	var phone: String = player_phone.strip_edges()
	var email: String = player_email.strip_edges()
	if phone.is_empty() and email.is_empty():
		return _fail(InvoError.invalid_input("query",
				{"player_email": player_email, "player_phone": player_phone},
				"requires a playerEmail or playerPhone"))
	var param: String = "player_phone=%s" % phone.uri_encode() if not phone.is_empty() \
			else "player_email=%s" % email.uri_encode()
	var res: InvoResult = await _http.get_json("/api/wallet/identities?%s" % param, _auth)
	if not res.ok:
		if res.error != null and res.error.status == 404:
			return InvoResult.success({
				"wallet_user_id": null, "primary_email": "", "primary_phone": "",
				"is_minor": false, "emails": [], "not_found": true,
				"raw": res.error.body if res.error.body is Dictionary else {},
			})
		return res
	var raw: Dictionary = res.dict()
	var raw_emails: Variant = raw.get("emails")
	var emails: Array[Dictionary] = []
	if raw_emails is Array:
		for r: Variant in raw_emails:
			if r is Dictionary:
				emails.append({
					"email": str((r as Dictionary).get("email", "")),
					"primary": (r as Dictionary).get("primary") == true,
					"verified_at": (r as Dictionary).get("verified_at"),
				})
	return InvoResult.success({
		"wallet_user_id": raw.get("wallet_user_id"),
		"primary_email": str(raw.get("primary_email", "")),
		"primary_phone": str(raw.get("primary_phone", "")),
		"is_minor": raw.get("is_minor") == true,
		"emails": emails,
		"not_found": false,
		"raw": raw,
	})


# ---- SMS-PIN completion (un-enrolled fallback) ----

## Complete a TRANSFER's SMS-PIN step. NOT idempotent — attempts are counted;
## a bad PIN is a 400 with attempts_remaining on err.body.
func verify_sms_transfer(transaction_id: String, sms_pin: String) -> InvoResult:
	var input_err: InvoError = _require_txn_pin(transaction_id, sms_pin)
	if input_err != null:
		return _fail(input_err)
	var res: InvoResult = await _http.post_json("/api/transfers/verify-sms",
			{"transaction_id": transaction_id, "sms_pin": sms_pin}, _auth)
	return InvoResult.success(InvoMap.to_sms_verify_result(res.dict())) if res.ok else res


## Complete a SEND's SMS-PIN step. See verify_sms_transfer.
func verify_sms_send(transaction_id: String, sms_pin: String) -> InvoResult:
	var input_err: InvoError = _require_txn_pin(transaction_id, sms_pin)
	if input_err != null:
		return _fail(input_err)
	var res: InvoResult = await _http.post_json("/api/currency-sends/verify-sms",
			{"transaction_id": transaction_id, "sms_pin": sms_pin}, _auth)
	return InvoResult.success(InvoMap.to_sms_verify_result(res.dict())) if res.ok else res


# ---- Claim by code ----

## Claim an inbound TRANSFER by claim code. NOT idempotent. A 200 may be
## needs_account_selection (multi-account phone) — re-submit with
## target_player_id. A 409 err.is_phone_share_approval_required() is NOT a
## failure: show err.message, re-issue the same claim once approved.
func claim_transfer(claim_code: String, target_player_name: String,
		target_player_email: String, target_player_phone: String,
		target_currency_id: Variant, target_player_id: Variant = null) -> InvoResult:
	var body: Dictionary = {
		"claim_code": claim_code,
		"target_player_name": target_player_name,
		"target_player_email": target_player_email,
		"target_player_phone": target_player_phone,
		"target_currency_id": target_currency_id,
	}
	if target_player_id != null:
		body["target_player_id"] = target_player_id
	var res: InvoResult = await _http.post_json("/api/transfers/claim-transfer", body, _auth)
	return InvoResult.success(InvoMap.to_claim_result(res.dict())) if res.ok else res


## Claim an inbound SEND by claim code. NOT idempotent. Same result/error
## surface as claim_transfer.
func claim_currency(claim_code: String, receiver_player_name: String,
		receiver_player_email: String, receiver_player_phone: String,
		receiver_player_id: Variant = null) -> InvoResult:
	var body: Dictionary = {
		"claim_code": claim_code,
		"receiver_player_name": receiver_player_name,
		"receiver_player_email": receiver_player_email,
		"receiver_player_phone": receiver_player_phone,
	}
	if receiver_player_id != null:
		body["receiver_player_id"] = receiver_player_id
	var res: InvoResult = await _http.post_json("/api/currency-sends/claim-currency", body, _auth)
	return InvoResult.success(InvoMap.to_claim_result(res.dict())) if res.ok else res


# ---- Transaction status reads ----

func get_transfer_status(transaction_id: String) -> InvoResult:
	if not InvoValidate.is_present(transaction_id):
		return _fail(InvoError.invalid_input("transactionId", transaction_id, "is required"))
	var res: InvoResult = await _http.get_json(
			"/api/transfers/%s/status" % transaction_id.uri_encode(), _auth)
	return InvoResult.success(InvoMap.to_transaction_status(res.dict())) if res.ok else res


func get_send_status(transaction_id: String) -> InvoResult:
	if not InvoValidate.is_present(transaction_id):
		return _fail(InvoError.invalid_input("transactionId", transaction_id, "is required"))
	var res: InvoResult = await _http.get_json(
			"/api/currency-sends/%s/status" % transaction_id.uri_encode(), _auth)
	return InvoResult.success(InvoMap.to_transaction_status(res.dict())) if res.ok else res


## Poll a transaction's guardian approval status (minor/guardian flow).
func get_guardian_approval_status(transaction_id: String) -> InvoResult:
	if not InvoValidate.is_present(transaction_id):
		return _fail(InvoError.invalid_input("transactionId", transaction_id, "is required"))
	var res: InvoResult = await _http.get_json(
			"/api/transactions/%s/approval-status" % transaction_id.uri_encode(), _auth)
	return InvoResult.success(InvoMap.to_guardian_approval_status(res.dict())) if res.ok else res


# ---- Destinations ----

## Games/tenants a player can send/transfer to FROM source_game_id.
## direction "transfer" (default) or "send". Idempotent (a POST read).
func get_destinations(source_game_id: Variant, direction: String = "transfer") -> InvoResult:
	if source_game_id == null or str(source_game_id).strip_edges().is_empty():
		return _fail(InvoError.invalid_input("sourceGameId", source_game_id, "is required"))
	var path: String = "/api/currency-sends/available-destinations" if direction == "send" \
			else "/api/transfers/available-destinations"
	var res: InvoResult = await _http.post_json(
			path, {"source_game_id": source_game_id}, _auth, true)
	return InvoResult.success(InvoMap.to_destinations_result(res.dict(), direction)) \
			if res.ok else res


# ---- Phone-share OTP handshake (UNAUTHENTICATED, phone-owner-driven) ----

## Send the fallback phone-share OTP — resolves a 409 PHONE_SHARE_APPROVAL_REQUIRED.
## NOT idempotent (sends an OTP; TTL ~10 min).
func phone_share_initiate(phone: String, email: String) -> InvoResult:
	if not InvoValidate.is_present(phone):
		return _fail(InvoError.invalid_input("phone", phone, "is required"))
	if not InvoValidate.is_present(email):
		return _fail(InvoError.invalid_input("email", email, "is required"))
	var res: InvoResult = await _http.post_json("/api/wallet/phone-share/initiate",
			{"phone": phone, "email": email}, {})
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	return InvoResult.success({
		"approval_id": raw.get("approval_id"),
		"code_sent": raw.get("code_sent") if raw.get("code_sent") is bool else null,
		"expires_at": raw.get("expires_at"),
		"already_approved": raw.get("already_approved")
				if raw.get("already_approved") is bool else null,
		"raw": raw,
	})


## Approve a phone-share with the OTP the phone owner received; then RE-ISSUE
## the identical original request. NOT idempotent (attempts are counted).
func phone_share_approve(approval_id: String, otp: String) -> InvoResult:
	if not InvoValidate.is_present(approval_id):
		return _fail(InvoError.invalid_input("approvalId", approval_id, "is required"))
	if not InvoValidate.is_present(otp):
		return _fail(InvoError.invalid_input("otp", otp, "is required"))
	var res: InvoResult = await _http.post_json("/api/wallet/phone-share/approve",
			{"approval_id": approval_id, "otp": otp}, {})
	if not res.ok:
		return res
	var raw: Dictionary = res.dict()
	return InvoResult.success({
		"approval_id": raw.get("approval_id"),
		"approved": raw.get("approved") if raw.get("approved") is bool else null,
		"already_approved": raw.get("already_approved")
				if raw.get("already_approved") is bool else null,
		"expires_at": raw.get("expires_at"),
		"raw": raw,
	})


## Poll whether a phone-share (phone, requesting_email) pair is approved yet.
func phone_share_status(phone: String, email: String) -> InvoResult:
	if not InvoValidate.is_present(phone):
		return _fail(InvoError.invalid_input("phone", phone, "is required"))
	if not InvoValidate.is_present(email):
		return _fail(InvoError.invalid_input("email", email, "is required"))
	var res: InvoResult = await _http.get_json(
			"/api/wallet/phone-share/status?phone=%s&email=%s" % [
				phone.uri_encode(), email.uri_encode()], {})
	if not res.ok:
		return res
	return InvoResult.success({
		"approved": res.dict().get("approved") == true,
		"raw": res.dict(),
	})


# ---- Internal ----

static func _fail(err: InvoError) -> InvoResult:
	return InvoResult.failure(err)


static func _require_txn_pin(transaction_id: String, sms_pin: String) -> InvoError:
	if not InvoValidate.is_present(transaction_id):
		return InvoError.invalid_input("transactionId", transaction_id, "is required")
	if not InvoValidate.is_present(sms_pin):
		return InvoError.invalid_input("smsPin", sms_pin, "is required")
	return null

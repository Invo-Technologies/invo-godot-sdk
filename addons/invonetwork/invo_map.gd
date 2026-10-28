class_name InvoMap
extends RefCounted
## Wire-body -> result-Dictionary mappers shared by the client and sandbox
## entries. Every mapped dict keeps the raw body under "raw" so nothing the
## backend returns is ever lost.


static func _sf(row: Dictionary, key: String) -> String:
	## String field: missing OR present-null -> "" (matches the JS `x ?? ""`).
	var v: Variant = row.get(key)
	return "" if v == null else str(v)


static func _idf(row: Dictionary, key: String) -> Variant:
	## Id field (String|int): present-null -> "", else keep as-is.
	var v: Variant = row.get(key)
	return "" if v == null else v


static func to_initiate_result(raw: Dictionary) -> Dictionary:
	# The minor/guardian path (202) layers `guardian_approval` onto a body that
	# ALSO carries verification_method:"sms" — guardian approval takes
	# precedence, so the method is suppressed when it is present.
	var vm: Variant = raw.get("verification_method")
	# An empty-but-present guardian block still suppresses verification_method,
	# so a guardian-pending minor is never routed into the SMS-PIN UI.
	var has_guardian: bool = raw.get("guardian_approval") != null
	var method: String = ""
	if not has_guardian and (vm is String) and (vm in ["in_app", "sms"]):
		method = vm
	return {
		"transaction_id": _sf(raw, "transaction_id"),
		# A 2xx is not success: "success", "pending_guardian_approval",
		# "pending_confirmation" or "needs_account_selection" — branch on it.
		"status": _sf(raw, "status"),
		"verification_method": method,
		"guardian_approval": raw.get("guardian_approval") if has_guardian else null,
		"raw": raw,
	}


static func to_claim_result(raw: Dictionary) -> Dictionary:
	# A 200 can carry status="needs_account_selection" + candidates (multi-
	# account phone) — a normal disambiguation result, NOT an error.
	var status: String = _sf(raw, "status")
	var candidates: Variant = raw.get("candidates")
	return {
		"status": status,
		"transaction_id": raw.get("transaction_id"),
		"new_balance": raw.get("new_balance"),
		"currency_name": raw.get("currency_name"),
		"order_id": raw.get("order_id"),
		"needs_account_selection": status == "needs_account_selection",
		"candidates": candidates if candidates is Array else null,
		"raw": raw,
	}


static func to_sms_verify_result(raw: Dictionary) -> Dictionary:
	return {
		"status": _sf(raw, "status"),
		"transaction_id": _sf(raw, "transaction_id"),
		"claim_code": raw.get("claim_code"),
		"new_balance": raw.get("new_balance"),
		"order_id": raw.get("order_id"),
		"raw": raw,
	}


static func to_transaction_status(raw: Dictionary) -> Dictionary:
	return {
		"transaction_id": _sf(raw, "transaction_id"),
		"transaction_type": _sf(raw, "transaction_type"),
		"transaction_status": _sf(raw, "transaction_status"),
		"verification_state": _sf(raw, "verification_state"),
		"amount": raw.get("amount"),
		"net_amount": raw.get("net_amount"),
		"currency_id": _idf(raw, "currency_id"),
		"order_id": raw.get("order_id"),
		"to_phone": raw.get("to_phone"),
		"to_identity_id": raw.get("to_identity_id"),
		# Transfers: the self-claim code, filled for the source game once approved.
		"claim_code": raw.get("claim_code"),
		"claim_code_expires_at": raw.get("claim_code_expires_at"),
		"failure_reason": raw.get("failure_reason"),
		"raw": raw,
	}


static func to_guardian_approval_status(raw: Dictionary) -> Dictionary:
	var approval: Dictionary = raw.get("approval") if raw.get("approval") is Dictionary else {}
	return {
		"state": _sf(approval, "state"),
		"approval_id": approval.get("approval_id"),
		"transaction_id": approval.get("transaction_id"),
		"expires_at": approval.get("expires_at"),
		"decided_at": approval.get("decided_at"),
		"decision_source": approval.get("decision_source"),
		"action_description": approval.get("action_description"),
		"raw": raw,
	}


static func to_order_details(raw: Dictionary) -> Dictionary:
	return {
		"order": raw.get("order") if raw.get("order") is Dictionary else {},
		"financial_summary": raw.get("financial_summary")
				if raw.get("financial_summary") is Dictionary else {},
		"status_timeline": raw.get("status_timeline"),
		"raw": raw,
	}


static func to_currency_balance(row: Dictionary) -> Dictionary:
	return {
		"currency_id": _idf(row, "currency_id"),
		"currency_name": _sf(row, "currency_name"),
		"currency_symbol": _sf(row, "currency_symbol"),
		"available_balance": _sf(row, "available_balance"),
		"reserved_balance": _sf(row, "reserved_balance"),
		"total_balance": _sf(row, "total_balance"),
		"last_transaction": row.get("last_transaction"),
		"raw": row,
	}


static func to_inbound_pending_item(row: Dictionary) -> Dictionary:
	return {
		"transaction_id": _sf(row, "transaction_id"),
		"flow": _sf(row, "flow"),
		"amount": _sf(row, "amount"),
		"net_amount": _sf(row, "net_amount"),
		"source_game_id": _idf(row, "source_game_id"),
		"source_game": _sf(row, "source_game"),
		"to_phone": _sf(row, "to_phone"),
		"to_identity_id": row.get("to_identity_id"),
		"created_at": _sf(row, "created_at"),
		"claim_code_expires_at": _sf(row, "claim_code_expires_at"),
		"raw": row,
	}


static func to_destination_game(row: Dictionary) -> Dictionary:
	return {
		"game_id": _idf(row, "game_id"),
		"game_name": _sf(row, "game_name"),
		"tenant_type": row.get("tenant_type"),
		"developer_name": row.get("developer_name"),
		"publisher_name": row.get("publisher_name"),
		"genre": row.get("genre"),
		"platform": row.get("platform"),
		"game_status": row.get("game_status"),
		"game_icon": row.get("game_icon"),
		"game_poster": row.get("game_poster"),
		"game_url": row.get("game_url"),
		"game_description": row.get("game_description"),
		"currency_name": _sf(row, "currency_name"),
		"currency_symbol": _sf(row, "currency_symbol"),
		"currency_symbol_url": row.get("currency_symbol_url"),
		"minimum_transfer": _sf(row, "minimum_transfer"),
		"maximum_transfer": _sf(row, "maximum_transfer"),
		"accepts_steam_origin_value": row.get("accepts_steam_origin_value") == true,
		"raw": row,
	}


static func to_destinations_result(raw: Dictionary, direction: String) -> Dictionary:
	var games_raw: Variant = raw.get("available_games")
	var games: Array = games_raw if games_raw is Array else []
	var mapped: Array[Dictionary] = []
	for g: Variant in games:
		if g is Dictionary:
			mapped.append(to_destination_game(g))
	var raw_total: Variant = raw.get("total_destinations")
	var total: int = mapped.size()
	if raw_total != null:
		if raw_total is int or raw_total is float:
			total = int(raw_total)
		elif raw_total is String and (raw_total as String).strip_edges().is_valid_int():
			total = (raw_total as String).to_int()
	var raw_direction: Variant = raw.get("direction")
	var linked: Variant = raw.get("linked_game_ids")
	return {
		"status": _sf(raw, "status"),
		"source_game_id": _idf(raw, "source_game_id"),
		"source_game_name": _sf(raw, "source_game_name"),
		"source_game_icon": raw.get("source_game_icon"),
		"source_currency_name": _sf(raw, "source_currency_name"),
		"source_currency_icon": raw.get("source_currency_icon"),
		"universal_transfers": raw.get("universal_transfers") == true,
		"transfer_mode": _sf(raw, "transfer_mode"),
		"available_games": mapped,
		"total_destinations": total,
		"direction": str(raw_direction) if raw_direction != null else direction,
		"linked_game_ids": linked if linked is Array else null,
		"raw": raw,
	}


static func to_player_balance_result(raw: Dictionary) -> Dictionary:
	var rows: Variant = raw.get("balances")
	var balances: Array[Dictionary] = []
	if rows is Array:
		for r: Variant in rows:
			if r is Dictionary:
				balances.append(to_currency_balance(r))
	return {
		"player": raw.get("player") if raw.get("player") is Dictionary else {},
		"balances": balances,
		"summary": raw.get("summary") if raw.get("summary") is Dictionary else {},
		"raw": raw,
	}


static func to_client_balance_result(raw: Dictionary) -> Dictionary:
	## The player-token /api/sdk/balance shape (browser-client parity).
	var rows: Variant = raw.get("balances")
	var summary: Dictionary = raw.get("summary") if raw.get("summary") is Dictionary else {}
	var count: Variant = summary.get("currency_count")
	var balances: Array = rows if rows is Array else []
	return {
		"game_id": raw.get("game_id") if raw.get("game_id") != null else "",
		"game_name": _sf(raw, "game_name"),
		"balances": balances,
		"total_value": str(summary.get("total_value")) if summary.get("total_value") != null else "0",
		"currency_count": int(count) if (count is int or count is float) else balances.size(),
		"has_funds": summary.get("has_funds") == true,
		"raw": raw,
	}


static func _intf(row: Dictionary, key: String, fallback: int = 0) -> int:
	## Integer field: int/float/integer-string -> int, anything else -> fallback.
	var v: Variant = row.get(key)
	if v is bool:
		return fallback
	if v is int or v is float:
		return int(v)
	if v is String and (v as String).strip_edges().is_valid_int():
		return (v as String).strip_edges().to_int()
	return fallback


static func _numf(row: Dictionary, key: String) -> Variant:
	## Number field: float, or null when missing/null/not numeric.
	var v: Variant = row.get(key)
	if v is bool:
		return null
	if v is int or v is float:
		return float(v)
	if v is String and (v as String).strip_edges().is_valid_float():
		return (v as String).strip_edges().to_float()
	return null


# ---- Device approval (RFC 8628 QR / system-browser flow) ----

## The four device-approval flows; the flow picks the settle endpoint.
const APPROVAL_FLOWS: Array[String] = ["transfer", "send", "send_receipt", "transfer_receipt"]
## A settle 2xx with one of these statuses is a HOLD: nothing moved, nothing refused.
const SETTLE_HOLD_STATUSES: Array[String] = [
	"pending_guardian_approval", "held_for_review", "step_up_required", "pending_confirmation"]


## POST /api/sdk/approvals/device/begin. device_code is a bearer factor for
## poll + settle: keep it in memory, never show or log it.
static func to_device_grant(raw: Dictionary) -> Dictionary:
	return {
		"device_code": _sf(raw, "device_code"),
		"user_code": _sf(raw, "user_code"),
		"verification_uri": _sf(raw, "verification_uri"),
		"verification_uri_complete": _sf(raw, "verification_uri_complete"),
		"expires_in": _intf(raw, "expires_in"),
		"interval": _intf(raw, "interval"),
		"channel": _sf(raw, "channel"),
		"raw": raw,
	}


## The `enrollment` block a pending poll carries while a first-time phone
## waits for the game screen to confirm its match code.
static func to_enrollment(row: Dictionary) -> Dictionary:
	return {
		"state": _sf(row, "state"),
		"device_label": _sf(row, "device_label"),
		"match_code": _sf(row, "match_code"),
		"requested_at": row.get("requested_at"),
		"recovery": row.get("recovery") == true,
		"raw": row,
	}


## One poll folded into one shape: the approved 200 body and the RFC 8628
## 400 outcomes alike. `status` is approved | authorization_pending |
## slow_down | access_denied | expired_token.
static func to_device_poll(raw: Dictionary, status: String) -> Dictionary:
	var enrollment: Variant = raw.get("enrollment")
	return {
		"status": status,
		"transaction_id": _sf(raw, "transaction_id"),
		"flow": _sf(raw, "flow"),
		"approved_at": raw.get("approved_at"),
		"interval": _intf(raw, "interval"),
		"enrollment": to_enrollment(enrollment) if enrollment is Dictionary else null,
		"raw": raw,
	}


## The approve / confirm-receipt answer (THE call that moves money).
static func to_settle_result(raw: Dictionary) -> Dictionary:
	var status: String = _sf(raw, "status")
	var hold_reason: String = _sf(raw, "error_code")
	if hold_reason.is_empty():
		hold_reason = _sf(raw, "code")
	return {
		"status": status,
		"next": raw.get("next"),
		"transaction_id": _sf(raw, "transaction_id"),
		"claim_code": raw.get("claim_code"),
		"claim_code_expires_at": raw.get("claim_code_expires_at"),
		"amount_received": raw.get("amount_received"),
		"is_hold": status in SETTLE_HOLD_STATUSES,
		"hold_reason": hold_reason,
		"guardian_approval": raw.get("guardian_approval")
				if raw.get("guardian_approval") is Dictionary else null,
		"poll_endpoint": raw.get("poll_endpoint"),
		# Set by the client on TRANSACTION_NOT_PENDING (status "not_pending").
		"current_status": "",
		"already_settled": false,
		"raw": raw,
	}


## One row of GET /api/sdk/transfers/pending. `approval_flow` is the device
## flow that approves (identity_gate) or collects (receiving_confirm) it.
static func to_pending_action(row: Dictionary) -> Dictionary:
	var kind: String = _sf(row, "kind")
	var flow: String = _sf(row, "flow")
	var receiving: bool = kind == "receiving_confirm"
	var approval_flow: String
	if flow == "transfer":
		approval_flow = "transfer_receipt" if receiving else "transfer"
	else:
		approval_flow = "send_receipt" if receiving else "send"
	return {
		"transfer_id": _sf(row, "transfer_id"),
		"kind": kind,
		"flow": flow,
		"amount": _sf(row, "amount"),
		"currency": _sf(row, "currency"),
		"counterparty_game": _sf(row, "counterparty_game"),
		"expires_at": row.get("expires_at"),
		"step_up_required": row.get("step_up_required") == true,
		"held": row.get("held") == true,
		"hold_reason": row.get("hold_reason"),
		"approval_flow": approval_flow,
		"raw": row,
	}


# ---- Store catalog ----

static func to_game_item(row: Dictionary) -> Dictionary:
	var price: Variant = _numf(row, "price_usd")
	var original: Variant = _numf(row, "original_price_usd")
	var amount: Variant = _numf(row, "currency_amount")
	var bonus: Variant = _numf(row, "bonus_amount")
	var discount: Variant = row.get("discount_percentage")
	var remaining: Variant = null
	if row.get("time_remaining_seconds") != null:
		remaining = _intf(row, "time_remaining_seconds", 0)
	var meta: Variant = row.get("metadata")
	return {
		"item_id": _sf(row, "item_id"),
		"game_id": _idf(row, "game_id"),
		"item_name": _sf(row, "item_name"),
		"display_name": _sf(row, "display_name"),
		"display_subtitle": _sf(row, "display_subtitle"),
		"display_tag": _sf(row, "display_tag"),
		"display_getting": _sf(row, "display_getting"),
		"item_description": _sf(row, "item_description"),
		"item_category": _sf(row, "item_category"),
		"item_type": _sf(row, "item_type"),
		"item_rarity": _sf(row, "item_rarity"),
		"item_color": _sf(row, "item_color"),
		"image_url": _sf(row, "image_url"),
		"icon_url": _sf(row, "icon_url"),
		"thumbnail_url": _sf(row, "thumbnail_url"),
		"is_featured": row.get("is_featured") == true,
		"is_most_popular": row.get("is_most_popular") == true,
		"is_best_value": row.get("is_best_value") == true,
		"is_active": row.get("is_active") != false,
		"price_usd": price if price != null else 0.0,
		"original_price_usd": original,
		"is_discounted": original != null and price != null and float(original) > float(price),
		"discount_percentage": int(discount) if (discount is int or discount is float) else null,
		"currency_amount": amount if amount != null else 0.0,
		"bonus_amount": bonus if bonus != null else 0.0,
		"is_limited_time": row.get("is_limited_time") == true,
		"available_from": row.get("available_from"),
		"available_until": row.get("available_until"),
		"time_remaining_seconds": remaining,
		"time_remaining_display": row.get("time_remaining_display"),
		"metadata": meta if meta is Dictionary else {},
		"raw": row,
	}


## POST /api/v1/game-items/list, pre-split the way the Unity store renders it:
## `featured` = the first is_featured item (the hero slot, null when none),
## `weekly` = item_category "weekly" minus the hero, `daily` = "daily".
static func to_game_items_result(raw: Dictionary) -> Dictionary:
	var rows: Variant = raw.get("items")
	var items: Array[Dictionary] = []
	if rows is Array:
		for r: Variant in rows:
			if r is Dictionary:
				items.append(to_game_item(r))
	var featured_index: int = -1
	for i: int in items.size():
		if items[i]["is_featured"]:
			featured_index = i
			break
	var weekly: Array[Dictionary] = []
	var daily: Array[Dictionary] = []
	for i: int in items.size():
		var category: String = str(items[i]["item_category"]).to_lower()
		if category == "weekly" and i != featured_index:
			weekly.append(items[i])
		elif category == "daily":
			daily.append(items[i])
	var featured: Variant = null
	if featured_index >= 0:
		featured = items[featured_index]
	return {
		"status": _sf(raw, "status"),
		"items": items,
		"total_items": _intf(raw, "total_items", items.size()),
		"featured": featured,
		"weekly": weekly,
		"daily": daily,
		"raw": raw,
	}


# ---- Player destinations ("games you play") ----

static func to_player_destination(row: Dictionary) -> Dictionary:
	var ccy: Dictionary = row.get("default_currency") \
			if row.get("default_currency") is Dictionary else {}
	return {
		"game_id": _idf(row, "game_id"),
		"game_name": _sf(row, "game_name"),
		"tenant_type": row.get("tenant_type"),
		"game_status": row.get("game_status"),
		"default_currency": {
			"currency_id": _idf(ccy, "currency_id"),
			"currency_name": _sf(ccy, "currency_name"),
			"currency_symbol": _sf(ccy, "currency_symbol"),
		},
		"available_balance": _sf(row, "available_balance"),
		"last_active": row.get("last_active"),
		"raw": row,
	}


## Most recent activity first. NOT filtered like available-destinations:
## offer only games that also appear in get_destinations().
static func to_player_destinations_result(raw: Dictionary) -> Dictionary:
	var rows: Variant = raw.get("destinations")
	var mapped: Array[Dictionary] = []
	if rows is Array:
		for r: Variant in rows:
			if r is Dictionary:
				mapped.append(to_player_destination(r))
	return {
		"status": _sf(raw, "status"),
		"source_game_id": _idf(raw, "source_game_id"),
		"source_game_name": _sf(raw, "source_game_name"),
		"transfer_mode": _sf(raw, "transfer_mode"),
		"destinations": mapped,
		"raw": raw,
	}


# ---- Player phone ----

## POST /api/sdk/players/phone. When identity_rekeyed is true the old player
## token belongs to the old identity: switch to player_token.
static func to_phone_change_result(raw: Dictionary) -> Dictionary:
	return {
		"status": _sf(raw, "status"),
		"identity_rekeyed": raw.get("identity_rekeyed") == true,
		"identity_id": _sf(raw, "identity_id"),
		"player_token": _sf(raw, "player_token"),
		"player_token_expires_at": _sf(raw, "player_token_expires_at"),
		"raw": raw,
	}


## A phone change request (create 202 / status 200). The player confirms on
## INVO's emailed page, never in the game.
static func to_phone_change_request(raw: Dictionary) -> Dictionary:
	var status: String = _sf(raw, "status")
	return {
		"change_request_id": _sf(raw, "change_request_id"),
		"status": status,
		"confirmation": _sf(raw, "confirmation"),
		"delivery": _sf(raw, "delivery"),
		"message": _sf(raw, "message"),
		"new_phone_masked": _sf(raw, "new_phone_masked"),
		"created_at": raw.get("created_at"),
		"expires_at": raw.get("expires_at"),
		"confirmed_at": raw.get("confirmed_at"),
		"confirmed_via": raw.get("confirmed_via"),
		"is_pending": status in ["pending", "pending_confirmation"],
		"is_confirmed": status == "confirmed",
		"raw": raw,
	}


## The short on-screen form of a phone, "••• 0111" (last four digits only) —
## the same mask the Unity phone panel shows. There is no INVO route that
## returns the player's phone; mask the number your game already holds.
static func mask_phone_short(phone: String) -> String:
	var digits: String = ""
	for i: int in phone.length():
		var c: String = phone[i]
		if c >= "0" and c <= "9":
			digits += c
	if digits.length() <= 4:
		return "•••" if not phone.strip_edges().is_empty() else ""
	return "••• " + digits.substr(digits.length() - 4)

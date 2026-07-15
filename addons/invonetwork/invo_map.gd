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

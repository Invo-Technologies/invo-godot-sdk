class_name InvoError
extends RefCounted
## The single error type produced by the INVO Godot SDK.
##
## Mirrors the Python/JS SDKs: the backend envelope is usually
## `{"error": <message>, "code": <STABLE_CODE>}`, but a few txn-state/claim
## errors carry only `error` (no `code`) and some use
## `{"status": "error", "message": ...}` — so `code` may be empty; branch on
## `code` when present, else fall back to `message`.

var message: String = ""
## Stable machine code from the backend, "" when absent.
var code: String = ""
## HTTP status. 0 for client-side validation and network errors.
var status: int = 0
## Raw parsed response body (Dictionary/String/null) for debugging.
var body: Variant = null
## Backend request id from response headers — quote it in support tickets.
var request_id: String = ""

static var _promotable_re: RegEx = null
static var _insufficient_re: RegEx = null
static var _not_enrolled_re: RegEx = null
static var _duplicate_re: RegEx = null


static func _regexes() -> void:
	if _promotable_re != null:
		return
	_promotable_re = RegEx.create_from_string(
		"^(flow_paused|spending_limit_exceeded|receiver_not_enrolled_use_claim_code" +
		"|no_channel_on_file|rate_limited)$")
	_insufficient_re = RegEx.create_from_string("(?i)insufficient[_ ]balance")
	_not_enrolled_re = RegEx.create_from_string("(?i)receiver_not_enrolled_use_claim_code")
	_duplicate_re = RegEx.create_from_string("(?i)duplicate")


static func make(p_message: String, p_code: String = "", p_status: int = 0,
		p_body: Variant = null, p_request_id: String = "") -> InvoError:
	var err: InvoError = InvoError.new()
	err.message = p_message
	err.code = p_code
	err.status = p_status
	err.body = p_body
	err.request_id = p_request_id
	return err


static func invalid_input(label: String, value: Variant, why: String) -> InvoError:
	return make("%s %s (got %s)." % [label, why, var_to_str(value)], "INVALID_INPUT", 0)


## Build an InvoError from a parsed (or text) non-2xx response body.
static func from_response(p_status: int, p_body: Variant, p_request_id: String = "") -> InvoError:
	_regexes()
	var msg: String = "INVO request failed (HTTP %d)" % p_status
	var c: String = ""
	if p_body is Dictionary:
		var d: Dictionary = p_body
		if d.get("code") is String:
			c = d["code"]
		elif d.get("error_code") is String:
			c = d["error_code"]
		if d.get("error") is String:
			msg = d["error"]
		elif d.get("message") is String:
			msg = d["message"]
		# A few txn-state errors ship only an `error` token with no code —
		# promote the known ones so consumers can branch on `code`.
		if c.is_empty() and d.get("error") is String \
				and _promotable_re.search(d["error"]) != null:
			c = d["error"]
	elif p_body is String and not (p_body as String).strip_edges().is_empty():
		msg = p_body
	if c == "KEY_FOR_OTHER_ENVIRONMENT":
		msg = KEY_FOR_OTHER_ENVIRONMENT_MESSAGE
	return make(msg, c, p_status, p_body, p_request_id)


## Shown when a sandbox key reaches production or the other way round (HTTP 401).
const KEY_FOR_OTHER_ENVIRONMENT_MESSAGE: String = "This key belongs to the other Invo environment. " \
		+ "Check sandbox/production in Project Settings > invonetwork/config/environment: sandbox keys " \
		+ "start with ivsdk_test_ and production keys (kept on your game server) with ivsdk_live_."


func _body_object() -> Dictionary:
	return body if body is Dictionary else {}


func _to_string() -> String:
	return "InvoError(code=%s, status=%d, message=%s)" % [code, status, message]


# ---- Classifiers (mirror the Python/JS getters) ----

## "Recipient isn't passkey-enrolled, fall back to claim code."
func is_receiver_not_enrolled() -> bool:
	_regexes()
	return code == "receiver_not_enrolled_use_claim_code" \
			or _not_enrolled_re.search(message) != null


## The session/SDK token expired — re-mint and retry.
func is_token_expired() -> bool:
	return code == "SDK_TOKEN_EXPIRED"


## A sandbox key was sent to production, or a production key to the sandbox.
func is_key_for_other_environment() -> bool:
	return code == "KEY_FOR_OTHER_ENVIRONMENT"


func is_enrollment_authorization_required() -> bool:
	return code == "ENROLLMENT_REQUIRES_AUTHORIZATION"


func is_user_verification_required() -> bool:
	return code == "WEBAUTHN_UV_REQUIRED"


func is_enrollment_proof_required() -> bool:
	return code == "ENROLLMENT_REQUIRES_PROOF"


## Item purchase failed on balance (400 only — the 429 abuse throttle with the
## same words is a rate limit, not a top-up condition).
func is_insufficient_balance() -> bool:
	_regexes()
	if status != 400:
		return false
	var b: Dictionary = _body_object()
	return code == "INSUFFICIENT_BALANCE" or b.has("required_amount") \
			or _insufficient_re.search(message) != null


## 409: the call needs phone-share approval first. NOT a failure — the money is
## held and the phone owner is texted. Show `message` (see phone_share_last4),
## then RE-ISSUE the same call once approved; on denial/expiry the sender is refunded.
func is_phone_share_approval_required() -> bool:
	return code == "PHONE_SHARE_APPROVAL_REQUIRED"


func phone_share_approval_id() -> String:
	var v: Variant = _body_object().get("approval_id")
	return v if v is String else ""


## Last 4 digits of the phone that must approve, for the UI message.
func phone_share_last4() -> String:
	var v: Variant = _body_object().get("phone_last4")
	return v if v is String else ""


## 409: moving more than the non-Steam balance to a non-Steam destination.
## Cap the amount at steam_transferable_max().
func is_steam_value_non_transferable() -> bool:
	return code == "STEAM_VALUE_NON_TRANSFERABLE"


func steam_transferable_max() -> String:
	var v: Variant = _body_object().get("transferable_max")
	return v if v is String else ""


func steam_origin_amount() -> String:
	var v: Variant = _body_object().get("steam_origin_amount")
	return v if v is String else ""


## 409: moving NON-Steam value INTO a Steam title. Pick another destination.
func is_non_steam_value_into_steam_blocked() -> bool:
	return code == "NON_STEAM_VALUE_INTO_STEAM_BLOCKED"


func is_phone_share_already_approved() -> bool:
	return code == "PHONE_SHARE_ALREADY_APPROVED"


func is_enrollment_code_invalid() -> bool:
	return code == "ENROLLMENT_CODE_INVALID"


## 403 SIM-swap protection: money-OUT paused for 24h after a passkey reset.
## Show the pause message with retry_after_at(); do not retry-loop.
func is_passkey_recovery_cooldown() -> bool:
	return code == "PASSKEY_RECOVERY_COOLDOWN"


## ISO timestamp when a PASSKEY_RECOVERY_COOLDOWN lifts ("" when absent).
## A numeric retry_after (throttle seconds) is retry_after_seconds(), not this.
func retry_after_at() -> String:
	var v: Variant = _body_object().get("retry_after")
	if not (v is String):
		return ""
	var s: String = (v as String)
	if s.strip_edges().is_empty():
		return ""
	if s.strip_edges().is_valid_float():
		return ""  # numeric string -> that's the throttle field
	return s


## Idempotency-keyed duplicate (item purchase -> 409).
func is_duplicate_request() -> bool:
	_regexes()
	return code == "DUPLICATE_REQUEST" \
			or (status == 409 and _duplicate_re.search(message) != null)


## Seconds to wait before retrying a throttled call (-1.0 when absent/invalid).
func retry_after_seconds() -> float:
	var v: Variant = _body_object().get("retry_after")
	var n: float
	if v is bool:
		return -1.0
	if v is String:
		if not (v as String).strip_edges().is_valid_float():
			return -1.0
		n = (v as String).to_float()
	elif v is int or v is float:
		n = float(v)
	else:
		return -1.0
	if is_finite(n) and n >= 0.0:
		return n
	return -1.0

class_name InvoValidate
extends RefCounted
## Client-side validation, ported from the Python/JS SDKs so a coerced-but-
## unintended value never reaches the wire.

## Max single currency purchase in USD (backend rejects amounts above this).
const MAX_USD_AMOUNT: float = 999.99
## Max item price in game-currency units.
const MAX_ITEM_PRICE: float = 999999.99

static var _decimal_re: RegEx = null
static var _e164_re: RegEx = null


static func _regexes() -> void:
	if _decimal_re != null:
		return
	# \z (not $): a trailing newline must not slip past the anchor.
	_decimal_re = RegEx.create_from_string("^\\d+(\\.\\d{1,2})?\\z")
	# E.164: leading +, country code, up to 15 digits, e.g. "+15555550100".
	# The backend keys network identity off the phone and only matches E.164.
	_e164_re = RegEx.create_from_string("^\\+[1-9]\\d{1,14}\\z")


static func is_present(value: Variant) -> bool:
	return value is String and not (value as String).strip_edges().is_empty()


## null when valid; an INVALID_INPUT InvoError otherwise.
## Requires > 0, <= max_value, at most 2 decimal places. Rejects non-plain-
## decimal strings (hex, scientific, signs, embedded whitespace).
static func money_problem(value: Variant, max_value: float, label: String) -> InvoError:
	_regexes()
	var why: String = "must be a positive decimal with at most 2 places"
	var n: float
	if value is bool:
		return InvoError.invalid_input(label, value, why)
	if value is int:
		n = float(value)
	elif value is float:
		var f: float = value
		if not is_finite(f):
			return InvoError.invalid_input(label, value, why)
		# At most 2 decimal places: exact in integer cents. ABSOLUTE epsilon —
		# a relative comparison (is_equal_approx) would wrongly accept
		# 3-decimal values at large magnitudes (e.g. 999999.999).
		if absf(roundf(f * 100.0) - f * 100.0) > 0.000001:
			return InvoError.invalid_input(label, value, why)
		n = f
	elif value is String:
		if _decimal_re.search(value) == null:
			return InvoError.invalid_input(label, value,
					"must be a plain decimal value with at most 2 places")
		n = (value as String).to_float()
	else:
		return InvoError.invalid_input(label, value, why)
	if not is_finite(n) or n <= 0.0 or n > max_value:
		return InvoError.invalid_input(label, value, "must be > 0 and <= %s" % max_value)
	return null


## null when valid E.164, else an INVALID_INPUT InvoError.
static func e164_problem(value: Variant, label: String) -> InvoError:
	_regexes()
	if not (value is String) or _e164_re.search(value) == null:
		return InvoError.invalid_input(label, value,
				'must be an E.164 phone number, e.g. "+15555550100"')
	return null


## Money value as a float (call only after money_problem returned null).
static func money_value(value: Variant) -> float:
	if value is String:
		return (value as String).to_float()
	return float(value)


## Round half away from +inf (matches JS Math.round for positive values).
static func round_half_up(x: float) -> int:
	return int(floor(x + 0.5))

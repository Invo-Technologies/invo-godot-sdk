class_name InvoHttp
extends Node
## HTTP core for the INVO Godot SDK — a faithful port of the Python SDK's
## transport semantics:
##
## - Retries apply ONLY to idempotent requests (network error/timeout, 429
##   honoring retry_after up to 20s, and 5xx). A non-idempotent POST is never
##   auto-retried (a timeout can fire while the server is mid-processing).
## - Exponential backoff with full jitter: base * 2^attempt, randomized.
## - Redirects are never followed (they would re-send credentials).
## - https is enforced (loopback exempt) — the game secret travels in a header.
## - An explicit User-Agent (the backend 403-blocks blank/scanner UAs).

## Observability signals. URLs are emitted WITHOUT their query string —
## queries can carry player emails/phones (PII) that must not reach logs.
signal request_completed(method: String, url: String, status: int, attempt: int)
signal request_errored(method: String, url: String, error: InvoError, will_retry: bool)

const DEFAULT_TIMEOUT: float = 30.0
const MAX_RETRY_AFTER: float = 20.0
const RETRIABLE_STATUS: Array[int] = [429, 500, 502, 503, 504]
const USER_AGENT: String = "invonetwork-godot-sdk/0.4.0 (+https://invo.network)"

var base_url: String = ""
var timeout: float = DEFAULT_TIMEOUT
var max_retries: int = 2
var retry_base_delay: float = 0.25
## Test/mock override: Callable(method: String, url: String, headers: Dictionary,
## body: Variant) -> Dictionary {status: int, headers: Dictionary, body: Variant}.
var transport: Callable = Callable()


## "" when the URL is acceptable, else the reason it is rejected.
## https only — plaintext would expose the game secret. Loopback http is
## allowed for local development.
static func secure_base_url_problem(url: String) -> String:
	var scheme_split: PackedStringArray = url.split("://", true, 1)
	if scheme_split.size() != 2 or scheme_split[1].is_empty():
		return "Invalid baseUrl: %s" % url
	var scheme: String = scheme_split[0].to_lower()
	var host_port: String = scheme_split[1].split("/", true, 1)[0].to_lower()
	var host: String
	if host_port.begins_with("["):
		host = host_port.split("]", true, 1)[0] + "]"  # bracketed IPv6
	else:
		host = host_port.split(":", true, 1)[0]
	var is_local: bool = host in ["localhost", "127.0.0.1", "[::1]"]
	if scheme == "https" or (scheme == "http" and is_local):
		return ""
	return 'baseUrl must use https:// (got "%s://"). Plaintext would expose the game secret on the wire.' % scheme


func configure(p_base_url: String, p_timeout: float = DEFAULT_TIMEOUT,
		p_max_retries: int = 2, p_retry_base_delay: float = 0.25) -> void:
	# Enforced here, not just at the facade — no code path may downgrade to
	# plaintext with credentials in the headers.
	var problem: String = secure_base_url_problem(p_base_url)
	if not problem.is_empty():
		push_error("[InvoHttp] %s" % problem)
		base_url = ""
		return
	base_url = p_base_url.rstrip("/")
	timeout = p_timeout
	max_retries = maxi(0, p_max_retries)
	retry_base_delay = p_retry_base_delay


## GET is always idempotent -> safe to retry.
func get_json(path: String, auth_headers: Dictionary) -> InvoResult:
	return await _request("GET", path, null, auth_headers, true)


## POST. idempotent=true marks it safe to auto-retry (carries an idempotency key).
func post_json(path: String, body: Variant, auth_headers: Dictionary,
		idempotent: bool = false) -> InvoResult:
	return await _request("POST", path, body, auth_headers, idempotent)


## POST to an ABSOLUTE url (e.g. the partner's own player-token endpoint).
## The same https rule applies.
func post_url(url: String, body: Variant, auth_headers: Dictionary,
		idempotent: bool = false) -> InvoResult:
	var problem: String = secure_base_url_problem(url)
	if not problem.is_empty():
		return InvoResult.failure(InvoError.make(problem, "INVALID_INPUT", 0))
	return await _request("POST", url, body, auth_headers, idempotent)


## Strip CR/LF and other control characters from a header value so a hostile
## string (e.g. a tampered token) can never smuggle extra headers.
static func sanitize_header_value(value: String) -> String:
	var out: String = ""
	for i: int in value.length():
		var c: int = value.unicode_at(i)
		if c >= 0x20 and c != 0x7F:
			out += value[i]
	return out


static func _is_absolute_url(path: String) -> bool:
	return path.begins_with("https://") or path.begins_with("http://")


func _request(method: String, path: String, body: Variant,
		auth_headers: Dictionary, idempotent: bool) -> InvoResult:
	var url: String = path if _is_absolute_url(path) else base_url + path
	if base_url.is_empty() and not _is_absolute_url(path):
		return InvoResult.failure(InvoError.make(
				"InvoHttp is not configured (no base URL).", "NOT_CONFIGURED", 0))
	var headers: Dictionary = {"Accept": "application/json", "User-Agent": USER_AGENT}
	for key: String in auth_headers:
		headers[key] = sanitize_header_value(str(auth_headers[key]))
	var body_text: String = ""
	if body != null:
		headers["Content-Type"] = "application/json"
		body_text = JSON.stringify(body)
	# PII rule: never emit query strings (they can carry emails/phones).
	var loggable_url: String = _redact_url(url)

	var attempt: int = 0
	while true:
		var raw: Dictionary = await _run_transport(method, url, headers, body_text, body)

		if raw.get("network_error", false):
			var message: String
			if raw.get("timeout", false):
				message = "Request to %s timed out after %ss" % [loggable_url, timeout]
			else:
				message = "Network error calling %s: %s" % [
						loggable_url, raw.get("message", "network error")]
			var net_err: InvoError = InvoError.make(message, "", 0)
			var will_retry: bool = idempotent and attempt < max_retries
			request_errored.emit(method, loggable_url, net_err, will_retry)
			if will_retry:
				await get_tree().create_timer(_backoff(attempt)).timeout
				attempt += 1
				continue
			return InvoResult.failure(net_err)

		var status: int = raw.get("status", 0)
		var response_headers: Dictionary = raw.get("headers", {})
		var parsed: Variant = raw.get("body", null)
		var request_id: String = _pick_request_id(response_headers)
		request_completed.emit(method, loggable_url, status, attempt)

		if status < 200 or status >= 300:
			var err: InvoError = InvoError.from_response(status, parsed, request_id)
			var wait: float = -1.0
			if idempotent and attempt < max_retries and status in RETRIABLE_STATUS:
				if status == 429:
					var ra: float = _retry_after_seconds(parsed, response_headers)
					if ra < 0.0:
						wait = _backoff(attempt)
					elif ra <= MAX_RETRY_AFTER:
						wait = ra
					# else: surface the 429 rather than stalling
				else:
					wait = _backoff(attempt)
			request_errored.emit(method, loggable_url, err, wait >= 0.0)
			if wait >= 0.0:
				await get_tree().create_timer(wait).timeout
				attempt += 1
				continue
			return InvoResult.failure(err)

		return InvoResult.success(parsed if parsed != null else {})
	return InvoResult.failure(InvoError.make("unreachable", "", 0))  # for the analyzer


func _run_transport(method: String, url: String, headers: Dictionary,
		body_text: String, body: Variant) -> Dictionary:
	if transport.is_valid():
		# Injected transport (tests/mock). May return a value or a coroutine.
		var out: Variant = await transport.call(method, url, headers, body)
		return out if out is Dictionary else {"network_error": true, "message": "bad mock"}

	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = timeout
	req.max_redirects = 0  # never re-send credentials to a Location header
	req.accept_gzip = true
	add_child(req)
	var header_list: PackedStringArray = []
	for key: String in headers:
		header_list.append("%s: %s" % [key, headers[key]])
	var method_enum: HTTPClient.Method = HTTPClient.METHOD_GET if method == "GET" \
			else HTTPClient.METHOD_POST
	var call_err: Error = req.request(url, header_list, method_enum, body_text)
	if call_err != OK:
		req.queue_free()
		return {"network_error": true, "message": "HTTPRequest.request error %d" % call_err}
	var response: Array = await req.request_completed
	req.queue_free()
	var result: int = response[0]
	var status: int = response[1]
	var raw_headers: PackedStringArray = response[2]
	var raw_body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {
			"network_error": true,
			"timeout": result == HTTPRequest.RESULT_TIMEOUT,
			"message": "transport result %d" % result,
		}
	var header_map: Dictionary = {}
	for line: String in raw_headers:
		var idx: int = line.find(":")
		if idx > 0:
			header_map[line.substr(0, idx).strip_edges().to_lower()] = \
					line.substr(idx + 1).strip_edges()
	var text: String = raw_body.get_string_from_utf8()
	var parsed: Variant = null
	if not text.is_empty():
		var json: JSON = JSON.new()
		parsed = text if json.parse(text) != OK else json.data
	return {"status": status, "headers": header_map, "body": parsed}


## The signal-safe form of a URL: no query string, and the by-email path
## parameter (the one route that carries an email in the PATH) redacted.
static func _redact_url(url: String) -> String:
	var out: String = url.split("?", true, 1)[0]
	var idx: int = out.find("/by-email/")
	if idx != -1:
		out = out.substr(0, idx) + "/by-email/<redacted>"
	return out


func _backoff(attempt: int) -> float:
	var ceiling: float = retry_base_delay * pow(2.0, float(attempt))
	return randf() * ceiling + retry_base_delay


static func _pick_request_id(headers: Dictionary) -> String:
	for name: String in ["x-invo-request-id", "x-request-id"]:
		for key: Variant in headers:
			if String(key).to_lower() == name:
				return str(headers[key])
	return ""


static func _retry_after_seconds(parsed: Variant, headers: Dictionary) -> float:
	if parsed is Dictionary:
		var v: Variant = (parsed as Dictionary).get("retry_after")
		var n: float = -1.0
		if v is bool:
			n = -1.0
		elif v is int or v is float:
			n = float(v)
		elif v is String and (v as String).strip_edges().is_valid_float():
			n = (v as String).to_float()
		if n >= 0.0:
			return n
	for key: Variant in headers:
		if String(key).to_lower() == "retry-after":
			var s: String = str(headers[key])
			if s.strip_edges().is_valid_float() and s.to_float() >= 0.0:
				return s.to_float()
	return -1.0

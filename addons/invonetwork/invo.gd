extends Node
## `Invo` — the INVO Network autoload facade. Added automatically when the
## plugin is enabled; configure it under Project Settings -> Invonetwork
## (or the INVO dock).
##
## Two entries, mirroring the official Unity/Unreal/web SDKs:
##
## - **Client mode** (`Invo.client()`): player-token flows, safe to ship.
##   Your backend mints the token (INVO Python/JS server SDK); wire the
##   endpoint in settings and call login_via_backend(), or push tokens in
##   yourself with set_player_token().
## - **Direct sandbox mode** (`Invo.sandbox()`): the full server API with the
##   game secret, for LOCAL PROTOTYPING against the sandbox only. Refused in
##   the production environment AND in non-debug (release/exported) builds —
##   the secret must never ship in a game build.
##
## Sandbox secret sourcing (first match wins):
##   1. The INVO_SANDBOX_SECRET environment variable  <- recommended: nothing
##      is persisted in project.godot, so nothing can leak into an export.
##   2. Project setting invonetwork/sandbox_only/game_secret (dev convenience).

## A call failed (after retries). Connect for global error UI/logging.
signal request_failed(error: InvoError)
## A player token is set and client-mode calls are ready.
signal logged_in(identity_id: String)
## Convenience re-broadcast after fetch_balance().
signal balance_updated(balance: Dictionary)
## A hosted checkout URL was opened in the system browser.
signal checkout_opened(url: String)

const SETTING_ENVIRONMENT: String = "invonetwork/config/environment"
const SETTING_GAME_ID: String = "invonetwork/config/game_id"
const SETTING_TOKEN_ENDPOINT: String = "invonetwork/config/player_token_endpoint"
const SETTING_SANDBOX_SECRET: String = "invonetwork/sandbox_only/game_secret"
const SECRET_ENV_VAR: String = "INVO_SANDBOX_SECRET"

const BASE_URLS: Dictionary = {
	"sandbox": "https://sandbox.invo.network/sandbox",
	"production": "https://invo.network",
}

var environment: String = "sandbox"
var game_id: String = ""

var _http: InvoHttp
var _client: InvoPlayerClient
var _sandbox: InvoSandboxServer
var _mock_enabled: bool = false


func _ready() -> void:
	_http = InvoHttp.new()
	_http.name = "InvoHttp"
	add_child(_http)
	_http.request_errored.connect(_on_request_errored)
	var env: String = str(ProjectSettings.get_setting(SETTING_ENVIRONMENT, "sandbox"))
	var gid: String = str(ProjectSettings.get_setting(SETTING_GAME_ID, ""))
	setup(env, gid)


## Configure (or re-configure) the SDK. Called automatically from project
## settings; call manually to override at runtime. The player token and
## token provider survive re-configuration.
func setup(p_environment: String, p_game_id: String = "", base_url_override: String = "") -> void:
	var env: String = p_environment if p_environment in BASE_URLS else "sandbox"
	var base: String = base_url_override if not base_url_override.is_empty() \
			else str(BASE_URLS[env])
	var problem: String = InvoHttp.secure_base_url_problem(base)
	if not problem.is_empty():
		# Reject BEFORE mutating: a failed setup() must leave the previous
		# (working) configuration fully intact.
		push_error("[Invo] %s" % problem)
		return
	environment = env
	game_id = p_game_id
	_http.configure(base)
	var previous_token: String = _client.token() if _client != null else ""
	var previous_provider: Callable = _client.token_provider if _client != null else Callable()
	_client = InvoPlayerClient.new(_http, previous_token)
	_client.token_provider = previous_provider
	_sandbox = null


## ------------------------------------------------------------------ client

## The player-token client (safe to ship). Set a token first — via
## login_via_backend(), set_player_token(), or (sandbox) login_sandbox().
func client() -> InvoPlayerClient:
	return _client


## Hand the client a player token your backend minted.
func set_player_token(token: String, identity_id: String = "") -> void:
	_client.set_token(token)
	if _client.has_token():
		logged_in.emit(identity_id)


## Async Callable() -> String that re-mints a token when one expires
## (SDK_TOKEN_EXPIRED) — typically an HTTP call to YOUR backend.
func set_token_provider(provider: Callable) -> void:
	_client.token_provider = provider


## Fetch a player token from YOUR backend's token endpoint (the
## invonetwork/config/player_token_endpoint setting, or `endpoint_override`).
##
## The endpoint is yours: POSTs `payload` as JSON (send whatever your backend
## needs to identify the session) and expects `{"token": "...",
## "identity_id"?: "..."}` back — on your server, that's one call to
## `mint_player_token` with the INVO Python/JS SDK. On success the client is
## logged in and a token provider is wired for automatic re-mint on expiry.
func login_via_backend(payload: Dictionary = {}, endpoint_override: String = "") -> InvoResult:
	var endpoint: String = endpoint_override if not endpoint_override.is_empty() \
			else str(ProjectSettings.get_setting(SETTING_TOKEN_ENDPOINT, ""))
	if endpoint.strip_edges().is_empty():
		return InvoResult.failure(InvoError.make(
				"No player-token endpoint configured. Set " +
				"invonetwork/config/player_token_endpoint (Project Settings or the " +
				"INVO dock) to an endpoint on YOUR backend that mints player tokens.",
				"NO_TOKEN_ENDPOINT", 0))
	var res: InvoResult = await _http.post_url(endpoint.strip_edges(), payload, {})
	if not res.ok:
		return res
	var token: String = str(res.dict().get("token", ""))
	if token.is_empty():
		return InvoResult.failure(InvoError.make(
				"The token endpoint responded without a `token` field.",
				"INVALID_RESPONSE", 0, res.data))
	set_player_token(token, str(res.dict().get("identity_id", "")))
	set_token_provider(func() -> String:
		var refresh: InvoResult = await _http.post_url(endpoint.strip_edges(), payload, {})
		return str(refresh.dict().get("token", "")) if refresh.ok else "")
	return res


## Fetch the player's balance (client mode) and broadcast balance_updated.
func fetch_balance() -> InvoResult:
	var res: InvoResult = await _client.get_balance()
	if res.ok:
		balance_updated.emit(res.dict())
	return res


## ---------------------------------------------------------------- sandbox

## The DIRECT sandbox entry (full server API, game secret). Returns null —
## with a loud error — outside the sandbox environment or in a non-debug
## (release/exported) build.
func sandbox() -> InvoSandboxServer:
	if _mock_enabled:
		if _sandbox == null:
			_sandbox = InvoSandboxServer.new(_http, "mock-secret")
		return _sandbox
	if environment != "sandbox":
		push_error(
			"[Invo] Direct mode is sandbox-only. In production your own backend " +
			"holds the game secret (INVO server SDKs on npm/PyPI) — the secret " +
			"must NEVER ship inside a game build.")
		return null
	if not OS.is_debug_build():
		push_error(
			"[Invo] Direct mode is disabled in release builds. A game secret in " +
			"an exported build is exposed to every player — use your backend + " +
			"player tokens (client mode) instead.")
		return null
	if _sandbox == null:
		var secret: String = _resolve_sandbox_secret()
		if secret.is_empty():
			push_error(
				"[Invo] No sandbox game secret configured. Prefer the %s " % SECRET_ENV_VAR +
				"environment variable (never persisted); or set it in Project " +
				"Settings -> Invonetwork -> Sandbox Only (dev only).")
			return null
		_sandbox = InvoSandboxServer.new(_http, secret)
	return _sandbox


func _resolve_sandbox_secret() -> String:
	var from_env: String = OS.get_environment(SECRET_ENV_VAR).strip_edges()
	if not from_env.is_empty():
		return from_env
	return str(ProjectSettings.get_setting(SETTING_SANDBOX_SECRET, "")).strip_edges()


## Sandbox convenience: mint a player token for an existing sandbox player and
## switch the client to it. (In production this mint happens on YOUR backend.)
func login_sandbox(player_email: String) -> InvoResult:
	var server: InvoSandboxServer = sandbox()
	if server == null:
		return InvoResult.failure(InvoError.make(
				"Direct sandbox mode unavailable.", "SANDBOX_ONLY", 0))
	var res: InvoResult = await server.mint_player_token(player_email)
	if res.ok:
		set_player_token(str(res.dict().get("token", "")), str(res.dict().get("identity_id", "")))
	return res


## Sandbox convenience: create a hosted checkout and open it in the system
## browser. Crediting lands via webhook to YOUR backend; poll get_order_details
## or re-fetch the balance after the player returns.
func open_checkout(player_email: String, usd_amount: Variant) -> InvoResult:
	var server: InvoSandboxServer = sandbox()
	if server == null:
		return InvoResult.failure(InvoError.make(
				"Direct sandbox mode unavailable.", "SANDBOX_ONLY", 0))
	var res: InvoResult = await server.create_checkout(player_email, usd_amount)
	if res.ok:
		var url: String = str(res.dict().get("checkout_url", ""))
		# Scheme allowlist: only ever hand https URLs to the OS. A tampered
		# response must not be able to launch file:// or custom-scheme handlers.
		if not url.begins_with("https://"):
			return InvoResult.failure(InvoError.make(
					"Refusing to open a non-https checkout URL.", "UNSAFE_URL", 0, res.data))
		if not _mock_enabled:
			OS.shell_open(url)
		checkout_opened.emit(url)
	return res


## ------------------------------------------------------------------- mock

## Route every request through the offline mock transport (no network, no
## credentials) — for tests and for trying the UI before you have a sandbox
## account. Debug builds only; a release build refuses (a shipped mock would
## fake commerce results).
func enable_mock() -> void:
	if not OS.is_debug_build():
		push_error("[Invo] The mock transport is for development only and is " +
				"disabled in release builds.")
		return
	_mock_enabled = true
	_http.transport = InvoMock.transport
	if _client != null and not _client.has_token():
		_client.set_token("mock-player-token")


## Return to real transport (still requires configuration/credentials).
func disable_mock() -> void:
	_mock_enabled = false
	_http.transport = Callable()
	_sandbox = null


func is_mock_enabled() -> bool:
	return _mock_enabled


func _on_request_errored(_method: String, _url: String, error: InvoError,
		will_retry: bool) -> void:
	if not will_retry:
		request_failed.emit(error)

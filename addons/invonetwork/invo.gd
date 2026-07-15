extends Node
## `Invo` — the INVO Network autoload facade. Added automatically when the
## plugin is enabled; configure it under Project Settings -> Invonetwork
## (or the INVO dock).
##
## Two entries, mirroring the official Unity/Unreal/web SDKs:
##
## - **Client mode** (`Invo.client()`): player-token flows, safe to ship.
##   Your backend mints the token (INVO Python/JS server SDK) and your game
##   fetches it from an endpoint you own; wire that in `token_provider`.
## - **Direct sandbox mode** (`Invo.sandbox()`): the full server API with the
##   game secret, for LOCAL PROTOTYPING against the sandbox only. Refused in
##   production — the secret must never ship in a game build.

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
## settings; call manually to override at runtime.
func setup(p_environment: String, p_game_id: String = "", base_url_override: String = "") -> void:
	environment = p_environment if p_environment in BASE_URLS else "sandbox"
	game_id = p_game_id
	var base: String = base_url_override if not base_url_override.is_empty() \
			else str(BASE_URLS[environment])
	var problem: String = InvoHttp.secure_base_url_problem(base)
	if not problem.is_empty():
		push_error("[Invo] %s" % problem)
		return
	_http.configure(base)
	_client = InvoPlayerClient.new(_http)
	_sandbox = null


## ------------------------------------------------------------------ client

## The player-token client (safe to ship). Set a token first — either from
## your backend via set_player_token()/token_provider, or in sandbox via
## login_sandbox().
func client() -> InvoPlayerClient:
	return _client


## Hand the client a player token your backend minted.
func set_player_token(token: String, identity_id: String = "") -> void:
	_client.set_token(token)
	if not token.is_empty():
		logged_in.emit(identity_id)


## Async Callable() -> String that re-mints a token when one expires
## (SDK_TOKEN_EXPIRED) — typically an HTTP call to YOUR backend.
func set_token_provider(provider: Callable) -> void:
	_client.token_provider = provider


## Fetch the player's balance (client mode) and broadcast balance_updated.
func fetch_balance() -> InvoResult:
	var res: InvoResult = await _client.get_balance()
	if res.ok:
		balance_updated.emit(res.dict())
	return res


## ---------------------------------------------------------------- sandbox

## The DIRECT sandbox entry (full server API, game secret). Returns null —
## with a loud error — outside the sandbox environment.
func sandbox() -> InvoSandboxServer:
	if environment != "sandbox" and not _mock_enabled:
		push_error(
			"[Invo] Direct mode is sandbox-only. In production your own backend " +
			"holds the game secret (INVO server SDKs on npm/PyPI) — the secret " +
			"must NEVER ship inside a game build.")
		return null
	if _sandbox == null:
		var secret: String = str(ProjectSettings.get_setting(SETTING_SANDBOX_SECRET, ""))
		if secret.is_empty() and not _mock_enabled:
			push_error(
				"[Invo] No sandbox game secret configured. Set it in Project " +
				"Settings -> Invonetwork -> Sandbox Only (editor/dev only).")
			return null
		_sandbox = InvoSandboxServer.new(_http, secret)
	return _sandbox


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
		OS.shell_open(url)
		checkout_opened.emit(url)
	return res


## ------------------------------------------------------------------- mock

## Route every request through the offline mock transport (no network, no
## credentials) — for tests and for trying the UI before you have a sandbox
## account. NOT for shipping.
func enable_mock() -> void:
	_mock_enabled = true
	_http.transport = InvoMock.transport
	if _client != null and not _client.has_token():
		_client.set_token("mock-player-token")


func is_mock_enabled() -> bool:
	return _mock_enabled


func _on_request_errored(_method: String, _url: String, error: InvoError,
		will_retry: bool) -> void:
	if not will_retry:
		request_failed.emit(error)

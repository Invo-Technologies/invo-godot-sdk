@tool
extends Control
## The INVO editor dock: project configuration + a sandbox connection test.

@onready var _environment: OptionButton = %Environment
@onready var _game_id: LineEdit = %GameId
@onready var _token_endpoint: LineEdit = %TokenEndpoint
@onready var _secret: LineEdit = %SandboxSecret
@onready var _test_email: LineEdit = %TestEmail
@onready var _status: Label = %Status


func _ready() -> void:
	_environment.clear()
	_environment.add_item("sandbox")
	_environment.add_item("production")
	_load_settings()
	%SaveButton.pressed.connect(_on_save)
	%TestButton.pressed.connect(_on_test)
	%DocsButton.pressed.connect(func() -> void:
		OS.shell_open("https://docs.invo.network/"))


func _load_settings() -> void:
	var env: String = str(ProjectSettings.get_setting("invonetwork/config/environment", "sandbox"))
	_environment.select(1 if env == "production" else 0)
	_game_id.text = str(ProjectSettings.get_setting("invonetwork/config/game_id", ""))
	_token_endpoint.text = str(ProjectSettings.get_setting(
			"invonetwork/config/player_token_endpoint", ""))
	_secret.text = str(ProjectSettings.get_setting("invonetwork/sandbox_only/game_secret", ""))


func _on_save() -> void:
	ProjectSettings.set_setting("invonetwork/config/environment",
			_environment.get_item_text(_environment.selected))
	ProjectSettings.set_setting("invonetwork/config/game_id", _game_id.text.strip_edges())
	ProjectSettings.set_setting("invonetwork/config/player_token_endpoint",
			_token_endpoint.text.strip_edges())
	ProjectSettings.set_setting("invonetwork/sandbox_only/game_secret",
			_secret.text.strip_edges())
	var err: Error = ProjectSettings.save()
	_status.text = "Saved." if err == OK else "Save failed (%d)." % err
	if not _secret.text.strip_edges().is_empty():
		_status.text += "\n⚠ Sandbox secret set — dev only. Never ship it in a build."


func _on_test() -> void:
	var email: String = _test_email.text.strip_edges()
	if email.is_empty():
		_status.text = "Enter a sandbox player email to test with."
		return
	if _secret.text.strip_edges().is_empty():
		_status.text = "Set the sandbox game secret first."
		return
	_status.text = "Testing sandbox connection..."
	var http: InvoHttp = InvoHttp.new()
	add_child(http)
	http.configure("https://sandbox.invo.network/sandbox")
	var server: InvoSandboxServer = InvoSandboxServer.new(http, _secret.text.strip_edges())
	var res: InvoResult = await server.mint_player_token(email)
	# The plugin may have been disabled (dock freed) while the request was in
	# flight — the resumed coroutine must not touch freed nodes.
	if not is_instance_valid(self) or not is_instance_valid(_status):
		return
	http.queue_free()
	if res.ok:
		_status.text = "✔ Connected — token minted for identity %s (expires %s)." % [
			str(res.dict().get("identity_id", "?")), str(res.dict().get("expires_at", "?"))]
	else:
		_status.text = "✘ %s%s" % [res.error.message,
				"" if res.error.code.is_empty() else " [%s]" % res.error.code]

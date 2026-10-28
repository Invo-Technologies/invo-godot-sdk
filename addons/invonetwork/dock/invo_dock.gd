@tool
extends Control
## The INVO editor dock, laid out like the Unity SDK's Tools > Invo SDK > Settings
## window: an environment picker, then Sandbox, Production and Game & display tabs.
## Sandbox and production are separate INVO environments with separate Game IDs.
## Only the Sandbox tab holds a key: a game secret must never ship in an export,
## so production goes through your backend, which mints player tokens.

const InvoScript: GDScript = preload("res://addons/invonetwork/invo.gd")

const SANDBOX_CONSOLE_URL: String = "https://console.invo.network/test"
const PRODUCTION_CONSOLE_URL: String = "https://console.invo.network"
const DOCS_URL: String = "https://docs.invo.network/docs/godot-sdk"
const README_PRODUCTION_URL: String = \
		"https://github.com/Invo-Technologies/invo-godot-sdk#production-integration"

## Test player details stay in this editor's project metadata (.godot/), never
## in project.godot, so they cannot end up in an export.
const META_SECTION: String = "invonetwork"

enum Note { INFO, WARNING, ERROR, NONE }

var _env: OptionButton
var _tabs: TabContainer
var _sandbox_game_id: LineEdit
var _secret: LineEdit
var _key_status: Label
var _live_key_note: Control
var _env_secret_note: Control
var _player_email: LineEdit
var _player_phone: LineEdit
var _player_name: LineEdit
var _phone_note: Control
var _usd_amount: LineEdit
var _production_game_id: LineEdit
var _token_endpoint: LineEdit
var _export_check: VBoxContainer
var _display: Dictionary = {}
var _results: Dictionary = {}
var _busy_buttons: Array[Button] = []


func _ready() -> void:
	_build()
	_load()


# ------------------------------------------------------------------ layout

func _build() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	header.add_child(_muted("Play and exports use"))
	_env = OptionButton.new()
	_env.add_item("Sandbox")
	_env.add_item("Production")
	_env.item_selected.connect(_on_env_selected)
	header.add_child(_env)
	header.add_child(_spacer())
	header.add_child(_link_button("Docs", DOCS_URL))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_add_tab("Sandbox", _build_sandbox_tab())
	_add_tab("Production", _build_production_tab())
	_add_tab("Game & display", _build_display_tab())


func _build_sandbox_tab() -> VBoxContainer:
	var v: VBoxContainer = _tab_body()
	v.add_child(_note(
			"The sandbox key works in the editor and debug runs only. Release exports refuse " +
			"it, and an export with a key saved in project.godot gets a loud error. Prefer the " +
			"%s environment variable: nothing is saved in the project." % InvoScript.SECRET_ENV_VAR,
			Note.INFO))

	v.add_child(_heading("Sandbox game"))
	_sandbox_game_id = _line(InvoScript.SETTING_SANDBOX_GAME_ID, "from console.invo.network/test")
	var game_row: HBoxContainer = _field_row("Sandbox Game ID", _sandbox_game_id)
	game_row.add_child(_busy_button("Test connection", _on_test_sandbox))
	v.add_child(game_row)
	v.add_child(_result("sandbox"))

	var key_head: HBoxContainer = HBoxContainer.new()
	key_head.add_child(_heading("Sandbox key"))
	key_head.add_child(_spacer())
	var reveal: CheckBox = CheckBox.new()
	reveal.text = "Show key"
	reveal.toggled.connect(func(on: bool) -> void: _secret.secret = not on)
	key_head.add_child(reveal)
	key_head.add_child(_link_button("Get keys", SANDBOX_CONSOLE_URL))
	v.add_child(key_head)
	_secret = _line(InvoScript.SETTING_SANDBOX_SECRET, "ivsdk_test_…")
	_secret.secret = true
	_secret.text_changed.connect(func(_t: String) -> void: _refresh_key_status())
	var key_row: HBoxContainer = _field_row("Key", _secret)
	_key_status = _muted("")
	_key_status.tooltip_text = "Sandbox keys look like ivsdk_test_...; older ivsdk_... keys still work."
	_key_status.custom_minimum_size.x = 90
	key_row.add_child(_key_status)
	v.add_child(key_row)
	_live_key_note = _note(
			"This is a production key (ivsdk_live_). Sandbox keys start with ivsdk_test_. " +
			"Production keys belong on your game server only, never in the project.", Note.ERROR)
	v.add_child(_live_key_note)
	_env_secret_note = _note(
			"Using %s from the environment. The key above is ignored." % InvoScript.SECRET_ENV_VAR,
			Note.NONE)
	v.add_child(_env_secret_note)

	v.add_child(_heading("Test player (sandbox only)"))
	_player_email = _meta_line("player_email", "player@yourgame.com")
	v.add_child(_field_row("Email", _player_email))
	_player_phone = _meta_line("player_phone", "+15555550111")
	_player_phone.tooltip_text = "International format, e.g. +15555550111."
	_player_phone.text_changed.connect(func(_t: String) -> void: _refresh_phone_note())
	v.add_child(_field_row("Phone", _player_phone))
	_phone_note = _note("", Note.WARNING)
	v.add_child(_phone_note)
	_player_name = _meta_line("player_name", "")
	v.add_child(_field_row("Name", _player_name))

	v.add_child(_heading("Quick actions"))
	_usd_amount = _meta_line("usd_amount", "5.00")
	var amount_row: HBoxContainer = _field_row("USD amount", _usd_amount)
	v.add_child(amount_row)
	var actions: HBoxContainer = HBoxContainer.new()
	var purchase: Button = _busy_button("Make test purchase", _on_test_purchase)
	purchase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(purchase)
	var balance: Button = _busy_button("Get player balance", _on_get_balance)
	balance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(balance)
	v.add_child(actions)
	v.add_child(_result("quick"))
	return v


func _build_production_tab() -> VBoxContainer:
	var v: VBoxContainer = _tab_body()
	v.add_child(_note(
			"No keys on this tab, by design. A game secret must never go into a Godot export. " +
			"Your backend holds the production key and mints player tokens; the game only " +
			"knows your backend's token endpoint.", Note.INFO))
	v.add_child(_link_button("Read: minting player tokens on your backend", README_PRODUCTION_URL))

	_production_game_id = _line(InvoScript.SETTING_PRODUCTION_GAME_ID, "from console.invo.network")
	v.add_child(_field_row("Production Game ID", _production_game_id))
	_token_endpoint = _line(InvoScript.SETTING_TOKEN_ENDPOINT, "https://api.yourgame.com/invo/token")
	_token_endpoint.tooltip_text = "Your endpoint that mints a player token and returns { token, identity_id }."
	var endpoint_row: HBoxContainer = _field_row("Player-token endpoint", _token_endpoint)
	endpoint_row.add_child(_busy_button("Test connection", _on_test_production))
	v.add_child(endpoint_row)
	v.add_child(_result("production"))
	v.add_child(_note(
			"Invo.login_via_backend(payload) POSTs your payload here as JSON. Your server calls " +
			"mint_player_token with the INVO Python or JS server SDK and returns the token.",
			Note.NONE))
	var server_url: LineEdit = _line(InvoScript.SETTING_GAME_SERVER_URL, "https://api.yourgame.com")
	server_url.tooltip_text = "Base URL of your server, which forwards /api/* to INVO with your production key."
	v.add_child(_field_row("Game Server URL", server_url))
	var checkout: LineEdit = _line(InvoScript.SETTING_CHECKOUT_ENDPOINT, "https://api.yourgame.com/invo/checkout")
	checkout.tooltip_text = "Your endpoint that mints a hosted-checkout session and returns { checkout_url }."
	v.add_child(_field_row("Checkout session endpoint", checkout))
	v.add_child(_note(
			"The wallet window's store, send, transfer and phone calls go to your Game Server URL " +
			"with the player's token; your server checks the player and attaches the key.",
			Note.NONE))

	v.add_child(_heading("Production export check"))
	_export_check = VBoxContainer.new()
	v.add_child(_export_check)
	v.add_child(_link_button("Manage and rotate production keys in the console", PRODUCTION_CONSOLE_URL))
	return v


func _build_display_tab() -> VBoxContainer:
	var v: VBoxContainer = _tab_body()
	v.add_child(_note(
			"Shown in the SDK's wallet UI. Test connection on the Sandbox tab fills the game " +
			"name and icons in for you.", Note.NONE))
	for field: Array in [
			["game_name", "Game name", ""],
			["game_icon_url", "Game icon URL", "https://…"],
			["currency_name", "Currency name", "Coins"],
			["currency_icon_url", "Currency icon URL", "https://…"],
			["game_version", "Game version", "1.0.0"]]:
		var edit: LineEdit = _line(InvoScript.SETTING_DISPLAY_PREFIX + str(field[0]), str(field[2]))
		_display[field[0]] = edit
		v.add_child(_field_row(str(field[1]), edit))
	return v


# ------------------------------------------------------------------ settings

func _load() -> void:
	var env: String = str(ProjectSettings.get_setting(InvoScript.SETTING_ENVIRONMENT, "sandbox"))
	_env.select(1 if env == "production" else 0)
	_tabs.current_tab = _env.selected
	_refresh_key_status()
	_refresh_phone_note()
	_refresh_export_check()


func _on_env_selected(index: int) -> void:
	_save_setting(InvoScript.SETTING_ENVIRONMENT, "production" if index == 1 else "sandbox")
	_tabs.current_tab = index
	_refresh_export_check()


func _save_setting(setting: String, value: Variant) -> void:
	if ProjectSettings.get_setting(setting, null) == value:
		return
	ProjectSettings.set_setting(setting, value)
	ProjectSettings.save()


func _refresh_key_status() -> void:
	var key: String = _secret.text
	_key_status.text = key_status(key)
	_live_key_note.visible = is_live_key(key.strip_edges())
	_env_secret_note.visible = not OS.get_environment(InvoScript.SECRET_ENV_VAR).strip_edges().is_empty()


func _refresh_phone_note() -> void:
	var phone: String = _player_phone.text.strip_edges()
	var problem: InvoError = null if phone.is_empty() else InvoValidate.e164_problem(phone, "Phone")
	_phone_note.visible = problem != null
	if problem != null:
		(_phone_note.get_meta("label") as Label).text = problem.message


func _refresh_export_check() -> void:
	if _export_check == null:
		return
	for child: Node in _export_check.get_children():
		child.queue_free()
	var problems: PackedStringArray = production_problems(
			_production_game_id.text, _token_endpoint.text, _secret.text)
	if problems.is_empty():
		_export_check.add_child(_note(
				"Ready. Release exports refuse the sandbox key and the test player.", Note.INFO))
	for problem: String in problems:
		_export_check.add_child(_note(problem, Note.ERROR))


## Format check for the sandbox key slot. New keys are ivsdk_test_ (sandbox) or
## ivsdk_live_ (production); older ivsdk_ keys have no environment in the prefix.
static func key_status(key: String) -> String:
	if key.strip_edges().is_empty():
		return "Not set"
	var trimmed: String = key.strip_edges()
	if trimmed != key:
		return "Has spaces"
	if is_live_key(trimmed):
		return "Live key"
	return "Looks valid" if trimmed.begins_with("ivsdk_") else "Not ivsdk_"


## Production keys start with ivsdk_live_; sandbox keys with ivsdk_test_ (older ones: ivsdk_).
static func is_live_key(key: String) -> bool:
	return key.begins_with("ivsdk_live_")


## What would stop a production export from working, in the order to fix it.
static func production_problems(production_game_id: String, token_endpoint: String,
		saved_secret: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	if production_game_id.strip_edges().is_empty():
		problems.append("Set the Production Game ID (console.invo.network > your game).")
	var endpoint: String = token_endpoint.strip_edges()
	if endpoint.is_empty():
		problems.append("Set the player-token endpoint: production players sign in through your backend.")
	elif not endpoint.begins_with("https://"):
		problems.append("The player-token endpoint must use https://.")
	if not saved_secret.strip_edges().is_empty():
		problems.append("A sandbox key is saved in project.godot, so it would be packed into the " +
				"export. Clear it and use the %s environment variable instead." % InvoScript.SECRET_ENV_VAR)
	return problems


## The text after "Failed: HTTP n." for a failed test call.
static func describe_failure(error: InvoError) -> String:
	if error.is_key_for_other_environment():
		return error.message
	match error.status:
		0:
			return "No response: check the URL and your network."
		401:
			return "The key was refused. Check it is a sandbox key for this game."
		403:
			return "This title may not send transfers. Check the console."
		404:
			return "Route not found. Check the Game ID and URL."
	return error.message if not error.message.is_empty() else "See the INVO console for this title."


# ------------------------------------------------------------------ actions

func _new_http() -> InvoHttp:
	var http: InvoHttp = InvoHttp.new()
	add_child(http)
	http.configure(InvoScript.BASE_URLS["sandbox"])
	return http


func _sandbox_server(http: InvoHttp) -> InvoSandboxServer:
	var secret: String = OS.get_environment(InvoScript.SECRET_ENV_VAR).strip_edges()
	if secret.is_empty():
		secret = _secret.text.strip_edges()
	return InvoSandboxServer.new(http, secret)


func _sandbox_ready(result_id: String, need_email: bool) -> bool:
	if _secret.text.strip_edges().is_empty() and not _env_secret_note.visible:
		_show_result(result_id, "Set the sandbox key first.", false)
		return false
	if is_live_key(_secret.text.strip_edges()):
		_show_result(result_id, "That's a live key. Test with a sandbox key (ivsdk_test_…) " +
				"from console.invo.network/test.", false)
		return false
	if need_email and _player_email.text.strip_edges().is_empty():
		_show_result(result_id, "Enter the test player's email first.", false)
		return false
	return true


func _on_test_sandbox() -> void:
	if _sandbox_game_id.text.strip_edges().is_empty():
		_show_result("sandbox", "Enter the Sandbox Game ID first.", false)
		return
	if not _sandbox_ready("sandbox", false):
		return
	var http: InvoHttp = _new_http()
	var server: InvoSandboxServer = _sandbox_server(http)
	_set_busy(true, "sandbox")
	var res: InvoResult = await server.get_destinations(_sandbox_game_id.text.strip_edges())
	if not _finish(http):
		return
	if not res.ok:
		_show_result("sandbox", "Failed: HTTP %d. %s" % [res.error.status, describe_failure(res.error)], false)
		return
	var d: Dictionary = res.dict()
	_fill_display("game_name", d.get("source_game_name"))
	_fill_display("game_icon_url", d.get("source_game_icon"))
	_fill_display("currency_name", d.get("source_currency_name"))
	_fill_display("currency_icon_url", d.get("source_currency_icon"))
	_show_result("sandbox", "Connected. %d game(s) can receive transfers." %
			(d.get("available_games", []) as Array).size(), true)


func _on_test_production() -> void:
	var endpoint: String = _token_endpoint.text.strip_edges()
	var problem: String = InvoHttp.secure_base_url_problem(endpoint) if not endpoint.is_empty() \
			else "Enter your player-token endpoint first."
	if not problem.is_empty():
		_show_result("production", problem, false)
		return
	var http: InvoHttp = _new_http()
	_set_busy(true, "production")
	var res: InvoResult = await http.post_url(endpoint, {}, {})
	if not _finish(http):
		return
	if res.ok:
		_show_result("production", "Connected. Your backend answered.", true)
	elif res.error.status >= 400 and res.error.status < 500:
		_show_result("production", "Reached your backend (HTTP %d). It needs a real login " % res.error.status +
				"payload to mint a token, so this is expected.", true)
	else:
		_show_result("production", "Failed: HTTP %d. %s" % [res.error.status, describe_failure(res.error)], false)


func _on_test_purchase() -> void:
	if not _sandbox_ready("quick", true):
		return
	var http: InvoHttp = _new_http()
	var server: InvoSandboxServer = _sandbox_server(http)
	_set_busy(true, "quick")
	var res: InvoResult = await server.create_checkout(
			_player_email.text.strip_edges(), _usd_amount.text.strip_edges())
	if not _finish(http):
		return
	if not res.ok:
		_show_result("quick", "Failed: HTTP %d. %s" % [res.error.status, describe_failure(res.error)], false)
		return
	var url: String = str(res.dict().get("checkout_url", ""))
	if not url.begins_with("https://"):
		_show_result("quick", "Refusing to open a non-https checkout URL.", false)
		return
	OS.shell_open(url)
	_show_result("quick", "Checkout opened in your browser. Pay with a sandbox test card, then " +
			"press Get player balance.", true)


func _on_get_balance() -> void:
	if not _sandbox_ready("quick", true):
		return
	var http: InvoHttp = _new_http()
	var server: InvoSandboxServer = _sandbox_server(http)
	_set_busy(true, "quick")
	var res: InvoResult = await server.get_player_balance(_player_email.text.strip_edges())
	if not _finish(http):
		return
	if not res.ok:
		_show_result("quick", "Failed: HTTP %d. %s" % [res.error.status, describe_failure(res.error)], false)
		return
	var lines: PackedStringArray = []
	for b: Variant in (res.dict().get("balances", []) as Array):
		if b is Dictionary:
			lines.append("%s: %s available" % [str(b.get("currency_name", "?")),
					str(b.get("available_balance", "?"))])
	_show_result("quick", "Balance for %s\n%s" % [_player_email.text.strip_edges(),
			"\n".join(lines) if not lines.is_empty() else "No balances yet."], true)


## Frees the request's HTTP node and re-enables the buttons. False when the dock
## was freed (plugin disabled) while the request was in flight.
func _finish(http: InvoHttp) -> bool:
	if not is_instance_valid(self):
		return false
	if is_instance_valid(http):
		http.queue_free()
	_set_busy(false, "")
	return true


func _fill_display(field: String, value: Variant) -> void:
	var edit: LineEdit = _display.get(field)
	if edit == null or not edit.text.strip_edges().is_empty():
		return
	if value is String and not (value as String).is_empty():
		edit.text = value
		_save_setting(InvoScript.SETTING_DISPLAY_PREFIX + field, value)


# ------------------------------------------------------------------ widgets

func _add_tab(title: String, body: VBoxContainer) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(body)
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, title)


func _tab_body() -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	return v


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override("font", get_theme_font("bold", "EditorFonts"))
	return label


func _muted(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _spacer() -> Control:
	var c: Control = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _link_button(text: String, url: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(func() -> void: OS.shell_open(url))
	return b


func _busy_button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(handler)
	_busy_buttons.append(b)
	return b


func _field_row(label_text: String, field: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


## A LineEdit bound to a project setting, saved when editing finishes.
func _line(setting: String, placeholder: String) -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = str(ProjectSettings.get_setting(setting, ""))
	var save: Callable = func() -> void:
		_save_setting(setting, edit.text.strip_edges())
		_refresh_export_check()
	edit.text_submitted.connect(func(_t: String) -> void: save.call())
	edit.focus_exited.connect(save)
	return edit


## A LineEdit bound to this editor's project metadata (never exported).
func _meta_line(key: String, placeholder: String) -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.placeholder_text = placeholder
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	edit.text = str(settings.get_project_metadata(META_SECTION, key, ""))
	var save: Callable = func() -> void:
		settings.set_project_metadata(META_SECTION, key, edit.text.strip_edges())
	edit.text_submitted.connect(func(_t: String) -> void: save.call())
	edit.focus_exited.connect(save)
	return edit


## A Unity-style help box: a tinted panel with wrapped text.
func _note(text: String, kind: Note) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	var tint: Color = {
		Note.INFO: get_theme_color("accent_color", "Editor"),
		Note.WARNING: get_theme_color("warning_color", "Editor"),
		Note.ERROR: get_theme_color("error_color", "Editor"),
		Note.NONE: Color(0.5, 0.5, 0.5),
	}[kind]
	box.bg_color = Color(tint, 0.12)
	box.border_color = Color(tint, 0.5)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", box)
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	panel.set_meta("label", label)
	return panel


func _result(id: String) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.visible = false
	_results[id] = label
	return label


func _show_result(id: String, text: String, ok: bool) -> void:
	var label: Label = _results.get(id)
	if label == null:
		return
	label.text = text
	label.visible = true
	label.add_theme_color_override("font_color",
			get_theme_color("success_color", "Editor") if ok else get_theme_color("error_color", "Editor"))


func _set_busy(busy: bool, id: String) -> void:
	for b: Button in _busy_buttons:
		b.disabled = busy
	if busy:
		var label: Label = _results.get(id)
		if label != null:
			label.text = "Testing…"
			label.visible = true
			label.remove_theme_color_override("font_color")

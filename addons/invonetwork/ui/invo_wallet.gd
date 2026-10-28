class_name InvoWallet
extends CanvasLayer
## The INVO wallet window, the Godot twin of the Unity SDK's InvoSDKWindow: a
## sheet over a dimmed backdrop with Store / Send / Transfer / Collect tabs, a
## phone button and a close button, in the shared INVO theme.
##
## Drop res://addons/invonetwork/ui/invo_wallet.tscn into a scene (or add it as
## an autoload) and call open("Store"), or press the `invo_wallet_toggle`
## action (F8 unless your InputMap defines it).

## The window opened or closed.
signal visibility_changed_to(open: bool)
## A purchase, send, transfer or collect changed the player's balance.
signal wallet_changed

const ACTION: String = "invo_wallet_toggle"
const PANELS: PackedStringArray = ["Store", "Send", "Transfer", "Collect"]
## Sheet size at the 1920x1080 reference.
const SHEET_SIZE: Vector2 = Vector2(560, 780)

## Opens on this panel when the scene starts; empty keeps the window closed.
@export var open_on_start: String = ""
## Use the light palette instead of the dark one.
@export var light_theme: bool = false

var _root: Control
var _sheet: PanelContainer
var _tab_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _current: String = ""
var _was_mouse_captured: bool = false
var _body: Control
var _sign_in: VBoxContainer
var _catalog: Array[Dictionary] = []
## The last balance broadcast by Invo.balance_updated.
var last_balance: Dictionary = {}

## Demo items for the Items tab while the mock transport is on.
const MOCK_CATALOG: Array[Dictionary] = [
	{"item_id": "sword_01", "name": "Ember Sword", "price": 250, "category": "weapon"},
	{"item_id": "shield_01", "name": "Oak Shield", "price": 120, "category": "armor"},
	{"item_id": "potion_05", "name": "Potion x5", "price": 40, "category": "consumable"},
	{"item_id": "skin_gold", "name": "Gold Skin", "price": 900, "category": "cosmetic"},
]


func _ready() -> void:
	layer = 100
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_F8
		InputMap.action_add_event(ACTION, key)
	# No credentials configured anywhere? Use the offline mock so the window
	# still shows every flow (debug builds only; never ship the mock).
	if OS.is_debug_build() and not Invo.is_mock_enabled() 			and OS.get_environment(Invo.SECRET_ENV_VAR).strip_edges().is_empty() 			and str(ProjectSettings.get_setting(Invo.SETTING_SANDBOX_SECRET, "")).strip_edges().is_empty() 			and str(ProjectSettings.get_setting(Invo.SETTING_TOKEN_ENDPOINT, "")).strip_edges().is_empty():
		Invo.enable_mock()
	Invo.balance_updated.connect(func(b: Dictionary) -> void: last_balance = b)
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()
	_root.visible = false
	if not open_on_start.is_empty():
		open(open_on_start)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif _root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Open on "Store", "Send", "Transfer", "Collect" or "Phone".
func open(panel_id: String = "Store") -> void:
	if not _root.visible:
		_was_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_root.visible = true
		visibility_changed_to.emit(true)
	show_panel(panel_id)
	if Invo.is_mock_enabled() and Invo.player_email.is_empty():
		await Invo.login_sandbox("player@example.com", "+15555550111", "Demo Player")
		show_panel(panel_id)


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	if _was_mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	visibility_changed_to.emit(false)


func toggle() -> void:
	if _root.visible:
		close()
	else:
		open(_current if not _current.is_empty() else "Store")


func is_open() -> bool:
	return _root.visible


func show_panel(panel_id: String) -> void:
	if not _pages.has(panel_id):
		push_error("[Invo] No wallet panel named %s." % panel_id)
		return
	_current = panel_id
	var signed_in: bool = Invo.client() != null and Invo.client().has_token()
	_sign_in.visible = not signed_in
	_body.visible = signed_in
	for id: String in _pages:
		(_pages[id] as Control).visible = id == panel_id
	for id: String in _tab_buttons:
		(_tab_buttons[id] as Button).theme_type_variation = \
				"InvoTabSelected" if id == panel_id else "InvoTab"
	# A container keeps its largest size; re-fit so the sheet never outgrows the screen.
	_fit.call_deferred()
	var page: Control = _pages[panel_id]
	if page.has_method("on_shown"):
		page.call("on_shown")


## Items for the Store's Items tab, priced in your game currency:
## [{item_id, name, price, description?, category?, image_url? or texture?}].
## Purchases go through purchase_item (sandbox) or your game server (production).
func set_item_catalog(items: Array[Dictionary]) -> void:
	_catalog = items.duplicate()


func item_catalog() -> Array[Dictionary]:
	if _catalog.is_empty() and Invo.is_mock_enabled():
		return MOCK_CATALOG
	return _catalog


## The game's currency name: Game & display settings, else the balance's.
func currency_name() -> String:
	var rows: Array = last_balance.get("balances", [])
	var from_balance: String = str((rows[0] as Dictionary).get("currency_name", "")) 			if not rows.is_empty() and rows[0] is Dictionary else ""
	return Invo.display_setting("currency_name", from_balance if not from_balance.is_empty() else "Coins")


func game_name() -> String:
	var from_balance: String = str(last_balance.get("game_name", ""))
	return Invo.display_setting("game_name", from_balance if not from_balance.is_empty() else "This game")


## "8,500 Gems" for the first currency in a balance payload, "-" before one arrives.
static func balance_text(balance: Dictionary) -> String:
	var rows: Array = balance.get("balances", [])
	if rows.is_empty() or not (rows[0] is Dictionary):
		return "-"
	var d: Dictionary = rows[0]
	return "%s %s" % [InvoUi.amount(d.get("available_balance", d.get("total_balance", "0"))),
			d.get("currency_name", d.get("currency_symbol", ""))]


## Called by panels after anything that moves the player's balance.
func notify_wallet_changed() -> void:
	wallet_changed.emit()
	Invo.fetch_balance()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = InvoUiTheme.build(InvoUiTheme.LIGHT if light_theme else InvoUiTheme.DARK)
	add_child(_root)
	var palette: Dictionary = InvoUiTheme.LIGHT if light_theme else InvoUiTheme.DARK

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = palette["backdrop"]
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	_sheet = InvoUi.card("InvoSheet")
	_sheet.custom_minimum_size = SHEET_SIZE
	_sheet.size = SHEET_SIZE
	_root.add_child(_sheet)
	var column: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	_sheet.add_child(column)

	var header: HBoxContainer = InvoUi.hbox()
	column.add_child(header)
	var tabs_panel: PanelContainer = InvoUi.card("InvoTabBar")
	var tabs: HBoxContainer = InvoUi.hbox(2)
	tabs_panel.add_child(tabs)
	header.add_child(tabs_panel)
	for id: String in PANELS:
		var b: Button = InvoUi.button(id, "InvoTab", show_panel.bind(id))
		_tab_buttons[id] = b
		tabs.add_child(b)
	header.add_child(InvoUi.spacer())
	header.add_child(InvoUi.icon_button("phone", "Your phone number", show_panel.bind("Phone")))
	header.add_child(InvoUi.icon_button("close", "Close", close))

	_sign_in = _build_sign_in()
	column.add_child(_sign_in)
	var body: Control = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	column.add_child(body)
	_body = body
	_add_page(body, "Store", InvoStorePanel.new())
	_add_page(body, "Send", InvoSendPanel.new())
	_add_page(body, "Transfer", InvoTransferPanel.new())
	_add_page(body, "Collect", InvoCollectPanel.new())
	_add_page(body, "Phone", InvoPhonePanel.new())

	if OS.is_debug_build() and Invo.environment == "sandbox":
		var mark: Label = InvoUi.label("SANDBOX", "InvoOverline")
		mark.add_theme_color_override("font_color", palette["warning"])
		mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		mark.position += Vector2(16, -32)
		_root.add_child(mark)


## Shown until the game sets a player token. Production games sign the player
## in themselves (Invo.login_via_backend); the email form is sandbox-only.
func _build_sign_in() -> VBoxContainer:
	var v: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(InvoUi.label("Sign in", "InvoTitle"))
	if Invo.environment != "sandbox" or not OS.is_debug_build():
		v.add_child(InvoUi.label("Sign in to the game to use your INVO wallet.", "InvoBody", true))
		return v
	v.add_child(InvoUi.label("Sandbox player for testing. Your game signs players in for real.", "InvoCaption", true))
	var email: LineEdit = InvoUi.field("player@yourgame.com")
	var phone: LineEdit = InvoUi.field("+15555550111 (optional)")
	v.add_child(email)
	v.add_child(phone)
	var err: Label = InvoUi.label("", "InvoDanger", true)
	v.add_child(err)
	var go: Button = InvoUi.button("Sign in", "InvoPrimaryButton")
	go.pressed.connect(func() -> void:
		err.text = ""
		go.disabled = true
		var res: InvoResult = await Invo.login_sandbox(email.text.strip_edges(), phone.text.strip_edges())
		go.disabled = false
		if res.ok:
			show_panel(_current if not _current.is_empty() else "Store")
		else:
			err.text = "That player was not found in this sandbox game." if res.error.status == 404 					else InvoPlayerCopy.send(res.error))
	v.add_child(go)
	return v


func _add_page(parent: Control, id: String, page: Control) -> void:
	page.name = id
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	parent.add_child(page)
	_pages[id] = page
	if page.has_method("setup"):
		page.call("setup", self)


## Scales the sheet like Unity's canvas scaler (1920x1080 reference, match 0.5)
## and centres it; on narrow portrait screens the sheet fills the width.
func _fit() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = vp.y > vp.x
	var ref: Vector2 = Vector2(640, 1000) if portrait else Vector2(1920, 1080)
	var s: float = sqrt((vp.x / ref.x) * (vp.y / ref.y))
	var size: Vector2 = SHEET_SIZE
	if portrait:
		size = Vector2(vp.x / s - 32.0, min(vp.y / s - 32.0, 1000.0))
	_sheet.custom_minimum_size = size
	_sheet.size = size
	_sheet.scale = Vector2(s, s)
	_sheet.position = ((vp - size * s) / 2.0).round()

class_name InvoMovePanel
extends VBoxContainer
## The four-step Send and Transfer screens from the Unity kit: 1 details,
## 2 review, 3 approve on your phone (QR), 4 done. Send moves currency to
## another player's phone in any game; Transfer moves the player's own balance
## to another game. InvoSendPanel and InvoTransferPanel only pick the mode.

const RECENT_FILE: String = "user://invo_wallet.cfg"

## "send" or "transfer".
var mode: String = "send"

var _wallet: InvoWallet
var _steps: Array[Control] = []
var _destinations: Array[Dictionary] = []
var _played: Dictionary = {}
var _game: Dictionary = {}
var _txn: Dictionary = {}
var _request_id: String = ""
# Step 1
var _from_line: Label
var _recent: HBoxContainer
var _recent_box: VBoxContainer
var _phone: LineEdit
var _game_card: PanelContainer
var _game_title: Label
var _game_sub: Label
var _game_badge: Label
var _amount: LineEdit
var _amount_hint: Label
var _error1: Label
var _continue: Button
# Game picker
var _picker: VBoxContainer
var _search: LineEdit
var _picker_list: VBoxContainer
# Step 2
var _review_rows: VBoxContainer
var _review_amount: Label
var _error2: Label
var _approve_button: Button
# Step 3
var _approval: InvoApprovalView
# Step 4
var _done_title: Label
var _done_text: Label
var _done_code: Label
var _copy_button: Button


func setup(wallet: InvoWallet) -> void:
	_wallet = wallet
	_steps = [_build_details(), _build_review(), _build_approve(), _build_done()]
	_picker = _build_picker()
	for s: Control in _steps:
		add_child(s)
	add_child(_picker)
	_go(0)


func on_shown() -> void:
	if _steps[0].visible:
		_refresh_details()
		if _destinations.is_empty():
			_load_destinations()


func _sending() -> bool:
	return mode == "send"


func _go(step: int) -> void:
	_picker.visible = false
	for i: int in _steps.size():
		_steps[i].visible = i == step


# ------------------------------------------------------------------ step 1

func _build_details() -> VBoxContainer:
	var v: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(InvoUi.label("Send" if _sending() else "Transfer to another game", "InvoTitle"))
	var from: HBoxContainer = InvoUi.hbox()
	_from_line = InvoUi.label("", "InvoCaption")
	from.add_child(_from_line)
	from.add_child(InvoUi.button("Change", "InvoLinkButton", func() -> void: _wallet.show_panel("Phone")))
	v.add_child(from)
	if _sending():
		_recent_box = InvoUi.vbox()
		_recent_box.add_child(InvoUi.overline("Recent"))
		_recent = InvoUi.hbox()
		_recent_box.add_child(_recent)
		v.add_child(_recent_box)
		var phone_box: VBoxContainer = InvoUi.vbox(4)
		phone_box.add_child(InvoUi.label("Their phone number", "InvoCaption"))
		_phone = InvoUi.field("+15555550123")
		phone_box.add_child(_phone)
		v.add_child(phone_box)

	_game_card = InvoUi.card("InvoCard")
	var g: HBoxContainer = InvoUi.hbox(InvoUiTheme.UNIT + 4)
	_game_card.add_child(g)
	var badge_box: PanelContainer = InvoUi.card("InvoCardRaised")
	badge_box.add_theme_stylebox_override("panel", InvoUiTheme.box(
			get_theme_color("font_color", "InvoMuted").darkened(0.7), 8, Color.TRANSPARENT, 8, 4))
	_game_badge = InvoUi.label("?", "InvoBodyStrong")
	badge_box.add_child(_game_badge)
	g.add_child(badge_box)
	var gcol: VBoxContainer = InvoUi.vbox(0)
	_game_title = InvoUi.label("Choose a game", "InvoBodyStrong")
	_game_sub = InvoUi.label("", "InvoMuted")
	gcol.add_child(_game_title)
	gcol.add_child(_game_sub)
	g.add_child(gcol)
	g.add_child(InvoUi.button("Change game", "InvoLinkButton", _open_picker))
	v.add_child(_game_card)

	_amount = LineEdit.new()
	_amount.theme_type_variation = "InvoAmountField"
	_amount.placeholder_text = "0"
	_amount.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount.text_changed.connect(func(_t: String) -> void: _refresh_details())
	v.add_child(_amount)
	_amount_hint = InvoUi.label("", "InvoCaption")
	_amount_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_amount_hint)
	_error1 = InvoUi.label("", "InvoDanger", true)
	_error1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_error1)
	v.add_child(InvoUi.spacer(true))
	_continue = InvoUi.button("Continue", "InvoPrimaryButton", _on_continue)
	v.add_child(_continue)
	return v


func _refresh_details() -> void:
	_from_line.text = "%s %s" % ["From your phone" if _sending() else "Approved on your phone",
			InvoUi.masked_phone(Invo.player_phone)]
	if _sending():
		_fill_recent()
	var bal: String = InvoWallet.balance_text(_wallet.last_balance)
	var hint: String = "Balance %s" % bal
	if not _game.is_empty():
		hint += " · %s %s" % ["They receive" if _sending() else "You receive", _game.get("currency_name", "")]
	_amount_hint.text = hint


func _fill_recent() -> void:
	for c: Node in _recent.get_children():
		c.queue_free()
	var recent: PackedStringArray = _load_recent()
	_recent_box.visible = not recent.is_empty()
	for phone: String in recent:
		var b: Button = InvoUi.button(InvoUi.masked_phone(phone),
				"InvoChipSelected" if phone == _phone.text.strip_edges() else "InvoChip")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			_phone.text = phone
			_fill_recent())
		_recent.add_child(b)


func _load_destinations() -> void:
	var res: InvoResult = await Invo.client().get_destinations(mode)
	if not is_instance_valid(self) or not res.ok:
		if is_instance_valid(self) and not res.ok:
			_error1.text = InvoPlayerCopy.send(res.error) if _sending() else InvoPlayerCopy.transfer(res.error)
		return
	_destinations.clear()
	if _sending() and not Invo.game_id.is_empty():
		_destinations.append({"game_id": Invo.game_id, "game_name": "Another player in this game",
				"currency_name": _wallet.currency_name(), "minimum_transfer": "", "maximum_transfer": ""})
	for g: Dictionary in res.dict().get("available_games", []):
		_destinations.append(g)
	var server: InvoSandboxServer = Invo.commerce()
	if server != null and not Invo.player_email.is_empty():
		var played: InvoResult = await server.get_player_destinations(Invo.player_email, Invo.player_phone)
		if is_instance_valid(self) and played.ok:
			for d: Dictionary in played.dict().get("destinations", []):
				_played[str(d["game_id"])] = true
	if is_instance_valid(self) and _game.is_empty() and not _destinations.is_empty():
		_pick_game(_destinations[0])


func _pick_game(game: Dictionary) -> void:
	_game = game
	var name: String = str(game.get("game_name", ""))
	_game_title.text = name
	_game_sub.text = "%s %s" % ["They receive" if _sending() else "You receive", game.get("currency_name", "")]
	var initials: String = ""
	for word: String in name.split(" ", false):
		if initials.length() < 2 and word.length() > 0:
			initials += word[0].to_upper()
	_game_badge.text = initials if not initials.is_empty() else "?"
	_go(0)
	_refresh_details()


func _on_continue() -> void:
	_error1.text = ""
	var amount: String = _amount.text.strip_edges()
	var phone: String = _phone.text.strip_edges() if _sending() else Invo.player_phone
	if Invo.player_email.is_empty():
		_error1.text = "Sign in first."
		return
	if _game.is_empty():
		_error1.text = "Choose a game first."
		return
	if _sending() and InvoValidate.e164_problem(phone, "phone") != null:
		_error1.text = "Enter their phone number with the country code, like +15555550123."
		return
	if not amount.is_valid_float() or float(amount) <= 0.0:
		_error1.text = "Enter an amount."
		return
	var lo: String = str(_game.get("minimum_transfer", ""))
	var hi: String = str(_game.get("maximum_transfer", ""))
	if lo.is_valid_float() and float(amount) < float(lo):
		_error1.text = "The smallest amount for %s is %s." % [_game["game_name"], InvoUi.amount(lo)]
		return
	if hi.is_valid_float() and float(hi) > 0.0 and float(amount) > float(hi):
		_error1.text = "The largest amount for %s is %s." % [_game["game_name"], InvoUi.amount(hi)]
		return
	var server: InvoSandboxServer = Invo.commerce()
	if server == null:
		_error1.text = "This build is not connected to its game server."
		return
	if _request_id.is_empty():
		_request_id = InvoSandboxServer.new_client_request_id()
	_continue.disabled = true
	_continue.text = "Checking…"
	var who: String = Invo.player_name if not Invo.player_name.is_empty() else Invo.player_email
	var res: InvoResult
	if _sending():
		res = await server.initiate_send(_request_id, who, Invo.player_email, Invo.player_phone,
				phone, _game["game_id"], amount)
	else:
		res = await server.initiate_transfer(_request_id, who, Invo.player_email, Invo.player_phone,
				phone, _game["game_id"], amount)
	if not is_instance_valid(self):
		return
	_continue.disabled = false
	_continue.text = "Continue"
	if not res.ok:
		_error1.text = InvoPlayerCopy.send(res.error) if _sending() else InvoPlayerCopy.transfer(res.error)
		return
	_txn = res.dict()
	_txn["amount"] = amount
	_txn["phone"] = phone
	if _sending():
		_save_recent(phone)
	_show_review()


# ------------------------------------------------------------------ picker

func _build_picker() -> VBoxContainer:
	var v: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = InvoUi.hbox()
	head.add_child(InvoUi.icon_button("back", "Back", func() -> void: _go(0)))
	head.add_child(InvoUi.label("Choose a game", "InvoHeading"))
	v.add_child(head)
	_search = InvoUi.field("Search games")
	_search.right_icon = InvoUiTheme.icon("search", 20)
	_search.text_changed.connect(func(_t: String) -> void: _fill_picker())
	v.add_child(_search)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker_list = InvoUi.vbox()
	scroll.add_child(_picker_list)
	v.add_child(scroll)
	return v


func _open_picker() -> void:
	for s: Control in _steps:
		s.visible = false
	_picker.visible = true
	_search.text = ""
	_fill_picker()
	_search.grab_focus()


func _fill_picker() -> void:
	for c: Node in _picker_list.get_children():
		c.queue_free()
	var q: String = _search.text.strip_edges().to_lower()
	var played: Array[Dictionary] = []
	var more: Array[Dictionary] = []
	for g: Dictionary in _destinations:
		if not q.is_empty() and str(g.get("game_name", "")).to_lower().find(q) < 0:
			continue
		(played if _played.has(str(g["game_id"])) else more).append(g)
	if played.is_empty() and more.is_empty():
		_picker_list.add_child(InvoUi.label("No games match \"%s\"." % _search.text.strip_edges(), "InvoCaption"))
		return
	for section: Array in [["Games you play", played], ["More games on INVO", more]]:
		if (section[1] as Array).is_empty():
			continue
		_picker_list.add_child(InvoUi.overline(str(section[0])))
		for g: Dictionary in section[1]:
			var b: Button = InvoUi.button("%s  ·  %s" % [g.get("game_name", ""), g.get("currency_name", "")],
					"InvoChipSelected" if str(g["game_id"]) == str(_game.get("game_id", "")) else "InvoChip")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(_pick_game.bind(g))
			_picker_list.add_child(b)


# ------------------------------------------------------------------ step 2

func _build_review() -> VBoxContainer:
	var v: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = InvoUi.hbox()
	head.add_child(InvoUi.icon_button("back", "Back", func() -> void: _go(0)))
	head.add_child(InvoUi.label("Review", "InvoHeading"))
	v.add_child(head)
	var you: Label = InvoUi.label("You're sending" if _sending() else "You're moving", "InvoCaption")
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(you)
	_review_amount = InvoUi.label("", "InvoDisplay")
	_review_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_review_amount)
	var card: PanelContainer = InvoUi.card("InvoCard")
	_review_rows = InvoUi.vbox()
	card.add_child(_review_rows)
	v.add_child(card)
	var note: String = "Check the number. Once you approve on your phone, a send can't be undone." if _sending() \
			else "You approve on your phone. A transfer can't be undone once approved."
	v.add_child(InvoUi.label(note, "InvoCaption", true))
	_error2 = InvoUi.label("", "InvoDanger", true)
	v.add_child(_error2)
	v.add_child(InvoUi.spacer(true))
	_approve_button = InvoUi.button("Approve on my phone", "InvoPrimaryButton", _start_approval)
	v.add_child(_approve_button)
	return v


func _show_review() -> void:
	_go(1)
	_error2.text = ""
	_review_amount.text = "%s %s" % [InvoUi.amount(_txn["amount"]), _wallet.currency_name()]
	for c: Node in _review_rows.get_children():
		c.queue_free()
	var raw: Dictionary = _txn.get("raw", {})
	var rows: Array = [["From", InvoUi.masked_phone(Invo.player_phone)]]
	if _sending():
		rows.append(["To", InvoUi.masked_phone(str(_txn["phone"]))])
	rows.append(["Game", str(_game.get("game_name", ""))])
	for key: String in ["fee_amount", "fee", "total_fee"]:
		if raw.get(key) != null:
			rows.append(["Fee", "%s %s" % [InvoUi.amount(raw[key]), _wallet.currency_name()]])
			break
	for key: String in ["net_amount", "amount_received", "receiver_amount"]:
		if raw.get(key) != null:
			rows.append(["They receive" if _sending() else "You receive",
					"%s %s" % [InvoUi.amount(raw[key]), _game.get("currency_name", "")]])
			break
	for pair: Array in rows:
		var r: HBoxContainer = InvoUi.hbox()
		r.add_child(InvoUi.label(str(pair[0]), "InvoMuted"))
		r.add_child(InvoUi.spacer())
		r.add_child(InvoUi.label(str(pair[1]), "InvoBodyStrong"))
		_review_rows.add_child(r)


# ------------------------------------------------------------------ step 3

func _build_approve() -> VBoxContainer:
	var v: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = InvoUi.hbox()
	head.add_child(InvoUi.icon_button("back", "Back", func() -> void: _approval.cancel()))
	head.add_child(InvoUi.label("Approve on your phone", "InvoHeading"))
	v.add_child(head)
	_approval = InvoApprovalView.new()
	_approval.finished.connect(_on_approved)
	_approval.failed.connect(_on_approval_failed)
	v.add_child(_approval)
	return v


func _start_approval() -> void:
	_go(2)
	var summary: String
	if _sending():
		summary = "Sending %s %s to %s in %s" % [InvoUi.amount(_txn["amount"]), _wallet.currency_name(),
				InvoUi.masked_phone(str(_txn["phone"])), _game.get("game_name", "")]
	else:
		summary = "Moving %s %s to %s" % [InvoUi.amount(_txn["amount"]), _wallet.currency_name(),
				_game.get("game_name", "")]
	_approval.start(str(_txn["transaction_id"]), mode, summary)


func _on_approval_failed(message: String) -> void:
	_show_review()
	_error2.text = message


func _on_approved(result: Dictionary, message: String) -> void:
	_request_id = ""
	_go(3)
	var code: String = str(result.get("claim_code", "")) if result.get("claim_code") != null else ""
	if _sending():
		_done_title.text = "Sent"
		_done_text.text = message if not message.is_empty() else "%s %s is waiting for %s in %s." % [
				InvoUi.amount(_txn["amount"]), _wallet.currency_name(),
				InvoUi.masked_phone(str(_txn["phone"])), _game.get("game_name", "")]
	else:
		_done_title.text = "Transfer complete" if message.is_empty() else "Transfer approved"
		_done_text.text = message if not message.is_empty() else "Collect it in %s." % _game.get("game_name", "")
	_done_code.text = code
	_done_code.visible = not code.is_empty()
	_copy_button.visible = not code.is_empty()
	_wallet.notify_wallet_changed()


# ------------------------------------------------------------------ step 4

func _build_done() -> VBoxContainer:
	var v: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var check: TextureRect = TextureRect.new()
	check.texture = InvoUiTheme.icon("check")
	check.custom_minimum_size = Vector2(56, 56)
	check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	check.modulate = get_theme_color("font_color", "InvoSuccess")
	check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(check)
	_done_title = InvoUi.label("", "InvoTitle")
	_done_text = InvoUi.label("", "InvoBody", true)
	_done_code = InvoUi.label("", "InvoDisplay")
	for l: Label in [_done_title, _done_text, _done_code]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var buttons: HBoxContainer = InvoUi.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_copy_button = InvoUi.button("Copy code", "InvoSecondaryButton",
			func() -> void: DisplayServer.clipboard_set(_done_code.text))
	buttons.add_child(_copy_button)
	buttons.add_child(InvoUi.button("Done", "InvoPrimaryButton", func() -> void:
		_amount.text = ""
		_go(0)
		_refresh_details()))
	v.add_child(buttons)
	return v


# ------------------------------------------------------------------ recent

func _load_recent() -> PackedStringArray:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(RECENT_FILE) != OK:
		return PackedStringArray()
	return cfg.get_value("recent", Invo.player_email.md5_text(), PackedStringArray())


func _save_recent(phone: String) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(RECENT_FILE)
	var list: PackedStringArray = _load_recent()
	var i: int = list.find(phone)
	if i >= 0:
		list.remove_at(i)
	list.insert(0, phone)
	cfg.set_value("recent", Invo.player_email.md5_text(), list.slice(0, 3))
	cfg.save(RECENT_FILE)

extends PanelContainer
## InvoWalletPanel — a drop-in wallet Control any game can instance.
##
## Shows the player's balance, pending items to collect, and (when a mode that
## can act is available) buy / claim / send flows. Wire-up is automatic through
## the `Invo` autoload; listen to its signals for game-side reactions.

## Emitted when the player completes an action that changed their balance.
signal wallet_changed

@onready var _balance_label: Label = %BalanceLabel
@onready var _status: Label = %StatusLabel
@onready var _pending_box: VBoxContainer = %PendingBox
@onready var _email: LineEdit = %EmailField
@onready var _phone: LineEdit = %PhoneField
@onready var _usd: LineEdit = %UsdField
@onready var _claim_code: LineEdit = %ClaimCode
@onready var _send_phone: LineEdit = %SendPhone
@onready var _send_amount: LineEdit = %SendAmount
@onready var _send_dest: OptionButton = %SendDestination

var _destinations: Array[Dictionary] = []


func _ready() -> void:
	%RefreshButton.pressed.connect(_on_refresh)
	%LoginButton.pressed.connect(_on_login)
	%BuyButton.pressed.connect(_on_buy)
	%ClaimButton.pressed.connect(_on_claim)
	%SendButton.pressed.connect(_on_send)
	Invo.balance_updated.connect(_on_balance_updated)
	Invo.request_failed.connect(_on_request_failed)
	if Invo.client() != null and Invo.client().has_token():
		_on_refresh()


func _say(text: String) -> void:
	_status.text = text


func _on_login() -> void:
	var email: String = _email.text.strip_edges()
	if email.is_empty():
		_say("Enter your player email first.")
		return
	_say("Signing in...")
	var res: InvoResult = await Invo.login_sandbox(email)
	if res.ok:
		_say("Signed in.")
		_on_refresh()
	else:
		_say(res.error.message)


func _on_refresh() -> void:
	if not Invo.client().has_token():
		_say("Sign in first (or configure a player token).")
		return
	_say("Refreshing...")
	var res: InvoResult = await Invo.fetch_balance()
	if not res.ok:
		_say(res.error.message)
		return
	_say("")
	var pending: InvoResult = await Invo.client().get_pending_collect()
	_render_pending(pending)
	var dests: InvoResult = await Invo.client().get_destinations()
	if dests.ok:
		_render_destinations(dests.dict())


func _on_balance_updated(balance: Dictionary) -> void:
	var rows: Array = balance.get("balances", [])
	if rows.is_empty():
		_balance_label.text = "0.00"
		return
	var parts: Array[String] = []
	for row: Variant in rows:
		if row is Dictionary:
			var d: Dictionary = row
			parts.append("%s %s" % [
				str(d.get("available_balance", d.get("total_balance", "0"))),
				str(d.get("currency_symbol", d.get("currency_name", ""))),
			])
	_balance_label.text = " · ".join(parts)
	wallet_changed.emit()


func _render_pending(pending: InvoResult) -> void:
	for child: Node in _pending_box.get_children():
		child.queue_free()
	if not pending.ok:
		return
	var rows: Array = pending.dict().get("pending", [])
	%PendingTitle.visible = not rows.is_empty()
	for row: Variant in rows:
		if not (row is Dictionary):
			continue
		var d: Dictionary = row
		var line: Label = Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "• %s %s from %s — approve in your INVO wallet (passkey)" % [
			str(d.get("amount", "?")), str(d.get("flow", "")),
			str(d.get("source_game", "another game")),
		]
		_pending_box.add_child(line)


func _render_destinations(dests: Dictionary) -> void:
	_destinations.clear()
	_send_dest.clear()
	for game: Variant in dests.get("available_games", []):
		if game is Dictionary:
			_destinations.append(game)
			_send_dest.add_item("%s (%s)" % [
				str((game as Dictionary).get("game_name", "?")),
				str((game as Dictionary).get("currency_name", "")),
			])


func _on_buy() -> void:
	var email: String = _email.text.strip_edges()
	var usd: String = _usd.text.strip_edges()
	if email.is_empty() or usd.is_empty():
		_say("Enter your email and a USD amount.")
		return
	_say("Opening checkout...")
	var res: InvoResult = await Invo.open_checkout(email, usd)
	if res.ok:
		_say("Checkout opened in your browser. Refresh after paying." if not Invo.is_mock_enabled()
				else "Mock checkout created: %s" % str(res.dict().get("checkout_url", "")))
	else:
		_say(res.error.message)


func _on_claim() -> void:
	var code: String = _claim_code.text.strip_edges()
	var email: String = _email.text.strip_edges()
	var phone: String = _phone.text.strip_edges()
	if code.is_empty() or email.is_empty() or phone.is_empty():
		_say("Enter your email, your phone (+countrycode...), and the claim code.")
		return
	var server: InvoSandboxServer = Invo.sandbox()
	if server == null:
		_say("Claiming runs on your backend in production; sandbox mode required here.")
		return
	_say("Claiming...")
	var res: InvoResult = await server.claim_currency(code, email.get_slice("@", 0), email, phone)
	if res.ok:
		if res.dict().get("needs_account_selection", false):
			_say("This phone maps to several accounts — pick one in your integration.")
		else:
			_say("Claimed! New balance: %s" % str(res.dict().get("new_balance", "?")))
			_on_refresh()
	elif res.error.is_phone_share_approval_required():
		_say("%s (phone ••••%s must approve — then claim again)" % [
			res.error.message, res.error.phone_share_last4()])
	else:
		_say(res.error.message)


func _on_send() -> void:
	var email: String = _email.text.strip_edges()
	var my_phone: String = _phone.text.strip_edges()
	var to_phone: String = _send_phone.text.strip_edges()
	var amount: String = _send_amount.text.strip_edges()
	if email.is_empty() or my_phone.is_empty() or to_phone.is_empty() or amount.is_empty() \
			or _send_dest.selected < 0 or _send_dest.selected >= _destinations.size():
		_say("Fill in your phone, the recipient phone, amount, and destination.")
		return
	var server: InvoSandboxServer = Invo.sandbox()
	if server == null:
		_say("Sends initiate on your backend in production; sandbox mode required here.")
		return
	_say("Initiating send...")
	var dest: Dictionary = _destinations[_send_dest.selected]
	var res: InvoResult = await server.initiate_send(
			"godot-%d" % Time.get_ticks_msec(),  # client_request_id (idempotency)
			email.get_slice("@", 0), email, my_phone,
			to_phone, dest.get("game_id"), amount)
	if res.ok:
		var method: String = str(res.dict().get("verification_method", ""))
		if res.dict().get("guardian_approval") != null:
			_say("Waiting on guardian approval.")
		elif method == "sms":
			_say("Sent — the recipient confirms with the SMS PIN they received.")
		else:
			_say("Sent — the sender approves in their INVO wallet (passkey).")
		_on_refresh()
	elif res.error.is_steam_value_non_transferable():
		_say("%s (max sendable: %s)" % [res.error.message, res.error.steam_transferable_max()])
	elif res.error.is_receiver_not_enrolled():
		_say("Recipient isn't enrolled yet — send them a claim code instead.")
	else:
		_say(res.error.message)


func _on_request_failed(error: InvoError) -> void:
	if _status.text.is_empty():
		_say(error.message)

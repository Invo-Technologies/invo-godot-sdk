class_name InvoPhonePanel
extends VBoxContainer
## Phone screen (the phone button in the header): the number that approves the
## player's sends, and changing it. A secured account confirms the change from
## an email link on INVO's page, never in the game, as in the Unity kit.

var _wallet: InvoWallet
var _form: VBoxContainer
var _current: Label
var _new_phone: LineEdit
var _update: Button
var _error: Label
var _waiting: VBoxContainer
var _wait_text: Label
var _wait_status: Label
var _done: VBoxContainer
var _done_text: Label
var _request_id: String = ""
var _requested_phone: String = ""
var _poll_run: int = 0


func setup(wallet: InvoWallet) -> void:
	_wallet = wallet
	var head: HBoxContainer = InvoUi.hbox()
	head.add_child(InvoUi.icon_button("back", "Back", func() -> void: _wallet.show_panel("Send")))
	head.add_child(InvoUi.label("Your phone number", "InvoTitle"))
	add_child(head)

	_form = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	var card: PanelContainer = InvoUi.card("InvoCard")
	var row: HBoxContainer = InvoUi.hbox()
	var col: VBoxContainer = InvoUi.vbox(0)
	col.add_child(InvoUi.label("Current", "InvoMuted"))
	_current = InvoUi.label("", "InvoHeading")
	col.add_child(_current)
	row.add_child(col)
	row.add_child(InvoUi.spacer())
	row.add_child(InvoUi.label("Approves your sends", "InvoCaption"))
	card.add_child(row)
	_form.add_child(card)
	_form.add_child(InvoUi.label("New number", "InvoCaption"))
	_new_phone = InvoUi.field("+15555550123")
	_form.add_child(_new_phone)
	_error = InvoUi.label("", "InvoDanger", true)
	_form.add_child(_error)
	_form.add_child(InvoUi.note("To keep your account safe, INVO may email you a link to confirm " +
			"the change. No text message is sent.", "mail"))
	_update = InvoUi.button("Update number", "InvoPrimaryButton", _on_update)
	_form.add_child(_update)
	add_child(_form)

	_waiting = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	_waiting.add_child(InvoUi.label("Check your email", "InvoHeading"))
	_wait_text = InvoUi.label("", "InvoBody", true)
	_waiting.add_child(_wait_text)
	_wait_status = InvoUi.label("", "InvoCaption", true)
	_waiting.add_child(_wait_status)
	var wb: HBoxContainer = InvoUi.hbox()
	wb.add_child(InvoUi.button("Resend email", "InvoSecondaryButton", _resend))
	wb.add_child(InvoUi.button("Cancel change", "InvoSecondaryButton", _cancel_change))
	_waiting.add_child(wb)
	add_child(_waiting)

	_done = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	_done_text = InvoUi.label("", "InvoBody", true)
	_done.add_child(_done_text)
	_done.add_child(InvoUi.button("Done", "InvoPrimaryButton", func() -> void: _wallet.show_panel("Send")))
	add_child(_done)
	_show(_form)


func on_shown() -> void:
	_current.text = InvoUi.masked_phone(Invo.player_phone) if not Invo.player_phone.is_empty() else "Not set"
	if _waiting.visible:
		return
	_new_phone.text = ""
	_error.text = ""
	_show(_form)


func _show(page: Control) -> void:
	for p: Control in [_form, _waiting, _done]:
		p.visible = p == page


func _on_update() -> void:
	var phone: String = _new_phone.text.strip_edges()
	_error.text = ""
	if InvoValidate.e164_problem(phone, "phone") != null:
		_error.text = "That doesn't look like a valid phone number. Include the country code."
		return
	var server: InvoSandboxServer = Invo.commerce()
	if server == null:
		_error.text = "Changing your number needs the game server."
		return
	_update.disabled = true
	var res: InvoResult = await server.change_player_phone(Invo.player_email, phone)
	if not is_instance_valid(self):
		return
	_update.disabled = false
	if res.ok:
		var r: Dictionary = res.dict()
		if r["identity_rekeyed"] and not str(r["player_token"]).is_empty():
			Invo.set_player_token(str(r["player_token"]), str(r["identity_id"]))
		var unchanged: bool = str(r["status"]) == "unchanged"
		Invo.set_active_player(Invo.player_email, phone, Invo.player_name)
		_finish("That's already your number." if unchanged
				else "Done. Your sends are now approved on %s." % InvoUi.masked_phone(phone))
		return
	if res.error.is_phone_change_requires_verification():
		_requested_phone = phone
		await _request_change()
		return
	_error.text = _describe(res.error)


func _request_change() -> void:
	var server: InvoSandboxServer = Invo.commerce()
	var res: InvoResult = await server.create_phone_change_request(Invo.player_email, _requested_phone)
	if not is_instance_valid(self):
		return
	if not res.ok:
		_show(_form)
		_error.text = _describe(res.error)
		return
	_request_id = str(res.dict()["change_request_id"])
	_wait_text.text = "We sent a link to your email. Open it and confirm on INVO's page to switch to %s." \
			% InvoUi.masked_phone(_requested_phone)
	_wait_status.text = "Waiting for you to confirm"
	_show(_waiting)
	_poll()


func _poll() -> void:
	_poll_run += 1
	var run: int = _poll_run
	var server: InvoSandboxServer = Invo.commerce()
	while run == _poll_run and is_instance_valid(self):
		await get_tree().create_timer(5.0).timeout
		if run != _poll_run or not is_instance_valid(self):
			return
		var res: InvoResult = await server.get_phone_change_request(_request_id)
		if run != _poll_run or not res.ok:
			continue
		var r: Dictionary = res.dict()
		if r["is_confirmed"]:
			Invo.set_active_player(Invo.player_email, _requested_phone, Invo.player_name)
			_finish("Confirmed. Your sends are now approved on %s." % InvoUi.masked_phone(_requested_phone))
			return
		if not r["is_pending"]:
			_wait_status.text = {
				"expired": "The link expired before it was confirmed. Nothing changed.",
				"cancelled": "A newer request replaced this one.",
				"denied": "The change was declined. Your number is unchanged.",
			}.get(str(r["status"]), "Change not made. The emailed link stops working when it expires.")
			return


func _resend() -> void:
	_poll_run += 1
	await _request_change()


## INVO has no cancel route: an unconfirmed request simply expires.
func _cancel_change() -> void:
	_poll_run += 1
	_show(_form)
	_error.text = "Change not made. The emailed link stops working when it expires."


func _finish(text: String) -> void:
	_poll_run += 1
	_done_text.text = text
	_current.text = InvoUi.masked_phone(Invo.player_phone)
	_show(_done)


static func _describe(e: InvoError) -> String:
	match e.code:
		"INVALID_PHONE", "INVALID_INPUT":
			return "That doesn't look like a valid phone number. Include the country code."
		"PHONE_SHARE_APPROVAL_REQUIRED":
			return "That number belongs to another INVO account."
		"PENDING_TRANSFERS_TO_OLD_PHONE":
			return "Collect what's waiting for your current number first, then change it."
		"PENDING_TRANSFERS_TO_NEW_PHONE":
			return "Currency is waiting to be collected on that number. Collect it first."
		"PHONE_UPDATE_UNAVAILABLE":
			return "Changing numbers is unavailable right now. Try again later."
		"player_not_found":
			return "Make a send or transfer first; then you can change your number."
	if InvoPlayerCopy.is_network_error(e):
		return "No connection. Check your network and try again."
	return "We could not change your number. Try again in a moment."

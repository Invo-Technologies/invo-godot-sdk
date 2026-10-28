class_name InvoApprovalView
extends VBoxContainer
## "Approve on your phone": the QR step shared by Send, Transfer and Collect,
## the Godot twin of the Unity kit's InvoApprovalStep. Begins a device grant,
## shows its QR and user code, polls until the phone answers, answers the
## first-time "Set up INVO on this phone?" match-code prompt, then settles the
## transaction. The device code is single use, so nothing here is retried.

## The money step finished. `result` is the settle result (see
## InvoMap.to_settle_result); `message` is what to tell the player.
signal finished(result: Dictionary, message: String)
## Nothing moved (declined, expired, refused). `message` is player-facing.
signal failed(message: String)

const MAX_TRANSIENT_FAILURES: int = 5

var _run: int = 0
var _summary: Label
var _qr: TextureRect
var _code_line: Label
var _status: Label
var _match_box: VBoxContainer
var _match_code: Label
var _device_code: String = ""
var _open_again: Button
var _approve_url: String = ""


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", InvoUiTheme.UNIT * 2)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_summary = InvoUi.label("", "InvoCaption")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_summary)
	var scan: Label = InvoUi.label("Scan with your phone to approve", "InvoBodyStrong")
	scan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(scan)
	var frame: PanelContainer = InvoUi.card("InvoQrFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_qr = TextureRect.new()
	_qr.custom_minimum_size = Vector2(200, 200)
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_qr)
	add_child(frame)
	_code_line = InvoUi.label("", "InvoMuted")
	_code_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_code_line)

	_match_box = InvoUi.vbox()
	_match_box.visible = false
	var ask: Label = InvoUi.label("Set up INVO on this phone?", "InvoHeading")
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(ask)
	_match_code = InvoUi.label("", "InvoDisplay")
	_match_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(_match_code)
	var hint: Label = InvoUi.label("Say Yes only if the phone you just opened shows this code.", "InvoCaption", true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(hint)
	var answers: HBoxContainer = InvoUi.hbox()
	answers.alignment = BoxContainer.ALIGNMENT_CENTER
	answers.add_child(InvoUi.button("Yes, it matches", "InvoPrimaryButton", _answer_match.bind(true)))
	answers.add_child(InvoUi.button("No, it's different", "InvoSecondaryButton", _answer_match.bind(false)))
	_match_box.add_child(answers)
	add_child(_match_box)

	var pill: PanelContainer = InvoUi.card("InvoStatusPill")
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status = InvoUi.label("", "InvoCaption")
	pill.add_child(_status)
	add_child(pill)
	var buttons: HBoxContainer = InvoUi.hbox()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_open_again = InvoUi.button("Open again", "InvoSecondaryButton", func() -> void: OS.shell_open(_approve_url))
	_open_again.visible = false
	buttons.add_child(_open_again)
	buttons.add_child(InvoUi.button("Cancel", "InvoSecondaryButton", cancel))
	add_child(buttons)


## Stop polling. Nothing has moved until the phone approves, so this is safe.
func cancel() -> void:
	_run += 1
	failed.emit("")


## Approve `transaction_id` for `flow` (transfer | send | send_receipt |
## transfer_receipt). `summary` is the line above the QR, e.g.
## "Sending 100 Gems to ••• 0112 in Star Raiders".
func start(transaction_id: String, flow: String, summary: String) -> void:
	_run += 1
	var run: int = _run
	_summary.text = summary
	_match_box.visible = false
	_qr.texture = null
	_code_line.text = ""
	_status.text = "Getting a code…"
	var client: InvoPlayerClient = Invo.client()
	var begin: InvoResult = await client.begin_device_approval(
			transaction_id, flow, InvoPlayerClient.default_channel())
	if run != _run:
		return
	if not begin.ok:
		failed.emit(_begin_problem(begin.error))
		return
	var grant: Dictionary = begin.dict()
	_device_code = str(grant["device_code"])
	_approve_url = str(grant["verification_uri_complete"])
	_qr.texture = InvoQr.to_texture(_approve_url, 8)
	_code_line.text = "Or go to %s and enter %s" % [
			str(grant["verification_uri"]).trim_prefix("https://"), grant["user_code"]]
	_open_again.visible = str(grant["channel"]) == "app_browser"
	if _open_again.visible:
		OS.shell_open(_approve_url)
	var deadline: float = Time.get_ticks_msec() / 1000.0 + float(grant["expires_in"])
	var interval: int = maxi(int(grant["interval"]), 2)
	var transient: int = 0
	while true:
		var waited: float = 0.0
		while waited < interval:
			_status.text = "Waiting for your phone · code expires in %s" % _clock(deadline)
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
			if run != _run:
				return
		var poll: InvoResult = await client.poll_device_approval(_device_code)
		if run != _run:
			return
		if not poll.ok:
			if InvoPlayerClient.is_transient_poll_failure(poll.error) and transient < MAX_TRANSIENT_FAILURES:
				transient += 1
				continue
			failed.emit("We could not confirm the approval. Check your history before trying again.")
			return
		transient = 0
		var p: Dictionary = poll.dict()
		var status: String = str(p["status"])
		interval = InvoPlayerClient.next_poll_interval(interval, status, int(p.get("interval", 0)))
		match status:
			"approved":
				_status.text = "Approved. Finishing…"
				await _settle(run, transaction_id, flow)
				return
			"access_denied":
				failed.emit("The approval was declined, so nothing was sent. Try again if that was a mistake.")
				return
			"expired_token":
				failed.emit("The QR code expired before it was approved. Show a new one to try again.")
				return
			_:
				var enrollment: Variant = p.get("enrollment")
				if enrollment is Dictionary and str(enrollment.get("match_code", "")) != "":
					_match_code.text = str(enrollment["match_code"])
					_match_box.visible = true
				else:
					_match_box.visible = false


func _settle(run: int, transaction_id: String, flow: String) -> void:
	var res: InvoResult = await Invo.client().settle_device_approval(transaction_id, flow, _device_code)
	if run != _run:
		return
	if not res.ok:
		var ref: String = "" if res.error.request_id.is_empty() else " (Ref %s)" % res.error.request_id
		if InvoPlayerCopy.is_network_error(res.error):
			failed.emit("No connection. If you already approved on your phone, check your history before trying again.")
		else:
			failed.emit("We could not confirm the approval. Check your history before trying again." + ref)
		return
	var r: Dictionary = res.dict()
	if r["is_hold"]:
		finished.emit(r, _hold_message(str(r["hold_reason"])))
	elif str(r["status"]) == "not_pending" and not r["already_settled"]:
		failed.emit("We could not confirm this. Check your history before trying again.")
	else:
		finished.emit(r, "")


func _answer_match(approve: bool) -> void:
	_match_box.visible = false
	var res: InvoResult = await Invo.client().confirm_device_enrollment(_device_code, approve)
	if not res.ok and not InvoPlayerClient.is_moot_enrollment_answer(res.error):
		_status.text = "We could not send your answer. The next check will show where things stand."


static func _hold_message(reason: String) -> String:
	match reason:
		"GUARDIAN_APPROVAL_PENDING":
			return "Approved. It now needs the guardian on file to approve as well; we will finish when they do."
		"RISK_HOLD":
			return "Approved. Invo is reviewing it before it goes through; nothing else is needed from you."
	return "Approved. One more check is running; we will finish as soon as it clears."


static func _begin_problem(e: InvoError) -> String:
	match e.code:
		"DEVICE_APPROVAL_ALREADY_PENDING":
			return "This was already approved on a phone and is finishing. Wait a few minutes, then try again."
		"PASSKEY_RECOVERY_COOLDOWN":
			return "Your INVO passkey was recently recovered, so sending is paused for a while. Try again later."
		"DEVICE_APPROVAL_NOT_CONFIGURED", "TENANT_NOT_MIGRATED":
			return "Phone approval is not enabled for this game yet. Contact Invo to enable it."
		"player_not_found":
			return "Your Invo account was not found in this game."
	if InvoPlayerCopy.is_network_error(e):
		return "No connection. Check your network and try again."
	return "We could not start the approval. Please try again."


static func _clock(deadline: float) -> String:
	var left: int = maxi(0, int(deadline - Time.get_ticks_msec() / 1000.0))
	return "%d:%02d" % [left / 60, left % 60]

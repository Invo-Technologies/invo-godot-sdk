class_name InvoCollectPanel
extends VBoxContainer
## Collect tab: sends and transfers waiting for this player. Collect approves
## the receipt on the player's phone (QR), then it lands in their balance.

var _wallet: InvoWallet
var _list_page: VBoxContainer
var _list: VBoxContainer
var _message: Label
var _approve_page: VBoxContainer
var _approval: InvoApprovalView
var _refreshed_at: int = -100000
var _refresh_run: int = 0


func setup(wallet: InvoWallet) -> void:
	_wallet = wallet
	_list_page = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	_list_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_page.add_child(InvoUi.label("Collect", "InvoTitle"))
	_message = InvoUi.label("", "InvoCaption", true)
	_list_page.add_child(_message)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = InvoUi.vbox()
	scroll.add_child(_list)
	_list_page.add_child(scroll)
	add_child(_list_page)

	_approve_page = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	_approve_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head: HBoxContainer = InvoUi.hbox()
	head.add_child(InvoUi.icon_button("back", "Back", func() -> void: _approval.cancel()))
	head.add_child(InvoUi.label("Approve on your phone", "InvoHeading"))
	_approve_page.add_child(head)
	_approval = InvoApprovalView.new()
	_approval.finished.connect(_on_collected)
	_approval.failed.connect(_on_failed)
	_approve_page.add_child(_approval)
	_approve_page.visible = false
	add_child(_approve_page)


func on_shown() -> void:
	if not _approve_page.visible:
		refresh()


## Re-reads the pending list (also called every 45 s while the tab is open).
func refresh() -> void:
	_refreshed_at = Time.get_ticks_msec()
	_refresh_run += 1
	var run: int = _refresh_run
	if Invo.client() == null or not Invo.client().has_token():
		_show_items([])
		return
	var res: InvoResult = await Invo.client().get_pending_actions()
	# Only the newest refresh draws; an older one finishing late would duplicate rows.
	if not is_instance_valid(self) or run != _refresh_run:
		return
	if not res.ok:
		_message.text = InvoPlayerCopy.transfer(res.error, "Your pending items could not be loaded. Please try again.")
		return
	_show_items(res.dict().get("receivable", []))


func _process(_delta: float) -> void:
	if is_visible_in_tree() and _list_page.visible and Time.get_ticks_msec() - _refreshed_at > 45000:
		refresh()


func _show_items(items: Array) -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	if items.is_empty():
		_message.text = "Nothing is waiting for you right now."
		_list.add_child(InvoUi.note("Expecting something that isn't here? If you don't play this game yet, " +
				"INVO emailed you a link to collect it.", "mail"))
		return
	_message.text = "Approve on your phone to add it to your balance."
	for item: Dictionary in items:
		var card: PanelContainer = InvoUi.card("InvoCard")
		var row: HBoxContainer = InvoUi.hbox()
		card.add_child(row)
		var col: VBoxContainer = InvoUi.vbox(0)
		col.add_child(InvoUi.label("%s %s" % [InvoUi.amount(item["amount"]), item["currency"]], "InvoBodyStrong"))
		var from: String = str(item["counterparty_game"])
		col.add_child(InvoUi.label("From %s" % from if not from.is_empty() else "From another player", "InvoMuted"))
		row.add_child(col)
		row.add_child(InvoUi.spacer())
		if item["held"]:
			row.add_child(InvoUi.label("On hold", "InvoWarning"))
		else:
			row.add_child(InvoUi.button("Collect", "InvoPrimaryButton", _collect.bind(item)))
		_list.add_child(card)


func _collect(item: Dictionary) -> void:
	_list_page.visible = false
	_approve_page.visible = true
	_approval.start(str(item["transfer_id"]), str(item["approval_flow"]),
			"Collecting %s %s" % [InvoUi.amount(item["amount"]), item["currency"]])


func _on_failed(message: String) -> void:
	_approve_page.visible = false
	_list_page.visible = true
	await refresh()
	if not message.is_empty():
		_message.text = message


func _on_collected(_result: Dictionary, message: String) -> void:
	_approve_page.visible = false
	_list_page.visible = true
	_wallet.notify_wallet_changed()
	await refresh()
	_message.text = message if not message.is_empty() else "Added to your balance."

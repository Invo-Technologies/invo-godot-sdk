extends Node
## Headless end-to-end run of the wallet window on the offline mock: every
## tab, a store item purchase, a send through QR approval, a collect, and a
## secured phone change. Run from the addon dev-host project:
##   godot --headless res://tests/ui_tests.tscn
## (a scene, not --script: the wallet scripts use the `Invo` autoload, which
## --script runs do not compile in).
## Exit code 0 = all passed.

var _passed: int = 0
var _failed: int = 0
var _invo: Node


func _ready() -> void:
	_run_all()


func _run_all() -> void:
	await get_tree().process_frame
	_invo = get_tree().root.get_node_or_null("Invo")
	_check(_invo != null, "Invo autoload is registered")
	if _invo == null:
		_finish()
		return
	_invo.call("enable_mock")
	var w: InvoWallet = (load("res://addons/invonetwork/ui/invo_wallet.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	await w.open("Store")
	_check(w.is_open(), "wallet opens")
	_check(str(_invo.get("player_email")) != "", "mock player is signed in")
	await _test_store(w)
	await _test_send(w)
	await _test_collect(w)
	await _test_phone(w)
	w.close()
	_check(not w.is_open(), "wallet closes")
	_check(InvoWallet.balance_text({}) == "-", "balance shows - before the first read")
	_check(InvoWallet.balance_text({"balances": [{"available_balance": "8500.00", "currency_name": "Gems"}]})
			== "8,500 Gems", "balance text matches Unity's format")
	_check(InvoUi.masked_phone("+15555550111") == "••• 0111", "phone masks to the last four")
	_finish()


func _test_store(w: InvoWallet) -> void:
	var store: InvoStorePanel = w._pages["Store"]
	await _until(func() -> bool: return store._loaded, 5.0)
	_check(store._loaded, "store loads game items")
	_check(_count_buttons(store._top_up, "Buy") >= 3, "top up shows featured, packs and daily deals")
	store._show_sub("Items")
	_check(_count_buttons(store._items, "Buy") == w.item_catalog().size(), "items tab lists the catalog")
	# The mock player holds 120; the 250 sword must be refused, the 40 potion bought.
	store._confirm_item(w.item_catalog()[0])
	var refused: Button = _find_button(store._confirm, "Buy")
	refused.pressed.emit()
	await _until(func() -> bool: return refused.text == "Try Again", 5.0)
	_check(refused.text == "Try Again" and _find_label(store._confirm, "You do not have enough balance for this item."),
			"unaffordable item is refused with Unity's copy")
	store._confirm_item(w.item_catalog()[2])
	var buy: Button = _find_button(store._confirm, "Buy")
	_check(buy != null, "confirm sheet has a Buy button")
	buy.pressed.emit()
	await _until(func() -> bool: return buy.text == "Purchase Complete", 5.0)
	_check(buy.text == "Purchase Complete", "item purchase completes")


func _test_send(w: InvoWallet) -> void:
	w.show_panel("Send")
	var send: InvoMovePanel = w._pages["Send"]
	await _until(func() -> bool: return not send._game.is_empty(), 5.0)
	_check(not send._game.is_empty(), "send picks a destination game")
	send._phone.text = "+15555550112"
	send._amount.text = "100"
	await send._on_continue()
	_check(send._steps[1].visible, "continue initiates the send and shows the review")
	send._start_approval()
	await _until(func() -> bool: return send._approval._qr.texture != null, 5.0)
	_check(send._approval._qr.texture != null, "approval shows a QR code")
	await _until(func() -> bool: return send._steps[3].visible, 30.0)
	_check(send._steps[3].visible and send._done_title.text == "Sent", "phone approval settles the send")


func _test_collect(w: InvoWallet) -> void:
	w.show_panel("Collect")
	var collect: InvoCollectPanel = w._pages["Collect"]
	await _until(func() -> bool: return _count_buttons(collect._list, "Collect") > 0, 5.0)
	var before: int = _count_buttons(collect._list, "Collect")
	_check(before > 0, "collect lists pending items")
	_find_button(collect._list, "Collect").pressed.emit()
	await _until(func() -> bool: return collect._message.text == "Added to your balance.", 30.0)
	_check(collect._message.text == "Added to your balance.", "collect approves and credits")
	_check(_count_buttons(collect._list, "Collect") == before - 1, "collected item leaves the list")


func _test_phone(w: InvoWallet) -> void:
	w.show_panel("Phone")
	var phone: InvoPhonePanel = w._pages["Phone"]
	phone._new_phone.text = "+15555550199"
	await phone._on_update()
	_check(phone._waiting.visible, "secured account gets the confirm-by-email step")
	await _until(func() -> bool: return phone._done.visible, 15.0)
	_check(phone._done.visible and str(_invo.get("player_phone")) == "+15555550199",
			"confirmed change updates the player's phone")


func _until(condition: Callable, timeout_s: float) -> void:
	var waited: float = 0.0
	while not condition.call() and waited < timeout_s:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


func _find_label(node: Node, text: String) -> bool:
	for l: Node in node.find_children("*", "Label", true, false):
		if (l as Label).text == text:
			return true
	return false


func _count_buttons(node: Node, text: String) -> int:
	var n: int = 0
	for b: Node in node.find_children("*", "Button", true, false):
		if (b as Button).text == text and not b.is_queued_for_deletion():
			n += 1
	return n


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	for b: Node in node.find_children("*", "Button", true, false):
		if (b as Button).text == text and not b.is_queued_for_deletion():
			return b
	return null


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("  ok   ", test_name)
	else:
		_failed += 1
		print("  FAIL ", test_name)


func _finish() -> void:
	print("\n[tests] %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)

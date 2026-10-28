class_name InvoStorePanel
extends VBoxContainer
## Store tab, as in the Unity kit: "Top up" (FEATURED / PACKS / DAILY DEALS,
## paid in the browser through INVO's hosted checkout) and "Items" (your
## catalog, paid from the in-game balance with a confirm sheet).

var _wallet: InvoWallet
var _balance: Label
var _sub_tabs: Dictionary = {}
var _top_up: VBoxContainer
var _items: GridContainer
var _items_page: VBoxContainer
var _message: Label
var _confirm: PanelContainer
var _loaded: bool = false


func setup(wallet: InvoWallet) -> void:
	_wallet = wallet
	add_theme_constant_override("separation", InvoUiTheme.UNIT * 2)
	var head: HBoxContainer = InvoUi.hbox()
	head.add_child(InvoUi.label("Store", "InvoTitle"))
	head.add_child(InvoUi.spacer())
	_balance = InvoUi.label("Balance -", "InvoCaption")
	head.add_child(_balance)
	add_child(head)

	var bar: PanelContainer = InvoUi.card("InvoTabBar")
	var row: HBoxContainer = InvoUi.hbox(2)
	bar.add_child(row)
	for id: String in ["Top up", "Items"]:
		var b: Button = InvoUi.button(id, "InvoTab", _show_sub.bind(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sub_tabs[id] = b
		row.add_child(b)
	add_child(bar)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pages: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT * 2)
	scroll.add_child(pages)
	add_child(scroll)
	_message = InvoUi.label("", "InvoCaption", true)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pages.add_child(_message)
	_top_up = InvoUi.vbox(InvoUiTheme.UNIT)
	pages.add_child(_top_up)
	_items_page = InvoUi.vbox(InvoUiTheme.UNIT)
	_items = GridContainer.new()
	_items.columns = 2
	_items_page.add_child(_items)
	pages.add_child(_items_page)

	add_child(InvoUi.note("Paying opens INVO's secure checkout in your browser. " +
			"Your balance updates when the payment clears."))
	Invo.balance_updated.connect(_on_balance)
	_show_sub("Top up")


func on_shown() -> void:
	if Invo.client() != null and Invo.client().has_token():
		Invo.fetch_balance()
	if not _loaded:
		_load()


func _on_balance(balance: Dictionary) -> void:
	_balance.text = "Balance %s" % InvoWallet.balance_text(balance)


func _show_sub(id: String) -> void:
	for k: String in _sub_tabs:
		(_sub_tabs[k] as Button).theme_type_variation = "InvoTabSelected" if k == id else "InvoTab"
	_top_up.visible = id == "Top up"
	_items_page.visible = id == "Items"
	if id == "Items":
		_build_items()


# ------------------------------------------------------------------ top up

func _load() -> void:
	_clear(_top_up)
	_message.text = "Loading packs..."
	var server: InvoSandboxServer = Invo.commerce()
	if server == null:
		_message.text = "The store could not be loaded. Please try again."
		return
	var res: InvoResult = await server.get_game_items()
	if not is_instance_valid(self):
		return
	if not res.ok:
		_message.text = InvoPlayerCopy.store(res.error)
		return
	_loaded = true
	var data: Dictionary = res.dict()
	var featured: Variant = data.get("featured")
	var weekly: Array = data.get("weekly", [])
	var daily: Array = data.get("daily", [])
	_message.text = "" if featured != null or not weekly.is_empty() or not daily.is_empty() \
			else "The store is empty right now."
	if featured is Dictionary:
		_top_up.add_child(InvoUi.overline("Featured"))
		_top_up.add_child(_hero_card(featured))
	for section: Array in [["Packs", weekly], ["Daily deals", daily]]:
		if (section[1] as Array).is_empty():
			continue
		_top_up.add_child(InvoUi.overline(str(section[0])))
		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		for item: Dictionary in section[1]:
			grid.add_child(_pack_card(item))
		_top_up.add_child(grid)


func _hero_card(item: Dictionary) -> PanelContainer:
	var card: PanelContainer = InvoUi.card("InvoCardSelected")
	var row: HBoxContainer = InvoUi.hbox(InvoUiTheme.UNIT * 2)
	card.add_child(row)
	row.add_child(_image(item, 96))
	var col: VBoxContainer = InvoUi.vbox(2)
	if item["is_discounted"] and item["discount_percentage"] != null:
		col.add_child(InvoUi.label("-%d%%" % int(item["discount_percentage"]), "InvoWarning"))
	col.add_child(InvoUi.label(_name(item), "InvoHeading"))
	col.add_child(InvoUi.label(str(item["display_subtitle"]), "InvoCaption", true))
	var bottom: HBoxContainer = InvoUi.hbox()
	bottom.add_child(_price(item))
	bottom.add_child(InvoUi.spacer())
	bottom.add_child(InvoUi.button("Buy", "InvoPrimaryButton", _buy_pack.bind(item)))
	col.add_child(bottom)
	row.add_child(col)
	return card


func _pack_card(item: Dictionary) -> PanelContainer:
	var card: PanelContainer = InvoUi.card("InvoCard")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = InvoUi.vbox(2)
	card.add_child(col)
	var img: TextureRect = _image(item, 64)
	img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(img)
	for l: Label in [InvoUi.label(_name(item), "InvoBodyStrong"),
			InvoUi.label(str(item["display_subtitle"]), "InvoMuted")]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	var price: Control = _price(item)
	price.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(price)
	var buy: Button = InvoUi.button("Buy", "InvoPrimaryButton", _buy_pack.bind(item))
	col.add_child(buy)
	return card


func _buy_pack(item: Dictionary) -> void:
	if Invo.player_email.is_empty():
		_message.text = "Sign in before making a purchase."
		return
	_message.text = ""
	var res: InvoResult = await Invo.open_checkout(Invo.player_email, item["price_usd"])
	if not is_instance_valid(self):
		return
	if not res.ok:
		_message.text = "Real-money purchases need a server endpoint — see README." \
				if res.error.code == "NO_CHECKOUT_ENDPOINT" \
				else ("No connection. Check your network and try again." if InvoPlayerCopy.is_network_error(res.error)
				else "Checkout could not be started. Please try again.")


# ------------------------------------------------------------------ items

func _build_items() -> void:
	_clear(_items)
	var catalog: Array[Dictionary] = _wallet.item_catalog()
	if catalog.is_empty():
		_message.text = "No items are available right now."
		return
	_message.text = ""
	for item: Dictionary in catalog:
		var card: PanelContainer = InvoUi.card("InvoCard")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col: VBoxContainer = InvoUi.vbox(2)
		card.add_child(col)
		var img: TextureRect = _image(item, 64)
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(img)
		var n: Label = InvoUi.label(str(item.get("name", "")), "InvoBodyStrong")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
		var p: Label = InvoUi.label("%s %s" % [InvoUi.amount(item.get("price", 0)), _wallet.currency_name()], "InvoCaption")
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(p)
		col.add_child(InvoUi.button("Buy", "InvoPrimaryButton", _confirm_item.bind(item)))
		_items.add_child(card)


func _confirm_item(item: Dictionary) -> void:
	if Invo.player_email.is_empty():
		_message.text = "Sign in before making a purchase."
		return
	if _confirm != null:
		_confirm.queue_free()
	_confirm = InvoUi.card("InvoCardRaised")
	var col: VBoxContainer = InvoUi.vbox(InvoUiTheme.UNIT)
	_confirm.add_child(col)
	col.add_child(InvoUi.label("Confirm purchase", "InvoHeading"))
	for pair: Array in [["Item", str(item.get("name", ""))],
			["Price", "%s %s" % [InvoUi.amount(item.get("price", 0)), _wallet.currency_name()]],
			["Player", Invo.player_name if not Invo.player_name.is_empty() else Invo.player_email],
			["Game", _wallet.game_name()]]:
		var r: HBoxContainer = InvoUi.hbox()
		r.add_child(InvoUi.label(str(pair[0]), "InvoMuted"))
		r.add_child(InvoUi.spacer())
		r.add_child(InvoUi.label(str(pair[1]), "InvoBodyStrong"))
		col.add_child(r)
	col.add_child(InvoUi.label("Paid from your in-game balance.", "InvoCaption"))
	col.add_child(InvoUi.label("This can't be undone.", "InvoCaption"))
	var warn: Label = InvoUi.label("", "InvoDanger", true)
	col.add_child(warn)
	var buttons: HBoxContainer = InvoUi.hbox()
	var cancel: Button = InvoUi.button("Cancel", "InvoSecondaryButton", func() -> void: _confirm.queue_free())
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(cancel)
	var buy: Button = InvoUi.button("Buy", "InvoPrimaryButton")
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(buy)
	col.add_child(buttons)
	# One client_request_id per purchase intent, reused on retry: a retry of
	# this intent must not be charged twice.
	var request_id: String = InvoSandboxServer.new_client_request_id()
	buy.pressed.connect(_purchase.bind(item, request_id, buy, warn))
	add_child(_confirm)
	move_child(_confirm, get_child_count() - 2)


func _purchase(item: Dictionary, request_id: String, buy: Button, warn: Label) -> void:
	var server: InvoSandboxServer = Invo.commerce()
	if server == null:
		warn.text = "This build is not connected to its game server."
		return
	buy.disabled = true
	buy.text = "Processing..."
	warn.text = ""
	var price: Variant = item.get("price", 0)
	var res: InvoResult = await server.purchase_item(request_id, Invo.player_email,
			Invo.player_name if not Invo.player_name.is_empty() else Invo.player_email,
			str(item.get("item_id", "")), str(item.get("name", "")), 1, price, price,
			Invo.player_phone, str(item.get("description", "")), str(item.get("category", "")))
	if not is_instance_valid(buy):
		return
	if res.ok or res.error.is_duplicate_request():
		buy.text = "Purchase Complete"
		if not res.ok:
			warn.text = "This purchase already went through."
		_wallet.notify_wallet_changed()
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(_confirm):
			_confirm.queue_free()
		return
	warn.text = InvoPlayerCopy.purchase(res.error)
	if InvoPlayerCopy.is_rate_limited(res.error):
		var seconds: int = clampi(int(ceil(res.error.retry_after_seconds())) if res.error.retry_after_seconds() >= 0.0 else 10, 1, 120)
		while seconds > 0 and is_instance_valid(buy):
			buy.text = "Try again in %ds" % seconds
			await get_tree().create_timer(1.0).timeout
			seconds -= 1
		if not is_instance_valid(buy):
			return
	buy.text = "Try Again"
	buy.disabled = false


# ------------------------------------------------------------------ bits

static func _name(item: Dictionary) -> String:
	var n: String = str(item.get("display_name", ""))
	return n if not n.is_empty() else str(item.get("item_name", ""))


func _price(item: Dictionary) -> Control:
	var rt: RichTextLabel = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.scroll_active = false
	rt.add_theme_font_override("bold_font", InvoUiTheme.font(true))
	rt.add_theme_font_size_override("normal_font_size", InvoUiTheme.SIZE_CAPTION)
	rt.add_theme_font_size_override("bold_font_size", InvoUiTheme.SIZE_BODY)
	var muted: Color = get_theme_color("font_color", "InvoMuted")
	rt.add_theme_color_override("default_color", get_theme_color("font_color", "InvoBodyStrong"))
	var text: String = "[b]%s[/b]" % InvoUi.usd(item["price_usd"])
	if item["is_discounted"]:
		text += "  [color=#%s][s]%s[/s][/color]" % [muted.to_html(false), InvoUi.usd(item["original_price_usd"])]
	rt.text = text
	return rt


func _image(item: Dictionary, px: int) -> TextureRect:
	var tr: TextureRect = TextureRect.new()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = item.get("texture") as Texture2D
	var has_own: bool = tr.texture != null
	var url: String = str(item.get("image_url", item.get("icon_url", "")))
	if tr.texture == null:
		tr.texture = load("res://addons/invonetwork/ui/art/pack.png") as Texture2D
	if not has_own and not url.is_empty():
		tr.ready.connect(func() -> void: InvoUi.load_remote_image(tr, url), CONNECT_ONE_SHOT)
	return tr


static func _clear(node: Node) -> void:
	for c: Node in node.get_children():
		c.queue_free()

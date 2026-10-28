class_name InvoUi
extends RefCounted
## Small builders for the wallet screens, so every panel is assembled from the
## same pieces as the Unity kit: titles, overlines, cards, primary/secondary
## buttons, link buttons and notes. Looks come from InvoUiTheme variations.


static func label(text: String, variation: String = "InvoBody", wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## UPPERCASE section label (FEATURED, PACKS, RECENT…).
static func overline(text: String) -> Label:
	return label(text.to_upper(), "InvoOverline")


static func button(text: String, variation: String = "InvoPrimaryButton",
		on_pressed: Callable = Callable()) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func icon_button(icon_name: String, tooltip: String, on_pressed: Callable) -> Button:
	var b: Button = button("", "InvoIconButton", on_pressed)
	b.icon = InvoUiTheme.icon(icon_name)
	b.expand_icon = true
	b.custom_minimum_size = Vector2(40, 40)
	b.tooltip_text = tooltip
	return b


static func card(variation: String = "InvoCard") -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func vbox(gap: int = InvoUiTheme.UNIT) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


static func hbox(gap: int = InvoUiTheme.UNIT) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h


static func spacer(vertical: bool = false) -> Control:
	var c: Control = Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func field(placeholder: String, text: String = "") -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## A note row with an icon, like Unity's lock-icon checkout footnote.
static func note(text: String, icon_name: String = "lock") -> PanelContainer:
	var p: PanelContainer = card("InvoNote")
	var row: HBoxContainer = hbox()
	if not icon_name.is_empty():
		var tr: TextureRect = TextureRect.new()
		tr.texture = InvoUiTheme.icon(icon_name)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(16, 16)
		tr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		# Tinted to the caption colour once the note is in a themed tree.
		tr.ready.connect(func() -> void: tr.modulate = tr.get_theme_color("font_color", "InvoCaption"))
		row.add_child(tr)
	row.add_child(label(text, "InvoCaption", true))
	p.add_child(row)
	return p


## Shows an image from an https URL in `target` (keeps the placeholder on any failure).
static func load_remote_image(target: TextureRect, url: String) -> void:
	if not url.begins_with("https://") or not target.is_inside_tree():
		return
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = 15.0
	target.add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray,
			body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not is_instance_valid(target):
			return
		var img: Image = Image.new()
		var err: Error = img.load_png_from_buffer(body)
		if err != OK:
			err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_webp_from_buffer(body)
		if err == OK:
			target.texture = ImageTexture.create_from_image(img))
	if req.request(url) != OK:
		req.queue_free()


## "$9.99" from a USD number or numeric string.
static func usd(amount: Variant) -> String:
	return "$%.2f" % float(str(amount))


## "••• 0111" from a phone number or a last-4.
static func masked_phone(phone: String) -> String:
	var digits: String = ""
	for ch: String in phone:
		if ch >= "0" and ch <= "9":
			digits += ch
	return "••• " + digits.right(4) if digits.length() >= 4 else "•••"


## A whole number with thousands separators ("8,500"); decimals kept when present.
static func amount(value: Variant) -> String:
	var s: String = str(value)
	if not s.is_valid_float():
		return s
	var parts: PackedStringArray = s.split(".")
	var whole: String = parts[0].trim_prefix("-")
	var out: String = ""
	while whole.length() > 3:
		out = "," + whole.right(3) + out
		whole = whole.left(whole.length() - 3)
	out = ("-" if s.begins_with("-") else "") + whole + out
	if parts.size() > 1 and parts[1].strip_edges().trim_suffix("0").trim_suffix("0") != "":
		out += "." + parts[1]
	return out

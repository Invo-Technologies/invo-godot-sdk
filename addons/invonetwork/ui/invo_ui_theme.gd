class_name InvoUiTheme
extends RefCounted
## The INVO wallet look, shared with the Unity SDK (Runtime/UI/Theme/InvoTheme.cs):
## the same dark and light palettes, Inter, corner radii, 8 px spacing unit and
## type scale. Sizes are at the 1920x1080 reference; the wallet window scales
## the whole sheet to the screen, as Unity's canvas scaler does.
##
## Controls pick a look with `theme_type_variation`, e.g. a Label with
## "InvoTitle" or a Button with "InvoPrimaryButton". Pass your own palette to
## build() to re-skin the wallet; every key of DARK must be present.

const DARK: Dictionary = {
	"backdrop": Color8(0x05, 0x07, 0x0B, 200),
	"surface": Color("#141922"),
	"surface_raised": Color("#1B2130"),
	"field": Color("#0F131A"),
	"border": Color("#283041"),
	"accent": Color("#3B6FE0"),
	"accent_soft": Color("#1A2336"),
	"on_accent": Color("#FFFFFF"),
	"text_primary": Color("#EEF1F6"),
	"text_secondary": Color("#A3ACBA"),
	"text_muted": Color("#7D8797"),
	"link": Color("#8FB3FF"),
	"success": Color("#6FD3A8"),
	"success_soft": Color("#133A2C"),
	"warning": Color("#F2A93B"),
	"danger": Color("#F07068"),
	"corner_radius": 20,
	"small_corner_radius": 12,
}

const LIGHT: Dictionary = {
	"backdrop": Color8(0x1E, 0x1B, 0x16, 140),
	"surface": Color("#FFFFFF"),
	"surface_raised": Color("#F4F1EA"),
	"field": Color("#F4F1EA"),
	"border": Color("#E2DDD2"),
	"accent": Color("#B4472E"),
	"accent_soft": Color("#FAE9E2"),
	"on_accent": Color("#FFFFFF"),
	"text_primary": Color("#1E1B16"),
	"text_secondary": Color("#5F5A50"),
	"text_muted": Color("#787267"),
	"link": Color("#A03C26"),
	"success": Color("#2F6B4F"),
	"success_soft": Color("#E0F0E6"),
	"warning": Color("#A66810"),
	"danger": Color("#B23228"),
	"corner_radius": 12,
	"small_corner_radius": 8,
}

## Spacing unit; paddings and gaps are multiples of it.
const UNIT: int = 8

## Type scale (InvoTheme.cs): Display 44, Title 26, Heading 18, Body 16, Caption 14, Overline 13.
const SIZE_DISPLAY: int = 44
const SIZE_TITLE: int = 26
const SIZE_HEADING: int = 18
const SIZE_BODY: int = 16
const SIZE_CAPTION: int = 14
const SIZE_OVERLINE: int = 13

const FONT_PATH: String = "res://addons/invonetwork/ui/art/Inter-Variable.ttf"
const ICON_DIR: String = "res://addons/invonetwork/ui/art/icons/"

static var _regular: Font = null
static var _bold: Font = null
static var _overline: Font = null
static var _sized: Dictionary = {}


## Inter at weight 400 (bold = false) or 700.
static func font(bold: bool = false) -> Font:
	_load_fonts()
	return _bold if bold else _regular


## One of: back, check, chevron, clock, close, lock, mail, phone, search.
## `px` > 0 returns a resized copy (for places that draw at texture size, like
## a LineEdit's right_icon); the 64 px originals are used everywhere else.
static func icon(icon_name: String, px: int = 0) -> Texture2D:
	var tex: Texture2D = load(ICON_DIR + icon_name + ".png") as Texture2D
	if px <= 0 or tex == null:
		return tex
	var key: String = "%s@%d" % [icon_name, px]
	if not _sized.has(key):
		var img: Image = tex.get_image()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		_sized[key] = ImageTexture.create_from_image(img)
	return _sized[key]


static func _load_fonts() -> void:
	if _regular != null:
		return
	var file: FontFile = load(FONT_PATH) as FontFile
	# MSDF keeps text sharp when the window scales the sheet.
	file.multichannel_signed_distance_field = true
	_regular = _weight(file, 400, 0.0)
	_bold = _weight(file, 700, 0.0)
	_overline = _weight(file, 700, 1.5)


static func _weight(file: FontFile, wght: int, glyph_spacing: float) -> FontVariation:
	var v: FontVariation = FontVariation.new()
	v.base_font = file
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): wght}
	v.spacing_glyph = int(glyph_spacing)
	return v


## A rounded panel style in palette colours.
static func box(fill: Color, radius: int, border: Color = Color.TRANSPARENT,
		pad_x: int = UNIT * 2, pad_y: int = UNIT) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.anti_aliasing = true
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


## The full wallet Theme for a palette (DARK by default).
static func build(p: Dictionary = DARK) -> Theme:
	_load_fonts()
	var t: Theme = Theme.new()
	var r: int = int(p["corner_radius"])
	var rs: int = int(p["small_corner_radius"])
	t.default_font = _regular
	t.default_font_size = SIZE_BODY

	t.set_color("font_color", "Label", p["text_primary"])
	_label(t, "InvoDisplay", _bold, SIZE_DISPLAY, p["text_primary"])
	_label(t, "InvoTitle", _bold, SIZE_TITLE, p["text_primary"])
	_label(t, "InvoHeading", _bold, SIZE_HEADING, p["text_primary"])
	_label(t, "InvoBodyStrong", _bold, SIZE_BODY, p["text_primary"])
	_label(t, "InvoBody", _regular, SIZE_BODY, p["text_secondary"])
	_label(t, "InvoCaption", _regular, SIZE_CAPTION, p["text_secondary"])
	_label(t, "InvoMuted", _regular, SIZE_CAPTION, p["text_muted"])
	_label(t, "InvoOverline", _overline, SIZE_OVERLINE, p["text_muted"])
	_label(t, "InvoSuccess", _regular, SIZE_CAPTION, p["success"])
	_label(t, "InvoWarning", _regular, SIZE_CAPTION, p["warning"])
	_label(t, "InvoDanger", _regular, SIZE_CAPTION, p["danger"])

	_panel(t, "InvoSheet", box(p["surface"], r, p["border"], UNIT * 3, UNIT * 3))
	_panel(t, "InvoCard", box(p["field"], rs, p["border"], UNIT * 2, UNIT * 2))
	_panel(t, "InvoCardRaised", box(p["surface_raised"], rs, Color.TRANSPARENT, UNIT * 2, UNIT * 2))
	_panel(t, "InvoCardSelected", box(p["accent_soft"], rs, p["accent"], UNIT * 2, UNIT * 2))
	_panel(t, "InvoTabBar", box(p["field"], rs, Color.TRANSPARENT, 4, 4))
	_panel(t, "InvoNote", box(p["field"], rs, Color.TRANSPARENT, UNIT * 2, UNIT * 1 + 4))
	_panel(t, "InvoQrFrame", box(Color.WHITE, rs, Color.TRANSPARENT, UNIT * 2, UNIT * 2))
	_panel(t, "InvoStatusPill", box(p["field"], 1000, Color.TRANSPARENT, UNIT * 2, UNIT))

	_button(t, "InvoPrimaryButton", p["accent"], p["accent"].lightened(0.08), p["accent"].darkened(0.1),
			p["on_accent"], rs, Color.TRANSPARENT, UNIT * 3, UNIT + 4, _bold)
	_button(t, "InvoSecondaryButton", p["field"], p["surface_raised"], p["border"],
			p["text_primary"], rs, p["border"], UNIT * 3, UNIT + 4, _bold)
	_button(t, "InvoIconButton", p["field"], p["surface_raised"], p["border"],
			p["text_primary"], rs, p["border"], UNIT, UNIT, _regular)
	_button(t, "InvoTab", Color.TRANSPARENT, p["accent_soft"], p["surface_raised"],
			p["text_secondary"], rs - 2, Color.TRANSPARENT, UNIT * 2, UNIT, _bold)
	_button(t, "InvoTabSelected", p["surface_raised"], p["surface_raised"], p["surface_raised"],
			p["text_primary"], rs - 2, Color.TRANSPARENT, UNIT * 2, UNIT, _bold)
	_button(t, "InvoChip", p["field"], p["surface_raised"], p["accent_soft"],
			p["text_secondary"], rs, Color.TRANSPARENT, UNIT * 2, UNIT * 2, _regular)
	_button(t, "InvoChipSelected", p["accent_soft"], p["accent_soft"], p["accent_soft"],
			p["text_primary"], rs, p["accent"], UNIT * 2, UNIT * 2, _regular)
	# Link buttons: no box, link colour.
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	t.set_type_variation("InvoLinkButton", "Button")
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "InvoLinkButton", empty)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "InvoLinkButton", p["link"])
	t.set_font("font", "InvoLinkButton", _regular)
	t.set_font_size("font_size", "InvoLinkButton", SIZE_CAPTION)

	var field: StyleBoxFlat = box(p["field"], rs, p["border"], UNIT * 2, UNIT + 4)
	var field_focus: StyleBoxFlat = box(p["field"], rs, p["accent"], UNIT * 2, UNIT + 4)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", p["text_primary"])
	t.set_color("font_placeholder_color", "LineEdit", p["text_muted"])
	t.set_color("caret_color", "LineEdit", p["accent"])
	t.set_color("selection_color", "LineEdit", Color(p["accent"], 0.35))
	t.set_font_size("font_size", "LineEdit", SIZE_BODY)
	t.set_type_variation("InvoAmountField", "LineEdit")
	var bare: StyleBoxEmpty = StyleBoxEmpty.new()
	t.set_stylebox("normal", "InvoAmountField", bare)
	t.set_stylebox("focus", "InvoAmountField", bare)
	t.set_font("font", "InvoAmountField", _bold)
	t.set_font_size("font_size", "InvoAmountField", SIZE_DISPLAY)

	var grabber: StyleBoxFlat = box(p["border"], 4, Color.TRANSPARENT, 0, 0)
	t.set_stylebox("scroll", "VScrollBar", box(Color.TRANSPARENT, 4, Color.TRANSPARENT, 4, 0))
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_constant("separation", "VBoxContainer", UNIT)
	t.set_constant("separation", "HBoxContainer", UNIT)
	t.set_constant("h_separation", "GridContainer", UNIT)
	t.set_constant("v_separation", "GridContainer", UNIT)
	return t


static func _label(t: Theme, type_name: String, f: Font, size: int, color: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, f)
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, color)


static func _panel(t: Theme, type_name: String, style: StyleBox) -> void:
	t.set_type_variation(type_name, "PanelContainer")
	t.set_stylebox("panel", type_name, style)


static func _button(t: Theme, type_name: String, normal: Color, hover: Color, pressed: Color,
		text: Color, radius: int, border: Color, pad_x: int, pad_y: int, f: Font) -> void:
	t.set_type_variation(type_name, "Button")
	t.set_stylebox("normal", type_name, box(normal, radius, border, pad_x, pad_y))
	t.set_stylebox("hover", type_name, box(hover, radius, border, pad_x, pad_y))
	t.set_stylebox("pressed", type_name, box(pressed, radius, border, pad_x, pad_y))
	t.set_stylebox("disabled", type_name, box(Color(normal, normal.a * 0.5), radius, border, pad_x, pad_y))
	t.set_stylebox("focus", type_name, box(Color.TRANSPARENT, radius, Color(text, 0.6), pad_x, pad_y))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		t.set_color(c, type_name, text)
	t.set_color("font_disabled_color", type_name, Color(text, 0.5))
	t.set_font("font", type_name, f)
	t.set_font_size("font_size", type_name, SIZE_BODY)

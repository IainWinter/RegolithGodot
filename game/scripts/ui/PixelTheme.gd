extends RefCounted
class_name PixelTheme

# the game's ui look, built in code so every in game panel shares it. hard
# edges, no anti aliasing, no rounded corners, thick borders, crisp font at
# integer sizes. controls that draw grabbers or arrows get tiny generated
# textures so nothing smooth leaks in from the default theme

const INK := Color8(16, 14, 20)
const PAPER := Color8(38, 36, 46)
const PAPER_RAISED := Color8(54, 52, 64)
const PAPER_HOVER := Color8(72, 70, 84)
const PAPER_SUNKEN := Color8(26, 25, 32)
const LINE := Color8(96, 92, 112)
const LINE_DIM := Color8(58, 56, 70)
const TEXT := Color8(226, 222, 212)
const TEXT_DIM := Color8(140, 136, 150)
const ACCENT := Color8(255, 196, 64)
const ACCENT_TEXT := Color8(28, 22, 12)
const SELECT := Color8(96, 168, 255)
const DANGER := Color8(226, 84, 84)

const FONT_SIZE := 12
const SMALL_FONT_SIZE := 10
const TITLE_FONT_SIZE := 16
const BORDER := 2
const PAD := 4

static var cached: Theme
static var cached_font: Font

static func font() -> Font:
	if cached_font:
		return cached_font

	var base := ThemeDB.fallback_font
	if base is FontFile:
		var file: FontFile = base.duplicate()
		file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		file.hinting = TextServer.HINTING_NORMAL
		file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		file.multichannel_signed_distance_field = false
		file.generate_mipmaps = false
		file.oversampling = 1.0
		cached_font = file
	else:
		cached_font = base

	return cached_font

static func theme() -> Theme:
	if cached:
		return cached

	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_SIZE

	# panels

	t.set_stylebox("panel", "PanelContainer", box(PAPER, LINE))
	t.set_stylebox("panel", "Panel", box(PAPER, LINE))
	t.set_stylebox("panel", "PopupPanel", box(PAPER, LINE))
	t.set_stylebox("panel", "PopupMenu", box(PAPER, LINE))
	t.set_stylebox("panel", "AcceptDialog", box(PAPER, LINE))
	t.set_stylebox("embedded_border", "Window", box(PAPER, LINE, BORDER, 24, BORDER, BORDER))
	t.set_stylebox("embedded_unfocused_border", "Window", box(PAPER, LINE_DIM, BORDER, 24, BORDER, BORDER))
	t.set_color("title_color", "Window", TEXT)
	t.set_font("title_font", "Window", font())
	t.set_font_size("title_font_size", "Window", FONT_SIZE)
	t.set_stylebox("panel", "ScrollContainer", empty())
	t.set_constant("separation", "HBoxContainer", PAD)
	t.set_constant("separation", "VBoxContainer", PAD)
	t.set_constant("h_separation", "GridContainer", PAD)
	t.set_constant("v_separation", "GridContainer", PAD)
	t.set_stylebox("separator", "HSeparator", line_box(LINE_DIM, true))
	t.set_stylebox("separator", "VSeparator", line_box(LINE_DIM, false))
	t.set_constant("separation", "HSeparator", 6)
	t.set_constant("separation", "VSeparator", 6)

	# text

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", FONT_SIZE)
	t.set_constant("line_spacing", "Label", 2)

	# buttons

	for kind in ["Button", "CheckBox", "OptionButton", "MenuButton", "ColorPickerButton"]:
		t.set_stylebox("normal", kind, box(PAPER_RAISED, LINE, BORDER, BORDER, BORDER, BORDER, 8, 3))
		t.set_stylebox("hover", kind, box(PAPER_HOVER, TEXT_DIM, BORDER, BORDER, BORDER, BORDER, 8, 3))
		t.set_stylebox("pressed", kind, box(ACCENT, ACCENT, BORDER, BORDER, BORDER, BORDER, 8, 3))
		t.set_stylebox("hover_pressed", kind, box(ACCENT.lightened(0.15), ACCENT, BORDER, BORDER, BORDER, BORDER, 8, 3))
		t.set_stylebox("disabled", kind, box(PAPER, LINE_DIM, BORDER, BORDER, BORDER, BORDER, 8, 3))
		t.set_stylebox("focus", kind, empty())
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, ACCENT_TEXT)
		t.set_color("font_hover_pressed_color", kind, ACCENT_TEXT)
		t.set_color("font_disabled_color", kind, TEXT_DIM)
		t.set_color("font_focus_color", kind, TEXT)
		t.set_color("icon_normal_color", kind, TEXT)
		t.set_color("icon_pressed_color", kind, ACCENT_TEXT)
		t.set_color("icon_hover_pressed_color", kind, ACCENT_TEXT)
		t.set_font_size("font_size", kind, FONT_SIZE)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0, 0, 2, 2))
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	t.set_icon("checked", "CheckBox", check_icon(true))
	t.set_icon("unchecked", "CheckBox", check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", check_icon(false))
	t.set_constant("h_separation", "CheckBox", 6)

	# line edits and spin boxes

	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", kind, box(PAPER_SUNKEN, LINE_DIM, BORDER, BORDER, BORDER, BORDER, 6, 3))
		t.set_stylebox("focus", kind, box(PAPER_SUNKEN, ACCENT, BORDER, BORDER, BORDER, BORDER, 6, 3))
		t.set_stylebox("read_only", kind, box(PAPER, LINE_DIM, BORDER, BORDER, BORDER, BORDER, 6, 3))
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_placeholder_color", kind, TEXT_DIM)
		t.set_color("caret_color", kind, ACCENT)
		t.set_color("selection_color", kind, Color(SELECT, 0.4))
		t.set_font_size("font_size", kind, FONT_SIZE)

	t.set_icon("updown", "SpinBox", updown_icon())
	for part in ["up_background", "down_background", "up_background_hovered", "down_background_hovered", "up_background_pressed", "down_background_pressed", "up_background_disabled", "down_background_disabled", "field_and_buttons_separator", "up_down_buttons_separator"]:
		t.set_stylebox(part, "SpinBox", empty())

	# sliders

	for kind in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", kind, box(PAPER_SUNKEN, LINE_DIM, BORDER, BORDER, BORDER, BORDER, 0, 0))
		t.set_stylebox("grabber_area", kind, box(ACCENT, ACCENT, 0, 0, 0, 0, 0, 0))
		t.set_stylebox("grabber_area_highlight", kind, box(ACCENT.lightened(0.15), ACCENT, 0, 0, 0, 0, 0, 0))
		t.set_icon("grabber", kind, grabber_icon(TEXT))
		t.set_icon("grabber_highlight", kind, grabber_icon(Color.WHITE))
		t.set_icon("grabber_disabled", kind, grabber_icon(TEXT_DIM))
		t.set_constant("center_grabber", kind, 0)
		t.set_constant("grabber_offset", kind, 0)

	# scroll bars

	for kind in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", kind, box(PAPER_SUNKEN, Color.TRANSPARENT, 0, 0, 0, 0, 2, 2))
		t.set_stylebox("scroll_focus", kind, box(PAPER_SUNKEN, Color.TRANSPARENT, 0, 0, 0, 0, 2, 2))
		t.set_stylebox("grabber", kind, box(LINE, LINE, 0, 0, 0, 0, 2, 2))
		t.set_stylebox("grabber_highlight", kind, box(TEXT_DIM, TEXT_DIM, 0, 0, 0, 0, 2, 2))
		t.set_stylebox("grabber_pressed", kind, box(ACCENT, ACCENT, 0, 0, 0, 0, 2, 2))
		for part in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
			t.set_icon(part, kind, blank_icon())

	# tooltips and popups

	t.set_stylebox("panel", "TooltipPanel", box(INK, LINE, BORDER, BORDER, BORDER, BORDER, 6, 3))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", SMALL_FONT_SIZE)
	t.set_stylebox("hover", "PopupMenu", box(PAPER_HOVER, Color.TRANSPARENT, 0, 0, 0, 0, 6, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	# file dialog lists

	t.set_stylebox("panel", "Tree", box(PAPER_SUNKEN, LINE_DIM))
	t.set_stylebox("focus", "Tree", empty())
	t.set_stylebox("selected", "Tree", box(Color(SELECT, 0.35), Color.TRANSPARENT, 0, 0, 0, 0, 0, 0))
	t.set_stylebox("selected_focus", "Tree", box(Color(SELECT, 0.35), Color.TRANSPARENT, 0, 0, 0, 0, 0, 0))
	t.set_stylebox("cursor", "Tree", empty())
	t.set_stylebox("cursor_unfocused", "Tree", empty())
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_stylebox("panel", "ItemList", box(PAPER_SUNKEN, LINE_DIM))
	t.set_stylebox("focus", "ItemList", empty())
	t.set_color("font_color", "ItemList", TEXT)

	cached = t
	return t

# styles

static func box(fill: Color, border: Color, left := BORDER, top := BORDER, right := BORDER, bottom := BORDER, pad_x := PAD, pad_y := PAD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.border_width_left = left
	s.border_width_top = top
	s.border_width_right = right
	s.border_width_bottom = bottom
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.content_margin_left = left + pad_x
	s.content_margin_right = right + pad_x
	s.content_margin_top = top + pad_y
	s.content_margin_bottom = bottom + pad_y
	return s

static func line_box(color: Color, horizontal: bool) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = color
	s.thickness = BORDER
	s.vertical = not horizontal
	return s

static func empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

# icons, tiny generated textures so no smooth default art shows

static func pixel_icon(w: int, h: int, paint: Callable) -> ImageTexture:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	paint.call(image)
	return ImageTexture.create_from_image(image)

static func blank_icon() -> ImageTexture:
	return pixel_icon(1, 1, func(_image: Image): pass)

static func grabber_icon(color: Color) -> ImageTexture:
	return pixel_icon(10, 14, func(image: Image):
		image.fill_rect(Rect2i(0, 0, 10, 14), INK)
		image.fill_rect(Rect2i(2, 2, 6, 10), color))

static func check_icon(on: bool) -> ImageTexture:
	return pixel_icon(14, 14, func(image: Image):
		image.fill_rect(Rect2i(0, 0, 14, 14), LINE)
		image.fill_rect(Rect2i(2, 2, 10, 10), PAPER_SUNKEN)
		if on:
			image.fill_rect(Rect2i(4, 4, 6, 6), ACCENT))

static func updown_icon() -> ImageTexture:
	return pixel_icon(10, 14, func(image: Image):
		for i in 3:
			image.fill_rect(Rect2i(4 - i, 1 + i, 2 + i * 2, 1), TEXT)
			image.fill_rect(Rect2i(4 - i, 12 - i, 2 + i * 2, 1), TEXT))

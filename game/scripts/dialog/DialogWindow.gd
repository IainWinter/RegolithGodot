extends CanvasLayer
class_name DialogWindow

# the speech box of the Dialog autoload: a PixelTheme frame anchored bottom
# center over the game with the speaker's icon in a framed square at the
# left, the name in the character's color, and the line under it revealed
# by the typewriter (visible_characters). sits on layer 15, under the pause
# and death menus at 20, and ignores the mouse everywhere so it never steals
# a click from the game. the Dialog autoload drives it: show_line, then
# set_revealed as the typewriter runs, and shown 0..1 for the slide in and
# out (the frame fades and rises SLIDE pixels). the width is WIDTH or the
# viewport minus the margins when narrower, so it fits the editor's taller
# window too. scene: res://game/scenes/dialog/DialogWindow.tscn

const LAYER := 15
const WIDTH := 560
const MARGIN := 24
const SLIDE := 16
const ICON := 32
const ICON_PAD := 4

@onready var root: Control = $Root
@onready var frame: PanelContainer = $Root/Frame
@onready var icon_frame: PanelContainer = $Root/Frame/Row/IconFrame
@onready var icon: TextureRect = $Root/Frame/Row/IconFrame/Icon
@onready var name_label: Label = $Root/Frame/Row/Column/Name
@onready var text_label: Label = $Root/Frame/Row/Column/Text

var character: Character
var text := ""

# 0 hidden, 1 fully on screen
var shown := 0.0:
	set(value):
		shown = clampf(value, 0.0, 1.0)
		apply_shown()

func _ready() -> void:
	layer = LAYER
	root.theme = PixelTheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for control in [frame, icon_frame, icon, name_label, text_label]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	frame.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 10, 8))
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	name_label.add_theme_font_size_override("font_size", PixelTheme.FONT_SIZE)
	name_label.uppercase = true
	text_label.add_theme_font_size_override("font_size", PixelTheme.FONT_SIZE)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.visible_characters_behavior = TextServer.VC_CHARS_BEFORE_SHAPING
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if not root.resized.is_connected(apply_shown):
		root.resized.connect(apply_shown)

	apply_shown()

func show_line(speaker: Character, line: String) -> void:
	character = speaker
	text = line
	name_label.text = speaker.display_name if speaker.display_name != "" else String(speaker.id)
	name_label.add_theme_color_override("font_color", speaker.color)
	icon.texture = speaker.icon
	icon_frame.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER_SUNKEN, speaker.color, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, ICON_PAD, ICON_PAD))
	text_label.text = line
	set_revealed(0)

# how many characters of the line are on screen
func set_revealed(count: int) -> void:
	text_label.visible_characters = clampi(count, 0, text.length())

func revealed() -> int:
	return text_label.visible_characters

func is_fully_revealed() -> bool:
	return text_label.visible_characters < 0 or text_label.visible_characters >= text.length()

# the frame's place and alpha from shown, and the width from the viewport
func apply_shown() -> void:
	if frame == null:
		return

	var width := WIDTH

	if root.is_inside_tree():
		width = mini(WIDTH, int(root.size.x) - MARGIN * 2)

	frame.custom_minimum_size.x = width
	frame.offset_left = -width / 2.0
	frame.offset_right = width / 2.0
	frame.offset_bottom = -MARGIN + (1.0 - shown) * SLIDE
	frame.offset_top = frame.offset_bottom
	frame.modulate.a = shown
	visible = shown > 0.0

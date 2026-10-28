# res://scenes/menus/pause_menu.gd
# Press Esc in the game to pause. Shows CONTINUE (button_play.png) and
# QUIT (button_quit.png, goes back to the main menu).
extends CanvasLayer

const MAIN_MENU_SCENE_PATH: String = "res://scenes/menus/main_menu.tscn"
const IMAGE_FOLDER: String = "res://assets/images/"
const PLAY_IMAGE: String = "button_play.png"
const QUIT_IMAGE: String = "button_quit.png"
const BUTTON_SIZE: Vector2 = Vector2(320, 100)

var root_control: Control


func _ready() -> void:
	# Keep running while the game is paused, otherwise the menu would freeze too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_build_ui()
	root_control.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if root_control.visible:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


func pause_game() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root_control.show()


func resume_game() -> void:
	get_tree().paused = false
	root_control.hide()


func quit_to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if not ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
		push_error("Main menu scene not found: " + MAIN_MENU_SCENE_PATH)
		return

	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "PauseRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Dark overlay behind the buttons (also blocks clicks on the game).
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)

	var continue_button := _make_button("CONTINUE", PLAY_IMAGE)
	continue_button.pressed.connect(resume_game)
	box.add_child(continue_button)

	var quit_button := _make_button("QUIT", QUIT_IMAGE)
	quit_button.pressed.connect(quit_to_main_menu)
	box.add_child(quit_button)


# Image button, or a plain text button if the image is missing.
func _make_button(fallback_text: String, image_filename: String) -> BaseButton:
	var image_path: String = IMAGE_FOLDER + image_filename
	var button: BaseButton

	if ResourceLoader.exists(image_path):
		var image_button := TextureButton.new()
		var texture := load(image_path) as Texture2D
		image_button.texture_normal = texture
		image_button.texture_hover = texture
		image_button.texture_pressed = texture
		image_button.ignore_texture_size = true
		image_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button = image_button
	else:
		var text_button := Button.new()
		text_button.text = fallback_text
		text_button.add_theme_font_size_override("font_size", 24)
		button = text_button
		push_warning("Missing button image: " + image_path)

	button.custom_minimum_size = BUTTON_SIZE
	button.pivot_offset = BUTTON_SIZE / 2.0
	button.mouse_entered.connect(_hover.bind(button, true))
	button.mouse_exited.connect(_hover.bind(button, false))
	return button


func _hover(button: Control, hovering: bool) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(1.05, 1.05) if hovering else Vector2.ONE, 0.15)


extends Node

signal level_won(final_score: int)
signal level_lost

const LEVEL_TIME: float = 100.0
const STARTING_SCORE: int = 100

const MAIN_MENU_SCENE: String = "res://scenes/menus/main_menu.tscn"
const NEXT_LEVEL_SCENE: String = "res://scenes/maps/map_two.tscn"

var time_left: float = LEVEL_TIME
var score: int = STARTING_SCORE
var level_finished: bool = false

var timer_label: Label
var score_label: Label
var result_message_label: Label


func _ready() -> void:
	# Keep the result screen working when the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_create_hud()

	var finish_trigger := get_parent().get_node_or_null("FinishTrigger")

	if finish_trigger:
		finish_trigger.body_entered.connect(
			_on_finish_trigger_body_entered
		)
	else:
		push_warning("FinishTrigger was not found under MapOne.")


func _process(delta: float) -> void:
	if level_finished:
		return

	time_left = maxf(time_left - delta, 0.0)
	score = ceili(time_left)

	_update_hud()

	if time_left <= 0.0:
		level_finished = true
		level_lost.emit()
		_show_result("TIME'S UP!", "You ran out of time!")


func _on_finish_trigger_body_entered(body: Node3D) -> void:
	if level_finished:
		return

	# The trolley controller creates a CharacterBody3D.
	if body is CharacterBody3D:
		complete_level()


func complete_level() -> void:
	if level_finished:
		return

	level_finished = true
	score = ceili(time_left)

	level_won.emit(score)
	_show_result(
		"LEVEL COMPLETE!",
		"Final score: %d / 100" % score
	)


func _create_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "LevelHUD"
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	hud.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 24)
	layout.add_child(timer_label)

	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 24)
	layout.add_child(score_label)

	_update_hud()


func _update_hud() -> void:
	if is_instance_valid(timer_label):
		timer_label.text = "Time: %d" % ceili(time_left)

	if is_instance_valid(score_label):
		score_label.text = "Score: %d / 100" % score


func _show_result(title_text: String, message_text: String) -> void:
	# Stop trolley movement, physics and the rest of the game.
	get_tree().paused = true

	var hud := get_node_or_null("LevelHUD")
	if hud == null:
		return

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-180, -100)
	panel.custom_minimum_size = Vector2(360, 200)
	hud.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	layout.add_child(title)

	result_message_label = Label.new()
	result_message_label.text = message_text
	result_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(result_message_label)

	var restart_button := Button.new()
	restart_button.text = "Restart Level"
	restart_button.pressed.connect(restart_level)
	layout.add_child(restart_button)

	if title_text == "LEVEL COMPLETE!":
		var next_button := Button.new()
		next_button.text = "Next Level"
		next_button.pressed.connect(next_level)
		layout.add_child(next_button)

	var menu_button := Button.new()
	menu_button.text = "Return to Main Menu"
	menu_button.pressed.connect(return_to_main_menu)
	layout.add_child(menu_button)


func restart_level() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func return_to_main_menu() -> void:
	get_tree().paused = false

	if ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		push_error("Main menu scene not found: " + MAIN_MENU_SCENE)


func next_level() -> void:
	if ResourceLoader.exists(NEXT_LEVEL_SCENE):
		get_tree().paused = false
		get_tree().change_scene_to_file(NEXT_LEVEL_SCENE)
	else:
		# Leave the game paused if the next map hasn't been created yet.
		if is_instance_valid(result_message_label):
			result_message_label.text = (
				"Next level isn't set up yet!\n"
				+ "Expected scene: map_two.tscn"
			)

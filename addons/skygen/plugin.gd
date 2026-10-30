@tool
extends EditorPlugin
# SkyGen editor plugin: adds the generator dock to the right-hand dock slot.

const DockScript := preload("res://addons/skygen/dock.gd")
var _dock: Control


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "SkyGen"
	_dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

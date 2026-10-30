# res://scenes/menus/fly_controller.gd  (kept the old file name; this script now handles DRIVING)
# Lets the player DRIVE the trolley around the map.
#
#   Space ........ one short push forward (press it, then wait 3 seconds to push again)
#   A ............ turn left
#   D ............ turn right
#   Backspace .... put the trolley back at the start
#   Right-click .. HOLD and move the mouse to look around the trolley (camera only)
#
# There are no brakes and no reverse: the trolley slows gradually by coasting,
# rolls down hills by itself, and keeps slowing on flat ground until it reaches 0.
#
# main_menu.gd adds this to the map and gives it the trolley to drive.
# The trolley is put inside a physics body (CharacterBody3D), so it has gravity,
# drives on the base plate and bumps into anything in the map that has collision.
# The model tilts to match the slope of the road under it.
extends Node3D

# A small, drawn speedometer HUD. Speed is displayed in km/h.
class SpeedometerDial:
	extends Control

	var speed_kmh: float = 0.0
	const MAX_SPEED_KMH: float = 250.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(230.0, 190.0)

	func _draw() -> void:
		var dial_centre := Vector2(size.x * 0.5, size.y * 0.53)
		var radius: float = minf(size.x * 0.36, size.y * 0.39)
		var start_angle: float = deg_to_rad(135.0)
		var end_angle: float = deg_to_rad(405.0)
		var font: Font = ThemeDB.fallback_font

		# Dark translucent panel behind the dial.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.045, 0.06, 0.88), true)
		draw_arc(dial_centre, radius, start_angle, end_angle, 72, Color(0.28, 0.31, 0.35), 7.0, true)

		# Tick marks and labels from 0 to 250 km/h.
		for tick in range(26):
			var ratio: float = float(tick) / 25.0
			var angle: float = lerpf(start_angle, end_angle, ratio)
			var outer_point: Vector2 = dial_centre + Vector2(cos(angle), sin(angle)) * (radius + 1.0)
			var inner_length: float = 10.0 if tick % 5 == 0 else 5.0
			var inner_point: Vector2 = dial_centre + Vector2(cos(angle), sin(angle)) * (radius - inner_length)
			draw_line(inner_point, outer_point, Color(1.0, 0.48, 0.05), 2.0 if tick % 5 == 0 else 1.0, true)
			if tick % 5 == 0:
				var label_point: Vector2 = dial_centre + Vector2(cos(angle), sin(angle)) * (radius - 24.0)
				draw_string(font, label_point + Vector2(-12.0, 4.0), str(tick * 10), HORIZONTAL_ALIGNMENT_CENTER, 26.0, 10, Color.WHITE)

		# Needle follows the current speed, capped at the dial's maximum.
		var speed_ratio: float = clampf(speed_kmh / MAX_SPEED_KMH, 0.0, 1.0)
		var needle_angle: float = lerpf(start_angle, end_angle, speed_ratio)
		var needle_tip: Vector2 = dial_centre + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 20.0)
		draw_line(dial_centre, needle_tip, Color(1.0, 0.32, 0.08), 3.0, true)
		draw_circle(dial_centre, 5.0, Color(1.0, 0.48, 0.05))

		var speed_text: String = str(roundi(speed_kmh))
		draw_string(font, Vector2(dial_centre.x - 38.0, dial_centre.y + 38.0), speed_text, HORIZONTAL_ALIGNMENT_CENTER, 76.0, 23, Color.WHITE)
		draw_string(font, Vector2(dial_centre.x - 24.0, size.y - 7.0), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11, Color(0.75, 0.78, 0.82))

# The Node3D to drive. Set by main_menu.gd before this node enters the tree.
var trolley: Node3D

# ---- Tweak these to taste -------------------------------------------------
const PUSH_KEY: Key = KEY_SPACE
# How much speed one push adds. Small = a short push.
const PUSH_SPEED_BOOST: float = 7.0
# Seconds you must wait after a push before you can push again.
const PUSH_COOLDOWN: float = 3.0

# How quickly the trolley loses speed on flat ground after a push or hill.
# Lower values mean it coasts for longer. 1.5 gives a gradual, noticeable roll-down.
const COAST_DRAG: float = 1.5

# ---- Hills ----
# How hard gravity pulls the trolley down a hill. Higher = rolls away faster.
const SLOPE_ACCEL: float = 32.0
# How steep a road is before it counts as "fully steep" (0.5 is about 30 degrees).
const STEEP_FULL_SLOPE: float = 0.5
# On a fully steep downhill the brakes and drag are only this strong
# (0.12 = 12% as strong as on flat road). Lower = harder to slow down.
const STEEP_BRAKE_MIN: float = 0.12
# Roads flatter than this don't make the trolley roll.
const MIN_SLOPE_TO_ROLL: float = 0.05
# The fastest the trolley can go when running downhill.
const MAX_DOWNHILL_SPEED: float = 70.0

# How fast the trolley turns (radians per second at full speed).
const TURN_RATE: float = 1.9
# Below this speed the trolley turns less, so it can't spin on the spot.
const FULL_TURN_SPEED: float = 5.0

const GRAVITY: float = 30.0

# How quickly the trolley tilts to match the road. Higher = snappier.
# Set to 0 to turn tilting off.
const TILT_SPEED: float = 8.0

const CAMERA_DISTANCE: float = 9.0
const CAMERA_HEIGHT: float = 4.0
const CAMERA_LOOK_HEIGHT: float = 1.5
const CAMERA_FOLLOW_SPEED: float = 6.0

# Right-click look around.
const LOOK_SENSITIVITY: float = 0.004
const LOOK_PITCH_MIN: float = -0.45 # lowest the camera can go (radians)
const LOOK_PITCH_MAX: float = 1.1   # highest the camera can go (radians)
# How quickly the camera swings back behind the trolley after you let go.
const LOOK_RECENTRE_SPEED: float = 5.0

const COLLISION_MASK: int = 0xFFFFFFFF

# Used only if the model has no meshes to measure.
const FALLBACK_BOX_SIZE: Vector3 = Vector3(2.0, 1.5, 3.0)

# If your trolley model drives sideways or backwards, change this to
# 90, -90 or 180 so the model faces the way you are driving.
const MODEL_FORWARD_OFFSET_DEGREES: float = 90.0

const RESET_KEY: Key = KEY_BACKSPACE

# If the trolley falls below this height it is put back at the start.
const FALL_RESET_HEIGHT: float = -60.0
# ---------------------------------------------------------------------------

var body: CharacterBody3D
var tilt_pivot: Node3D
var shape_node: CollisionShape3D

var camera: Camera3D
var previous_camera: Camera3D
var hint_label: Label
var speedometer: SpeedometerDial

var model_offset_degrees: float = MODEL_FORWARD_OFFSET_DEGREES
var box_centre: Vector3 = Vector3.ZERO
var box_size: Vector3 = Vector3.ONE

var heading: float = 0.0
var camera_heading: float = 0.0
var start_position: Vector3 = Vector3.ZERO
var start_heading: float = 0.0

# The (smoothed) direction the road surface is facing, used for tilting.
var tilt_normal: Vector3 = Vector3.UP

# Right-click look around. These are offsets from the normal "behind" view.
var looking: bool = false
var look_yaw: float = 0.0
var look_pitch: float = 0.0

# False until the map's collision has been registered and the trolley has
# been set down on the ground.
var driving_ready: bool = false

# Pushing and cooldown.
var push_requested: bool = false
var push_cooldown: float = 0.0


func _ready() -> void:
	name = "DriveController"

	# Keep running while paused so the mouse can be freed when the pause menu
	# opens. Driving itself stops while paused (see _physics_process).
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not is_instance_valid(trolley):
		push_warning("DriveController has no trolley to drive.")
		return

	_build_hud()
	_build_body()

	camera = Camera3D.new()
	camera.name = "DriveCamera"
	camera.far = 4000.0
	add_child(camera)

	previous_camera = get_viewport().get_camera_3d()
	camera.make_current()
	_update_camera(1.0, true)

	# Wait two physics frames so the map's collision exists before we look
	# for the ground.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_place_on_ground()
	driving_ready = true


func _exit_tree() -> void:
	# Never leave the mouse captured if the map is removed.
	if looking:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if is_instance_valid(previous_camera) and previous_camera.is_inside_tree():
		previous_camera.make_current()


# ------------------------------------------------------------
# SET UP
# ------------------------------------------------------------

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "DriveHud"
	hud.layer = 5
	add_child(hud)

	hint_label = Label.new()
	hint_label.position = Vector2(20, 20)
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color.WHITE)
	hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hint_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(hint_label)

	# Keep the speedometer fixed in the top-right corner of the game view.
	speedometer = SpeedometerDial.new()
	speedometer.name = "Speedometer"
	speedometer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	speedometer.offset_left = -250.0
	speedometer.offset_right = -20.0
	speedometer.offset_top = 20.0
	speedometer.offset_bottom = 210.0
	hud.add_child(speedometer)

	_update_hint()


# Wraps the trolley in a CharacterBody3D with a box sized from its model.
# Structure:  TrolleyBody (drives, turns left/right)
#               +-- TiltPivot (tilts to match the road)
#               |     +-- the trolley model
#               +-- TrolleyCollisionShape
func _build_body() -> void:
	# Measure the model, in a frame that has the trolley's position and
	# turn removed (but keeps its scale).
	var frame := Transform3D(
		Basis(trolley.global_basis.get_rotation_quaternion()),
		trolley.global_position
	)
	var inverse_frame: Transform3D = frame.affine_inverse()

	var bounds := AABB()
	var found_mesh := false

	for mesh_node in trolley.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue

		var local_bounds: AABB = (
			inverse_frame * mesh_instance.global_transform
		) * mesh_instance.mesh.get_aabb()

		if found_mesh:
			bounds = bounds.merge(local_bounds)
		else:
			bounds = local_bounds
			found_mesh = true

	if found_mesh:
		box_size = bounds.size.max(Vector3(0.1, 0.1, 0.1))
		box_centre = bounds.get_center()
	else:
		box_size = FALLBACK_BOX_SIZE
		box_centre = Vector3(0.0, FALLBACK_BOX_SIZE.y / 2.0, 0.0)
		push_warning("Trolley has no meshes to measure, using a default collision box.")

	heading = trolley.global_rotation.y
	camera_heading = heading
	start_heading = heading

	var parent: Node = trolley.get_parent()
	var start_transform: Transform3D = trolley.global_transform
	start_position = start_transform.origin

	body = CharacterBody3D.new()
	body.name = "TrolleyBody"
	body.collision_mask = COLLISION_MASK
	body.floor_snap_length = 0.5
	body.floor_max_angle = deg_to_rad(50.0)
	body.safe_margin = 0.01

	parent.add_child(body)
	body.global_position = start_position
	body.rotation.y = heading

	# The pivot the model sits on, so the model can tilt on its own.
	tilt_pivot = Node3D.new()
	tilt_pivot.name = "TiltPivot"
	body.add_child(tilt_pivot)

	# Move the trolley model inside the pivot.
	parent.remove_child(trolley)
	tilt_pivot.add_child(trolley)
	trolley.position = Vector3.ZERO

	shape_node = CollisionShape3D.new()
	shape_node.name = "TrolleyCollisionShape"
	var box := BoxShape3D.new()
	box.size = box_size
	shape_node.shape = box
	body.add_child(shape_node)

	_apply_model_offset()


# Turns the model (and its collision box) by the current model offset.
func _apply_model_offset() -> void:
	var offset_basis := Basis(Vector3.UP, deg_to_rad(model_offset_degrees))

	trolley.rotation = Vector3(0.0, deg_to_rad(model_offset_degrees), 0.0)
	shape_node.transform = Transform3D(offset_basis, offset_basis * box_centre)


# Drops the trolley onto whatever is below the start position.
func _place_on_ground() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		start_position + Vector3.UP * 200.0,
		start_position + Vector3.DOWN * 400.0
	)
	query.collision_mask = COLLISION_MASK
	query.exclude = [body.get_rid()]

	var hit: Dictionary = space.intersect_ray(query)

	# Lift so the bottom of the box sits just above the ground.
	var box_bottom: float = box_centre.y - box_size.y / 2.0
	var lift: float = -box_bottom + 0.15

	if hit.is_empty():
		push_warning(
			"No ground found under the trolley. Check the base plate has collision "
			+ "(see BASE_PLATE_NAMES in main_menu.gd)."
		)
		body.global_position = start_position + Vector3.UP * 1.0
	else:
		var hit_position: Vector3 = hit["position"]
		body.global_position = hit_position + Vector3.UP * lift

	body.velocity = Vector3.ZERO


# ------------------------------------------------------------
# INPUT
# ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return

	# Right-click: hold to look around, let go to snap back behind the trolley.
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_RIGHT:
			_set_looking(button_event.pressed)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if looking and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			var sensitivity: float = _get_look_sensitivity()
			look_yaw = wrapf(look_yaw - motion.relative.x * sensitivity, -PI, PI)
			look_pitch = clampf(
				look_pitch + motion.relative.y * sensitivity,
				LOOK_PITCH_MIN,
				LOOK_PITCH_MAX
			)
		return

	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == PUSH_KEY:
		# Handled in the next physics step (only if the cooldown is over).
		push_requested = true
		get_viewport().set_input_as_handled()

	elif key_event.keycode == RESET_KEY:
		_reset_to_start()
		get_viewport().set_input_as_handled()


func _set_looking(value: bool) -> void:
	if value == looking:
		return

	looking = value

	if looking:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _reset_to_start() -> void:
	if not is_instance_valid(body):
		return

	heading = start_heading
	camera_heading = start_heading
	look_yaw = 0.0
	look_pitch = 0.0
	push_cooldown = 0.0
	push_requested = false
	tilt_normal = Vector3.UP
	body.rotation.y = heading
	body.global_position = start_position
	body.velocity = Vector3.ZERO

	if is_instance_valid(tilt_pivot):
		tilt_pivot.basis = Basis.IDENTITY

	_place_on_ground()


# ------------------------------------------------------------
# DRIVING
# ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	if not driving_ready or not is_instance_valid(body):
		return

	# Fell off the map: back to the start.
	if body.global_position.y < FALL_RESET_HEIGHT:
		_reset_to_start()
		return

	var steer: float = 0.0
	if Input.is_physical_key_pressed(KEY_A):
		steer += 1.0
	if Input.is_physical_key_pressed(KEY_D):
		steer -= 1.0

	# Current speed along the way the trolley is facing (negative = reversing).
	var forward: Vector3 = -body.global_transform.basis.z
	var speed: float = body.velocity.dot(forward)

	# Hills: work out how steep the road is, and which way is downhill.
	var slope_push: float = 0.0
	var brake_factor: float = 1.0

	if body.is_on_floor():
		var floor_normal: Vector3 = body.get_floor_normal()
		# Straight down, flattened onto the road. Its length is the steepness
		# (0 on flat road, bigger the steeper the road gets).
		var downhill: Vector3 = Vector3.DOWN - floor_normal * Vector3.DOWN.dot(floor_normal)
		var steepness: float = downhill.length()

		if steepness > MIN_SLOPE_TO_ROLL:
			# Gravity pulls the trolley down the hill, whichever way it faces.
			slope_push = downhill.dot(forward) * SLOPE_ACCEL

			# Going down a hill: the steeper it is, the weaker the brakes and
			# the drag get, so it is harder to slow down.
			if downhill.dot(body.velocity) > 0.0:
				var steep_amount: float = clampf(steepness / STEEP_FULL_SLOPE, 0.0, 1.0)
				brake_factor = lerpf(1.0, STEEP_BRAKE_MIN, steep_amount)

	# Push cooldown counts down.
	push_cooldown = maxf(0.0, push_cooldown - delta)

	# Space was pressed: one short push, then the cooldown starts.
	if push_requested:
		push_requested = false
		if push_cooldown <= 0.0 and body.is_on_floor():
			speed = maxf(speed, 0.0) + PUSH_SPEED_BOOST
			push_cooldown = PUSH_COOLDOWN

	# On flat ground (or going uphill), gradually lose speed. A downhill
	# supplies fresh acceleration, so reaching another hill builds speed again.
	# There is no timed momentum cut-off: coasting continues smoothly towards 0.
	if slope_push <= 0.0:
		speed = move_toward(speed, 0.0, COAST_DRAG * brake_factor * delta)

	# Gravity on the hill speeds the trolley up all by itself, more and more
	# the steeper the road is.
	speed = clampf(
		speed + slope_push * delta,
		-MAX_DOWNHILL_SPEED,
		MAX_DOWNHILL_SPEED
	)

	# Steering. Turning gets stronger with speed, and flips when reversing.
	var turn_factor: float = clampf(speed / FULL_TURN_SPEED, -1.0, 1.0)
	heading += steer * TURN_RATE * turn_factor * delta
	body.rotation.y = heading

	forward = -body.global_transform.basis.z

	var new_velocity: Vector3 = forward * speed

	if body.is_on_floor():
		new_velocity.y = 0.0
	else:
		new_velocity.y = body.velocity.y - GRAVITY * delta

	body.velocity = new_velocity
	body.move_and_slide()

	_update_hint()
	_update_speedometer()

	_update_tilt(delta)


# Tilts the model so it sits flat on the road, including going up and down
# hills and leaning over sideways slopes.
func _update_tilt(delta: float) -> void:
	if TILT_SPEED <= 0.0 or not is_instance_valid(tilt_pivot):
		return

	var target_normal: Vector3 = Vector3.UP
	if body.is_on_floor():
		target_normal = body.get_floor_normal()

	tilt_normal = tilt_normal.slerp(
		target_normal,
		1.0 - exp(-TILT_SPEED * delta)
	).normalized()

	# Build a basis that faces the way the trolley is heading, but stands on
	# the tilted road instead of on flat ground.
	var facing: Vector3 = -body.global_transform.basis.z
	var right: Vector3 = facing.cross(tilt_normal).normalized()
	var tilted_forward: Vector3 = tilt_normal.cross(right).normalized()
	var world_basis := Basis(right, tilt_normal, -tilted_forward)

	tilt_pivot.basis = body.global_transform.basis.inverse() * world_basis


# ------------------------------------------------------------
# CAMERA
# ------------------------------------------------------------

func _process(delta: float) -> void:
	# The pause menu opened while right-click was held: give the mouse back.
	if get_tree().paused:
		if looking:
			_set_looking(false)
		return

	if not is_instance_valid(body) or not is_instance_valid(camera):
		return

	# After letting go of right-click, swing back behind the trolley.
	if not looking:
		var recentre: float = 1.0 - exp(-LOOK_RECENTRE_SPEED * delta)
		look_yaw = lerp_angle(look_yaw, 0.0, recentre)
		look_pitch = lerpf(look_pitch, 0.0, recentre)

	_update_camera(delta, false)


func _update_camera(delta: float, snap: bool) -> void:
	if snap:
		camera_heading = heading
	else:
		camera_heading = lerp_angle(
			camera_heading,
			heading,
			1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
		)

	var target: Vector3 = body.global_position
	var look_point: Vector3 = target + Vector3.UP * CAMERA_LOOK_HEIGHT

	# Orbit around the trolley: right-click look turns and raises/lowers it.
	var orbit := Basis(Vector3.UP, camera_heading + look_yaw) * Basis(
		Vector3.RIGHT, -look_pitch
	)
	var camera_position: Vector3 = target + orbit * Vector3(
		0.0, CAMERA_HEIGHT, CAMERA_DISTANCE
	)

	# Keep the camera from going through the ground or walls.
	if driving_ready:
		var query := PhysicsRayQueryParameters3D.create(look_point, camera_position)
		query.collision_mask = COLLISION_MASK
		query.exclude = [body.get_rid()]

		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			var towards_target: Vector3 = (look_point - camera_position).normalized()
			camera_position = hit_position + towards_target * 0.3

	camera.global_position = camera_position
	camera.look_at(look_point, Vector3.UP)


func _get_look_sensitivity() -> float:
	# Uses the Mouse Sensitivity slider from Settings (50 = normal speed).
	var setting: float = float(
		get_tree().root.get_meta("mouse_sensitivity", 50.0)
	)
	return LOOK_SENSITIVITY * (setting / 50.0)


func _update_speedometer() -> void:
	if not is_instance_valid(speedometer) or not is_instance_valid(body):
		return

	# Use horizontal movement speed, converted from metres/second to km/h.
	speedometer.speed_kmh = Vector2(body.velocity.x, body.velocity.z).length() * 3.6
	speedometer.queue_redraw()


func _update_hint() -> void:
	if not is_instance_valid(hint_label):
		return

	var push_text: String = "ready"
	if push_cooldown > 0.0:
		push_text = "%.1fs" % push_cooldown

	hint_label.text = (
		"Space: push (" + push_text + ")   A: left   D: right   Backspace: reset   "
		+ "Hold right-click: look around"
	)

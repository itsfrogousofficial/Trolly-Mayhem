@tool
extends VBoxContainer
## SkyGen dock: edit parameters, preview, save PNG (+ PanoramaSkyMaterial) into the project.
## Built in code so the addon has no scene dependencies; it also instantiates headless for verification.

const Core := preload("res://addons/skygen/skygen_core.gd")

var editor_plugin: EditorPlugin = null
var params: Dictionary = Core.default_params()
var _controls := {}
var _preview: TextureRect
var _status: Label
var _preset: OptionButton
var _path_edit: LineEdit
var _material_check: CheckBox
var last_saved_path := ""


func _init() -> void:
	custom_minimum_size = Vector2(240, 0)
	_build_ui()
	_apply_preset(Core.preset_names()[0])


func _build_ui() -> void:
	var title := Label.new()
	title.text = "SkyGen LITE (free)" if Core.LITE else "SkyGen: Procedural Skybox Generator"
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_label("Preset"))
	_preset = OptionButton.new()
	for n in Core.preset_names():
		_preset.add_item(n)
	_preset.item_selected.connect(func(i: int) -> void: _apply_preset(_preset.get_item_text(i)))
	_preset.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_preset)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(box)

	var max_w := Core.LITE_MAX_WIDTH if Core.LITE else Core.FULL_MAX_WIDTH
	_add_spin(box, "width", "Width (px, height = half)", 256, max_w, 256)
	_add_spin(box, "seed", "Seed", 0, 999999, 1)
	_add_section(box, "Sky gradient")
	_add_color(box, "zenith_color", "Zenith")
	_add_color(box, "horizon_color", "Horizon")
	_add_color(box, "ground_color", "Ground")
	_add_slider(box, "gradient_curve", "Gradient curve", 0.2, 2.5, 0.05)
	_add_section(box, "Sun")
	_add_check(box, "sun_enabled", "Sun enabled")
	_add_slider(box, "sun_azimuth_deg", "Azimuth", 0.0, 360.0, 1.0)
	_add_slider(box, "sun_elevation_deg", "Elevation", -10.0, 90.0, 0.5)
	_add_slider(box, "sun_size_deg", "Disc size (deg)", 0.0, 15.0, 0.1)
	_add_color(box, "sun_color", "Sun colour")
	_add_slider(box, "sun_glow_deg", "Glow radius (deg)", 1.0, 90.0, 1.0)
	_add_slider(box, "sun_glow_strength", "Glow strength", 0.0, 2.0, 0.05)
	_add_section(box, "Stars")
	_add_check(box, "stars_enabled", "Stars enabled")
	_add_spin(box, "star_count", "Star count", 0, 20000, 100)
	_add_slider(box, "star_brightness", "Star brightness", 0.0, 2.0, 0.05)
	if not Core.LITE:
		_add_section(box, "Nebula")
		_add_check(box, "nebula_enabled", "Nebula enabled")
		_add_color(box, "nebula_color_a", "Nebula colour A")
		_add_color(box, "nebula_color_b", "Nebula colour B")
		_add_slider(box, "nebula_scale", "Nebula scale", 0.3, 5.0, 0.1)
		_add_slider(box, "nebula_intensity", "Nebula intensity", 0.0, 2.0, 0.05)
		_add_section(box, "Clouds")
		_add_check(box, "clouds_enabled", "Clouds enabled")
		_add_slider(box, "cloud_coverage", "Coverage", 0.0, 1.0, 0.01)
		_add_slider(box, "cloud_softness", "Edge softness", 0.01, 1.0, 0.01)
		_add_slider(box, "cloud_scale", "Cloud scale", 0.5, 8.0, 0.1)
		_add_color(box, "cloud_color", "Cloud colour")
	else:
		var lite := Label.new()
		lite.text = "LITE: width up to 1024, three presets,\nno nebula or cloud layers."
		lite.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		box.add_child(lite)

	var btn_row := HBoxContainer.new()
	add_child(btn_row)
	var prev_btn := Button.new()
	prev_btn.text = "Preview"
	prev_btn.tooltip_text = "Render a 512 px preview with the current settings"
	prev_btn.pressed.connect(render_preview)
	btn_row.add_child(prev_btn)
	var rnd_btn := Button.new()
	rnd_btn.text = "Random seed"
	rnd_btn.pressed.connect(func() -> void:
		_set_param("seed", randi() % 100000)
		render_preview())
	btn_row.add_child(rnd_btn)

	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(224, 112)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)

	var path_row := HBoxContainer.new()
	add_child(path_row)
	path_row.add_child(_label("Save as"))
	_path_edit = LineEdit.new()
	_path_edit.text = "res://skies/skygen_sky.png"
	_path_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	path_row.add_child(_path_edit)
	_material_check = CheckBox.new()
	_material_check.text = "Also create a PanoramaSkyMaterial (.tres)"
	_material_check.button_pressed = true
	add_child(_material_check)
	var save_btn := Button.new()
	save_btn.text = "Generate and save"
	save_btn.pressed.connect(save_full)
	add_child(save_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Pick a preset, press Preview, then Generate and save."
	add_child(_status)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(70, 0)
	return l


func _add_section(parent: Control, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	parent.add_child(l)


func _add_spin(parent: Control, key: String, t: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_label(t))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void: params[key] = int(v))
	row.add_child(s)
	_controls[key] = s


func _add_slider(parent: Control, key: String, t: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_label(t))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v: float) -> void: params[key] = v)
	row.add_child(s)
	_controls[key] = s


func _add_check(parent: Control, key: String, t: String) -> void:
	var c := CheckBox.new()
	c.text = t
	c.toggled.connect(func(on: bool) -> void: params[key] = on)
	parent.add_child(c)
	_controls[key] = c


func _add_color(parent: Control, key: String, t: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_label(t))
	var c := ColorPickerButton.new()
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(60, 0)
	c.size_flags_horizontal = SIZE_EXPAND_FILL
	c.color_changed.connect(func(col: Color) -> void: params[key] = col)
	row.add_child(c)
	_controls[key] = c


func _set_param(key: String, value) -> void:
	params[key] = value
	var c = _controls.get(key)
	if c == null:
		return
	if c is SpinBox or c is HSlider:
		c.set_value_no_signal(float(value))
	elif c is CheckBox:
		c.set_pressed_no_signal(bool(value))
	elif c is ColorPickerButton:
		c.color = value


func _apply_preset(name: String) -> void:
	var p := Core.preset(name)
	for k in p.keys():
		_set_param(k, p[k])
	for i in _preset.item_count:
		if _preset.get_item_text(i) == name:
			_preset.select(i)
	_status.text = "Preset: %s" % name


## Render a small preview into the dock (same seed and layers, 512 px wide).
func render_preview() -> Image:
	var p := params.duplicate()
	p["width"] = 512
	var t0 := Time.get_ticks_msec()
	var img := Core.generate(p)
	_preview.texture = ImageTexture.create_from_image(img)
	_status.text = "Preview %dx%d in %d ms" % [img.get_width(), img.get_height(), Time.get_ticks_msec() - t0]
	return img


## Generate at full size and save PNG (+ material) at the path in the dock.
func save_full() -> String:
	var path := _path_edit.text.strip_edges()
	if not path.ends_with(".png"):
		path += ".png"
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var t0 := Time.get_ticks_msec()
	var img := Core.generate(params)
	var out := Core.save_png_and_material(img, path, _material_check.button_pressed)
	if out == "":
		_status.text = "Save failed; see the Output panel."
		return ""
	last_saved_path = path
	_status.text = "Saved %s (%dx%d, %.1f s)" % [path, img.get_width(), img.get_height(), (Time.get_ticks_msec() - t0) / 1000.0]
	if editor_plugin != null:
		var fs := editor_plugin.get_editor_interface().get_resource_filesystem()
		fs.scan()
		# After the scan the PNG is an imported texture; point the material at it so it is not an embedded copy.
		if _material_check.button_pressed:
			call_deferred("_repoint_material", path)
	return path


func _repoint_material(png_path: String) -> void:
	var mat_path := png_path.get_basename() + "_sky.tres"
	if not ResourceLoader.exists(png_path):
		return
	var tex := load(png_path)
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = tex
	ResourceSaver.save(mat, mat_path)

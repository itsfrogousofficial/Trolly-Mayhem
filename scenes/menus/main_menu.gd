# res://scenes/menus/main_menu.gd  (attach to your existing menu root Control, same as now)
extends Control

# Emitted when the player has successfully logged in or signed up.
signal auth_succeeded

const BACKGROUND_PATH: String = "res://assets/images/background1.png"
const CREDITS_BACKGROUND_PATH: String = "res://assets/images/background2.jpg"
const LOGO_PATH: String = "res://assets/images/logo.png"
const GODOT_LOGO_PATH: String = "res://assets/images/gd.png"
const HORIZON_LOGO_PATH: String = "res://assets/images/hz.png"
const IMAGE_FOLDER: String = "res://assets/images/"
# FIX: the map lives in the scenes/maps folder, not res://maps/.
const GAME_SCENE_PATH: String = "res://scenes/maps/map_one.tscn"
# Old path, only tried if the main path is missing.
const GAME_SCENE_FALLBACK_PATH: String = "res://maps/map_one.tscn"
const STARTER_TROLLEY_PATH: String = "res://assets/models/trollys/starter/starter.glb"
const BACK_BUTTON_IMAGE: String = "button_back.png"

# Names the game looks for in the map to decide where the trolley appears.
# Add a Marker3D with one of these names to map_one.tscn.
const TROLLEY_SPAWN_NAMES: Array[String] = [
	"TrolleySpawn", "TrolleySpawnPoint", "PlayerSpawn", "SpawnPoint", "Spawn", "Start"
]

# Startup logo timing
const GODOT_LOGO_DURATION: float = 1.5
const HORIZON_LOGO_DURATION: float = 2.0
const SPLASH_FADE_DURATION: float = 0.4
const SPLASH_BLACK_GAP: float = 0.25

# Menu soundtrack
const MENU_TRACKS: Array[AudioStream] = [
	preload("res://assets/audio/open_roads.mp3"),
	preload("res://assets/audio/somewhere_else.mp3"),
	preload("res://assets/audio/routes_and_rhythms.mp3")
]

const TRACK_GAP: float = 20.0

const LOGO_SIZE: Vector2 = Vector2(700, 230)
const PLAY_SIZE: Vector2 = Vector2(360, 115)
const SIDE_BUTTON_SIZE: Vector2 = Vector2(220, 46)
const TROLLEY_SIZE: Vector2 = Vector2(300, 250)
const BACK_BUTTON_SIZE: Vector2 = Vector2(200, 55)

const COLUMN_GAP: float = 30.0
const ROW_GAP: float = 20.0
const BUTTON_GAP: float = 18.0
const HOVER_SCALE: Vector2 = Vector2(1.05, 1.05)

var logo: Control
var menu_layout: Control

var play_button: Control
var trolley_button: Control
var settings_button: Control
var credits_button: Control
var quit_button: Control

var music_player: AudioStreamPlayer
var music_gap_timer: Timer
var music_index: int = 0

var credits_panel: Control


#------------------
# INITIALISE MENU
#------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Load the list of accounts stored on this device.
	_accounts_load()

	create_background()
	create_logo()
	create_menu()

	# The main menu stays hidden until the player is logged in.
	menu_layout.hide()
	menu_layout.modulate.a = 0.0
	logo.modulate.a = 0.0

	await get_tree().process_frame
	await play_startup_logos()

	_place_logo_top()
	logo.modulate.a = 1.0

	create_music_player()

	# Show the log in / sign up screen and wait until the player gets in.
	show_auth_screen()
	await auth_succeeded

	# Restore the trolley and colour saved on THIS account.
	garage_load_saved()
	create_account_bar()

	menu_layout.show()
	await animate_intro()


#------------------
# HELPERS
#------------------

# Removes and frees every child of a node. The children are detached
# straight away and freed safely at the end of the frame. This matters
# because many of them are buttons that are in the middle of emitting
# their "pressed" signal when we rebuild the UI.
func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# Shows a clear error message on screen (and in the Output panel).
func show_error(title_text: String, message: String) -> void:
	push_error(title_text + ": " + message)

	var dialog := AcceptDialog.new()
	dialog.title = title_text
	dialog.dialog_text = message
	dialog.dialog_autowrap = true
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 180))


# Returns the first map path that exists, or "" if none do.
func _resolve_map_path() -> String:
	if ResourceLoader.exists(GAME_SCENE_PATH):
		return GAME_SCENE_PATH

	if ResourceLoader.exists(GAME_SCENE_FALLBACK_PATH):
		return GAME_SCENE_FALLBACK_PATH

	return ""


# Puts the logo at the top centre of the screen.
func _place_logo_top() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	logo.position = Vector2((screen_size.x - LOGO_SIZE.x) / 2.0, 15.0)


# ============================================================
# ACCOUNTS (sign up / log in) - stored on this device
# ============================================================
#
# Accounts are saved in user://trolley_mayhem_accounts.cfg
# Passwords are NEVER stored. Only a random salt and a hash of
# (salt + password) is saved, so the file does not reveal passwords.
#
# Each account also gets its own save file:
#   user://trolley_mayhem_save_<username>.cfg
# Use user_data_set() / user_data_get() from anywhere in this script
# to save and load game data for the logged-in account.
#
# Other scripts can read who is logged in with:
#   get_tree().root.get_meta("current_username")

const ACCOUNTS_PATH: String = "user://trolley_mayhem_accounts.cfg"
const USER_SAVE_PREFIX: String = "user://trolley_mayhem_save_"
const USERNAME_MIN: int = 3
const USERNAME_MAX: int = 16
const PASSWORD_MIN: int = 6
const PASSWORD_MAX: int = 64
const HASH_ROUNDS: int = 2000

var accounts_config: ConfigFile = ConfigFile.new()
var current_user: String = ""


func _accounts_load() -> void:
	# It is fine if the file does not exist yet (first launch).
	accounts_config.load(ACCOUNTS_PATH)


# Usernames are matched ignoring upper/lower case, so "Bob" and "bob"
# count as the same name.
func _account_key(username: String) -> String:
	return username.strip_edges().to_lower()


func _account_section(username: String) -> String:
	return "user:" + _account_key(username)


func account_exists(username: String) -> bool:
	return accounts_config.has_section(_account_section(username))


# Returns "" if the username is allowed, otherwise the reason it is not.
func account_validate_username(username: String) -> String:
	if username.length() < USERNAME_MIN:
		return "Username must be at least " + str(USERNAME_MIN) + " characters."

	if username.length() > USERNAME_MAX:
		return "Username can be at most " + str(USERNAME_MAX) + " characters."

	var regex := RegEx.create_from_string("^[A-Za-z0-9_]+$")
	if regex.search(username) == null:
		return "Username can only use letters, numbers and underscores."

	return ""


# Returns "" if the password is allowed, otherwise the reason it is not.
func account_validate_password(password: String) -> String:
	if password.length() < PASSWORD_MIN:
		return "Password must be at least " + str(PASSWORD_MIN) + " characters."

	if password.length() > PASSWORD_MAX:
		return "Password can be at most " + str(PASSWORD_MAX) + " characters."

	return ""


func _account_hash(password: String, salt: String) -> String:
	var hashed: String = (salt + password).sha256_text()

	for _round in HASH_ROUNDS:
		hashed = (hashed + salt + password).sha256_text()

	return hashed


# Creates a new account and logs it in.
# Returns {"ok": bool, "message": String}
func account_create(username: String, password: String) -> Dictionary:
	username = username.strip_edges()

	var username_error: String = account_validate_username(username)
	if username_error != "":
		return {"ok": false, "message": username_error}

	var password_error: String = account_validate_password(password)
	if password_error != "":
		return {"ok": false, "message": password_error}

	if account_exists(username):
		return {"ok": false, "message": "That username is already taken."}

	var salt: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var section: String = _account_section(username)

	accounts_config.set_value(section, "display_name", username)
	accounts_config.set_value(section, "salt", salt)
	accounts_config.set_value(section, "hash", _account_hash(password, salt))
	accounts_config.set_value(section, "created", Time.get_datetime_string_from_system())

	var error: int = accounts_config.save(ACCOUNTS_PATH)
	if error != OK:
		# Undo, so a failed save does not leave a half-made account in memory.
		accounts_config.erase_section(section)
		return {
			"ok": false,
			"message": "Could not save the account (error " + str(error) + ")."
		}

	_account_set_current(username)
	return {"ok": true, "message": "Account created!"}


# Checks the username and password and logs in.
# Returns {"ok": bool, "message": String}
func account_login(username: String, password: String) -> Dictionary:
	username = username.strip_edges()

	if username == "" or password == "":
		return {"ok": false, "message": "Enter your username and password."}

	# The same message is used for "no such user" and "wrong password".
	var failed := {"ok": false, "message": "Incorrect username or password."}

	if not account_exists(username):
		return failed

	var section: String = _account_section(username)
	var salt: String = str(accounts_config.get_value(section, "salt", ""))
	var stored_hash: String = str(accounts_config.get_value(section, "hash", ""))

	if salt == "" or stored_hash == "":
		return failed

	if _account_hash(password, salt) != stored_hash:
		return failed

	var display_name: String = str(
		accounts_config.get_value(section, "display_name", username)
	)
	_account_set_current(display_name)
	return {"ok": true, "message": "Logged in!"}


func _account_set_current(display_name: String) -> void:
	current_user = display_name
	get_tree().root.set_meta("current_username", current_user)

	# Remember the name so it is filled in next time.
	accounts_config.set_value("meta", "last_username", current_user)
	accounts_config.save(ACCOUNTS_PATH)


func account_last_username() -> String:
	return str(accounts_config.get_value("meta", "last_username", ""))


# ------------------------------------------------------------
# PER-ACCOUNT SAVE DATA
# ------------------------------------------------------------

func _user_save_path() -> String:
	return USER_SAVE_PREFIX + _account_key(current_user) + ".cfg"


# Saves one value for the logged-in account.
# Example: user_data_set("progress", "winter_level", 3)
func user_data_set(section: String, key: String, value: Variant) -> void:
	if current_user == "":
		push_warning("Not logged in, nothing was saved.")
		return

	var config := ConfigFile.new()
	config.load(_user_save_path()) # OK if it does not exist yet.
	config.set_value(section, key, value)

	var error: int = config.save(_user_save_path())
	if error != OK:
		push_warning("Could not save account data. Error code: " + str(error))


# Loads one value for the logged-in account (or the default).
# Example: user_data_get("progress", "winter_level", 1)
func user_data_get(section: String, key: String, default_value: Variant = null) -> Variant:
	if current_user == "":
		return default_value

	var config := ConfigFile.new()
	if config.load(_user_save_path()) != OK:
		return default_value

	return config.get_value(section, key, default_value)


# ------------------------------------------------------------
# LOG IN / SIGN UP SCREEN
# ------------------------------------------------------------

var auth_panel: Control
var auth_mode: String = "login"
var auth_busy: bool = false

var auth_title_label: Label
var auth_username_edit: LineEdit
var auth_password_edit: LineEdit
var auth_confirm_edit: LineEdit
var auth_confirm_box: VBoxContainer
var auth_message_label: Label
var auth_submit_button: Button
var auth_login_tab: Button
var auth_signup_tab: Button


func show_auth_screen() -> void:
	if is_instance_valid(auth_panel):
		auth_panel.queue_free()

	if is_instance_valid(menu_layout):
		menu_layout.hide()

	_place_logo_top()
	logo.show()

	auth_busy = false
	auth_mode = "login"

	auth_panel = Control.new()
	auth_panel.name = "AuthPanel"
	auth_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	auth_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	auth_panel.z_index = 300
	add_child(auth_panel)

		# Keeps the card underneath the logo.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", int(LOGO_SIZE.y + 30.0))
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	auth_panel.add_child(margin)

	# Lets the card scroll when it is taller than the space available.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(center)

	# The card
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.055, 0.055, 0.07, 0.94)
	card_style.set_corner_radius_all(14)
	card_style.set_border_width_all(1)
	card_style.border_color = Color("#f97316")
	card_style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)


	# Tabs: LOG IN / SIGN UP
	var tab_group := ButtonGroup.new()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)

	auth_login_tab = Button.new()
	auth_login_tab.text = "LOG IN"
	auth_login_tab.toggle_mode = true
	auth_login_tab.button_group = tab_group
	auth_login_tab.button_pressed = true
	auth_login_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_login_tab.custom_minimum_size.y = 42
	auth_login_tab.pressed.connect(_auth_set_mode.bind("login"))
	tabs.add_child(auth_login_tab)

	auth_signup_tab = Button.new()
	auth_signup_tab.text = "SIGN UP"
	auth_signup_tab.toggle_mode = true
	auth_signup_tab.button_group = tab_group
	auth_signup_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_signup_tab.custom_minimum_size.y = 42
	auth_signup_tab.pressed.connect(_auth_set_mode.bind("signup"))
	tabs.add_child(auth_signup_tab)

	# Title
	auth_title_label = Label.new()
	auth_title_label.text = "WELCOME BACK"
	auth_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auth_title_label.add_theme_font_size_override("font_size", 24)
	auth_title_label.add_theme_color_override("font_color", Color("#f97316"))
	box.add_child(auth_title_label)

	# Username
	var username_label := Label.new()
	username_label.text = "Username"
	box.add_child(username_label)

	auth_username_edit = LineEdit.new()
	auth_username_edit.placeholder_text = "Enter your username"
	auth_username_edit.max_length = USERNAME_MAX
	auth_username_edit.custom_minimum_size.y = 40
	auth_username_edit.text = account_last_username()
	auth_username_edit.text_changed.connect(_auth_on_username_changed)
	auth_username_edit.text_submitted.connect(_auth_username_submitted)
	box.add_child(auth_username_edit)

	# Password
	var password_label := Label.new()
	password_label.text = "Password"
	box.add_child(password_label)

	auth_password_edit = LineEdit.new()
	auth_password_edit.placeholder_text = "Enter your password"
	auth_password_edit.secret = true
	auth_password_edit.max_length = PASSWORD_MAX
	auth_password_edit.custom_minimum_size.y = 40
	auth_password_edit.text_submitted.connect(_auth_password_submitted)
	box.add_child(auth_password_edit)

	# Confirm password (sign up only)
	auth_confirm_box = VBoxContainer.new()
	auth_confirm_box.add_theme_constant_override("separation", 6)
	auth_confirm_box.visible = false
	box.add_child(auth_confirm_box)

	var confirm_label := Label.new()
	confirm_label.text = "Confirm password"
	auth_confirm_box.add_child(confirm_label)

	auth_confirm_edit = LineEdit.new()
	auth_confirm_edit.placeholder_text = "Type your password again"
	auth_confirm_edit.secret = true
	auth_confirm_edit.max_length = PASSWORD_MAX
	auth_confirm_edit.custom_minimum_size.y = 40
	auth_confirm_edit.text_submitted.connect(_auth_text_submit)
	auth_confirm_box.add_child(auth_confirm_edit)

	# Show password
	var show_password := CheckBox.new()
	show_password.text = "Show password"
	show_password.toggled.connect(_auth_on_show_password_toggled)
	box.add_child(show_password)

	# Message (errors / availability / success)
	auth_message_label = Label.new()
	auth_message_label.text = ""
	auth_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auth_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auth_message_label.custom_minimum_size.y = 44
	box.add_child(auth_message_label)

	# Submit
	auth_submit_button = Button.new()
	auth_submit_button.text = "LOG IN"
	auth_submit_button.custom_minimum_size = Vector2(0, 50)
	auth_submit_button.add_theme_color_override("font_color", Color("#f97316"))
	auth_submit_button.pressed.connect(_auth_submit)
	box.add_child(auth_submit_button)

	var note := Label.new()
	note.text = "Accounts are saved on this device."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	box.add_child(note)

	# Put the cursor in the first empty box.
	if auth_username_edit.text == "":
		auth_username_edit.call_deferred("grab_focus")
	else:
		auth_password_edit.call_deferred("grab_focus")


func _auth_set_mode(mode: String) -> void:
	auth_mode = mode

	var is_signup: bool = mode == "signup"

	auth_title_label.text = "CREATE ACCOUNT" if is_signup else "WELCOME BACK"
	auth_submit_button.text = "CREATE ACCOUNT" if is_signup else "LOG IN"
	auth_confirm_box.visible = is_signup

	auth_password_edit.text = ""
	auth_confirm_edit.text = ""
	_auth_show_message("", false)

	if is_signup:
		auth_username_edit.placeholder_text = "Choose a username"
		auth_password_edit.placeholder_text = "Choose a password"
		_auth_on_username_changed(auth_username_edit.text)
	else:
		auth_username_edit.placeholder_text = "Enter your username"
		auth_password_edit.placeholder_text = "Enter your password"


# While signing up, tell the player straight away if the name is free.
func _auth_on_username_changed(new_text: String) -> void:
	if auth_mode != "signup":
		_auth_show_message("", false)
		return

	var username: String = new_text.strip_edges()

	if username == "":
		_auth_show_message("", false)
		return

	var problem: String = account_validate_username(username)
	if problem != "":
		_auth_show_message(problem, true)
		return

	if account_exists(username):
		_auth_show_message("\"" + username + "\" is already taken.", true)
	else:
		_auth_show_message("\"" + username + "\" is available!", false)


func _auth_on_show_password_toggled(pressed: bool) -> void:
	auth_password_edit.secret = not pressed
	auth_confirm_edit.secret = not pressed


func _auth_username_submitted(_text: String) -> void:
	auth_password_edit.grab_focus()


func _auth_password_submitted(_text: String) -> void:
	if auth_mode == "signup":
		auth_confirm_edit.grab_focus()
	else:
		_auth_submit()


func _auth_text_submit(_text: String) -> void:
	_auth_submit()


func _auth_show_message(message: String, is_error: bool) -> void:
	if not is_instance_valid(auth_message_label):
		return

	auth_message_label.text = message
	auth_message_label.add_theme_color_override(
		"font_color",
		Color("#ef4444") if is_error else Color("#22c55e")
	)


func _auth_submit() -> void:
	if auth_busy:
		return

	auth_busy = true
	auth_submit_button.disabled = true

	var username: String = auth_username_edit.text.strip_edges()
	var password: String = auth_password_edit.text
	var result: Dictionary

	if auth_mode == "signup":
		if password != auth_confirm_edit.text:
			result = {"ok": false, "message": "Passwords do not match."}
		else:
			result = account_create(username, password)
	else:
		result = account_login(username, password)

	if not bool(result["ok"]):
		_auth_show_message(str(result["message"]), true)

		# Short pause after a failed attempt (slows down password guessing).
		await get_tree().create_timer(0.6).timeout
		auth_busy = false

		if is_instance_valid(auth_submit_button):
			auth_submit_button.disabled = false
		return

	_auth_show_message("Welcome, " + current_user + "!", false)
	await get_tree().create_timer(0.5).timeout

	if is_instance_valid(auth_panel):
		auth_panel.queue_free()

	auth_panel = null
	auth_busy = false
	auth_succeeded.emit()


# ------------------------------------------------------------
# ACCOUNT BAR (top right of the main menu) + LOG OUT
# ------------------------------------------------------------

var account_bar: HBoxContainer


func create_account_bar() -> void:
	if is_instance_valid(account_bar):
		account_bar.queue_free()

	account_bar = HBoxContainer.new()
	account_bar.name = "AccountBar"
	account_bar.z_index = 5
	account_bar.add_theme_constant_override("separation", 12)
	add_child(account_bar)

	account_bar.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT,
		Control.PRESET_MODE_MINSIZE,
		20
	)
	account_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var name_label := Label.new()
	name_label.text = "Logged in as: " + current_user
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	account_bar.add_child(name_label)

	var logout_button := Button.new()
	logout_button.text = "LOG OUT"
	logout_button.custom_minimum_size = Vector2(110, 38)
	logout_button.pressed.connect(_on_logout_pressed)
	account_bar.add_child(logout_button)


func _on_logout_pressed() -> void:
	await logout()


func logout() -> void:
	current_user = ""

	var root := get_tree().root
	if root.has_meta("current_username"):
		root.remove_meta("current_username")

	if is_instance_valid(account_bar):
		account_bar.queue_free()
		account_bar = null

	show_auth_screen()
	await auth_succeeded

	garage_load_saved()
	create_account_bar()
	menu_layout.show()


#------------------
# STARTUP LOGOS
#------------------

func play_startup_logos() -> void:
	var godot_texture := load(GODOT_LOGO_PATH) as Texture2D
	var horizon_texture := load(HORIZON_LOGO_PATH) as Texture2D

	if godot_texture == null:
		push_error("Could not load Godot logo: " + GODOT_LOGO_PATH)
		return

	if horizon_texture == null:
		push_error("Could not load Horizon Studios logo: " + HORIZON_LOGO_PATH)
		return

	var black_screen := ColorRect.new()
	black_screen.name = "StartupBlackScreen"
	black_screen.color = Color.BLACK
	black_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_screen.z_index = 1000
	add_child(black_screen)

	var splash_logo := TextureRect.new()
	splash_logo.name = "StartupLogo"
	splash_logo.texture = godot_texture
	splash_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	splash_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash_logo.modulate.a = 0.0
	black_screen.add_child(splash_logo)

	await fade_startup_logo(splash_logo, GODOT_LOGO_DURATION)

	splash_logo.texture = null
	await get_tree().create_timer(SPLASH_BLACK_GAP).timeout

	splash_logo.texture = horizon_texture
	await fade_startup_logo(splash_logo, HORIZON_LOGO_DURATION)

	black_screen.queue_free()


func fade_startup_logo(
	splash_logo: TextureRect,
	duration: float
) -> void:
	var fade_time: float = minf(SPLASH_FADE_DURATION, duration / 2.0)

	var fade_in := create_tween()
	fade_in.set_trans(Tween.TRANS_SINE)
	fade_in.set_ease(Tween.EASE_IN_OUT)
	fade_in.tween_property(splash_logo, "modulate:a", 1.0, fade_time)
	await fade_in.finished

	var hold_time: float = maxf(0.0, duration - fade_time * 2.0)

	if hold_time > 0.0:
		await get_tree().create_timer(hold_time).timeout

	var fade_out := create_tween()
	fade_out.set_trans(Tween.TRANS_SINE)
	fade_out.set_ease(Tween.EASE_IN_OUT)
	fade_out.tween_property(splash_logo, "modulate:a", 0.0, fade_time)
	await fade_out.finished


#------------------
# MENU SOUNDTRACK
#------------------

func create_music_player() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.name = "MenuMusic"
	add_child(music_player)

	music_gap_timer = Timer.new()
	music_gap_timer.name = "MusicGapTimer"
	music_gap_timer.one_shot = true
	music_gap_timer.wait_time = TRACK_GAP
	add_child(music_gap_timer)

	music_player.finished.connect(_on_music_finished)
	music_gap_timer.timeout.connect(_on_music_gap_finished)

	play_menu_track()


func play_menu_track() -> void:
	if MENU_TRACKS.is_empty():
		return

	music_index = music_index % MENU_TRACKS.size()
	music_player.stream = MENU_TRACKS[music_index]
	music_player.play()


func _on_music_finished() -> void:
	music_gap_timer.start()


func _on_music_gap_finished() -> void:
	music_index = (music_index + 1) % MENU_TRACKS.size()
	play_menu_track()


#------------------
# BACKGROUND
#------------------

func create_background() -> void:
	var background := TextureRect.new()
	background.name = "Background"

	if ResourceLoader.exists(BACKGROUND_PATH):
		background.texture = load(BACKGROUND_PATH) as Texture2D
	else:
		push_warning("Missing background: " + BACKGROUND_PATH)

	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)
	move_child(background, 0)


#------------------
# LOGO
#------------------

func create_logo() -> void:
	if ResourceLoader.exists(LOGO_PATH):
		var image := TextureRect.new()
		image.texture = load(LOGO_PATH) as Texture2D
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo = image
	else:
		var title := Label.new()
		title.text = "TROLLEY MAYHEM"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 48)
		title.add_theme_color_override("font_color", Color.WHITE)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo = title

		push_warning("Missing logo: " + LOGO_PATH)

	logo.name = "Logo"
	logo.size = LOGO_SIZE
	add_child(logo)


#------------------
# MENU BUTTONS
#------------------

func create_menu() -> void:
	menu_layout = Control.new()
	menu_layout.name = "MenuLayout"
	menu_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_layout)

	play_button = make_button("PLAY", "button_play.png", PLAY_SIZE)
	play_button.name = "PlayButton"
	menu_layout.add_child(play_button)
	connect_button(play_button, "PLAY")

	trolley_button = make_button("GARAGE", "trolly1.png", TROLLEY_SIZE)
	trolley_button.name = "TrolleyGarageButton"
	menu_layout.add_child(trolley_button)
	connect_button(trolley_button, "GARAGE")

	settings_button = make_button("SETTINGS", "button_settings.png", SIDE_BUTTON_SIZE)
	settings_button.name = "SettingsButton"
	menu_layout.add_child(settings_button)
	connect_button(settings_button, "SETTINGS")

	credits_button = make_button("CREDITS", "button_credits.png", SIDE_BUTTON_SIZE)
	credits_button.name = "CreditsButton"
	menu_layout.add_child(credits_button)
	connect_button(credits_button, "CREDITS")

	quit_button = make_button("QUIT", "button_quit.png", SIDE_BUTTON_SIZE)
	quit_button.name = "QuitButton"
	menu_layout.add_child(quit_button)
	connect_button(quit_button, "QUIT")


func make_button(
	button_name: String,
	image_filename: String,
	button_size: Vector2
) -> Control:
	var image_path: String = IMAGE_FOLDER + image_filename
	var button: Control

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
		text_button.text = button_name
		text_button.add_theme_font_size_override("font_size", 20)
		button = text_button
		push_warning("Missing button image: " + image_path)

	button.custom_minimum_size = button_size
	button.size = button_size
	button.pivot_offset = button_size / 2.0
	button.mouse_filter = Control.MOUSE_FILTER_STOP

	button.mouse_entered.connect(_on_button_hover.bind(button, true))
	button.mouse_exited.connect(_on_button_hover.bind(button, false))

	return button


func connect_button(button: Control, button_name: String) -> void:
	if button is BaseButton:
		(button as BaseButton).pressed.connect(
			_on_menu_button_pressed.bind(button_name)
		)


#------------------
# INTRO ANIMATION
#------------------

# The logo is already at the top (it stays there from the log in screen),
# so the intro now lays out the menu and fades it in.
func animate_intro() -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	_place_logo_top()

	var top_row_width: float = PLAY_SIZE.x + COLUMN_GAP + TROLLEY_SIZE.x
	var bottom_row_width: float = SIDE_BUTTON_SIZE.x * 3.0 + BUTTON_GAP * 2.0
	var menu_width: float = max(top_row_width, bottom_row_width)
	var top_row_height: float = max(PLAY_SIZE.y, TROLLEY_SIZE.y)
	var menu_height: float = top_row_height + ROW_GAP + SIDE_BUTTON_SIZE.y

	menu_layout.size = Vector2(menu_width, menu_height)
	menu_layout.position = Vector2(
		(screen_size.x - menu_width) / 2.0,
		max(
			LOGO_SIZE.y + 35.0,
			(screen_size.y - menu_height) / 2.0 + 60.0
		)
	)

	var top_start_x: float = (menu_width - top_row_width) / 2.0

	play_button.position = Vector2(
		top_start_x,
		(top_row_height - PLAY_SIZE.y) / 2.0
	)

	trolley_button.position = Vector2(
		top_start_x + PLAY_SIZE.x + COLUMN_GAP,
		(top_row_height - TROLLEY_SIZE.y) / 2.0
	)

	var bottom_start_x: float = (menu_width - bottom_row_width) / 2.0
	var bottom_y: float = top_row_height + ROW_GAP

	settings_button.position = Vector2(bottom_start_x, bottom_y)
	credits_button.position = Vector2(
		bottom_start_x + SIDE_BUTTON_SIZE.x + BUTTON_GAP,
		bottom_y
	)
	quit_button.position = Vector2(
		bottom_start_x + (SIDE_BUTTON_SIZE.x + BUTTON_GAP) * 2.0,
		bottom_y
	)

	menu_layout.modulate.a = 0.0

	await get_tree().create_timer(0.3).timeout

	var fade_tween := create_tween()
	fade_tween.set_trans(Tween.TRANS_CUBIC)
	fade_tween.set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(menu_layout, "modulate:a", 1.0, 1.0)
	await fade_tween.finished


#------------------
# BUTTON HOVER
#------------------

func _on_button_hover(button: Control, hovering: bool) -> void:
	var target_scale: Vector2 = HOVER_SCALE if hovering else Vector2.ONE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, 0.18)


#------------------
# BUTTON ACTIONS
#------------------

func _on_menu_button_pressed(button_name: String) -> void:
	match button_name:
		"PLAY":
			print("PLAY BUTTON PRESSED")
			show_level_select()

		"GARAGE":
			print("Garage selected!")
			show_garage()

		"SETTINGS":
			print("Settings selected!")
			show_settings()

		"CREDITS":
			show_credits()

		"QUIT":
			get_tree().quit()


#------------------
# GAME START
#------------------

# Loads the map, spawns the applied trolley into it, then switches to it.
# Every step is checked, and a clear error is shown if anything fails.
func start_game() -> void:
	# 1. Check the files exist.
	var map_path: String = _resolve_map_path()

	if map_path == "":
		show_error(
			"Map not found",
			"The gameplay map could not be found. Looked in:\n"
			+ GAME_SCENE_PATH + "\n" + GAME_SCENE_FALLBACK_PATH
			+ "\n\nIn the FileSystem dock, right-click map_one.tscn and choose"
			+ " \"Copy Path\", then paste it into GAME_SCENE_PATH at the top of this script."
		)
		return

	var trolley_path: String = garage_get_applied_trolley_path()

	if trolley_path == "" or not ResourceLoader.exists(trolley_path):
		show_error(
			"Trolley model not found",
			"The applied trolley \"" + garage_applied_trolley
			+ "\" has no model file at:\n" + trolley_path
			+ "\n\nCheck the .glb file exists and has been imported by Godot."
		)
		return

	# 2. Load both resources.
	var map_scene := load(map_path) as PackedScene
	if map_scene == null:
		show_error(
			"Map failed to load",
			"Godot could not load " + map_path
			+ " as a scene. Open it in the editor and check for errors."
		)
		return

	var trolley_scene := load(trolley_path) as PackedScene
	if trolley_scene == null:
		show_error(
			"Trolley failed to load",
			"Godot could not load " + trolley_path
			+ " as a 3D scene. Check the import settings of the .glb file."
		)
		return

	# 3. Pass the selections on BEFORE the map is created, so any script
	#    in the map can read them as soon as it starts.
	garage_publish_meta()
	get_tree().root.set_meta("selected_season", level_current_season)
	get_tree().root.set_meta("selected_level", level_selected_number)

	# 4. Create the map and the trolley.
	var map_instance: Node = map_scene.instantiate()
	if map_instance == null:
		show_error("Map failed to start", "Could not create " + map_path)
		return

	var trolley_instance: Node = trolley_scene.instantiate()
	if not (trolley_instance is Node3D):
		if trolley_instance != null:
			trolley_instance.free()
		map_instance.free()
		show_error(
			"Trolley is not a 3D model",
			trolley_path + " did not load as a Node3D, so it cannot be placed in the map."
		)
		return

	if not (map_instance is Node3D):
		trolley_instance.free()
		var map_type: String = map_instance.get_class()
		map_instance.free()
		show_error(
			"Map is not a 3D scene",
			map_path + " has a root node of type " + map_type
			+ ", but the trolley is a 3D model. The map root should be a Node3D."
		)
		return

	# 5. Put the map in the tree, then place the trolley in it.
	var tree := get_tree()
	tree.root.add_child(map_instance)

	trolley_instance.name = "PlayerTrolley"
	map_instance.add_child(trolley_instance)

	var spawn_point: Node3D = _find_trolley_spawn(map_instance)

	if spawn_point != null:
		(trolley_instance as Node3D).global_transform = spawn_point.global_transform
	else:
		push_warning(
			"No spawn marker found in the map (looked for: "
			+ ", ".join(TROLLEY_SPAWN_NAMES)
			+ "). The trolley was placed at the map origin."
		)

	# 6. Make the map the active scene and remove the menu.
	tree.current_scene = map_instance
	queue_free()


# Looks for a spawn marker inside the loaded map.
func _find_trolley_spawn(map_root: Node) -> Node3D:
	for spawn_name in TROLLEY_SPAWN_NAMES:
		var found: Node = map_root.find_child(spawn_name, true, false)
		if found is Node3D:
			return found as Node3D

	return null


#------------------
# CREDITS
#------------------

func show_credits() -> void:
	if is_instance_valid(credits_panel):
		return

	menu_layout.hide()

	# Full-screen overlay, above the menu and background.
	credits_panel = Control.new()
	credits_panel.name = "CreditsPanel"
	credits_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	credits_panel.z_index = 10
	add_child(credits_panel)

	# Credits background.
	var background := TextureRect.new()
	background.name = "CreditsBackground"

	if ResourceLoader.exists(CREDITS_BACKGROUND_PATH):
		background.texture = load(CREDITS_BACKGROUND_PATH) as Texture2D
	else:
		push_error("Missing Credits background: " + CREDITS_BACKGROUND_PATH)

	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits_panel.add_child(background)

	# Keep the existing logo in its original position above the credits.
	logo.show()
	logo.z_index = 11

	# Grey panel: 25% opacity, with rounded corners.
	var credits_box := Panel.new()
	credits_box.name = "CreditsBox"
	credits_box.anchor_left = 0.15
	credits_box.anchor_top = 0.34
	credits_box.anchor_right = 0.85
	credits_box.anchor_bottom = 0.81
	credits_box.offset_left = 0.0
	credits_box.offset_top = 0.0
	credits_box.offset_right = 0.0
	credits_box.offset_bottom = 0.0
	credits_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.65, 0.65, 0.65, 0.53)
	box_style.set_corner_radius_all(18)
	credits_box.add_theme_stylebox_override("panel", box_style)
	credits_panel.add_child(credits_box)

	# Text container fills the grey panel.
	var content := VBoxContainer.new()
	content.name = "CreditsContent"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 30.0
	content.offset_top = 20.0
	content.offset_right = -30.0
	content.offset_bottom = -20.0
	content.add_theme_constant_override("separation", 16)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits_box.add_child(content)

	# Credits heading.
	var heading := Label.new()
	heading.text = "CREDITS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 42)
	heading.add_theme_color_override("font_color", Color.BLACK)
	content.add_child(heading)

	# Studio.
	var studio := Label.new()
	studio.text = "Horizon Studio"
	studio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio.add_theme_font_size_override("font_size", 30)
	studio.add_theme_color_override("font_color", Color.BLACK)
	content.add_child(studio)

	# Acknowledgements.
	var soundtrack := Label.new()
	soundtrack.text = "Original Soundtrack made in Soundtrap"
	soundtrack.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soundtrack.add_theme_font_size_override("font_size", 22)
	soundtrack.add_theme_color_override("font_color", Color.BLACK)
	soundtrack.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	soundtrack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(soundtrack)

	var engine := Label.new()
	engine.text = "Made with Godot Engine"
	engine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	engine.add_theme_font_size_override("font_size", 22)
	engine.add_theme_color_override("font_color", Color.BLACK)
	content.add_child(engine)

	# Back button below the credits panel.
	var back_button := make_button(
		"BACK",
		BACK_BUTTON_IMAGE,
		BACK_BUTTON_SIZE
	)
	back_button.name = "BackButton"
	back_button.z_index = 12
	back_button.position = Vector2(
		(get_viewport_rect().size.x - BACK_BUTTON_SIZE.x) / 2.0,
		get_viewport_rect().size.y * 0.85
	)
	credits_panel.add_child(back_button)

	if back_button is BaseButton:
		(back_button as BaseButton).pressed.connect(hide_credits)


func hide_credits() -> void:
	if is_instance_valid(credits_panel):
		credits_panel.queue_free()

	credits_panel = null
	menu_layout.show()


#------------------
# GARAGE
#------------------

const GARAGE_TROLLEY_PATH := "res://assets/images/garage/trollys/"
const GARAGE_PEOPLE_PATH := "res://assets/images/garage/people/"
const GARAGE_BACKGROUND_PATH := "res://assets/images/background1.png"

var garage_panel: Control
var garage_grid: GridContainer
var garage_details: VBoxContainer
var garage_current_tab: String = "Trolly"

# Independent selections.
var garage_selected_trolley: String = "Starter Trolly"
var garage_selected_colour: String = "White"

var garage_applied_trolley: String = "Starter Trolly"
var garage_applied_colour: String = "White"

# Trolley information. "model" is the 3D model spawned in gameplay.
var garage_trolleys: Array[Dictionary] = [
	{
		"name": "Starter Trolly",
		"image": "starter.png",
		"model": STARTER_TROLLEY_PATH,
		"turning": "Drift Trolly",
		"difficulty": "Easy",
		"map_suitability": "Suitable for this map"
	}
]

# Available person colours.
var garage_colours: Array[String] = [
	"White", "Black", "Red", "Blue", "Green",
	"Yellow", "Orange", "Purple", "Pink", "Cyan",
	"Grey", "Brown", "Teal", "Navy", "Maroon",
	"Olive", "Beige", "Lavender", "Mint", "Gold"
]


# Returns the data for a trolley by name (empty Dictionary if not found).
func garage_find_trolley(trolley_name: String) -> Dictionary:
	for trolley in garage_trolleys:
		if str(trolley["name"]) == trolley_name:
			return trolley

	return {}


# Returns the model path for the trolley applied in the Garage.
func garage_get_applied_trolley_path() -> String:
	var data: Dictionary = garage_find_trolley(garage_applied_trolley)

	if data.is_empty():
		return ""

	return str(data.get("model", ""))


# Stores the applied choices where the gameplay scene can read them.
func garage_publish_meta() -> void:
	var root := get_tree().root
	root.set_meta("selected_trolley_path", garage_get_applied_trolley_path())
	root.set_meta("selected_trolley_name", garage_applied_trolley)
	root.set_meta("selected_person_colour", garage_applied_colour)
	root.set_meta("current_username", current_user)


# Saves the applied choices to the logged-in account's save file.
func garage_save() -> void:
	user_data_set("garage", "trolley", garage_applied_trolley)
	user_data_set("garage", "colour", garage_applied_colour)


# Loads the logged-in account's saved choices (if any) and checks they are
# still valid. A brand new account starts with the defaults.
func garage_load_saved() -> void:
	# Start from the defaults so one account's choices never leak into another.
	garage_applied_trolley = "Starter Trolly"
	garage_applied_colour = "White"

	var saved_trolley: String = str(
		user_data_get("garage", "trolley", garage_applied_trolley)
	)
	var saved_colour: String = str(
		user_data_get("garage", "colour", garage_applied_colour)
	)

	if not garage_find_trolley(saved_trolley).is_empty():
		garage_applied_trolley = saved_trolley

	if garage_colours.has(saved_colour):
		garage_applied_colour = saved_colour

	garage_selected_trolley = garage_applied_trolley
	garage_selected_colour = garage_applied_colour
	garage_publish_meta()


func show_garage() -> void:
	if is_instance_valid(garage_panel):
		garage_panel.queue_free()

	# Start the Garage showing what is currently applied.
	garage_selected_trolley = garage_applied_trolley
	garage_selected_colour = garage_applied_colour

	garage_panel = Control.new()
	garage_panel.name = "GaragePanel"
	garage_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garage_panel.z_index = 100
	add_child(garage_panel)

	#------------------
	# BACKGROUND
	#------------------

	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load(GARAGE_BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	garage_panel.add_child(background)

	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.38)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	garage_panel.add_child(overlay)

	#------------------
	# MAIN LAYOUT
	#------------------

	var main_layout := VBoxContainer.new()
	main_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_layout.offset_left = 25
	main_layout.offset_top = 20
	main_layout.offset_right = -25
	main_layout.offset_bottom = -20
	main_layout.add_theme_constant_override("separation", 16)
	garage_panel.add_child(main_layout)

	#------------------
	# HEADER / TABS
	#------------------

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 50
	header.add_theme_constant_override("separation", 12)
	main_layout.add_child(header)

	var back_button := Button.new()
	back_button.text = "← Back"
	back_button.custom_minimum_size = Vector2(110, 45)
	back_button.pressed.connect(hide_garage)
	header.add_child(back_button)

	var trolley_tab := Button.new()
	trolley_tab.text = "Trolly"
	trolley_tab.custom_minimum_size = Vector2(140, 45)
	trolley_tab.pressed.connect(func():
		garage_change_tab("Trolly")
	)
	header.add_child(trolley_tab)

	var colour_tab := Button.new()
	colour_tab.text = "Person Color"
	colour_tab.custom_minimum_size = Vector2(160, 45)
	colour_tab.pressed.connect(func():
		garage_change_tab("Person Color")
	)
	header.add_child(colour_tab)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var heading := Label.new()
	heading.text = "GARAGE"
	heading.add_theme_font_size_override("font_size", 28)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)

	#------------------
	# GRID AND DETAILS
	#------------------

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	main_layout.add_child(content)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	content.add_child(scroll)

	garage_grid = GridContainer.new()
	garage_grid.columns = 5
	garage_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage_grid.add_theme_constant_override("h_separation", 12)
	garage_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(garage_grid)

	var details_panel := PanelContainer.new()
	details_panel.custom_minimum_size = Vector2(260, 0)
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(details_panel)

	garage_details = VBoxContainer.new()
	garage_details.add_theme_constant_override("separation", 12)
	details_panel.add_child(garage_details)

	garage_build_grid()
	garage_update_details()


func garage_change_tab(tab_name: String) -> void:
	garage_current_tab = tab_name
	garage_build_grid()
	garage_update_details()


func garage_build_grid() -> void:
	if not is_instance_valid(garage_grid):
		return

	# FIX: the old code called child.free() here. That deleted the tile's
	# button while it was still running its own "pressed" signal, which
	# Godot does not allow. Safe removal is used instead.
	_clear_children(garage_grid)

	if garage_current_tab == "Trolly":
		for trolley in garage_trolleys:
			garage_add_tile(
				str(trolley["name"]),
				str(trolley["image"]),
				garage_selected_trolley == str(trolley["name"])
			)
	else:
		for colour in garage_colours:
			garage_add_tile(
				colour,
				"dude_" + colour.to_lower() + ".png",
				garage_selected_colour == colour
			)


func garage_add_tile(
	item_name: String,
	image_name: String,
	is_selected: bool
) -> void:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(125, 125)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Red border for the selected item.
	var tile_style := StyleBoxFlat.new()
	tile_style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	tile_style.set_border_width_all(4 if is_selected else 1)
	tile_style.border_color = (
		Color.RED if is_selected else Color(0.55, 0.55, 0.55)
	)
	tile_style.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("panel", tile_style)

	var tile_content := VBoxContainer.new()
	tile_content.add_theme_constant_override("separation", 5)
	tile.add_child(tile_content)

	# Choose the correct image folder for the active tab.
	var image_path: String

	if garage_current_tab == "Trolly":
		image_path = GARAGE_TROLLEY_PATH + image_name
	else:
		image_path = GARAGE_PEOPLE_PATH + image_name

	var image := TextureRect.new()

	if ResourceLoader.exists(image_path):
		image.texture = load(image_path)
	else:
		push_warning("Garage image not found: " + image_path)

	image.custom_minimum_size = Vector2(100, 85)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_content.add_child(image)

	var name_label := Label.new()
	name_label.text = item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_content.add_child(name_label)

	garage_grid.add_child(tile)

	# Invisible button makes the whole tile clickable.
	var select_button := Button.new()
	select_button.flat = true
	select_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	select_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	select_button.pressed.connect(func():
		garage_select_item(item_name)
	)
	tile.add_child(select_button)


func garage_select_item(item_name: String) -> void:
	if garage_current_tab == "Trolly":
		garage_selected_trolley = item_name
	else:
		garage_selected_colour = item_name

	garage_build_grid()
	garage_update_details()


func garage_update_details() -> void:
	if not is_instance_valid(garage_details):
		return

	# FIX: same problem as the grid. The "Apply" button was being freed
	# while its own "pressed" signal was still running, so Apply failed.
	_clear_children(garage_details)

	if garage_current_tab == "Trolly":
		var selected_data: Dictionary = garage_trolleys[0]

		for trolley in garage_trolleys:
			if str(trolley["name"]) == garage_selected_trolley:
				selected_data = trolley
				break

		#------------------
		# TROLLEY IMAGE
		#------------------

		var trolley_preview := TextureRect.new()
		var trolley_path: String = (
			GARAGE_TROLLEY_PATH + str(selected_data["image"])
		)

		if ResourceLoader.exists(trolley_path):
			trolley_preview.texture = load(trolley_path)
		else:
			push_warning("Trolley image not found: " + trolley_path)

		trolley_preview.custom_minimum_size = Vector2(200, 150)
		trolley_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trolley_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trolley_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trolley_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		garage_details.add_child(trolley_preview)

		var title := Label.new()
		title.text = garage_selected_trolley
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 22)
		garage_details.add_child(title)

		#------------------
		# TROLLEY STATS
		#------------------

		var stats_heading := Label.new()
		stats_heading.text = "Stats"
		stats_heading.add_theme_font_size_override("font_size", 20)
		garage_details.add_child(stats_heading)

		garage_add_stat("Turning", str(selected_data["turning"]))
		garage_add_stat("Map", str(selected_data["map_suitability"]))
		garage_add_stat("Difficulty", str(selected_data["difficulty"]))

		var applied_label := Label.new()
		applied_label.text = (
			"Currently applied"
			if garage_applied_trolley == garage_selected_trolley
			else "Not currently applied"
		)
		garage_details.add_child(applied_label)

		var apply_button := Button.new()
		apply_button.text = "Apply Trolly"
		apply_button.custom_minimum_size.y = 45
		apply_button.pressed.connect(garage_apply_selection)
		garage_details.add_child(apply_button)

	else:
		#------------------
		# PERSON PREVIEW
		#------------------

		var title := Label.new()
		title.text = "Person Preview"
		title.add_theme_font_size_override("font_size", 22)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		garage_details.add_child(title)

		var preview := TextureRect.new()
		var preview_path: String = (
			GARAGE_PEOPLE_PATH
			+ "dude_"
			+ garage_selected_colour.to_lower()
			+ ".png"
		)

		if ResourceLoader.exists(preview_path):
			preview.texture = load(preview_path)
		else:
			push_warning("Person image not found: " + preview_path)

		preview.custom_minimum_size = Vector2(200, 220)
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		garage_details.add_child(preview)

		var colour_label := Label.new()
		colour_label.text = "Selected: " + garage_selected_colour
		colour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		garage_details.add_child(colour_label)

		var applied_label := Label.new()
		applied_label.text = (
			"Currently applied"
			if garage_applied_colour == garage_selected_colour
			else "Not currently applied"
		)
		garage_details.add_child(applied_label)

		var apply_button := Button.new()
		apply_button.text = "Apply Colour"
		apply_button.custom_minimum_size.y = 45
		apply_button.pressed.connect(garage_apply_selection)
		garage_details.add_child(apply_button)


func garage_add_stat(stat_name: String, stat_value: String) -> void:
	var stat_label := Label.new()
	stat_label.text = stat_name + ": " + stat_value
	stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	garage_details.add_child(stat_label)


func garage_apply_selection() -> void:
	if garage_current_tab == "Trolly":
		# Only accept trolleys that exist and have a model file.
		var data: Dictionary = garage_find_trolley(garage_selected_trolley)

		if data.is_empty():
			show_error(
				"Cannot apply trolley",
				"The trolley \"" + garage_selected_trolley + "\" is not in the Garage list."
			)
			return

		var model_path: String = str(data.get("model", ""))

		if model_path == "" or not ResourceLoader.exists(model_path):
			show_error(
				"Cannot apply trolley",
				"The model file for \"" + garage_selected_trolley
				+ "\" was not found:\n" + model_path
			)
			return

		garage_applied_trolley = garage_selected_trolley
		print("Applied trolley: ", garage_applied_trolley)
	else:
		garage_applied_colour = garage_selected_colour
		print("Applied person colour: ", garage_applied_colour)

	# Make the choice available to gameplay and remember it for next time.
	garage_publish_meta()
	garage_save()

	garage_update_details()


func hide_garage() -> void:
	if is_instance_valid(garage_panel):
		garage_panel.queue_free()
		garage_panel = null

	if is_instance_valid(menu_layout):
		menu_layout.show()


#------------------
# SETTINGS
#------------------

const SETTINGS_BACKGROUND_PATH: String = "res://assets/images/background2.jpg"

var settings_panel: Control
var settings_tab: String = "Graphics"

var settings_fullscreen: bool = true
var settings_vsync: bool = true
var settings_fps: int = 120

var settings_master_volume: float = 80.0
var settings_music_volume: float = 65.0
var settings_sfx_volume: float = 85.0

var settings_mouse_sensitivity: float = 50.0
var settings_camera_shake: bool = true
var settings_language: String = "English"


func show_settings() -> void:
	if is_instance_valid(settings_panel):
		settings_panel.queue_free()

	if is_instance_valid(menu_layout):
		menu_layout.hide()

	settings_panel = Control.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.z_index = 200
	add_child(settings_panel)

	# Background
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ResourceLoader.exists(SETTINGS_BACKGROUND_PATH):
		background.texture = load(SETTINGS_BACKGROUND_PATH) as Texture2D
	else:
		push_warning("Settings background not found: " + SETTINGS_BACKGROUND_PATH)

	settings_panel.add_child(background)

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.025, 0.025, 0.035, 0.78)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_panel.add_child(overlay)

	# Main layout
	var main := VBoxContainer.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.offset_left = 30
	main.offset_top = 20
	main.offset_right = -30
	main.offset_bottom = -20
	main.add_theme_constant_override("separation", 16)
	settings_panel.add_child(main)

	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 48
	header.add_theme_constant_override("separation", 15)
	main.add_child(header)

	var back := Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(110, 45)
	back.pressed.connect(_settings_back)
	header.add_child(back)

	var heading := Label.new()
	heading.text = "SETTINGS"
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("#f97316"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)

	# Tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	main.add_child(tabs)

	for tab_name in ["Graphics", "Audio", "Controls", "Game"]:
		var tab_button := Button.new()
		tab_button.text = tab_name
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.custom_minimum_size.y = 42
		tab_button.pressed.connect(_settings_change_tab.bind(tab_name))
		tabs.add_child(tab_button)

	# Settings content card
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.055, 0.055, 0.07, 0.94)
	card_style.set_corner_radius_all(14)
	card_style.set_border_width_all(1)
	card_style.border_color = Color("#f97316")
	card.add_theme_stylebox_override("panel", card_style)
	main.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 16)
	page.offset_left = 15
	page.offset_top = 15
	page.offset_right = -15
	page.offset_bottom = -15
	scroll.add_child(page)

	_settings_build_page(page)

	# Footer
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	main.add_child(footer)

	var apply_button := Button.new()
	apply_button.text = "APPLY SETTINGS"
	apply_button.custom_minimum_size = Vector2(200, 48)
	apply_button.add_theme_color_override("font_color", Color("#f97316"))
	apply_button.pressed.connect(_settings_apply)
	footer.add_child(apply_button)


func _settings_change_tab(tab_name: String) -> void:
	settings_tab = tab_name
	show_settings()


func _settings_build_page(page: VBoxContainer) -> void:
	var section := Label.new()

	match settings_tab:
		"Graphics":
			section.text = "01  /  DISPLAY & PERFORMANCE"
		"Audio":
			section.text = "02  /  SOUND MIXER"
		"Controls":
			section.text = "03  /  CONTROL PREFERENCES"
		_:
			section.text = "04  /  GAME PREFERENCES"

	section.add_theme_font_size_override("font_size", 20)
	section.add_theme_color_override("font_color", Color("#f97316"))
	page.add_child(section)

	match settings_tab:
		"Graphics":
			_settings_add_toggle(
				page,
				"Fullscreen",
				settings_fullscreen,
				func(value: bool):
					settings_fullscreen = value
			)

			_settings_add_toggle(
				page,
				"Vertical Sync",
				settings_vsync,
				func(value: bool):
					settings_vsync = value
			)

			_settings_add_option(
				page,
				"FPS Limit",
				["30", "60", "120", "144", "240", "Unlimited"],
				str(settings_fps),
				func(value: String):
					settings_fps = 0 if value == "Unlimited" else int(value)
			)

		"Audio":
			_settings_add_slider(
				page,
				"Master Volume",
				settings_master_volume,
				func(value: float):
					settings_master_volume = value
			)

			_settings_add_slider(
				page,
				"Music Volume",
				settings_music_volume,
				func(value: float):
					settings_music_volume = value
			)

			_settings_add_slider(
				page,
				"Sound Effects Volume",
				settings_sfx_volume,
				func(value: float):
					settings_sfx_volume = value
			)

		"Controls":
			_settings_add_slider(
				page,
				"Mouse Sensitivity",
				settings_mouse_sensitivity,
				func(value: float):
					settings_mouse_sensitivity = value
			)

			_settings_add_toggle(
				page,
				"Camera Shake",
				settings_camera_shake,
				func(value: bool):
					settings_camera_shake = value
			)

			var controls_note := Label.new()
			controls_note.text = "Key bindings can be added when gameplay controls are implemented."
			controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			page.add_child(controls_note)

		"Game":
			_settings_add_option(
				page,
				"Language",
				["English"],
				settings_language,
				func(value: String):
					settings_language = value
			)

			var game_note := Label.new()
			game_note.text = "More game preferences will be added as development continues."
			game_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			page.add_child(game_note)


func _settings_add_toggle(
	page: VBoxContainer,
	label_text: String,
	current_value: bool,
	on_change: Callable
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var toggle := CheckButton.new()
	toggle.button_pressed = current_value
	toggle.toggled.connect(on_change)
	row.add_child(toggle)


func _settings_add_slider(
	page: VBoxContainer,
	label_text: String,
	current_value: float,
	on_change: Callable
) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 5)
	page.add_child(group)

	var row := HBoxContainer.new()
	group.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value_label := Label.new()
	value_label.text = str(roundi(current_value)) + "%"
	value_label.custom_minimum_size.x = 55
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = current_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(slider)

	slider.value_changed.connect(func(value: float):
		value_label.text = str(roundi(value)) + "%"
		on_change.call(value)
	)


func _settings_add_option(
	page: VBoxContainer,
	label_text: String,
	options: Array[String],
	current_value: String,
	on_change: Callable
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var option := OptionButton.new()
	for item in options:
		option.add_item(item)

	var selected_index := options.find(current_value)
	if selected_index >= 0:
		option.select(selected_index)

	option.custom_minimum_size.x = 150
	option.item_selected.connect(func(index: int):
		on_change.call(option.get_item_text(index))
	)
	row.add_child(option)


func _settings_apply() -> void:
	# Display mode
	if settings_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# Vertical Sync
	if settings_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# FPS limit: zero means unlimited.
	Engine.max_fps = settings_fps

	# Audio buses
	_settings_set_bus_volume("Master", settings_master_volume)
	_settings_set_bus_volume("Music", settings_music_volume)
	_settings_set_bus_volume("SFX", settings_sfx_volume)

	print("Settings applied!")


func _settings_set_bus_volume(
	bus_name: String,
	volume_percent: float
) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		push_warning("Audio bus not found: " + bus_name)
		return

	if volume_percent <= 0.0:
		AudioServer.set_bus_mute(bus_index, true)
	else:
		AudioServer.set_bus_mute(bus_index, false)
		AudioServer.set_bus_volume_db(
			bus_index,
			linear_to_db(volume_percent / 100.0)
		)


func _settings_back() -> void:
	if is_instance_valid(settings_panel):
		settings_panel.queue_free()
		settings_panel = null

	if is_instance_valid(menu_layout):
		menu_layout.show()


# ============================================================
# LEVEL SELECT
# ============================================================

const LEVEL_BACKGROUND_PATH := "res://assets/images/background3.png"
const LEVEL_SEASONS_PATH := "res://assets/images/seasons/"
const LEVEL_SEASONS: Array[String] = ["Winter", "Spring", "Summer", "Autumn"]
const LEVELS_PER_SEASON: int = 20

var level_select_panel: Control
var level_grid: GridContainer
var level_details: VBoxContainer

var level_current_season: String = "Winter"
var level_selected_number: int = 1


# ------------------------------------------------------------
# OPEN LEVEL SELECT
# ------------------------------------------------------------

func show_level_select() -> void:
	if is_instance_valid(level_select_panel):
		level_select_panel.queue_free()

	level_current_season = "Winter"
	level_selected_number = 1

	level_select_panel = Control.new()
	level_select_panel.name = "LevelSelectPanel"
	level_select_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_select_panel.z_index = 100
	add_child(level_select_panel)

	# Background
	if ResourceLoader.exists(LEVEL_BACKGROUND_PATH):
		var background := TextureRect.new()
		background.texture = load(LEVEL_BACKGROUND_PATH)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_SCALE
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		level_select_panel.add_child(background)

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.03, 0.05, 0.08, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_select_panel.add_child(overlay)

	# Main layout
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 35
	layout.offset_right = -35
	layout.offset_top = 25
	layout.offset_bottom = -25
	layout.add_theme_constant_override("separation", 14)
	level_select_panel.add_child(layout)

	# Header
	var header := HBoxContainer.new()
	layout.add_child(header)

	var back_button := Button.new()
	back_button.text = "← BACK"
	back_button.custom_minimum_size = Vector2(130, 45)
	back_button.pressed.connect(hide_level_select)
	header.add_child(back_button)

	var heading := Label.new()
	heading.text = "SELECT A LEVEL"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	header.add_child(heading)

	var header_spacer := Control.new()
	header_spacer.custom_minimum_size.x = 130
	header.add_child(header_spacer)

	# Season tabs
	var season_tabs := HBoxContainer.new()
	season_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	season_tabs.add_theme_constant_override("separation", 12)
	layout.add_child(season_tabs)

	for season in LEVEL_SEASONS:
		var season_button := Button.new()
		season_button.text = season.to_upper()
		season_button.custom_minimum_size = Vector2(145, 45)
		season_button.pressed.connect(_level_change_season.bind(season))
		season_tabs.add_child(season_button)

	# Main content
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 25)
	layout.add_child(content)

	# Left: level grid
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(left_panel)

	var left_layout := VBoxContainer.new()
	left_layout.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_layout)

	var season_heading := Label.new()
	season_heading.name = "SeasonHeading"
	season_heading.text = "WINTER LEVELS"
	season_heading.add_theme_font_size_override("font_size", 22)
	left_layout.add_child(season_heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_layout.add_child(scroll)

	level_grid = GridContainer.new()
	level_grid.columns = 4
	level_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_grid.add_theme_constant_override("h_separation", 12)
	level_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(level_grid)

	# Right: selected level details
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size.x = 310
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(right_panel)

	level_details = VBoxContainer.new()
	level_details.add_theme_constant_override("separation", 12)
	right_panel.add_child(level_details)

	_level_build_grid()
	_level_update_details()


# ------------------------------------------------------------
# SEASON SELECTION
# ------------------------------------------------------------

func _level_change_season(season: String) -> void:
	level_current_season = season
	level_selected_number = 1
	_level_build_grid()
	_level_update_details()


# ------------------------------------------------------------
# LEVEL IMAGE PATH
# ------------------------------------------------------------

func _level_image_path(season: String, number: int) -> String:
	return LEVEL_SEASONS_PATH + season + "/level_" + str(number) + ".png"


# ------------------------------------------------------------
# BUILD LEVEL GRID
# ------------------------------------------------------------

func _level_build_grid() -> void:
	if not is_instance_valid(level_grid):
		return

	# Old tiles are detached immediately so they cannot overlap the new ones.
	_clear_children(level_grid)

	var heading_node: Node = level_select_panel.find_child("SeasonHeading", true, false)
	if heading_node is Label:
		(heading_node as Label).text = level_current_season.to_upper() + " LEVELS"

	var found_any := false

	for number in range(1, LEVELS_PER_SEASON + 1):
		var image_path := _level_image_path(level_current_season, number)

		if ResourceLoader.exists(image_path):
			found_any = true
			_level_add_tile(number, image_path)

	if not found_any:
		var empty_label := Label.new()
		empty_label.text = "Nothing to see here..."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 20)
		level_grid.add_child(empty_label)


func _level_add_tile(number: int, image_path: String) -> void:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(145, 125)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.clip_contents = true
	tile.pressed.connect(_level_select.bind(number))
	level_grid.add_child(tile)

	var tile_layout := VBoxContainer.new()
	tile_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile_layout.add_theme_constant_override("separation", 3)
	tile.add_child(tile_layout)

	var thumbnail := TextureRect.new()
	thumbnail.texture = load(image_path)
	thumbnail.custom_minimum_size = Vector2(125, 78)
	thumbnail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_layout.add_child(thumbnail)

	var level_label := Label.new()
	level_label.text = "LEVEL " + str(number)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 15)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_layout.add_child(level_label)

	var difficulty_label := Label.new()
	difficulty_label.text = _level_get_difficulty(number)
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_label.add_theme_font_size_override("font_size", 12)
	difficulty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_layout.add_child(difficulty_label)


# ------------------------------------------------------------
# PLACEHOLDER DIFFICULTY
# ------------------------------------------------------------

func _level_get_difficulty(number: int) -> String:
	if number <= 5:
		return "EASY"
	elif number <= 10:
		return "MEDIUM"
	elif number <= 15:
		return "HARD"
	else:
		return "EXTREME"


# ------------------------------------------------------------
# SELECT A LEVEL
# ------------------------------------------------------------

func _level_select(number: int) -> void:
	level_selected_number = number
	_level_update_details()


# ------------------------------------------------------------
# UPDATE LEVEL DETAILS
# ------------------------------------------------------------

func _level_update_details() -> void:
	if not is_instance_valid(level_details):
		return

	_clear_children(level_details)

	var image_path := _level_image_path(
		level_current_season,
		level_selected_number
	)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(280, 190)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	if ResourceLoader.exists(image_path):
		preview.texture = load(image_path)

	level_details.add_child(preview)

	var title := Label.new()
	title.text = "LEVEL " + str(level_selected_number)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	level_details.add_child(title)

	_level_add_detail("SEASON", level_current_season)
	_level_add_detail(
		"DIFFICULTY",
		_level_get_difficulty(level_selected_number)
	)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_details.add_child(spacer)

	var play_level_button := Button.new()
	play_level_button.text = "PLAY LEVEL"
	play_level_button.custom_minimum_size = Vector2(0, 55)
	play_level_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_level_button.pressed.connect(_level_play_pressed)
	level_details.add_child(play_level_button)


func _level_add_detail(detail_name: String, detail_value: String) -> void:
	var detail := Label.new()
	detail.text = detail_name + ": " + detail_value
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 17)
	level_details.add_child(detail)


# ------------------------------------------------------------
# PLAY SELECTED LEVEL
# ------------------------------------------------------------

func _level_play_pressed() -> void:
	print("Selected season: ", level_current_season)
	print("Selected level: ", level_selected_number)

	# Load the map and spawn the trolley applied in the Garage.
	start_game()


# ------------------------------------------------------------
# CLOSE LEVEL SELECT
# ------------------------------------------------------------

func hide_level_select() -> void:
	if is_instance_valid(level_select_panel):
		level_select_panel.queue_free()
		level_select_panel = null

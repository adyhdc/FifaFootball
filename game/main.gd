extends Node

const Game = preload("res://game/match.gd")
const Stadium = preload("res://game/stadium.gd")
const Rules = preload("res://game/rules.gd")
const NAMES := ["SV Hafenstrom", "Rotfalken 05"]
const CODES := ["HAF", "ROT"]
const ACCENT := Color("#e8ff71")
const PAPER := Color("#eaf4f5")
const MUTED := Color("#9db3c6")
const INK := Color("#101d30")
const CONTROLS := [
	["Laufen / zielen", "Linker Stick", "WASD / Pfeile"],
	["Kurzpass", "✕  Kreuz", "J"],
	["Steilpass", "△  Dreieck", "I"],
	["Schuss (halten für Kraft)", "◯  Kreis", "K"],
	["Sprint", "R2", "Umschalt"],
	["Zweikampf", "◯  Kreis / □ Quadrat", "Leertaste"],
	["Feldspieler wechseln", "L1", "Q"],
	["Pause", "Options", "Esc"]
]

enum Screen { TEAMS, GAME, PAUSE, CONTROLS, BREAK, RESULT }

var model := Game.new()
var stadium: Stadium
var screen := Screen.TEAMS
var controls_return := Screen.TEAMS
var layer: CanvasLayer
var root: Control
var overlay: Control
var board: PanelContainer
var home_score: Label
var away_score: Label
var game_clock: Label
var bottom: Label
var banner: Label
var banner_panel: PanelContainer
var power_meter: ProgressBar
var team_button: Button
var charge := 0.0
var charging := false
var playing_half := 0
var map_board: Control

class Radar extends Control:
	var model: RefCounted
	func _draw() -> void:
		var field := Rect2(0, 0, 164, 99)
		draw_style_box(minimap_style(), field)
		var inner := field.grow(-7)
		var white := Color("#7a9fa6")
		draw_rect(inner, white, false, 1)
		draw_line(Vector2(82, 7), Vector2(82, 92), white)
		draw_arc(field.get_center(), 13, 0, TAU, 20, white)
		for id in range(10):
			var p: Vector2 = model.players[id].point
			var location := field.get_center() + Vector2(p.x / Rules.HALF_LENGTH * 74, p.y / Rules.HALF_WIDTH * 41)
			draw_circle(location, 3.0, Stadium.KITS[model.players[id].team])
			if id == model.selected:
				draw_arc(location, 5.2, 0, TAU, 12, ACCENT, 1.3, true)
		var ball: Vector2 = model.ball
		draw_circle(field.get_center() + Vector2(ball.x / Rules.HALF_LENGTH * 74, ball.y / Rules.HALF_WIDTH * 41), 2.3, Color.WHITE)
	func minimap_style() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.08, 0.14, 0.86)
		style.set_corner_radius_all(8)
		return style

func _ready() -> void:
	configure_input()
	stadium = Stadium.new()
	add_child(stadium)
	layer = CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	build_hud()
	show_teams()
	if "--smoke" in OS.get_cmdline_user_args():
		run_smoke.call_deferred()

func _process(delta: float) -> void:
	stadium.update_view(model, delta, screen == Screen.TEAMS or (screen == Screen.CONTROLS and controls_return == Screen.TEAMS))
	if screen == Screen.GAME:
		update_hud()

func _physics_process(delta: float) -> void:
	if screen != Screen.GAME:
		return
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.19)
	var action := ""
	var can_shoot := model.owner == model.selected or (model.phase == Game.Phase.RESTART and model.restart_team == model.human)
	if Input.is_action_just_pressed("shoot"):
		if can_shoot:
			charge = 0.0
			charging = true
		else:
			action = "tackle"
	if charging:
		charge = minf(1.0, charge + delta * 1.85)
		if Input.is_action_just_released("shoot"):
			action = "shot"
			charging = false
		if not can_shoot:
			charging = false
	if Input.is_action_just_pressed("pass"):
		action = "pass"
	elif Input.is_action_just_pressed("through"):
		action = "through"
	elif Input.is_action_just_pressed("tackle"):
		action = "tackle"
	model.tick(delta, {"move": move, "action": action, "power": maxf(charge, 0.24),
		"sprint": Input.is_action_pressed("sprint"), "switch": Input.is_action_just_pressed("switch")})
	if model.phase == Game.Phase.HALF_TIME:
		show_break()
	elif model.phase == Game.Phase.FULL_TIME:
		show_result()

func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if screen == Screen.GAME and (event.is_action("pause") or event.is_action("ui_cancel")):
		show_pause()
		get_viewport().set_input_as_handled()
	elif screen == Screen.PAUSE and (event.is_action("pause") or event.is_action("ui_cancel")):
		show_game()
		get_viewport().set_input_as_handled()
	elif screen == Screen.CONTROLS and event.is_action("ui_cancel"):
		close_controls()
		get_viewport().set_input_as_handled()

func configure_input() -> void:
	bind("move_left", [KEY_A, KEY_LEFT], [], [Vector2(JOY_AXIS_LEFT_X, -1)])
	bind("move_right", [KEY_D, KEY_RIGHT], [], [Vector2(JOY_AXIS_LEFT_X, 1)])
	bind("move_up", [KEY_W, KEY_UP], [], [Vector2(JOY_AXIS_LEFT_Y, -1)])
	bind("move_down", [KEY_S, KEY_DOWN], [], [Vector2(JOY_AXIS_LEFT_Y, 1)])
	bind("pass", [KEY_J], [JOY_BUTTON_A])
	bind("through", [KEY_I], [JOY_BUTTON_Y])
	bind("shoot", [KEY_K], [JOY_BUTTON_B])
	bind("tackle", [KEY_SPACE], [JOY_BUTTON_X])
	bind("sprint", [KEY_SHIFT], [], [Vector2(JOY_AXIS_TRIGGER_RIGHT, 1)])
	bind("switch", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	bind("pause", [KEY_ESCAPE], [JOY_BUTTON_START])
	bind("ui_accept", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A])
	bind("ui_cancel", [KEY_ESCAPE], [JOY_BUTTON_B])
	bind("ui_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [Vector2(JOY_AXIS_LEFT_Y, -1)])
	bind("ui_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [Vector2(JOY_AXIS_LEFT_Y, 1)])
	bind("ui_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [Vector2(JOY_AXIS_LEFT_X, -1)])
	bind("ui_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [Vector2(JOY_AXIS_LEFT_X, 1)])

func bind(action: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.22)
	else:
		InputMap.action_erase_events(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	for index in buttons:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = index
		InputMap.action_add_event(action, event)
	for axis in axes:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = int(axis.x)
		event.axis_value = axis.y
		InputMap.action_add_event(action, event)

func show_teams() -> void:
	var column := open_panel(Screen.TEAMS, Vector2(58, 72), Vector2(552, 575))
	heading(column, "ANSTOSS  /  WINDOWS-ALPHA", "TOUCHLINE 5", "Flutlicht im Dockpark")
	var intro := make_label("Wähle deinen Verein. Die KI übernimmt das andere Team.", 17, MUTED)
	column.add_child(intro)
	team_button = add_button(column, "  01    SV Hafenstrom", Stadium.KITS[0], start_match.bind(0))
	add_button(column, "  02    Rotfalken 05", Stadium.KITS[1], start_match.bind(1))
	add_button(column, "  Steuerung", PAPER, show_controls.bind(Screen.TEAMS))
	add_button(column, "  Spiel verlassen", MUTED, get_tree().quit)
	column.add_child(make_label("5 GEGEN 5    /    2 × 3 MIN    /    v0.1.0-alpha.1", 15, ACCENT))
	team_button.grab_focus()

func start_match(team: int) -> void:
	model.reset(team)
	show_game()

func show_game() -> void:
	set_screen(Screen.GAME)
	playing_half = model.half
	update_hud()

func show_pause() -> void:
	var column := open_panel(Screen.PAUSE, Vector2(390, 164), Vector2(500, 392))
	heading(column, "DOCKPARK  /  SPIELMENÜ", "Pause", "Das Spiel ist angehalten.")
	var button := add_button(column, "  Weiterspielen", ACCENT, show_game)
	add_button(column, "  Steuerung", PAPER, show_controls.bind(Screen.PAUSE))
	add_button(column, "  Zur Teamauswahl", MUTED, show_teams)
	button.grab_focus()

func show_break() -> void:
	var column := open_panel(Screen.BREAK, Vector2(390, 180), Vector2(500, 350))
	heading(column, "45:00  /  SEITENWECHSEL", "Halbzeit", scoreline())
	var button := add_button(column, "  2. Halbzeit starten", ACCENT, resume_second_half)
	add_button(column, "  Zur Teamauswahl", MUTED, show_teams)
	button.grab_focus()

func resume_second_half() -> void:
	model.second_half()
	show_game()

func show_result() -> void:
	var column := open_panel(Screen.RESULT, Vector2(390, 173), Vector2(500, 375))
	var result := "Unentschieden"
	if model.score[0] != model.score[1]:
		var winner := 0 if model.score[0] > model.score[1] else 1
		result = NAMES[winner] + " gewinnt"
	heading(column, "90:00  /  ABPFIFF", scoreline(), result)
	var button := add_button(column, "  Revanche", ACCENT, start_match.bind(model.human))
	add_button(column, "  Zur Teamauswahl", MUTED, show_teams)
	button.grab_focus()

func scoreline() -> String:
	return "%s   %d : %d   %s" % [CODES[0], model.score[0], model.score[1], CODES[1]]

func show_controls(return_to: int) -> void:
	controls_return = return_to
	var column := open_panel(Screen.CONTROLS, Vector2(300, 58), Vector2(680, 602))
	heading(column, "DUALSENSE (USB)  /  TASTATUR", "Steuerung", "Menü: Stick oder Steuerkreuz · Kreuz bestätigt · Kreis geht zurück")
	var table := GridContainer.new()
	table.columns = 3
	table.add_theme_constant_override("h_separation", 22)
	table.add_theme_constant_override("v_separation", 8)
	column.add_child(table)
	for row in CONTROLS:
		for index in range(3):
			var label := make_label(row[index], 17, PAPER if index == 0 else MUTED)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			table.add_child(label)
	var button := add_button(column, "  Zurück", ACCENT, close_controls)
	button.grab_focus()

func close_controls() -> void:
	if controls_return == Screen.PAUSE:
		show_pause()
	else:
		show_teams()

func set_screen(value: int) -> void:
	screen = value
	charging = false
	charge = 0.0
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
		overlay = null
	board.visible = screen == Screen.GAME
	bottom.visible = board.visible
	map_board.visible = board.visible
	banner_panel.visible = false
	power_meter.visible = false

func open_panel(value: int, at: Vector2, dimensions: Vector2) -> VBoxContainer:
	set_screen(value)
	overlay = Control.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fade := ColorRect.new()
	fade.color = Color(0.021, 0.04, 0.085, 0.34 if value == Screen.TEAMS else 0.64)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(fade)
	var panel := PanelContainer.new()
	panel.position = at
	panel.custom_minimum_size = dimensions
	panel.add_theme_stylebox_override("panel", style(Color(0.040, 0.080, 0.14, 0.97), Color("#36546b"), 18, 28))
	overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	panel.add_child(column)
	return column

func heading(column: VBoxContainer, kicker: String, title: String, subtitle: String) -> void:
	column.add_child(make_label(kicker, 15, ACCENT))
	column.add_child(make_label(title, 53, PAPER))
	column.add_child(make_label(subtitle, 20, MUTED))
	var rule := ColorRect.new()
	rule.color = Color("#38516b")
	rule.custom_minimum_size.y = 2
	column.add_child(rule)

func add_button(column: VBoxContainer, title: String, tint: Color, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 49
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_focus_color", ACCENT)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_stylebox_override("normal", style(Color("#142942"), Color("#32506c"), 9, 6))
	button.add_theme_stylebox_override("hover", style(Color("#233e57"), tint, 9, 6))
	button.add_theme_stylebox_override("pressed", style(Color("#30546a"), ACCENT, 9, 6))
	button.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), ACCENT, 9, 6))
	button.pressed.connect(callback)
	column.add_child(button)
	return button

func build_hud() -> void:
	board = PanelContainer.new()
	board.position = Vector2(34, 29)
	board.add_theme_stylebox_override("panel", style(INK, Color("#526a80"), 10, 11))
	root.add_child(board)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	board.add_child(row)
	home_score = make_label("", 25, Stadium.KITS[0])
	away_score = make_label("", 25, Stadium.KITS[1])
	game_clock = make_label("", 19, PAPER)
	row.add_child(home_score)
	row.add_child(make_label(":", 21, MUTED))
	row.add_child(away_score)
	row.add_child(game_clock)

	banner_panel = PanelContainer.new()
	banner_panel.position = Vector2(400, 82)
	banner_panel.custom_minimum_size.x = 480
	banner_panel.add_theme_stylebox_override("panel", style(INK, Color("#526a80"), 9, 9))
	root.add_child(banner_panel)
	banner = make_label("", 20, ACCENT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_panel.add_child(banner)

	bottom = make_label("", 16, PAPER)
	bottom.position = Vector2(35, 675)
	bottom.add_theme_color_override("font_shadow_color", Color("#0a1425"))
	bottom.add_theme_constant_override("shadow_outline_size", 4)
	root.add_child(bottom)
	power_meter = ProgressBar.new()
	power_meter.position = Vector2(35, 649)
	power_meter.size = Vector2(198, 12)
	power_meter.show_percentage = false
	power_meter.add_theme_stylebox_override("background", style(INK, INK, 4, 1))
	power_meter.add_theme_stylebox_override("fill", style(ACCENT, ACCENT, 4, 1))
	root.add_child(power_meter)
	map_board = Radar.new()
	map_board.model = model
	map_board.position = Vector2(1082, 586)
	map_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_board)

func update_hud() -> void:
	home_score.text = "%s  %d" % [CODES[0], model.score[0]]
	away_score.text = "%d  %s" % [model.score[1], CODES[1]]
	var seconds := floori((Game.HALF_SECONDS - model.remaining) * 15.0) + (playing_half - 1) * 2700
	game_clock.text = "  %d. HZ  %02d:%02d" % [playing_half, floori(seconds / 60.0), seconds % 60]
	bottom.text = "%s   •   %s" % [CODES[model.human], "L1 / Q  Wechsel     Options / Esc  Pause"]
	if model.phase == Game.Phase.RESTART:
		banner.text = "%s  ·  %s" % [model.notice, CODES[model.restart_team]]
		if model.restart_team == model.human:
			bottom.text = "SPIELFORTSETZUNG   /   Kreuz oder J: Pass   ·   Kreis oder K: Schuss"
	else:
		banner.text = model.notice
	banner_panel.visible = not banner.text.is_empty()
	power_meter.visible = charging
	power_meter.value = charge * 100
	map_board.queue_redraw()

func make_label(words: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label

func style(fill: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, padding)
	return box

func run_smoke() -> void:
	Input.use_accumulated_input = false
	await get_tree().process_frame
	if screen != Screen.TEAMS or not team_button.has_focus() or stadium.athletes.size() != 10:
		push_error("Team selection or stadium failed to initialise.")
		get_tree().quit(1)
		return
	simulate_button(JOY_BUTTON_A, true)
	await get_tree().process_frame
	simulate_button(JOY_BUTTON_A, false)
	for frame in range(120):
		if screen == Screen.GAME and model.delay < 0.28:
			break
		await get_tree().physics_frame
	if screen != Screen.GAME or model.delay >= 0.3:
		push_error("Gamepad confirmation did not start the match.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	simulate_button(JOY_BUTTON_A, true)
	for frame in range(6):
		if model.phase == Game.Phase.PLAY:
			break
		await get_tree().physics_frame
	simulate_button(JOY_BUTTON_A, false)
	if screen != Screen.GAME or not board.visible or model.phase != Game.Phase.PLAY:
		push_error("Could not play the opening kick.")
		get_tree().quit(1)
		return
	print("TOUCHLINE_SMOKE_OK")
	if stadium.crowd != null:
		stadium.crowd.stop()
		stadium.whistle.stop()
		stadium.impact.stop()
		await get_tree().create_timer(0.1).timeout
	get_tree().quit()

func simulate_button(index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)

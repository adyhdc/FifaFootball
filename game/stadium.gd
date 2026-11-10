extends Node3D

const Rules = preload("res://game/rules.gd")
const Match = preload("res://game/match.gd")
const KITS := [Color("#16d0ca"), Color("#ff6450")]
const TRIM := [Color("#103c58"), Color("#671c38")]
const SKIN := [Color("#b97654"), Color("#e7ae82"), Color("#774835"), Color("#f2bd92"), Color("#ac705b")]
const HAIR := [Color("#27232e"), Color("#3f2927"), Color("#161d23"), Color("#62453b"), Color("#232330")]

var camera: Camera3D
var athletes: Array[Node3D] = []
var legs: Array[Array] = []
var arms: Array[Array] = []
var athlete_shadows: Array[Node3D] = []
var strides: Array[float] = []
var ball_mesh: Node3D
var ball_shadow: Node3D
var cursor: Node3D
var pitch_focus := Vector3.ZERO
var whistle: AudioStreamPlayer
var impact: AudioStreamPlayer
var crowd: AudioStreamPlayer
var last_signal := 0
var previous_touch := -1
var previous_owner := -1

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111c38")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c8d6ff")
	environment.ambient_light_energy = 0.76
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62, -37, 0)
	key.light_color = Color("#fff2ce")
	key.light_energy = 1.11
	add_child(key)
	camera = Camera3D.new()
	camera.fov = 45
	camera.current = true
	add_child(camera)
	build_pitch()
	build_stands()
	build_goals()
	for id in range(10):
		build_player(id)
	build_ball()
	build_cursor()
	if DisplayServer.get_name() != "headless":
		whistle = audio_player(make_audio("whistle"), -17.0)
		impact = audio_player(make_audio("kick"), -17.0)
		crowd = audio_player(make_audio("crowd"), -24.0)
		crowd.play()

func build_pitch() -> void:
	box(self, Vector3(0, -0.28, 0), Vector3(65, 0.46, 44), material("#16594b"))
	for strip in range(10):
		var shade := "#258251" if strip % 2 == 0 else "#2d8e55"
		box(self, Vector3(-23.4 + 5.2 * strip, -0.06, 0), Vector3(5.2, 0.12, 32), material(shade))
	var paint := material("#e4f1c8", true)
	var half_x := Rules.HALF_LENGTH
	var half_z := Rules.HALF_WIDTH
	for z in [-half_z, half_z]:
		line(Vector2(-half_x, z), Vector2(half_x, z), paint)
	for x in [-half_x, 0.0, half_x]:
		line(Vector2(x, -half_z), Vector2(x, half_z), paint)
	arc(Vector2.ZERO, 4.3, 0, TAU, paint)
	spot(Vector2.ZERO, paint)
	for side in [-1.0, 1.0]:
		var edge: float = side * half_x
		var box_x: float = side * (half_x - Rules.BOX_DEPTH)
		var small_x: float = side * (half_x - 3.3)
		line(Vector2(box_x, -Rules.BOX_HALF), Vector2(box_x, Rules.BOX_HALF), paint)
		line(Vector2(small_x, -4.5), Vector2(small_x, 4.5), paint)
		for z in [-1.0, 1.0]:
			line(Vector2(box_x, z * Rules.BOX_HALF), Vector2(edge, z * Rules.BOX_HALF), paint)
			line(Vector2(small_x, z * 4.5), Vector2(edge, z * 4.5), paint)
			var flag_spot := Vector3(edge, 0, z * half_z)
			box(self, flag_spot + Vector3(0, 0.66, 0), Vector3(0.06, 1.32, 0.06), paint)
			box(self, flag_spot + Vector3(0.20, 1.17, 0), Vector3(0.40, 0.28, 0.07), material("#ffb943", true))
		spot(Vector2(side * (half_x - 5.9), 0), paint)

func build_stands() -> void:
	var concrete := material("#293953")
	var step_trim := material("#55657d")
	var walls := material("#101e33")
	var gold := material("#ddff6e", true)
	var advertisement := material("#1c3047", true)
	var random := RandomNumberGenerator.new()
	random.seed = 53681
	var people: Array[Transform3D] = []
	var colors: Array[Color] = []
	for row in range(6):
		var height := 0.4 + 0.76 * row
		var z := -22.0 - row * 1.3
		box(self, Vector3(0, height * 0.5 - 0.1, z), Vector3(69, height + 0.3, 1.33), concrete)
		box(self, Vector3(0, height + 0.05, z + 0.61), Vector3(69, 0.13, 0.10), step_trim)
		for column in range(84):
			if (column % 21) in [0, 1, 2] or random.randf() < 0.15:
				continue
			var position := Vector3(-33.3 + column * 0.8, height + 0.47, z)
			people.append(Transform3D(Basis.IDENTITY, position))
			colors.append([Color("#314d73"), Color("#8caaaf"), Color("#357f87"), Color("#c89079"), Color("#d0b658")][random.randi_range(0, 4)])
		for side in [-1.0, 1.0]:
			var x: float = side * (33.1 + row * 1.23)
			box(self, Vector3(x, height * 0.5 - 0.1, 0), Vector3(1.27, height + 0.3, 43), concrete)
			for column in range(45):
				if (column % 15) in [0, 1] or random.randf() < 0.27:
					continue
				people.append(Transform3D(Basis.IDENTITY, Vector3(x, height + 0.46, -20.5 + column * 0.94)))
				colors.append([Color("#558eac"), Color("#c48368"), Color("#4b587d")][random.randi_range(0, 2)])
	var audience := MultiMesh.new()
	audience.transform_format = MultiMesh.TRANSFORM_3D
	audience.use_colors = true
	var silhouette := CapsuleMesh.new()
	silhouette.radius = 0.23
	silhouette.height = 0.73
	silhouette.radial_segments = 6
	silhouette.rings = 2
	var audience_material := material("#ffffff")
	audience_material.vertex_color_use_as_albedo = true
	silhouette.material = audience_material
	audience.mesh = silhouette
	audience.instance_count = people.size()
	for id in range(people.size()):
		audience.set_instance_transform(id, people[id])
		audience.set_instance_color(id, colors[id])
	var audience_node := MultiMeshInstance3D.new()
	audience_node.multimesh = audience
	add_child(audience_node)

	box(self, Vector3(0, 5.25, -29.3), Vector3(79, 1.5, 0.65), walls)
	box(self, Vector3(0, 5.95, -29.3), Vector3(79, 0.16, 0.8), gold)
	for side in [-1.0, 1.0]:
		box(self, Vector3(side * 40.15, 5.25, 0), Vector3(0.65, 1.5, 58), walls)
		box(self, Vector3(side * 40.15, 5.95, 0), Vector3(0.8, 0.16, 58), gold)
		for z in [-23.0, 19.5]:
			var x: float = side * 30.5
			box(self, Vector3(x, 5.8, z), Vector3(0.32, 11.6, 0.32), step_trim)
			box(self, Vector3(x, 11.65, z), Vector3(4.0, 1.35, 0.4), walls)
			for lamp in range(6):
				box(self, Vector3(x - 1.56 + lamp * 0.62, 11.65, z + 0.24), Vector3(0.48, 0.86, 0.11), material("#fff1be", true))
			var light := OmniLight3D.new()
			light.position = Vector3(x, 10.8, z)
			light.omni_range = 30
			light.light_energy = 1.55
			light.light_color = Color("#c0d7ff")
			add_child(light)
	for i in range(9):
		var x := -25.6 + i * 6.4
		box(self, Vector3(x, 0.52, -19.45), Vector3(6.23, 1.03, 0.26), advertisement)
		box(self, Vector3(x, 0.99, -19.29), Vector3(6.05, 0.06, 0.05), gold)
		signboard(Vector3(x, 0.5, -19.29), ["NACHTLIGA", "TOUCHLINE 5", "FLUTLICHT"][i % 3], 0.008)

func signboard(at: Vector3, words: String, scale_factor: float) -> void:
	var text := Label3D.new()
	text.text = words
	text.position = at
	text.font_size = 48
	text.pixel_size = scale_factor
	text.outline_size = 0
	text.modulate = Color("#e0f5f9")
	add_child(text)

func build_goals() -> void:
	var frame := material("#e7f5f8", true)
	var net := material("#7eaaa9", true)
	for side in [-1.0, 1.0]:
		var x: float = side * Rules.HALF_LENGTH
		var back: float = x + side * 2.0
		box(self, Vector3(x, Rules.BAR, 0), Vector3(0.12, 0.12, Rules.GOAL_HALF * 2 + 0.1), frame)
		for z in [-Rules.GOAL_HALF, Rules.GOAL_HALF]:
			box(self, Vector3(x, Rules.BAR / 2, z), Vector3(0.12, Rules.BAR, 0.12), frame)
			box(self, Vector3(back, Rules.BAR / 2, z), Vector3(0.06, Rules.BAR, 0.06), net)
			box(self, Vector3((x + back) / 2, Rules.BAR, z), Vector3(2.0, 0.05, 0.05), frame)
			for i in range(5):
				box(self, Vector3((x + back) / 2, 0.14 + i * 0.50, z), Vector3(2.0, 0.022, 0.022), net)
		for i in range(17):
			var z := -Rules.GOAL_HALF + i * Rules.GOAL_HALF / 8
			box(self, Vector3(back, Rules.BAR / 2, z), Vector3(0.021, Rules.BAR, 0.021), net)
			box(self, Vector3((x + back) / 2, Rules.BAR, z), Vector3(2, 0.021, 0.021), net)
		for i in range(6):
			box(self, Vector3(back, i * Rules.BAR / 5, 0), Vector3(0.021, 0.021, Rules.GOAL_HALF * 2), net)

func build_player(id: int) -> void:
	var team := floori(id / 5.0)
	var slot := id % 5
	var kit := material(KITS[team])
	var shorts := material(TRIM[team])
	if slot == 0:
		kit = material("#ffd047" if team == 0 else "#9e8af7")
	var skin := material(SKIN[(slot + team * 2) % 5])
	var hair := material(HAIR[(slot + team * 2) % 5])
	var boots := material("#131b2b")
	var white := material("#d6e8ea")
	var root := Node3D.new()
	add_child(root)
	athletes.append(root)
	athlete_shadows.append(shadow(0.58, 0.38))
	strides.append(0.0)
	var torso := box(root, Vector3(0, 1.28, 0), Vector3(0.62, 0.58, 0.35), kit)
	torso.rotation.x = 0.07
	box(root, Vector3(0, 1.49, 0.184), Vector3(0.62, 0.09, 0.027), shorts)
	box(root, Vector3(0, 0.92, 0), Vector3(0.56, 0.21, 0.32), shorts)
	sphere(root, Vector3(0, 1.77, 0.025), 0.22, skin)
	var cap := sphere(root, Vector3(0, 1.88, -0.032), 0.196, hair)
	cap.scale = Vector3(1.03, 0.7, 1)
	for x in [-0.071, 0.071]:
		sphere(root, Vector3(x, 1.80, 0.223), 0.024, boots)
	var pair: Array[Node3D] = []
	var arm_pair: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.16, 0.87, 0)
		root.add_child(leg)
		box(leg, Vector3(0, -0.15, 0), Vector3(0.23, 0.34, 0.25), shorts)
		box(leg, Vector3(0, -0.36, 0), Vector3(0.19, 0.20, 0.20), skin)
		box(leg, Vector3(0, -0.55, 0), Vector3(0.19, 0.27, 0.20), kit)
		box(leg, Vector3(0, -0.74, 0.075), Vector3(0.22, 0.15, 0.34), boots)
		pair.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.39, 1.45, 0)
		arm.rotation.z = side * 0.17
		root.add_child(arm)
		box(arm, Vector3(0, -0.10, 0), Vector3(0.20, 0.23, 0.23), kit)
		box(arm, Vector3(0, -0.31, 0.025), Vector3(0.15, 0.29, 0.15), skin)
		sphere(arm, Vector3(0, -0.49, 0.045), 0.088, white if slot == 0 else skin)
		arm_pair.append(arm)
	legs.append(pair)
	arms.append(arm_pair)

func build_ball() -> void:
	ball_mesh = Node3D.new()
	add_child(ball_mesh)
	sphere(ball_mesh, Vector3.ZERO, Rules.BALL_RADIUS, material("#f8fae5", true))
	var panel := material("#29324f", true)
	for normal in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		sphere(ball_mesh, normal * 0.193, 0.061, panel)
	ball_shadow = shadow(0.29, 0.29)

func build_cursor() -> void:
	cursor = Node3D.new()
	add_child(cursor)
	var lime := material("#f1ff66", true)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.62
	ring.outer_radius = 0.72
	ring.rings = 20
	ring.ring_segments = 8
	mesh_at(cursor, ring, Vector3(0, 0.028, 0), lime)
	var marker := CylinderMesh.new()
	marker.top_radius = 0.17
	marker.bottom_radius = 0.0
	marker.height = 0.28
	marker.radial_segments = 5
	mesh_at(cursor, marker, Vector3(0, 2.27, 0), lime)

func update_view(match_state: RefCounted, delta: float, in_menu: bool) -> void:
	for id in range(10):
		var player: Match.Footballer = match_state.players[id]
		var body := athletes[id]
		body.position = Vector3(player.point.x, 0, player.point.y)
		athlete_shadows[id].position = Vector3(player.point.x, 0.013, player.point.y)
		var facing := atan2(player.facing.x, player.facing.y)
		body.rotation.y = lerp_angle(body.rotation.y, facing, minf(delta * 18, 1))
		var speed := player.velocity.length()
		if not in_menu and match_state.phase == Match.Phase.PLAY:
			strides[id] += delta * (5.0 + speed * 1.45)
		var stride := sin(strides[id]) * minf(speed * 0.092, 0.78)
		body.position.y = absf(stride) * 0.08
		legs[id][0].rotation.x = stride
		legs[id][1].rotation.x = -stride
		arms[id][0].rotation.x = -stride * 0.69
		arms[id][1].rotation.x = stride * 0.69
	var ball: Vector2 = match_state.ball
	ball_mesh.position = Vector3(ball.x, match_state.ball_height, ball.y)
	ball_shadow.position = Vector3(ball.x, 0.017, ball.y)
	var roll: Vector2 = match_state.ball_velocity
	ball_mesh.rotate_x(roll.y * delta / Rules.BALL_RADIUS)
	ball_mesh.rotate_z(-roll.x * delta / Rules.BALL_RADIUS)
	cursor.visible = not in_menu
	cursor.position = athletes[match_state.selected].position
	var focus := Vector3(clampf(ball.x * 0.39, -9, 9), 0, ball.y * 0.21)
	if in_menu:
		focus = Vector3(0, 0, -2)
	pitch_focus = pitch_focus.lerp(focus, minf(delta * 3.4, 1))
	camera.position = pitch_focus + Vector3(0, 27.4, 31.0)
	camera.look_at(pitch_focus + Vector3(0, 0, -1.3))
	if whistle == null:
		return
	if match_state.signal_count != last_signal:
		last_signal = match_state.signal_count
		if not in_menu:
			whistle.play()
	if match_state.last_touch != previous_touch or previous_owner != match_state.owner:
		if not in_menu and match_state.last_touch >= 0 and match_state.owner < 0:
			impact.play()
	previous_touch = match_state.last_touch
	previous_owner = match_state.owner

func material(tint: Color, luminous: bool = false) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tint
	paint.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	paint.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if luminous:
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return paint

func mesh_at(parent: Node3D, mesh: Mesh, at: Vector3, paint: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = paint
	parent.add_child(instance)
	instance.position = at
	return instance

func box(parent: Node3D, at: Vector3, dimensions: Vector3, paint: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return mesh_at(parent, mesh, at, paint)

func sphere(parent: Node3D, at: Vector3, radius: float, paint: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = 2 * radius
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh_at(parent, mesh, at, paint)

func line(a: Vector2, b: Vector2, paint: Material) -> void:
	var midpoint := (a + b) / 2
	var tile := box(self, Vector3(midpoint.x, 0.012, midpoint.y), Vector3(a.distance_to(b) + 0.04, 0.025, 0.09), paint)
	tile.rotation.y = -(b - a).angle()

func arc(center: Vector2, radius: float, start: float, finish: float, paint: Material) -> void:
	var previous := center + Vector2.from_angle(start) * radius
	for i in range(1, 49):
		var point := center + Vector2.from_angle(lerpf(start, finish, i / 48.0)) * radius
		line(previous, point, paint)
		previous = point

func spot(at: Vector2, paint: Material) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.12
	disc.bottom_radius = 0.12
	disc.height = 0.026
	mesh_at(self, disc, Vector3(at.x, 0.012, at.y), paint)

func shadow(x: float, z: float) -> MeshInstance3D:
	var paint := material(Color(0.024, 0.085, 0.073, 0.44), true)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.012
	disc.radial_segments = 16
	var shape := mesh_at(self, disc, Vector3.ZERO, paint)
	shape.scale = Vector3(x, 1, z)
	return shape

func audio_player(stream: AudioStreamWAV, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	return player

func make_audio(kind: String) -> AudioStreamWAV:
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 22050
	var duration := 1.6 if kind == "crowd" else (0.3 if kind == "whistle" else 0.09)
	var frames := int(audio.mix_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 16679
	var filtered := 0.0
	for i in range(frames):
		var time := float(i) / audio.mix_rate
		var value := 0.0
		match kind:
			"whistle":
				var gate := minf(1.0, time * 90) * minf(1.0, (duration - time) * 28)
				value = sin(TAU * 1910.0 * time + sin(TAU * 33 * time) * 0.45) * gate * 0.72
			"kick":
				value = (sin(TAU * 104.0 * time) * 0.5 + rng.randf_range(-0.5, 0.5)) * exp(-time * 43.0)
			"crowd":
				filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.064)
				value = filtered * (0.74 + 0.26 * sin(TAU * time / duration))
		bytes.encode_s16(i * 2, int(value * 32760))
	audio.data = bytes
	if kind == "crowd":
		audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
		audio.loop_end = frames
	return audio

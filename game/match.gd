extends RefCounted

const Rules = preload("res://game/rules.gd")
const R = Rules.Restart
const HALF_SECONDS := 180.0
const PLAYER_RADIUS := 0.45
const FORMATION := [Vector2(-23.7, 0), Vector2(-10, 0), Vector2(-4, -8),
	Vector2(-4, 8), Vector2(-1.6, 0)]

enum Phase { RESTART, PLAY, GOAL, HALF_TIME, FULL_TIME }

class Footballer:
	var point := Vector2.ZERO
	var velocity := Vector2.ZERO
	var facing := Vector2.RIGHT
	var team := 0
	var slot := 0
	var tackle_cooldown := 0.0

var players: Array[Footballer] = []
var score: Array[int] = [0, 0]
var human := 0
var selected := 4
var right_attack := 0
var half := 1
var remaining := HALF_SECONDS
var phase := Phase.RESTART
var notice := ""
var delay := 0.0
var restart := R.KICKOFF
var restart_team := 0
var taker := 4
var restart_ball := Vector2.ZERO
var restart_kicker := -1
var direct_restart := -1
var last_touch := -1
var owner := -1
var offside: Array[int] = []
var ball := Vector2.ZERO
var ball_velocity := Vector2.ZERO
var ball_height := Rules.BALL_RADIUS
var vertical_speed := 0.0
var pickup_delay := 0.0
var decision_delay := 0.0
var signal_count := 0
var input_receiver := -1

func _init() -> void:
	for id in range(10):
		var player := Footballer.new()
		player.team = id / 5
		player.slot = id % 5
		players.append(player)
	reset(0)

func reset(team: int) -> void:
	human = team
	selected = human * 5 + 4
	right_attack = 0
	half = 1
	remaining = HALF_SECONDS
	score = [0, 0]
	signal_count = 0
	for player in players:
		player.tackle_cooldown = 0.0
	place_restart(R.KICKOFF, 0, Vector2.ZERO, "Anstoß")

func direction(team: int) -> float:
	return 1.0 if team == right_attack else -1.0

func spots() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for player in players:
		result.append(player.point)
	return result

func place_restart(kind: int, team: int, spot: Vector2, message: String) -> void:
	phase = Phase.RESTART
	restart = kind
	restart_team = team
	restart_ball = spot
	notice = message
	signal_count += 1
	delay = 0.75
	ball = spot
	ball_velocity = Vector2.ZERO
	ball_height = Rules.BALL_RADIUS
	vertical_speed = 0.0
	owner = -1
	last_touch = -1
	restart_kicker = -1
	direct_restart = -1
	input_receiver = -1
	pickup_delay = 0.0
	decision_delay = 0.0
	offside.clear()
	for player in players:
		player.velocity = Vector2.ZERO
		if kind == R.KICKOFF or kind == R.PENALTY:
			player.point = FORMATION[player.slot] * direction(player.team)
			player.facing = Vector2(direction(player.team), 0)
	taker = nearest(team, spot, kind == R.GOAL_KICK)
	if kind == R.KICKOFF or kind == R.PENALTY:
		taker = team * 5 + 4
	if kind == R.GOAL_KICK:
		taker = team * 5
	if kind == R.PENALTY:
		players[(1 - team) * 5].point = Vector2(direction(team) * (Rules.HALF_LENGTH - 0.16), 0)
	var approach := Vector2(direction(team), 0)
	if kind == R.THROW_IN:
		approach = Vector2(0, -signf(spot.y))
	elif kind == R.CORNER:
		approach = -spot.normalized()
	players[taker].point = spot - approach * 0.7
	players[taker].facing = approach
	for id in range(10):
		if id == taker:
			continue
		var player := players[id]
		if kind == R.PENALTY:
			if id == (1 - team) * 5:
				continue
			var x_limit := Rules.HALF_LENGTH - Rules.BOX_DEPTH - 1.4
			player.point.x = minf(player.point.x * direction(team), x_limit) * direction(team)
		elif player.team != team and player.point.distance_to(spot) < 3.0:
			var side := 1.0 if kind == R.KICKOFF else -1.0
			player.point = clamp_pitch(spot + approach * (2.7 * side) + Vector2(0, 2.6 * signf(player.point.y - spot.y + 0.01)))
	if team == human and players[taker].slot != 0:
		selected = taker

func nearest(team: int, point: Vector2, include_keeper: bool = false, exclude: int = -1) -> int:
	var best := -1
	var distance := INF
	for id in range(team * 5 + (0 if include_keeper else 1), team * 5 + 5):
		var candidate := players[id].point.distance_squared_to(point)
		if id != exclude and candidate < distance:
			best = id
			distance = candidate
	return best

func switch_player() -> void:
	if owner >= 0 and players[owner].team == human and owner != selected and players[owner].slot != 0:
		selected = owner
		return
	var candidates: Array[int] = []
	for id in range(human * 5 + 1, human * 5 + 5):
		candidates.append(id)
	var target := ball + ball_velocity * 0.15
	candidates.sort_custom(func(a: int, b: int) -> bool:
		return players[a].point.distance_squared_to(target) < players[b].point.distance_squared_to(target))
	selected = candidates[(candidates.find(selected) + 1) % candidates.size()]

func tick(delta: float, command: Dictionary = {}) -> void:
	var move: Vector2 = command.get("move", Vector2.ZERO)
	var action: String = command.get("action", "")
	var power: float = command.get("power", 0.55)
	match phase:
		Phase.FULL_TIME, Phase.HALF_TIME:
			return
		Phase.GOAL:
			delay -= delta
			if delay <= 0:
				place_restart(R.KICKOFF, restart_team, Vector2.ZERO, "Anstoß")
			return
		Phase.RESTART:
			delay = maxf(0, delay - delta)
			if move.length_squared() > 0.09 and restart_team == human:
				players[taker].facing = move.normalized()
			if restart_team != human:
				if delay <= 0:
					take_restart("shot" if restart == R.PENALTY else "pass", Vector2.ZERO, 0.75)
			elif action in ["pass", "through", "shot"] and delay <= 0.3:
				take_restart(action, move, power)
			return
	remaining = maxf(remaining - delta, 0)
	if remaining <= 0:
		finish_half()
		return

	if command.get("switch", false):
		switch_player()
	pickup_delay = maxf(0, pickup_delay - delta)
	decision_delay = maxf(0, decision_delay - delta)
	var manual := owner == selected
	if manual and action in ["pass", "through", "shot"]:
		kick_action(selected, action, move, power)
	move_players(delta, move, command.get("sprint", false))
	if action == "tackle":
		attempt_tackle(selected)
	if phase != Phase.PLAY:
		return
	ai_actions()
	if phase != Phase.PLAY:
		return
	step_ball(delta)

func finish_half() -> void:
	phase = Phase.HALF_TIME if half == 1 else Phase.FULL_TIME
	notice = "Halbzeit" if half == 1 else "Abpfiff"
	offside.clear()
	signal_count += 1

func second_half() -> void:
	if phase != Phase.HALF_TIME:
		return
	half = 2
	right_attack = 1 - right_attack
	remaining = HALF_SECONDS
	for player in players:
		player.tackle_cooldown = 0.0
	place_restart(R.KICKOFF, 1, Vector2.ZERO, "Anstoß · 2. Halbzeit")

func move_players(delta: float, move: Vector2, sprint: bool) -> void:
	var press_team := -1 if owner < 0 else 1 - players[owner].team
	var pressers := [nearest(0, ball), nearest(1, ball)]
	if owner < 0 and input_receiver >= 0:
		pressers[players[input_receiver].team] = input_receiver
	if press_team == human and pressers[human] == selected:
		pressers[human] = nearest(human, ball, false, selected) if players[selected].point.distance_to(ball) > 5.0 else -1
	for id in range(10):
		var player := players[id]
		player.tackle_cooldown = maxf(0, player.tackle_cooldown - delta)
		var desired := move
		var speed := 8.5 if sprint else 6.25
		if id == selected and id == input_receiver and move.is_zero_approx():
			var lead := ball + ball_velocity * 0.12
			if player.point.distance_to(lead) < 3.0:
				desired = (lead - player.point).limit_length(0.7)
		if id != selected:
			var team_presser: int = pressers[player.team]
			var target := ai_target(id, team_presser, press_team)
			desired = (target - player.point).limit_length(1.0)
			speed = 6.5 if id == owner or id == team_presser else 5.65
			if player.slot == 0:
				speed = 6.1
		if id == owner:
			speed *= 0.88
		player.velocity = player.velocity.move_toward(desired * speed, delta * 34.0)
		if player.velocity.length_squared() > 0.12:
			player.facing = player.velocity.normalized()
		player.point = clamp_pitch(player.point + player.velocity * delta)
	for a in range(10):
		for b in range(a + 1, 10):
			var difference := players[a].point - players[b].point
			var distance := difference.length()
			if distance > 0.001 and distance < 2.0 * PLAYER_RADIUS:
				var push := difference / distance * (2.0 * PLAYER_RADIUS - distance) * 0.5
				players[a].point = clamp_pitch(players[a].point + push)
				players[b].point = clamp_pitch(players[b].point - push)

func ai_target(id: int, presser: int, press_team: int) -> Vector2:
	var player := players[id]
	var dir := direction(player.team)
	var own_goal := Vector2(-dir * Rules.HALF_LENGTH, 0)
	var attack_goal := -own_goal
	var loose := owner < 0
	var possession := owner >= 0 and players[owner].team == player.team
	if player.slot == 0:
		if owner == id:
			return player.point
		var projected := ball + ball_velocity * 0.15
		var depth := dir * (ball.x - own_goal.x)
		if depth < 7.0 and absf(ball.y) < 6.4 and (loose or press_team == player.team):
			return own_goal + Vector2(dir * clampf(depth - 0.4, 0.65, 3.8), clampf(projected.y, -4.5, 4.5))
		return own_goal + Vector2(dir * clampf(depth * 0.07, 0.8, 2.8), clampf(projected.y * 0.36, -2.85, 2.85))
	if id == owner:
		var drive := player.point.direction_to(attack_goal)
		var defender := players[nearest(1 - player.team, player.point, true)]
		if defender.point.distance_to(player.point) < 3.5 and drive.dot(player.point.direction_to(defender.point)) > 0.45:
			drive = drive.rotated(0.65 * signf(player.point.y - defender.point.y + 0.01))
		return clamp_pitch(player.point + drive * 4.0)
	if id == input_receiver and loose:
		return clamp_pitch(ball + ball_velocity.limit_length(19.0) * 0.25)
	if id == presser and (loose or press_team == player.team):
		return clamp_pitch(ball + ball_velocity.limit_length(18.0) * 0.14)
	var shape: Vector2 = FORMATION[player.slot] * dir
	var shift := Vector2(ball.x * 0.51, ball.y * 0.31)
	if possession:
		var lane: float = FORMATION[player.slot].y * dir
		var depth := 6.6 if player.slot == 4 else (3.1 if player.slot != 1 else -5.4)
		var support := ball + Vector2(dir * depth, lane - ball.y * 0.32)
		# Time the forward run to stay near the second defender before the pass.
		var line: Array[float] = []
		for opponent in range((1 - player.team) * 5, (1 - player.team) * 5 + 5):
			line.append(players[opponent].point.x * dir)
		line.sort()
		support.x = minf(support.x * dir, maxf(ball.x * dir + 0.5, line[3] - 0.9)) * dir
		return clamp_pitch(support)
	return clamp_pitch(shape + shift - Vector2(dir * 2.5, 0))

func ai_actions() -> void:
	if owner < 0:
		return
	var player := players[owner]
	if owner != selected and decision_delay <= 0:
		var goal := Vector2(direction(player.team) * Rules.HALF_LENGTH, 0)
		var pressure := players[nearest(1 - player.team, player.point, true)].point.distance_to(player.point)
		if player.slot == 0:
			kick_action(owner, "pass", Vector2(direction(player.team), 0), 0.55)
			return
		if player.point.distance_to(goal) < 14.5 and absf(player.point.y) < 10.0:
			kick_action(owner, "shot", Vector2.ZERO, 0.66)
			return
		if pressure < 3.1:
			kick_action(owner, "pass", Vector2(direction(player.team), 0), 0.55)
			return
	var defender := nearest(1 - player.team, player.point)
	if defender != selected and players[defender].point.distance_to(player.point) < 1.32:
		attempt_tackle(defender)

func take_restart(action: String, aim: Vector2, power: float) -> void:
	phase = Phase.PLAY
	notice = ""
	direct_restart = restart
	restart_kicker = taker
	if restart == R.PENALTY and restart_team != human:
		aim = Vector2(direction(restart_team), 0.18)
	kick_action(taker, action, aim, power, restart)

func kick_action(id: int, action: String, aim: Vector2, power: float, from_restart: int = -1) -> void:
	var player := players[id]
	var dir := direction(player.team)
	var intended := aim.normalized() if aim.length_squared() > 0.09 else player.facing
	if action == "shot" and from_restart != R.THROW_IN:
		var target := Vector2(dir * (Rules.HALF_LENGTH + 0.6), clampf(intended.y * 2.5, -2.65, 2.65))
		var speed := lerpf(18.5, 35.0, power)
		var lift := lerpf(2.2, 5.1, power)
		strike(id, ball.direction_to(target), speed, lift, from_restart)
		return

	if from_restart == R.THROW_IN:
		intended.y = -signf(ball.y) * maxf(0.48, absf(intended.y))
		intended = intended.normalized()
	var teammate := pass_target(id, intended)
	var through := action == "through"
	var target := players[teammate].point + players[teammate].velocity * (0.18 if through else 0.08)
	if through:
		target = clamp_pitch(target + (intended + Vector2(dir, 0)).normalized() * 2.8)
	var distance := ball.distance_to(target)
	var speed := clampf(7.0 + distance * 0.75, 10.0, 23.5)
	var lift := 0.0
	if through:
		speed += 2.0
	if from_restart == R.THROW_IN:
		lift = 4.0
		ball_height = 1.65
		speed = clampf(speed, 7.5, 13.5)
	elif from_restart == R.CORNER:
		lift = 4.8
	elif from_restart == R.GOAL_KICK:
		lift = 2.9
	strike(id, ball.direction_to(target), speed, lift, from_restart)
	input_receiver = teammate
	if player.team == human and players[teammate].slot != 0:
		selected = teammate

func pass_target(id: int, aim: Vector2) -> int:
	var player := players[id]
	var best := -1
	var best_score := -INF
	for candidate in range(player.team * 5, player.team * 5 + 5):
		if candidate == id:
			continue
		var offset := players[candidate].point - ball
		var distance := offset.length()
		var cost := offset.normalized().dot(aim) * 7.8 - distance * 0.28
		if players[candidate].slot == 0:
			cost -= 4.6
		for defender in range((1 - player.team) * 5, (1 - player.team) * 5 + 5):
			var danger := players[defender].point
			var along := (danger - ball).dot(offset.normalized())
			if along > 0.8 and along < distance - 0.5:
				var clearance := danger.distance_to(ball + offset.normalized() * along)
				cost -= maxf(0, 1.65 - clearance) * 1.15
		if cost > best_score:
			best = candidate
			best_score = cost
	return best

func strike(id: int, aim: Vector2, speed: float, lift: float, from_restart: int = -1) -> void:
	var team := players[id].team
	offside = Rules.offside_ids(team, id, direction(team), ball, spots(), from_restart)
	ball_velocity = aim * speed
	vertical_speed = lift
	owner = -1
	last_touch = id
	input_receiver = -1
	pickup_delay = 0.19

func attempt_tackle(id: int) -> void:
	var player := players[id]
	if player.tackle_cooldown > 0:
		return
	player.tackle_cooldown = 0.55
	if owner < 0 or players[owner].team == player.team:
		return
	var victim := players[owner]
	var offset := victim.point - player.point
	if offset.length() > 1.46 or player.facing.dot(offset.normalized()) < -0.16:
		return
	if player.point.distance_to(ball) <= 1.30 and victim.facing.dot(offset.normalized()) < 0.47:
		touch(id)
	else:
		call_foul(id, victim.point)

func call_foul(id: int, spot: Vector2) -> void:
	var team := players[id].team
	var kind := Rules.foul_restart(spot, direction(team))
	var position := spot
	if kind == R.PENALTY:
		position = Vector2(-direction(team) * (Rules.HALF_LENGTH - 5.9), 0)
	place_restart(kind, 1 - team, position, "Foul · " + Rules.RESTART_NAMES[kind])

func step_ball(delta: float) -> void:
	var previous := ball
	var old_height := ball_height
	if owner >= 0:
		var player := players[owner]
		ball = player.point + player.facing * 0.64
		ball_height = Rules.BALL_RADIUS
	else:
		ball += ball_velocity * delta
		ball_velocity = ball_velocity.move_toward(Vector2.ZERO, delta * (0.8 if ball_height > 0.26 else 5.1))
		vertical_speed -= delta * 12.5
		ball_height += vertical_speed * delta
		if ball_height <= Rules.BALL_RADIUS:
			ball_height = Rules.BALL_RADIUS
			vertical_speed = -vertical_speed * 0.31 if vertical_speed < -1.7 else 0.0
	var team := players[last_touch].team if last_touch >= 0 else restart_team
	var exit := Rules.exit_event(previous, ball, old_height, ball_height, team, right_attack)
	if exit.has("goal"):
		var attacking: int = exit.goal
		if offside_obstruction(attacking, exit.side):
			return
		var direct_forbidden := direct_restart in [R.THROW_IN, R.INDIRECT]
		if direct_restart >= 0 and attacking != team:
			var corner := Vector2(exit.side * (Rules.HALF_LENGTH - 0.25), Rules.HALF_WIDTH - 0.25)
			place_restart(R.CORNER, attacking, corner, "Ecke")
		elif direct_forbidden:
			var spot := Vector2(exit.side * (Rules.HALF_LENGTH - 3.3), 0)
			place_restart(R.GOAL_KICK, 1 - attacking, spot, "Abstoß")
		else:
			score[attacking] += 1
			phase = Phase.GOAL
			restart_team = 1 - attacking
			notice = "TOR!"
			delay = 2.0
			signal_count += 1
		return
	if exit.has("restart"):
		place_restart(exit.restart, exit.team, exit.spot, Rules.RESTART_NAMES[exit.restart])
		return
	if owner >= 0:
		return

	var best := -1
	var closest := INF
	for id in range(10):
		if id == last_touch and pickup_delay > 0:
			continue
		var player := players[id]
		var keeper := player.slot == 0
		var distance := player.point.distance_to(ball)
		if distance < closest and distance < (1.20 if keeper else 0.76) and ball_height < (2.14 if keeper else 0.83):
			best = id
			closest = distance
	if best < 0:
		return
	var receiver := players[best]
	if last_touch >= 0 and receiver.team != players[last_touch].team:
		for id in offside:
			if players[id].point.distance_to(ball) < 1.35 and players[id].point.distance_to(receiver.point) < 1.5:
				call_offside(id)
				return
		if receiver.slot == 0 and is_on_target(receiver.team):
			if offside_obstruction(1 - receiver.team, -direction(receiver.team)):
				return
			if ball_velocity.length() > 20.0:
				# A save deflects a hard shot without resetting the offside snapshot.
				ball_velocity = Vector2(direction(receiver.team) * 6.5, signf(ball.y + 0.01) * 9.0)
				vertical_speed = 2.0
				last_touch = best
				direct_restart = -1
				restart_kicker = -1
				pickup_delay = 0.15
				return
	touch(best)

func is_on_target(defending_team: int) -> bool:
	var goal_x := -direction(defending_team) * Rules.HALF_LENGTH
	if absf(ball_velocity.x) < 0.1:
		return false
	var seconds := (goal_x - ball.x) / ball_velocity.x
	return seconds >= 0 and seconds < 0.7 and absf(ball.y + seconds * ball_velocity.y) < Rules.GOAL_HALF + 0.3

func offside_obstruction(attacking: int, side: float) -> bool:
	var goalkeeper := players[(1 - attacking) * 5].point
	for id in offside:
		var p := players[id].point
		if players[id].team == attacking and absf(p.y - ball.y) < 0.68 \
				and absf(p.y - goalkeeper.y) < 0.85 and (goalkeeper.x - p.x) * side > 0.0 \
				and goalkeeper.distance_to(p) < 3.2:
			call_offside(id)
			return true
	return false

func call_offside(id: int) -> void:
	place_restart(R.INDIRECT, 1 - players[id].team, players[id].point, "Abseits · Indirekter Freistoß")

func touch(id: int) -> void:
	if offside.has(id):
		call_offside(id)
		return
	var player := players[id]
	if id == restart_kicker:
		place_restart(R.INDIRECT, 1 - player.team, ball, "Doppelberührung · Indirekter Freistoß")
		return
	var same_team := last_touch >= 0 and players[last_touch].team == player.team
	if same_team:
		offside = Rules.offside_ids(player.team, id, direction(player.team), ball, spots())
	else:
		offside.clear()
	owner = id
	last_touch = id
	input_receiver = -1
	direct_restart = -1
	restart_kicker = -1
	ball_velocity = Vector2.ZERO
	vertical_speed = 0.0
	ball_height = Rules.BALL_RADIUS
	decision_delay = 0.35
	if player.team == human and player.slot != 0 and selected != id and same_team:
		selected = id

func clamp_pitch(point: Vector2) -> Vector2:
	return point.clamp(Vector2(-Rules.HALF_LENGTH + 0.2, -Rules.HALF_WIDTH + 0.2),
		Vector2(Rules.HALF_LENGTH - 0.2, Rules.HALF_WIDTH - 0.2))

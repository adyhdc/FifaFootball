extends SceneTree

const Game = preload("res://game/match.gd")
const Rules = preload("res://game/rules.gd")
const R = Rules.Restart
const STEP := 1.0 / 60.0

var cases := 0
var failures := 0

func _initialize() -> void:
	test_goals_and_lines()
	test_restarts_and_fouls()
	test_offside()
	test_controls_and_ai()
	test_open_play_shots()
	test_match_lifecycle()
	print("TOUCHLINE_RULES: %d checks, %d failures" % [cases, failures])
	quit(1 if failures else 0)

func check(condition: bool, label: String) -> void:
	cases += 1
	if not condition:
		failures += 1
		push_error(label)

func crossing(game: RefCounted, start: Vector2, velocity: Vector2, toucher: int, height := 0.23) -> void:
	game.phase = Game.Phase.PLAY
	game.owner = -1
	game.ball = start
	game.ball_velocity = velocity
	game.ball_height = height
	game.vertical_speed = 0.0
	game.last_touch = toucher
	game.step_ball(STEP)

func test_goals_and_lines() -> void:
	var game := Game.new()
	crossing(game, Vector2(25.99, 0), Vector2(8, 0), 4)
	check(game.score == [0, 0] and game.phase == Game.Phase.PLAY, "A partial crossing is still in play")
	crossing(game, Vector2(26.13, 0), Vector2(18, 0), 9)
	check(game.score == [1, 0] and game.phase == Game.Phase.GOAL, "Right-side own goal counts for the attacker")
	game.tick(2.1)
	check(game.restart == R.KICKOFF and game.restart_team == 1 and game.ball == Vector2.ZERO,
		"Conceding team restarts at the centre")
	crossing(game, Vector2(-26.0, 1.9), Vector2(-30, 0), 9)
	check(game.score == [1, 1], "Left-side goal")
	game.tick(2.1)
	crossing(game, Vector2(26.04, 0), Vector2(24, 0), 4, 2.6)
	check(game.score == [1, 1] and game.restart == R.GOAL_KICK and game.restart_team == 1, "Over the bar")
	crossing(game, Vector2(-26.1, 11), Vector2(-22, 0), 4)
	check(game.restart == R.CORNER and game.restart_team == 1 and game.ball.x < 0, "Corner off a defender")
	crossing(game, Vector2(13, 15.95), Vector2(3, 22), 4)
	check(game.restart == R.THROW_IN and game.restart_team == 1 and is_equal_approx(game.ball.y, 16),
		"Throw-in to the other team from the crossing")
	var event := Rules.exit_event(Vector2(26.02, 16.21), Vector2(26.7, 16.8), 0.3, 0.3, 0, 0)
	check(event.restart == R.THROW_IN, "Earliest crossing decides the restart at a corner")

func test_restarts_and_fouls() -> void:
	var game := Game.new()
	var kinds := [R.KICKOFF, R.THROW_IN, R.CORNER, R.GOAL_KICK, R.FREE_KICK, R.INDIRECT, R.PENALTY]
	var locations := [Vector2.ZERO, Vector2(4, 16), Vector2(25.75, 15.75), Vector2(-22.7, 0),
		Vector2(15, 3), Vector2(12, 2), Vector2(20.1, 0)]
	for index in range(kinds.size()):
		game.place_restart(kinds[index], 0, locations[index], "Test")
		game.tick(0.51, {"action": "shot" if kinds[index] == R.PENALTY else "pass"})
		check(game.phase == Game.Phase.PLAY and game.ball_velocity.length() > 0.0,
			"Human can take " + Rules.RESTART_NAMES[kinds[index]])
	game.place_restart(R.THROW_IN, 0, Vector2(25, 16), "Test")
	game.take_restart("pass", Vector2.ZERO, 0.5)
	crossing(game, Vector2(26.09, 0), Vector2(22, 0), 4)
	check(game.score == [0, 0] and game.restart == R.GOAL_KICK, "Direct throw into opponent goal gives a goal kick")
	game.place_restart(R.INDIRECT, 0, Vector2(23, 0), "Test")
	game.take_restart("shot", Vector2.ZERO, 0.7)
	crossing(game, Vector2(26.09, 0), Vector2(22, 0), 4)
	check(game.score == [0, 0] and game.restart == R.GOAL_KICK, "Indirect free kick needs a second touch")
	game.place_restart(R.GOAL_KICK, 0, Vector2(-22.7, 0), "Test")
	game.take_restart("pass", Vector2.RIGHT, 0.6)
	crossing(game, Vector2(-26.09, 0), Vector2(-22, 0), 0)
	check(game.score == [0, 0] and game.restart == R.CORNER and game.restart_team == 1, "Direct restart into own net gives a corner")
	game.place_restart(R.FREE_KICK, 0, Vector2(6, 0), "Test")
	game.take_restart("pass", Vector2.RIGHT, 0.6)
	game.touch(game.taker)
	check(game.restart == R.INDIRECT and game.restart_team == 1, "Second touch by the same kicker")
	game.phase = Game.Phase.PLAY
	game.players[9].point = Vector2(-22, 3)
	game.players[9].facing = Vector2.LEFT
	game.players[4].point = Vector2(-21, 3)
	game.players[4].facing = Vector2.LEFT
	game.owner = 9
	game.ball = Vector2(-22.64, 3)
	game.attempt_tackle(4)
	check(game.restart == R.PENALTY and game.restart_team == 1 and game.ball.is_equal_approx(Vector2(-20.1, 0)),
		"Tackle from behind in the box leads to a penalty")
	game.call_foul(9, Vector2(15, 1))
	check(game.restart == R.FREE_KICK and game.restart_team == 0 and game.ball == Vector2(15, 1),
		"Contact foul outside the box leads to a direct free kick")
	game.right_attack = 1
	game.call_foul(4, Vector2(19, 6))
	check(game.restart == R.PENALTY and game.ball.x > 0, "Penalty mirrors with the side switch")

func setup_offside(game: RefCounted, team: int) -> void:
	game.phase = Game.Phase.PLAY
	var direction: float = game.direction(team)
	var front := [4.0, 18.0, 0.0, 13.0, 7.0]
	var back := [23.0, 13.0, 9.0, 11.0, 12.0]
	for slot in range(5):
		game.players[team * 5 + slot].point = Vector2(front[slot] * direction, 2.0 if slot == 1 else 0.0)
		game.players[(1 - team) * 5 + slot].point = Vector2(back[slot] * direction, -3)
	game.ball = Vector2(7 * direction, 0)

func test_offside() -> void:
	var game := Game.new()
	for team in range(2):
		setup_offside(game, team)
		var passer := team * 5 + 4
		var target := team * 5 + 1
		var dir: float = game.direction(team)
		game.strike(passer, Vector2(dir, 0), 15.0, 0.0)
		check(game.offside == [target] and game.phase == Game.Phase.PLAY, "Snapshot in direction %s, level and midfield are onside" % dir)
		game.players[target].point.x = 10 * dir
		game.touch(target)
		check(game.phase == Game.Phase.RESTART and game.restart == R.INDIRECT and game.restart_team == 1 - team,
			"Late involvement penalised even after moving back (%s)" % dir)
		for kind in [R.THROW_IN, R.CORNER, R.GOAL_KICK]:
			setup_offside(game, team)
			game.strike(passer, Vector2(dir, 0), 15.0, 0.0, kind)
			game.touch(target)
			check(game.phase == Game.Phase.PLAY and game.owner == target, "Direct offside exemption for " + Rules.RESTART_NAMES[kind])
		setup_offside(game, team)
		game.ball.x = 19 * dir
		game.strike(passer, Vector2(dir, 0), 15.0, 0.0)
		check(game.offside.is_empty(), "Level with or behind the ball is onside")
		setup_offside(game, team)
		game.strike(passer, Vector2(dir, 0), 15.0, 0.0)
		game.touch((1 - team) * 5 + 2)
		check(game.offside.is_empty(), "Controlled opponent possession clears the snapshot")
		setup_offside(game, team)
		game.strike(passer, Vector2(dir, 0), 15.0, 0.0)
		var defender := (1 - team) * 5 + 2
		game.ball = Vector2(18 * dir, 2.7)
		game.ball_velocity = Vector2.ZERO
		game.players[defender].point = game.ball
		game.step_ball(STEP)
		check(game.restart == R.INDIRECT and game.phase == Game.Phase.RESTART, "Challenge for the ball triggers offside")
		setup_offside(game, team)
		game.strike(passer, Vector2(dir, 0), 26.0, 0.0)
		game.players[(1 - team) * 5].point = Vector2(24.4 * dir, 0)
		game.players[target].point = Vector2(22.7 * dir, 0)
		crossing(game, Vector2(26.05 * dir, 0), Vector2(26 * dir, 0), passer)
		check(game.score == [0, 0] and game.restart == R.INDIRECT, "Blocking the keeper's sight cancels the goal")
		setup_offside(game, team)
		game.strike(passer, Vector2(dir, 0), 26.0, 0.0)
		crossing(game, Vector2(26.05 * dir, 0), Vector2(26 * dir, 0), passer)
		check(game.score[team] == 1, "Passive offside position doesn't cancel a goal")
		game.score = [0, 0]

func test_controls_and_ai() -> void:
	var game := Game.new()
	game.tick(0.9, {"action": "pass", "move": Vector2.DOWN})
	check(game.phase == Game.Phase.PLAY and game.ball_velocity.length() >= 10, "Opening pass uses the normal input route")
	var receiver: int = game.selected
	for i in range(75):
		game.tick(STEP)
		if game.owner == receiver:
			break
	check(game.owner == receiver, "An aimed kickoff pass can be received by the selected teammate")
	if game.owner == receiver:
		var before: Vector2 = game.players[receiver].point
		for i in range(15):
			game.tick(STEP, {"move": Vector2.RIGHT, "sprint": true})
		check(game.players[receiver].point.x > before.x + 0.4, "The user can dribble and sprint")
		game.tick(STEP, {"action": "through", "move": Vector2.RIGHT})
		check(game.owner < 0 and game.ball_velocity.length() >= 10, "A through pass releases the ball into space")
	var previous: int = game.selected
	game.tick(STEP, {"switch": true})
	check(game.selected != previous and game.selected > 0 and game.selected < 5, "Manual change selects another outfielder")
	game.reset(1)
	for i in range(360):
		game.tick(STEP)
	check(game.remaining < Game.HALF_SECONDS - 1, "AI takes the kickoff and plays without human input")

func test_open_play_shots() -> void:
	for team in range(2):
		var game := Game.new()
		game.reset(team)
		var dir := game.direction(team)
		var shooter := team * 5 + 4
		var keeper := (1 - team) * 5
		for id in range(10):
			game.players[id].point = Vector2(-6.0 + id, 12.0)
		game.players[shooter].point = Vector2(20.2 * dir, -1.1)
		game.players[shooter].facing = Vector2(dir, 0)
		game.players[keeper].point = Vector2(24.5 * dir, 0)
		game.ball = game.players[shooter].point + Vector2(dir * 0.64, 0)
		game.phase = Game.Phase.PLAY
		game.touch(shooter)
		game.tick(STEP, {"action": "shot", "move": Vector2(dir * 0.4, -0.8), "power": 0.85})
		for frame in range(35):
			game.tick(STEP)
			if game.phase == Game.Phase.GOAL:
				break
		check(game.score[team] == 1, "An aimed open-play shot can beat the goalkeeper in direction %s" % dir)

func test_match_lifecycle() -> void:
	var game := Game.new()
	game.reset(1)
	game.score = [2, 1]
	game.phase = Game.Phase.PLAY
	game.remaining = 0.01
	game.tick(STEP)
	check(game.phase == Game.Phase.HALF_TIME and game.score == [2, 1], "Halftime freezes play and preserves the score")
	game.second_half()
	check(game.half == 2 and game.direction(0) == -1 and game.direction(1) == 1 and game.restart_team == 1,
		"Second half changes ends and grants kickoff to the other team")
	check(game.remaining == 180 and game.players[0].point.x > 0 and game.players[5].point.x < 0,
		"Second half has fresh time and mirrored keeper positions")
	crossing(game, Vector2(26.09, 0), Vector2(22, 0), 9)
	check(game.score == [2, 2], "Goals are attributed to the new attack direction after halftime")
	game.phase = Game.Phase.PLAY
	game.remaining = 0.01
	game.tick(STEP)
	check(game.phase == Game.Phase.FULL_TIME, "Second half ends the match")
	game.offside = [1, 4]
	game.players[4].tackle_cooldown = 1.0
	game.reset(game.human)
	check(game.human == 1 and game.selected == 9 and game.half == 1 and game.remaining == 180, "Rematch preserves team and restarts at 00:00")
	check(game.score == [0, 0] and game.phase == Game.Phase.RESTART and game.right_attack == 0 and game.restart_team == 0,
		"Rematch restores score and opening end")
	check(game.ball == Vector2.ZERO and game.ball_velocity == Vector2.ZERO and game.offside.is_empty() and game.owner == -1
		and game.players[4].tackle_cooldown == 0.0 and game.last_touch == -1,
		"Rematch clears transient referee, ball, and player state")

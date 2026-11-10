extends RefCounted

const HALF_LENGTH := 26.0
const HALF_WIDTH := 16.0
const GOAL_HALF := 3.25
const BAR := 2.25
const BALL_RADIUS := 0.23
const BOX_DEPTH := 7.5
const BOX_HALF := 8.0

enum Restart { KICKOFF, THROW_IN, CORNER, GOAL_KICK, FREE_KICK, INDIRECT, PENALTY }

const RESTART_NAMES := [
	"Anstoß", "Einwurf", "Ecke", "Abstoß", "Freistoß", "Indirekter Freistoß", "Elfmeter"
]

# Positions use the pitch plane: x runs between goals, y between touchlines.
static func offside_ids(team: int, passer: int, direction: float, ball: Vector2,
		players: Array[Vector2], direct_restart: int = -1) -> Array[int]:
	var flagged: Array[int] = []
	if direct_restart in [Restart.THROW_IN, Restart.CORNER, Restart.GOAL_KICK]:
		return flagged
	var opponents: Array[float] = []
	for id in range((1 - team) * 5, (1 - team) * 5 + 5):
		opponents.append(players[id].x * direction)
	opponents.sort()
	var line := maxf(ball.x * direction, opponents[3])
	for id in range(team * 5, team * 5 + 5):
		var depth := players[id].x * direction
		if id != passer and depth > 0.0 and depth > line + 0.01:
			flagged.append(id)
	return flagged

static func foul_restart(spot: Vector2, offender_direction: float) -> Restart:
	var depth := -spot.x * offender_direction
	if depth >= HALF_LENGTH - BOX_DEPTH and absf(spot.y) <= BOX_HALF:
		return Restart.PENALTY
	return Restart.FREE_KICK

# Find the first line fully crossed by the ball, even if both are crossed in one tick.
static func exit_event(previous: Vector2, current: Vector2, old_height: float,
		height: float, last_team: int, right_attack: int) -> Dictionary:
	var x_edge := HALF_LENGTH + BALL_RADIUS
	var y_edge := HALF_WIDTH + BALL_RADIUS
	var x_time := 2.0
	var y_time := 2.0
	if absf(current.x) > x_edge and current.x != previous.x:
		x_time = clampf((signf(current.x) * x_edge - previous.x) / (current.x - previous.x), 0.0, 1.0)
	if absf(current.y) > y_edge and current.y != previous.y:
		y_time = clampf((signf(current.y) * y_edge - previous.y) / (current.y - previous.y), 0.0, 1.0)
	if minf(x_time, y_time) > 1.0:
		return {}
	if y_time < x_time:
		var side := signf(current.y)
		var x := lerpf(previous.x, current.x, y_time)
		return {"restart": Restart.THROW_IN, "team": 1 - last_team,
			"spot": Vector2(clampf(x, -HALF_LENGTH + 0.4, HALF_LENGTH - 0.4), side * HALF_WIDTH)}
	var end := signf(current.x)
	var attacker := right_attack if end > 0 else 1 - right_attack
	var lateral := lerpf(previous.y, current.y, x_time)
	var crossing_height := lerpf(old_height, height, x_time)
	if absf(lateral) + BALL_RADIUS < GOAL_HALF and crossing_height + BALL_RADIUS < BAR:
		return {"goal": attacker, "side": end}
	if last_team == attacker:
		return {"restart": Restart.GOAL_KICK, "team": 1 - attacker,
			"spot": Vector2(end * (HALF_LENGTH - 3.3), clampf(lateral, -3.4, 3.4))}
	return {"restart": Restart.CORNER, "team": attacker,
		"spot": Vector2(end * (HALF_LENGTH - 0.25), signf(lateral + 0.001) * (HALF_WIDTH - 0.25))}

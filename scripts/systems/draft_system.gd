# scripts/systems/draft_system.gd
extends Node

class_name DraftSystem

class DraftState:
	var prospects: Array            # Array[AdventurerResource]
	var teams: Array                # e.g., [{ "name": "You", "roster": [] }, { "name": "AI", "roster": [] }]
	var order: Array[int]           # index into teams, e.g., [0,1,0,1,0,1] for 3 rounds with 2 teams
	var pick_index: int = 0         # which pick in order we’re on
	var picks_per_team: int = 3

func make_linear_order(num_teams: int, rounds: int) -> Array[int]:
	var order: Array[int] = []
	for r in rounds:
		for t in num_teams:
			order.append(t) # 0..num_teams-1
	return order

func make_snake_order(num_teams: int, rounds: int) -> Array[int]:
	var order: Array[int] = []
	var forward := true
	for r in rounds:
		if forward:
			for t in num_teams:
				order.append(t)
		else:
			for t in range(num_teams - 1, -1, -1):
				order.append(t)
		forward = !forward
	return order

func create_draft_state(prospects: Array, team_names: Array[String], rounds := 3, snake := false) -> DraftState:
	var s := DraftState.new()
	s.prospects = prospects.duplicate()
	s.teams = []
	for n in team_names:
		s.teams.append({ "name": n, "roster": [] })
	s.picks_per_team = rounds
	if snake:
		s.order = make_snake_order(s.teams.size(), rounds)
	else:
		s.order = make_linear_order(s.teams.size(), rounds)
	s.pick_index = 0
	return s

func is_done(state: DraftState) -> bool:
	return state.pick_index >= state.order.size()

func current_team_index(state: DraftState) -> int:
	return state.order[state.pick_index]

func is_player_turn(state: DraftState, player_team_index := 0) -> bool:
	return current_team_index(state) == player_team_index

func pick(state: DraftState, prospect_idx: int) -> void:
	if prospect_idx < 0 or prospect_idx >= state.prospects.size():
		return
	var team_i := current_team_index(state)
	var picked = state.prospects.pop_at(prospect_idx)
	state.teams[team_i]["roster"].append(picked)
	state.pick_index += 1

# --- AI logic (greedy but decent) ---

func ai_choose_index(state: DraftState, team_i: int) -> int:
	var need_bias := _role_need_bias(state.teams[team_i]["roster"])  # Dictionary
	var best_score: float = -INF
	var best_idx: int = 0

	for i in state.prospects.size():
		var a = state.prospects[i]
		var role_name: String = a.role.display_name  # <-- typed

		var score: float = a.attack * 1.0 + a.defense * 0.8 + a.hp * 0.3 + a.role_stat * 0.6 \
			- a.wage * 0.4  # <-- wage, not mage

		score += float(need_bias.get(role_name, 0.0))
		if score > best_score:
			best_score = score
			best_idx = i
	return best_idx


func _role_need_bias(roster: Array) -> Dictionary:
	# Encourage 1 of each role before duplicates
	var counts: Dictionary = { "Tank": 0, "Healer": 0, "Damage": 0, "Navigator": 0 }
	for a in roster:
		var r: String = a.role.display_name  # <-- typed
		if counts.has(r):
			counts[r] += 1

	var bias: Dictionary = {}
	for k in counts.keys():
		# diminishing return; prefer roles you don’t have yet
		bias[k] = max(0.0, 2.0 - float(counts[k]) * 1.5)
	return bias

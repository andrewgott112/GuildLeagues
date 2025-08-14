# scripts/systems/playoff_system.gd
extends Node
class_name PlayoffSystem

# Preload necessary resources
const AITeamResource = preload("res://resources/AITeam.gd")
const AdventurerResource = preload("res://resources/Adventurer.gd")

signal match_completed(match_result: Dictionary)
signal round_completed(round_results: Array)
signal tournament_completed(final_result: Dictionary)
signal bracket_updated()

enum TournamentFormat {
	SINGLE_ELIMINATION,
	DOUBLE_ELIMINATION,
	ROUND_ROBIN,
	SWISS_SYSTEM
}

enum MatchStatus {
	PENDING,
	IN_PROGRESS,
	COMPLETED,
	CANCELLED
}

class Match:
	var match_id: String
	var team1  # AITeamResource - remove typing for now
	var team2  # AITeamResource - remove typing for now
	var status: MatchStatus = MatchStatus.PENDING
	var winner = null  # AITeamResource - remove typing for now
	var loser = null   # AITeamResource - remove typing for now
	var margin: int = 0  # Victory margin for rivalry/narrative purposes
	var round_number: int = 0
	var bracket_position: int = 0
	var is_championship: bool = false
	var match_narrative: String = ""  # For storytelling
	
	func _init(id: String, t1, t2, round: int = 0):
		match_id = id
		team1 = t1
		team2 = t2
		round_number = round

class Tournament:
	var tournament_id: String
	var format: TournamentFormat
	var teams: Array = []  # Remove typing for now
	var matches: Array = []  # Array[Match] - remove typing for now
	var current_round: int = 0
	var max_rounds: int = 0
	var is_completed: bool = false
	var champion = null  # AITeamResource - remove typing for now
	var runner_up = null  # AITeamResource - remove typing for now
	var tournament_narrative: String = ""
	
	func _init(id: String, fmt: TournamentFormat):
		tournament_id = id
		format = fmt

# Current tournament state
var current_tournament: Tournament = null
var player_team = null  # AITeamResource - remove typing for now
var rng: RandomNumberGenerator

# League settings
var league_name: String = "Guild Leagues Championship"
var season: int = 1

func _init():
	rng = RandomNumberGenerator.new()
	rng.randomize()

# Initialize a new tournament
func create_tournament(teams: Array, format: TournamentFormat = TournamentFormat.SINGLE_ELIMINATION) -> Tournament:
	var tournament_id = "tournament_s%d" % season
	current_tournament = Tournament.new(tournament_id, format)
	current_tournament.teams = teams.duplicate()
	
	match format:
		TournamentFormat.SINGLE_ELIMINATION:
			_setup_single_elimination()
		TournamentFormat.ROUND_ROBIN:
			_setup_round_robin()
		# Add other formats as needed
	
	return current_tournament

# Create player team from roster
func create_player_team(roster: Array, team_name: String = "Your Guild"):
	player_team = AITeamResource.new()
	player_team.team_name = team_name
	player_team.coach_name = "You"
	player_team.team_id = StringName("player_team")
	player_team.roster = roster.duplicate()
	
	# Player team has balanced personality (can evolve based on player choices)
	player_team.aggression = 0.5
	player_team.discipline = 0.5
	player_team.experience = 0.3  # Start as newcomers
	player_team.wealth = 0.5
	
	player_team.primary_color = Color.BLUE
	player_team.secondary_color = Color.WHITE
	
	return player_team

# Setup single elimination bracket
func _setup_single_elimination():
	var team_count = current_tournament.teams.size()
	
	# Ensure power of 2 for clean bracket (add byes if needed)
	var bracket_size = 1
	while bracket_size < team_count:
		bracket_size *= 2
	
	current_tournament.max_rounds = _calculate_rounds_needed(bracket_size)
	
	# Create first round matches
	var shuffled_teams = current_tournament.teams.duplicate()
	shuffled_teams.shuffle()
	
	var match_count = 0
	for i in range(0, team_count, 2):
		if i + 1 < team_count:
			var match_id = "R1_M%d" % match_count
			var new_match = Match.new(match_id, shuffled_teams[i], shuffled_teams[i + 1], 1)
			new_match.bracket_position = match_count
			current_tournament.matches.append(new_match)
			match_count += 1
	
	current_tournament.current_round = 1

# Setup round robin (everyone plays everyone)
func _setup_round_robin():
	var teams = current_tournament.teams
	current_tournament.max_rounds = teams.size() - 1
	
	var match_count = 0
	# Generate all possible pairings
	for i in range(teams.size()):
		for j in range(i + 1, teams.size()):
			var match_id = "RR_M%d" % match_count
			var new_match = Match.new(match_id, teams[i], teams[j], 1)  # All matches in "round 1" for round robin
			current_tournament.matches.append(new_match)
			match_count += 1
	
	current_tournament.current_round = 1

# Get matches for current round
func get_current_round_matches() -> Array:
	if not current_tournament:
		return []
	
	var current_matches: Array = []
	for match_item in current_tournament.matches:
		if match_item.round_number == current_tournament.current_round and match_item.status == MatchStatus.PENDING:
			current_matches.append(match_item)
	
	return current_matches

# Get next match for player
func get_next_player_match():
	if not player_team:
		return null
	
	var current_matches = get_current_round_matches()
	for match_item in current_matches:
		if match_item.team1 == player_team or match_item.team2 == player_team:
			return match_item
	
	return null

# Process a match result
func complete_match(match_item: Match, winner, battle_details: Dictionary = {}):
	if match_item.status != MatchStatus.PENDING:
		return
	
	match_item.status = MatchStatus.COMPLETED
	match_item.winner = winner
	match_item.loser = match_item.team1 if winner == match_item.team2 else match_item.team2
	
	# Calculate margin based on battle details
	if battle_details.has("team1_survivors") and battle_details.has("team2_survivors"):
		var survivor_diff = abs(battle_details.team1_survivors - battle_details.team2_survivors)
		match_item.margin = survivor_diff * 20  # Each surviving member = 20 margin points
	else:
		match_item.margin = rng.randi_range(5, 25)  # Default random margin
	
	# Update team records
	match_item.winner.record_match_result(true, match_item.margin)
	match_item.loser.record_match_result(false, match_item.margin)
	
	# Update rivalries
	match_item.winner.update_rivalry(match_item.loser.team_id, true, match_item.margin)
	match_item.loser.update_rivalry(match_item.winner.team_id, false, match_item.margin)
	
	# Generate match narrative
	match_item.match_narrative = _generate_match_narrative(match_item, battle_details)
	
	print("Match completed: %s defeats %s (margin: %d)" % [match_item.winner.team_name, match_item.loser.team_name, match_item.margin])
	
	match_completed.emit({
		"match": match_item,
		"winner": winner,
		"loser": match_item.loser,
		"margin": match_item.margin,
		"narrative": match_item.match_narrative
	})
	
	_check_round_completion()
	bracket_updated.emit()

# Check if current round is complete and advance
func _check_round_completion():
	var current_matches = get_current_round_matches()
	
	if current_matches.is_empty():
		# Round is complete
		var round_results = []
		for match_item in current_tournament.matches:
			if match_item.round_number == current_tournament.current_round:
				round_results.append(match_item)
		
		round_completed.emit(round_results)
		
		if current_tournament.format == TournamentFormat.SINGLE_ELIMINATION:
			_advance_single_elimination()
		elif current_tournament.format == TournamentFormat.ROUND_ROBIN:
			_complete_round_robin()

# Advance single elimination bracket
func _advance_single_elimination():
	if current_tournament.current_round >= current_tournament.max_rounds:
		_complete_tournament()
		return
	
	# Get winners from current round
	var winners: Array = []
	for match_item in current_tournament.matches:
		if match_item.round_number == current_tournament.current_round and match_item.status == MatchStatus.COMPLETED:
			winners.append(match_item.winner)
	
	if winners.size() <= 1:
		_complete_tournament()
		return
	
	# Create next round matches
	current_tournament.current_round += 1
	var next_round = current_tournament.current_round
	var match_count = 0
	
	for i in range(0, winners.size(), 2):
		if i + 1 < winners.size():
			var match_id = "R%d_M%d" % [next_round, match_count]
			var new_match = Match.new(match_id, winners[i], winners[i + 1], next_round)
			new_match.bracket_position = match_count
			
			# Mark championship match
			if next_round == current_tournament.max_rounds and winners.size() == 2:
				new_match.is_championship = true
			
			current_tournament.matches.append(new_match)
			match_count += 1

# Complete round robin
func _complete_round_robin():
	_complete_tournament()

# Complete the tournament
func _complete_tournament():
	current_tournament.is_completed = true
	
	# Determine champion based on format
	if current_tournament.format == TournamentFormat.SINGLE_ELIMINATION:
		var championship_match = null
		for match_item in current_tournament.matches:
			if match_item.is_championship and match_item.status == MatchStatus.COMPLETED:
				championship_match = match_item
				break
		
		if championship_match:
			current_tournament.champion = championship_match.winner
			current_tournament.runner_up = championship_match.loser
	elif current_tournament.format == TournamentFormat.ROUND_ROBIN:
		# Find team with best record
		var best_team = null
		var best_record = -1.0
		
		for team in current_tournament.teams:
			var record = team.get_win_rate()
			if record > best_record:
				best_record = record
				best_team = team
		
		current_tournament.champion = best_team
	
	# Update championship count
	if current_tournament.champion:
		current_tournament.champion.championships += 1
		current_tournament.champion.playoff_appearances += 1
	
	# Update playoff appearances for all teams
	for team in current_tournament.teams:
		if team != current_tournament.champion:
			team.playoff_appearances += 1
	
	# Generate tournament narrative
	current_tournament.tournament_narrative = _generate_tournament_narrative()
	
	print("Tournament completed! Champion: %s" % current_tournament.champion.team_name if current_tournament.champion else "No champion")
	
	tournament_completed.emit({
		"tournament": current_tournament,
		"champion": current_tournament.champion,
		"runner_up": current_tournament.runner_up,
		"narrative": current_tournament.tournament_narrative
	})

# Generate narrative for a match
func _generate_match_narrative(match_item: Match, battle_details: Dictionary) -> String:
	var narrative = ""
	
	# Rivalry context
	if match_item.winner.rivalries.has(match_item.loser.team_id):
		var rivalry = match_item.winner.rivalries[match_item.loser.team_id]
		if rivalry.intensity > 0.7:
			narrative += "In a heated rivalry matchup, "
		elif rivalry.intensity > 0.4:
			narrative += "Continuing their competitive history, "
	
	# Match description based on margin
	if match_item.margin > 20:
		narrative += "%s dominated %s" % [match_item.winner.team_name, match_item.loser.team_name]
	elif match_item.margin > 10:
		narrative += "%s defeated %s convincingly" % [match_item.winner.team_name, match_item.loser.team_name]
	else:
		narrative += "%s edged out %s in a close match" % [match_item.winner.team_name, match_item.loser.team_name]
	
	# Add championship context
	if match_item.is_championship:
		narrative += " to claim the championship!"
	elif match_item.round_number == current_tournament.max_rounds - 1:
		narrative += " to advance to the championship!"
	
	return narrative

# Generate narrative for the tournament
func _generate_tournament_narrative() -> String:
	var narrative = "The %s concluded with " % league_name
	
	if current_tournament.champion:
		narrative += "%s claiming the championship" % current_tournament.champion.team_name
		
		# Add context based on champion's history
		if current_tournament.champion.championships == 1:
			narrative += " in their first title victory"
		elif current_tournament.champion.championships > 1:
			narrative += ", adding another title to their legacy"
		
		# Player-specific narrative
		if current_tournament.champion == player_team:
			narrative += ". Your guild has proven themselves among the elite!"
		else:
			narrative += ". Better luck next season!"
	
	return narrative + "."

# Helper functions
func _calculate_rounds_needed(bracket_size: int) -> int:
	var rounds = 0
	var teams_remaining = bracket_size
	while teams_remaining > 1:
		teams_remaining = teams_remaining / 2
		rounds += 1
	return rounds

# Get tournament standings (for round robin or tracking)
func get_tournament_standings() -> Array:
	var standings = []
	
	for team in current_tournament.teams:
		standings.append({
			"team": team,
			"wins": team.current_season_wins,
			"losses": team.current_season_losses,
			"win_rate": team.get_win_rate()
		})
	
	# Sort by wins, then by win rate
	standings.sort_custom(func(a, b): 
		if a.wins != b.wins:
			return a.wins > b.wins
		return a.win_rate > b.win_rate
	)
	
	return standings

# Get bracket visualization data
func get_bracket_data() -> Dictionary:
	return {
		"tournament": current_tournament,
		"current_round": current_tournament.current_round if current_tournament else 0,
		"matches": current_tournament.matches if current_tournament else [],
		"player_team": player_team,
		"format": current_tournament.format if current_tournament else TournamentFormat.SINGLE_ELIMINATION
	}

# Simulate AI vs AI matches
func simulate_ai_match(match_item: Match):
	var team1_strength = match_item.team1.get_team_strength()
	var team2_strength = match_item.team2.get_team_strength()
	
	# Add some randomness and personality factors
	var team1_modifier = 1.0
	var team2_modifier = 1.0
	
	# Apply personality modifiers
	team1_modifier += match_item.team1.aggression * 0.1
	team1_modifier += match_item.team1.experience * 0.15
	team2_modifier += match_item.team2.aggression * 0.1
	team2_modifier += match_item.team2.experience * 0.15
	
	# Add randomness (15% variance)
	team1_modifier *= rng.randf_range(0.85, 1.15)
	team2_modifier *= rng.randf_range(0.85, 1.15)
	
	var final_team1_strength = team1_strength * team1_modifier
	var final_team2_strength = team2_strength * team2_modifier
	
	return match_item.team1 if final_team1_strength > final_team2_strength else match_item.team2

# Auto-advance AI matches
func process_ai_matches():
	var ai_matches = []
	var current_matches = get_current_round_matches()
	
	for match_item in current_matches:
		if match_item.team1 != player_team and match_item.team2 != player_team:
			ai_matches.append(match_item)
	
	for match_item in ai_matches:
		var winner = simulate_ai_match(match_item)
		var battle_details = {
			"simulated": true,
			"team1_survivors": rng.randi_range(1, 3),
			"team2_survivors": rng.randi_range(0, 2)
		}
		complete_match(match_item, winner, battle_details)

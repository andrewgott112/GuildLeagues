# scripts/autoload/Game.gd - Updated to use draft-based AI teams
extends Node

const AITeamResource = preload("res://resources/AITeam.gd")
const PlayoffSystem = preload("res://scripts/systems/playoff_system.gd")

enum Phase { GUILD, DUNGEONS, PLAYOFFS, DRAFT }

signal phase_changed(new_phase: Phase)
signal season_changed(new_season: int)
signal playoff_match_available()
signal season_completed(results: Dictionary)

var phase: Phase = Phase.GUILD
var season: int = 1
var gold: int = 20
var roster: Array = []

var draft_done_for_season: bool = false
var playoffs_done_for_season: bool = false

# AI Team and Playoff Management
var ai_teams: Array = []
var playoff_system: PlayoffSystem = null
var league_size: int = 8
var player_team = null

# NEW: Draft-based team management
var all_drafted_adventurers: Dictionary = {}  # team_id -> Array of adventurers

# Season performance tracking
var season_results: Dictionary = {}
var season_stats: Dictionary = {
	"dungeons_completed": 0,
	"total_gold_earned": 0,
	"monsters_defeated": 0,
	"playoff_performance": ""
}

# ───────────────────────────────────────────────────────────────────
# Phase helpers
# ───────────────────────────────────────────────────────────────────
func goto(p: Phase) -> void:
	var old_phase = phase
	phase = p
	print("[Game] Phase changed: %s -> %s" % [phase_name(old_phase), phase_name(p)])
	emit_signal("phase_changed", p)

func phase_name(p: Phase = phase) -> String:
	match p:
		Phase.GUILD: return "Guild"
		Phase.DUNGEONS: return "Dungeons"
		Phase.PLAYOFFS: return "Playoffs"
		Phase.DRAFT: return "Draft"
		_: return "~"

# ───────────────────────────────────────────────────────────────────
# Draft gating
# ───────────────────────────────────────────────────────────────────
func can_start_draft() -> bool:
	return phase == Phase.GUILD and not draft_done_for_season

func start_draft_gate() -> bool:
	if not can_start_draft():
		return false
	draft_done_for_season = true
	playoffs_done_for_season = false
	goto(Phase.DRAFT)
	return true

func start_new_draft_gate() -> bool:
	return start_draft_gate()

func finish_draft() -> void:
	draft_done_for_season = true
	
	# NEW: After draft, distribute AI picks to AI teams
	_distribute_ai_draft_picks()
	
	goto(Phase.GUILD)

# ───────────────────────────────────────────────────────────────────
# NEW: Draft-based AI Team Management
# ───────────────────────────────────────────────────────────────────
func initialize_ai_teams():
	"""Create AI teams WITHOUT rosters - they'll get them from draft"""
	print("[Game] Initializing AI teams (without rosters)...")
	ai_teams.clear()
	all_drafted_adventurers.clear()
	
	# Create AI teams with empty rosters
	for i in range(league_size - 1):
		var difficulty_tier = 1 + (i / 3)
		var ai_team = AITeamResource.generate_ai_team(i, difficulty_tier)
		ai_team.roster = []  # Empty - will be filled by draft
		ai_teams.append(ai_team)
		
		# Initialize empty draft results
		all_drafted_adventurers[ai_team.team_id] = []
		
		print("[Game] Created AI team: %s (empty roster)" % ai_team.team_name)
	
	print("[Game] Generated %d AI teams for the league" % ai_teams.size())

func simulate_ai_draft_picks():
	"""Simulate AI teams making draft picks - called by DraftSystem"""
	print("[Game] Simulating AI draft picks...")
	
	# This is a simplified version - in reality, the DraftSystem would handle this
	# For now, we'll simulate by giving each AI team 3 random adventurers
	
	if ai_teams.is_empty():
		initialize_ai_teams()
	
	# Generate a pool of prospects (similar to what DraftScreen does)
	var prospect_pool = _generate_ai_draft_prospects(20)  # 20 prospects for 7 AI teams
	
	# Each AI team picks 3 adventurers
	for ai_team in ai_teams:
		var team_picks = []
		
		# Pick 3 adventurers for this team
		for pick in range(3):
			if prospect_pool.is_empty():
				break
				
			# AI picks based on team preferences
			var chosen_index = _ai_choose_prospect(ai_team, prospect_pool)
			var chosen_adventurer = prospect_pool[chosen_index]
			prospect_pool.remove_at(chosen_index)
			
			team_picks.append(chosen_adventurer)
			print("[Game] %s drafted %s (%s)" % [ai_team.team_name, chosen_adventurer.name, chosen_adventurer.role.display_name])
		
		all_drafted_adventurers[ai_team.team_id] = team_picks

func _generate_ai_draft_prospects(count: int) -> Array:
	"""Generate prospects for AI draft simulation"""
	var prospects = []
	
	# Load roles
	var role_files = [
		"res://data/roles/navigator_role.tres",
		"res://data/roles/healer_role.tres", 
		"res://data/roles/tank_role.tres",
		"res://data/roles/damage_role.tres"
	]
	
	var roles = []
	for role_path in role_files:
		var role = load(role_path)
		if role:
			roles.append(role)
	
	if roles.is_empty():
		print("[Game] Warning: No roles found for prospect generation")
		return prospects
	
	# Generate prospects using the existing method
	const AdventurerResource = preload("res://resources/Adventurer.gd")
	for i in range(count):
		var prospect = AdventurerResource.generate_random_prospect(roles)
		prospects.append(prospect)
	
	return prospects

func _ai_choose_prospect(ai_team: AITeamResource, prospects: Array) -> int:
	"""AI logic for choosing prospects (simplified)"""
	var best_index = 0
	var best_score = -1.0
	
	for i in range(prospects.size()):
		var prospect = prospects[i]
		var score = prospect.attack + prospect.defense + prospect.hp + prospect.role_stat
		
		# Add team personality modifiers
		if ai_team.aggression > 0.7:
			score += prospect.attack * 0.3
		if ai_team.discipline > 0.7:
			score += prospect.defense * 0.3
		
		# Random factor
		score += randf_range(-10, 10)
		
		if score > best_score:
			best_score = score
			best_index = i
	
	return best_index

func _distribute_ai_draft_picks():
	"""After draft ends, assign AI picks to their rosters"""
	print("[Game] Distributing AI draft picks to team rosters...")
	
	# If we haven't simulated AI picks yet, do it now
	if all_drafted_adventurers.is_empty():
		simulate_ai_draft_picks()
	
	# Assign drafted adventurers to AI team rosters
	for ai_team in ai_teams:
		if all_drafted_adventurers.has(ai_team.team_id):
			ai_team.roster = all_drafted_adventurers[ai_team.team_id].duplicate()
			print("[Game] %s roster: %d adventurers" % [ai_team.team_name, ai_team.roster.size()])

func get_all_teams() -> Array:
	"""Get all teams including player team"""
	var all_teams: Array = []
	if player_team:
		all_teams.append(player_team)
	all_teams.append_array(ai_teams)
	return all_teams

func create_player_team():
	"""Create/update player team from current roster"""
	if not playoff_system:
		playoff_system = PlayoffSystem.new()
		add_child(playoff_system)
		_connect_playoff_signals()
	
	player_team = playoff_system.create_player_team(roster, "Your Guild")
	print("[Game] Created player team with %d adventurers" % roster.size())
	return player_team

func _connect_playoff_signals():
	if playoff_system:
		playoff_system.match_completed.connect(_on_match_completed)
		playoff_system.round_completed.connect(_on_round_completed)
		playoff_system.tournament_completed.connect(_on_tournament_completed)

# ───────────────────────────────────────────────────────────────────
# Season flow - UPDATED
# ───────────────────────────────────────────────────────────────────
func start_regular_season() -> bool:
	if phase != Phase.GUILD or not draft_done_for_season:
		return false
	goto(Phase.DUNGEONS)
	
	season_stats = {
		"dungeons_completed": 0,
		"total_gold_earned": 0,
		"monsters_defeated": 0,
		"playoff_performance": ""
	}
	
	return true

func finish_regular_season() -> void:
	print("[Game] Finishing regular season and starting playoffs...")
	goto(Phase.PLAYOFFS)
	_start_playoffs()

func _start_playoffs():
	"""Initialize and start the playoff tournament"""
	print("[Game] Starting playoffs...")
	
	if not playoff_system:
		playoff_system = PlayoffSystem.new()
		add_child(playoff_system)
		_connect_playoff_signals()
		print("[Game] Created new playoff system")
	
	# Ensure we have AI teams with rosters
	if ai_teams.is_empty():
		print("[Game] No AI teams found, initializing...")
		initialize_ai_teams()
		simulate_ai_draft_picks()  # Give them rosters
	
	# Ensure AI teams have rosters
	for ai_team in ai_teams:
		if ai_team.roster.is_empty():
			print("[Game] AI team %s has empty roster, simulating draft..." % ai_team.team_name)
			# Emergency roster generation - in a real game this would be from draft
			all_drafted_adventurers[ai_team.team_id] = _generate_emergency_roster()
	
	_distribute_ai_draft_picks()
	
	if roster.is_empty():
		print("[Game] ERROR: Player has no roster for playoffs!")
		return
	
	create_player_team()
	
	var all_teams = get_all_teams()
	print("[Game] Tournament will have %d teams:" % all_teams.size())
	for team in all_teams:
		print("  - %s (%d adventurers)" % [team.team_name, team.roster.size()])
	
	playoff_system.season = season
	var tournament = playoff_system.create_tournament(all_teams, PlayoffSystem.TournamentFormat.SINGLE_ELIMINATION)
	
	if tournament:
		print("[Game] Tournament created successfully!")
		playoff_system.process_ai_matches()
		
		var player_match = get_next_player_match()
		if player_match:
			print("[Game] Player match available immediately")
			emit_signal("playoff_match_available")
		else:
			print("[Game] No player match yet")
	else:
		print("[Game] ERROR: Failed to create tournament!")

func _generate_emergency_roster() -> Array:
	"""Emergency roster generation if AI teams don't have draft picks"""
	var emergency_roster = []
	
	var role_files = [
		"res://data/roles/navigator_role.tres",
		"res://data/roles/healer_role.tres", 
		"res://data/roles/tank_role.tres",
		"res://data/roles/damage_role.tres"
	]
	
	var roles = []
	for role_path in role_files:
		var role = load(role_path)
		if role:
			roles.append(role)
	
	if not roles.is_empty():
		const AdventurerResource = preload("res://resources/Adventurer.gd")
		for i in range(3):
			var adventurer = AdventurerResource.generate_random_prospect(roles)
			emergency_roster.append(adventurer)
	
	return emergency_roster

func can_start_playoffs() -> bool:
	if not draft_done_for_season:
		return false
	if roster.is_empty():
		return false
	return true

# ───────────────────────────────────────────────────────────────────
# Rest of the methods remain the same...
# ───────────────────────────────────────────────────────────────────

func finish_playoffs_and_roll_season() -> void:
	if phase != Phase.PLAYOFFS:
		return
	playoffs_done_for_season = true
	
	var season_result = {
		"season": season,
		"champion": playoff_system.current_tournament.champion.team_name if playoff_system.current_tournament.champion else "Unknown",
		"player_champion": playoff_system.current_tournament.champion == player_team,
		"player_performance": _calculate_player_playoff_performance(),
		"stats": season_stats.duplicate()
	}
	season_results[season] = season_result
	
	season += 1
	emit_signal("season_changed", season)
	
	for ai_team in ai_teams:
		ai_team.start_new_season()
	
	if player_team:
		player_team.start_new_season()
	
	draft_done_for_season = false
	playoffs_done_for_season = false
	
	# Clear draft data for new season
	all_drafted_adventurers.clear()
	
	goto(Phase.GUILD)
	
	print("[Game] Season %d completed, starting season %d" % [season - 1, season])
	emit_signal("season_completed", season_result)

func _calculate_player_playoff_performance() -> String:
	if not playoff_system or not playoff_system.current_tournament:
		return "Did not participate"
	
	if playoff_system.current_tournament.champion == player_team:
		return "Champion"
	elif playoff_system.current_tournament.runner_up == player_team:
		return "Runner-up"
	else:
		var last_round = 0
		for match_item in playoff_system.current_tournament.matches:
			if (match_item.team1 == player_team or match_item.team2 == player_team) and match_item.status == PlayoffSystem.MatchStatus.COMPLETED:
				last_round = max(last_round, match_item.round_number)
		
		if last_round <= 1:
			return "First round exit"
		elif last_round == 2:
			return "Quarterfinals"
		elif last_round == 3:
			return "Semifinals"
		else:
			return "Early exit"

# Playoff match management
func get_next_player_match():
	if phase != Phase.PLAYOFFS or not playoff_system:
		return null
	return playoff_system.get_next_player_match()

func is_player_match_available() -> bool:
	return get_next_player_match() != null

func complete_player_match(winner, battle_details: Dictionary = {}):
	var current_match = get_next_player_match()
	if current_match:
		playoff_system.complete_match(current_match, winner, battle_details)

# Signal handlers
func _on_match_completed(match_result: Dictionary):
	print("[Game] Match completed: %s" % match_result.get("narrative", ""))
	if is_player_match_available():
		emit_signal("playoff_match_available")

func _on_round_completed(round_results: Array):
	print("[Game] Round %d completed with %d matches" % [playoff_system.current_tournament.current_round - 1, round_results.size()])
	playoff_system.process_ai_matches()
	if is_player_match_available():
		emit_signal("playoff_match_available")

func _on_tournament_completed(final_result: Dictionary):
	print("[Game] Tournament completed! %s" % final_result.get("narrative", ""))
	season_stats.playoff_performance = _calculate_player_playoff_performance()
	finish_playoffs_and_roll_season()

# Statistics
func record_dungeon_completion(gold_earned: int, monsters_defeated: int):
	season_stats.dungeons_completed += 1
	season_stats.total_gold_earned += gold_earned
	season_stats.monsters_defeated += monsters_defeated

func get_season_summary(season_num: int = season) -> Dictionary:
	if season_results.has(season_num):
		return season_results[season_num]
	return {
		"season": season_num,
		"in_progress": true,
		"stats": season_stats.duplicate()
	}

func get_all_time_stats() -> Dictionary:
	var total_stats = {
		"seasons_played": season_results.size(),
		"championships": 0,
		"playoff_appearances": 0,
		"total_dungeons": 0,
		"total_gold": 0,
		"total_monsters": 0
	}
	
	for season_data in season_results.values():
		if season_data.get("player_champion", false):
			total_stats.championships += 1
		if season_data.get("player_performance", "") != "Did not participate":
			total_stats.playoff_appearances += 1
		
		var stats = season_data.get("stats", {})
		total_stats.total_dungeons += stats.get("dungeons_completed", 0)
		total_stats.total_gold += stats.get("total_gold_earned", 0)
		total_stats.total_monsters += stats.get("monsters_defeated", 0)
	
	total_stats.total_dungeons += season_stats.get("dungeons_completed", 0)
	total_stats.total_gold += season_stats.get("total_gold_earned", 0)
	total_stats.total_monsters += season_stats.get("monsters_defeated", 0)
	
	return total_stats

# New game
func start_new_game() -> void:
	season = 1
	gold = 20
	roster.clear()
	draft_done_for_season = false
	playoffs_done_for_season = false
	
	ai_teams.clear()
	all_drafted_adventurers.clear()
	if playoff_system:
		playoff_system.queue_free()
		playoff_system = null
	player_team = null
	
	season_results.clear()
	season_stats = {
		"dungeons_completed": 0,
		"total_gold_earned": 0,
		"monsters_defeated": 0,
		"playoff_performance": ""
	}
	
	goto(Phase.GUILD)
	emit_signal("season_changed", season)
	print("[Game] New game started")

# Convenience methods
func get_playoff_bracket_data() -> Dictionary:
	if playoff_system:
		return playoff_system.get_bracket_data()
	return {}

func get_league_standings() -> Array:
	if playoff_system and playoff_system.current_tournament:
		return playoff_system.get_tournament_standings()
	return []

func season_progress_text() -> String:
	if phase == Phase.GUILD:
		if draft_done_for_season:
			return "Pre-season (Ready for dungeons)"
		else:
			return "Off-season (Draft available)"
	elif phase == Phase.DRAFT:
		return "Draft in progress"
	elif phase == Phase.DUNGEONS:
		return "Regular season (Dungeon runs)"
	elif phase == Phase.PLAYOFFS:
		if is_player_match_available():
			return "Playoffs (Match ready)"
		else:
			return "Playoffs (Waiting for results)"
	else:
		return "Unknown"

# TESTING ONLY
func force_start_playoffs() -> bool:
	print("[Game] FORCE STARTING PLAYOFFS")
	if roster.is_empty():
		print("[Game] No roster - cannot start playoffs")
		return false
	draft_done_for_season = true
	finish_regular_season()
	return true

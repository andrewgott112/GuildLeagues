# scripts/autoload/Game.gd
extends Node
## Central game state & season/phase gating with AI teams and playoffs

# Preload the classes we need
const AITeamResource = preload("res://resources/AITeam.gd")
const PlayoffSystem = preload("res://scripts/systems/playoff_system.gd")

# No Main Menu here — phases are just gameplay screens.
enum Phase { GUILD, DUNGEONS, PLAYOFFS, DRAFT }

signal phase_changed(new_phase: Phase)
signal season_changed(new_season: int)
signal playoff_match_available()
signal season_completed(results: Dictionary)

var phase: Phase = Phase.GUILD
var season: int = 1
var gold: int = 20
var roster: Array = []

# -------------------------------------------------------------------
# Draft gate semantics:
#   Season 1: unlocked (draft_done_for_season = false)
#   When you ENTER Draft: set draft_done_for_season = true  (locks button)
#   After Playoffs (season roll): set draft_done_for_season = false (unlocks again)
# -------------------------------------------------------------------
var draft_done_for_season: bool = false
var playoffs_done_for_season: bool = false

# NEW: AI Team and Playoff Management
var ai_teams: Array = []  # Array of AITeamResource - remove typing for now
var playoff_system: PlayoffSystem = null
var league_size: int = 8  # Total teams including player
var player_team = null  # AITeamResource - remove typing for now

# Season performance tracking
var season_results: Dictionary = {}  # season -> results_data
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
	if p == Phase.GUILD:
		return "Guild"
	elif p == Phase.DUNGEONS:
		return "Dungeons"
	elif p == Phase.PLAYOFFS:
		return "Playoffs"
	elif p == Phase.DRAFT:
		return "Draft"
	else:
		return "~"

# ───────────────────────────────────────────────────────────────────
# Draft gating
# ───────────────────────────────────────────────────────────────────
func can_start_draft() -> bool:
	# Draft can only be started from Guild and only if the gate is open
	return phase == Phase.GUILD and not draft_done_for_season

## Preferred entry point from GuildScreen:
## Closes the gate *immediately* so when you come back to Guild the button is locked.
func start_draft_gate() -> bool:
	if not can_start_draft():
		return false
	draft_done_for_season = true        # close gate as soon as we enter Draft
	playoffs_done_for_season = false    # we're in a new cycle until playoffs finish
	goto(Phase.DRAFT)
	return true

## Back-compat alias (useful if your UI calls this name):
func start_new_draft_gate() -> bool:
	return start_draft_gate()

## Called by DraftScreen when "Finish Draft" is pressed.
## We *also* lock in start_draft_gate(), but keep this for safety/clarity.
func finish_draft() -> void:
	draft_done_for_season = true
	goto(Phase.GUILD)

# ───────────────────────────────────────────────────────────────────
# NEW: AI Team Management
# ───────────────────────────────────────────────────────────────────
func initialize_ai_teams():
	"""Create AI teams for the league"""
	ai_teams.clear()
	
	# Create AI teams (league_size - 1 since player is one team)
	for i in range(league_size - 1):
		var difficulty_tier = 1 + (i / 3)  # Gradually increase difficulty
		var ai_team = AITeamResource.generate_ai_team(i, difficulty_tier)
		ai_teams.append(ai_team)
	
	print("[Game] Generated %d AI teams for the league" % ai_teams.size())

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
	return player_team

func _connect_playoff_signals():
	if playoff_system:
		playoff_system.match_completed.connect(_on_match_completed)
		playoff_system.round_completed.connect(_on_round_completed)
		playoff_system.tournament_completed.connect(_on_tournament_completed)

# ───────────────────────────────────────────────────────────────────
# Season flow with playoffs
# ───────────────────────────────────────────────────────────────────
func start_regular_season() -> bool:
	# If you want to force the player to draft before dungeons, keep this check.
	# Remove the draft_done_for_season check if you want to allow skipping.
	if phase != Phase.GUILD or not draft_done_for_season:
		return false
	goto(Phase.DUNGEONS)
	
	# Reset season stats
	season_stats = {
		"dungeons_completed": 0,
		"total_gold_earned": 0,
		"monsters_defeated": 0,
		"playoff_performance": ""
	}
	
	return true

func finish_regular_season() -> void:
	if phase == Phase.DUNGEONS:
		print("[Game] Regular season complete, starting playoffs...")
		goto(Phase.PLAYOFFS)
		_start_playoffs()

func _start_playoffs():
	"""Initialize and start the playoff tournament"""
	if not playoff_system:
		playoff_system = PlayoffSystem.new()
		add_child(playoff_system)
		_connect_playoff_signals()
	
	# Ensure we have AI teams
	if ai_teams.is_empty():
		initialize_ai_teams()
	
	# Create/update player team
	create_player_team()
	
	# Get all teams for tournament
	var all_teams = get_all_teams()
	
	# Create tournament
	playoff_system.season = season
	var tournament = playoff_system.create_tournament(all_teams, PlayoffSystem.TournamentFormat.SINGLE_ELIMINATION)
	
	# Process AI matches first
	playoff_system.process_ai_matches()
	
	print("[Game] Playoffs started with %d teams" % all_teams.size())

func can_start_playoffs() -> bool:
	# More flexible conditions - playoffs available if:
	# 1. Draft is done AND
	# 2. Player has done at least some dungeon exploration OR is in dungeon phase
	if not draft_done_for_season:
		return false
	
	if roster.is_empty():
		return false
	
	# Allow playoffs if:
	# - Currently in dungeons phase, OR
	# - Have completed at least one dungeon run, OR  
	# - Are in guild phase but have done dungeons this season
	return (phase == Phase.DUNGEONS or 
			season_stats.dungeons_completed > 0 or
			(phase == Phase.GUILD and draft_done_for_season))

## Call this when Playoffs end; it rolls the season and *reopens* the draft.
func finish_playoffs_and_roll_season() -> void:
	if phase != Phase.PLAYOFFS:
		return
	playoffs_done_for_season = true
	
	# Store season results
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
	
	# Evolve AI teams for next season
	for ai_team in ai_teams:
		ai_team.start_new_season()
	
	# Reset player team stats but keep experience
	if player_team:
		player_team.start_new_season()
	
	# New season reset/unlock:
	draft_done_for_season = false
	playoffs_done_for_season = false
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
		# Calculate round reached
		var last_round = 0
		for match_item in playoff_system.current_tournament.matches:
			if (match_item.team1 == player_team or match_item.team2 == player_team) and match_item.status == PlayoffSystem.MatchStatus.COMPLETED:
				last_round = max(last_round, match_item.round_number)
		
		# Use if-else instead of match to avoid keyword conflicts
		if last_round <= 1:
			return "First round exit"
		elif last_round == 2:
			return "Quarterfinals"
		elif last_round == 3:
			return "Semifinals"
		else:
			return "Early exit"

# ───────────────────────────────────────────────────────────────────
# Playoff match management
# ───────────────────────────────────────────────────────────────────
func get_next_player_match():
	"""Get the next match the player needs to play"""
	if phase != Phase.PLAYOFFS or not playoff_system:
		return null
	
	return playoff_system.get_next_player_match()

func is_player_match_available() -> bool:
	"""Check if player has a match waiting"""
	return get_next_player_match() != null

func complete_player_match(winner, battle_details: Dictionary = {}):
	"""Complete a player match with battle results"""
	var current_match = get_next_player_match()
	if current_match:
		playoff_system.complete_match(current_match, winner, battle_details)

# ───────────────────────────────────────────────────────────────────
# Playoff signal handlers
# ───────────────────────────────────────────────────────────────────
func _on_match_completed(match_result: Dictionary):
	print("[Game] Match completed: %s" % match_result.get("narrative", ""))
	
	# Check if player has next match
	if is_player_match_available():
		emit_signal("playoff_match_available")

func _on_round_completed(round_results: Array):
	print("[Game] Round %d completed with %d matches" % [playoff_system.current_tournament.current_round - 1, round_results.size()])
	
	# Process AI matches for next round
	playoff_system.process_ai_matches()
	
	# Check if player advances
	if is_player_match_available():
		emit_signal("playoff_match_available")

func _on_tournament_completed(final_result: Dictionary):
	print("[Game] Tournament completed! %s" % final_result.get("narrative", ""))
	
	# Update season stats
	season_stats.playoff_performance = _calculate_player_playoff_performance()
	
	# Tournament is done, can finish season
	finish_playoffs_and_roll_season()

# ───────────────────────────────────────────────────────────────────
# Statistics and progression
# ───────────────────────────────────────────────────────────────────
func record_dungeon_completion(gold_earned: int, monsters_defeated: int):
	"""Record dungeon run stats"""
	season_stats.dungeons_completed += 1
	season_stats.total_gold_earned += gold_earned
	season_stats.monsters_defeated += monsters_defeated

func get_season_summary(season_num: int = season) -> Dictionary:
	"""Get summary of a specific season"""
	if season_results.has(season_num):
		return season_results[season_num]
	
	# Current season in progress
	return {
		"season": season_num,
		"in_progress": true,
		"stats": season_stats.duplicate()
	}

func get_all_time_stats() -> Dictionary:
	"""Get career statistics across all seasons"""
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
	
	# Add current season if in progress
	total_stats.total_dungeons += season_stats.get("dungeons_completed", 0)
	total_stats.total_gold += season_stats.get("total_gold_earned", 0)
	total_stats.total_monsters += season_stats.get("monsters_defeated", 0)
	
	return total_stats

# ───────────────────────────────────────────────────────────────────
# New game
# ───────────────────────────────────────────────────────────────────
func start_new_game() -> void:
	season = 1
	gold = 20
	roster.clear()
	draft_done_for_season = false      # Season 1: unlocked
	playoffs_done_for_season = false
	
	# Clear AI teams and playoff system
	ai_teams.clear()
	if playoff_system:
		playoff_system.queue_free()
		playoff_system = null
	player_team = null
	
	# Clear season data
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

# ───────────────────────────────────────────────────────────────────
# Convenience methods for UI
# ───────────────────────────────────────────────────────────────────
func get_playoff_bracket_data() -> Dictionary:
	"""Get bracket data for UI display"""
	if playoff_system:
		return playoff_system.get_bracket_data()
	return {}

func get_league_standings() -> Array:
	"""Get current league standings"""
	if playoff_system and playoff_system.current_tournament:
		return playoff_system.get_tournament_standings()
	return []

func season_progress_text() -> String:
	"""Get descriptive text for current season progress"""
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

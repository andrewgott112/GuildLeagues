# scripts/autoload/Game.gd - Updated to use draft-based AI teams
extends Node

const AITeamResource = preload("res://resources/AITeam.gd")
const PlayoffSystem = preload("res://scripts/systems/playoff_system.gd")
const RoleResource = preload("res://resources/Role.gd")
const AdventurerResource = preload("res://resources/Adventurer.gd")

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

# Contract management
var active_contracts: Array = []  # Array of Contract objects
var free_agent_pool: Array = []   # Array of AdventurerResource (no contracts)
var salary_cap: int = 100          # Player's salary cap

# Character lifecycle tracking
var retired_characters: Array = []  # Characters who have retired (for hall of fame)
var deceased_characters: Array = []  # Characters who died (for memorial)

# Season transition tracking
var characters_processing: bool = false  # Prevent re-entry during season processing

# ═══════════════════════════════════════════════════════════════════
# CONTRACT SYSTEM
# ═══════════════════════════════════════════════════════════════════

class Contract:
	var character  # AdventurerResource reference
	var seasons_remaining: int
	var salary_per_season: int
	var team  # AITeamResource reference (or null for player team)
	var signed_date: int  # Season number when signed
	var is_player_contract: bool  # Quick check if this is player's contract
	
	func _init(char, team_ref, seasons: int, salary: int, season_signed: int):
		character = char
		team = team_ref
		seasons_remaining = seasons
		salary_per_season = salary
		signed_date = season_signed
		is_player_contract = (team_ref == null)
	
	func get_total_value() -> int:
		return seasons_remaining * salary_per_season
	
	func advance_season() -> bool:
		"""Advance contract by one season. Returns true if expired."""
		seasons_remaining -= 1
		return seasons_remaining <= 0
	
	func get_info_text() -> String:
		var team_name = "Your Guild" if is_player_contract else team.team_name
		return "%s: %d seasons @ %dg/season (Total: %dg)" % [
			character.name,
			seasons_remaining,
			salary_per_season,
			get_total_value()
		]

# ═══════════════════════════════════════════════════════════════════
# CONTRACT MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

func sign_contract(character, team_ref, seasons: int, salary: int) -> Contract:
	"""Sign a character to a contract. team_ref is null for player team."""
	var new_contract = Contract.new(character, team_ref, seasons, salary, season)
	active_contracts.append(new_contract)
	
	# Add to appropriate roster
	if new_contract.is_player_contract:
		if character not in roster:
			roster.append(character)
		print("[Game] Player signed %s: %d seasons @ %dg/season" % [character.name, seasons, salary])
	else:
		if character not in team_ref.roster:
			team_ref.roster.append(character)
		print("[Game] %s signed %s: %d seasons @ %dg/season" % [team_ref.team_name, character.name, seasons, salary])
	
	# Remove from free agent pool if present
	if character in free_agent_pool:
		free_agent_pool.erase(character)
	
	return new_contract

func get_player_contracts() -> Array:
	"""Get all player's active contracts"""
	var player_contracts = []
	for contract in active_contracts:
		if contract.is_player_contract:
			player_contracts.append(contract)
	return player_contracts

func get_team_contracts(team) -> Array:
	"""Get all contracts for a specific team"""
	var team_contracts = []
	for contract in active_contracts:
		if contract.team == team:
			team_contracts.append(contract)
	return team_contracts

func get_player_total_salary() -> int:
	"""Calculate player's current total salary commitments"""
	var total = 0
	for contract in get_player_contracts():
		total += contract.salary_per_season
	return total

func get_player_salary_space() -> int:
	"""Calculate player's remaining salary cap space"""
	return salary_cap - get_player_total_salary()

func can_afford_contract(salary: int) -> bool:
	"""Check if player can afford a contract within salary cap"""
	return get_player_salary_space() >= salary

func process_contract_expirations() -> Dictionary:
	"""Process contract expirations at end of season. Returns expired characters."""
	print("[Game] Processing contract expirations...")
	
	var expired_contracts = []
	var expired_player_characters = []
	var expired_ai_characters = []
	
	# Advance all contracts and collect expired ones
	for contract in active_contracts:
		if contract.advance_season():
			expired_contracts.append(contract)
			
			if contract.is_player_contract:
				expired_player_characters.append(contract.character)
			else:
				expired_ai_characters.append(contract.character)
	
	# Remove expired contracts from active list
	for expired_contract in expired_contracts:
		active_contracts.erase(expired_contract)
		
		# Remove character from team roster
		if expired_contract.is_player_contract:
			if expired_contract.character in roster:
				roster.erase(expired_contract.character)
		else:
			if expired_contract.character in expired_contract.team.roster:
				expired_contract.team.roster.erase(expired_contract.character)
		
		# Add to free agent pool
		if expired_contract.character not in free_agent_pool:
			free_agent_pool.append(expired_contract.character)
		
		print("[Game] Contract expired: %s (was with %s)" % [
			expired_contract.character.name,
			"Your Guild" if expired_contract.is_player_contract else expired_contract.team.team_name
		])
	
	return {
		"player_losses": expired_player_characters,
		"ai_losses": expired_ai_characters,
		"total_expired": expired_contracts.size()
	}

func get_contract_for_character(character) -> Contract:
	"""Find active contract for a character, if any"""
	for contract in active_contracts:
		if contract.character == character:
			return contract
	return null


# ───────────────────────────────────────────────────────────────────
# Phase helpers
# ───────────────────────────────────────────────────────────────────

func get_hall_of_fame() -> Array:
	"""Get all retired characters (sorted by achievements)"""
	var hof = retired_characters.duplicate()
	
	# Sort by total wins
	hof.sort_custom(func(a, b): 
		return a.battles_won > b.battles_won
	)
	
	return hof

func get_memorial() -> Array:
	"""Get all deceased characters"""
	return deceased_characters.duplicate()

func get_active_character_count() -> int:
	"""Get total number of characters actively playing"""
	var count = roster.size()
	for ai_team in ai_teams:
		count += ai_team.roster.size()
	count += free_agent_pool.size()
	return count

func get_total_character_count() -> int:
	"""Get total number of characters ever created"""
	return get_active_character_count() + retired_characters.size() + deceased_characters.size()

func _handle_character_removal(character, results: Dictionary):
	"""Handle a character being removed from active play"""
	
	# Remove any contracts
	var contract = get_contract_for_character(character)
	if contract:
		active_contracts.erase(contract)
		print("[Game] Removed contract for %s" % character.name)
	
	# Add to appropriate tracking array
	if character.madness_level >= 100:
		# Went mad - add to special tracking
		if character not in deceased_characters:  # Don't track twice
			deceased_characters.append(character)
			print("[Game] %s went mad and was removed from play" % character.name)
	elif character.is_retired:
		# Retired - add to hall of fame tracking
		if character not in retired_characters:
			retired_characters.append(character)
			print("[Game] %s retired and entered the hall of fame" % character.name)
	else:
		# Died - memorial tracking
		if character not in deceased_characters:
			deceased_characters.append(character)
			print("[Game] %s was removed from play (deceased)" % character.name)

func _process_character_season_end(character) -> Dictionary:
	"""Process a single character's end-of-season updates"""
	var result = {
		"injuries_healed": 0,
		"retired": false,
		"died": false,
		"went_mad": false
	}
	
	# Age the character
	character.apply_aging()
	
	# Process injury recovery
	if character.has_method("process_injury_recovery"):
		var injuries_before = character.injuries.size()
		character.process_injury_recovery()
		var injuries_after = character.injuries.size()
		result.injuries_healed = injuries_before - injuries_after
	
	# Check for retirement (age-based)
	if character.age > character.peak_age + 5:
		# Higher chance of retirement past prime
		var retirement_chance = (character.age - character.peak_age - 5) * 0.15
		if randf() < retirement_chance:
			character.is_retired = true
			result.retired = true
			print("[Game] %s has retired at age %d" % [character.name, character.age])
	
	# Check if already dead or mad
	if character.madness_level >= 100:
		result.went_mad = true
	
	# Very small chance of death from natural causes if very old
	if character.age > character.peak_age + 8:
		if randf() < 0.02:  # 2% chance per season when very old
			result.died = true
			print("[Game] %s has passed away from old age" % character.name)
	
	return result

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
	
	# Load roles with proper typing
	var role_files = [
		"res://data/roles/navigator_role.tres",
		"res://data/roles/healer_role.tres", 
		"res://data/roles/tank_role.tres",
		"res://data/roles/damage_role.tres"
	]
	
	# Create properly typed array
	var roles: Array[RoleResource] = []
	for role_path in role_files:
		var role = load(role_path) as RoleResource
		if role:
			roles.append(role)
	
	if roles.is_empty():
		print("[Game] Warning: No roles found for prospect generation")
		return prospects
	
	# Generate prospects using the properly typed array
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
	
	# Create properly typed array
	var roles: Array[RoleResource] = []
	for role_path in role_files:
		var role = load(role_path) as RoleResource
		if role:
			roles.append(role)
	
	if not roles.is_empty():
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
	
	# NEW: Process character aging and status effects FIRST
	var aging_results = process_all_character_aging()
	season_result["character_lifecycle"] = aging_results
	
	# THEN process contract expirations
	var expiration_results = process_contract_expirations()
	season_result["contract_expirations"] = expiration_results
	
	# Show important notifications
	if expiration_results.player_losses.size() > 0:
		print("[Game] Player lost %d characters to free agency!" % expiration_results.player_losses.size())
		for character in expiration_results.player_losses:
			print("  - %s is now a free agent" % character.name)
	
	if aging_results.retirements.size() > 0:
		print("[Game] %d characters retired this season" % aging_results.retirements.size())
	
	if aging_results.deaths.size() > 0:
		print("[Game] %d characters died this season" % aging_results.deaths.size())
	
	# Increment season
	season += 1
	emit_signal("season_changed", season)
	
	# Start new season for all teams
	for ai_team in ai_teams:
		ai_team.start_new_season()
		ai_team.update_salary_commitments(active_contracts)
	
	if player_team:
		player_team.start_new_season()
	
	# Reset season flags
	draft_done_for_season = false
	playoffs_done_for_season = false
	
	# Clear draft data for new season
	all_drafted_adventurers.clear()
	
	goto(Phase.GUILD)
	
	print("[Game] Season %d completed, starting season %d" % [season - 1, season])
	print("[Game] Player roster: %d characters" % roster.size())
	print("[Game] Free agents available: %d" % free_agent_pool.size())
	print("[Game] Retired characters: %d" % retired_characters.size())
	
	emit_signal("season_completed", season_result)

func process_all_character_aging() -> Dictionary:
	"""Process aging, injuries, and status effects for ALL characters at season end"""
	print("[Game] Processing character aging and status effects...")
	
	if characters_processing:
		print("[Game] Already processing characters, skipping...")
		return {}
	
	characters_processing = true
	
	var results = {
		"aged_characters": 0,
		"injuries_healed": 0,
		"retirements": [],
		"deaths": [],
		"madness": []
	}
	
	# Process player roster
	var player_removals = []
	for character in roster:
		var character_result = _process_character_season_end(character)
		results.aged_characters += 1
		results.injuries_healed += character_result.injuries_healed
		
		if character_result.retired:
			results.retirements.append(character.name)
			player_removals.append(character)
		elif character_result.died:
			results.deaths.append(character.name)
			player_removals.append(character)
		elif character_result.went_mad:
			results.madness.append(character.name)
			player_removals.append(character)
	
	# Remove retired/dead/mad characters from player roster
	for character in player_removals:
		roster.erase(character)
		_handle_character_removal(character, results)
	
	# Process AI team rosters
	for ai_team in ai_teams:
		var ai_removals = []
		for character in ai_team.roster:
			var character_result = _process_character_season_end(character)
			results.aged_characters += 1
			results.injuries_healed += character_result.injuries_healed
			
			if character_result.retired or character_result.died or character_result.went_mad:
				ai_removals.append(character)
		
		# Remove from AI roster
		for character in ai_removals:
			ai_team.roster.erase(character)
			_handle_character_removal(character, results)
	
	# Process free agents
	var fa_removals = []
	for character in free_agent_pool:
		var character_result = _process_character_season_end(character)
		results.aged_characters += 1
		results.injuries_healed += character_result.injuries_healed
		
		if character_result.retired or character_result.died or character_result.went_mad:
			fa_removals.append(character)
	
	# Remove from free agents
	for character in fa_removals:
		free_agent_pool.erase(character)
		_handle_character_removal(character, results)
	
	characters_processing = false
	
	print("[Game] Character processing complete:")
	print("  - Aged: %d characters" % results.aged_characters)
	print("  - Healed: %d injuries" % results.injuries_healed)
	print("  - Retired: %d (%s)" % [results.retirements.size(), ", ".join(results.retirements)])
	print("  - Died: %d (%s)" % [results.deaths.size(), ", ".join(results.deaths)])
	print("  - Went Mad: %d (%s)" % [results.madness.size(), ", ".join(results.madness)])
	
	return results

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
	
	retired_characters.clear()
	deceased_characters.clear()
	free_agent_pool.clear()
	active_contracts.clear()
	characters_processing = false
	
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

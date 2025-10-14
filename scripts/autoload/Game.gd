# scripts/autoload/Game.gd
extends Node

const AITeamResource = preload("res://resources/AITeam.gd")
const PlayoffSystem = preload("res://scripts/systems/playoff_system.gd")

enum Phase { GUILD, DUNGEONS, PLAYOFFS, DRAFT }

signal phase_changed(new_phase: Phase)
signal season_changed(new_season: int)
signal playoff_match_available()
signal season_completed(results: Dictionary)

# ═══════════════════════════════════════════════════════════════════
# MANAGERS
# ═══════════════════════════════════════════════════════════════════

var contract_manager: ContractManager
var season_lifecycle: SeasonLifecycle
var ai_team_manager: AITeamManager
var draft_coordinator: DraftCoordinator

# ═══════════════════════════════════════════════════════════════════
# GAME STATE (stays in Game.gd - orchestration level)
# ═══════════════════════════════════════════════════════════════════

var gold: int = 20
var roster: Array = []
var player_team = null
var scouting_database: Dictionary = {}

# Season flow gates
var draft_done_for_season: bool = false
var playoffs_done_for_season: bool = false

# External systems
var playoff_system: PlayoffSystem = null
var league_size: int = 8

# Computed properties (delegate to managers)
var phase: Phase:
	get: return season_lifecycle.current_phase
var season: int:
	get: return season_lifecycle.current_season
var salary_cap: int:
	get: return contract_manager.salary_cap
var ai_teams: Array:
	get: return ai_team_manager.ai_teams
var season_stats: Dictionary:
	get: return season_lifecycle.season_stats
var active_contracts: Array:
	get: return contract_manager.active_contracts
var free_agent_pool: Array:
	get: return contract_manager.free_agent_pool
var retired_characters: Array:
	get: return season_lifecycle.retired_characters
var deceased_characters: Array:
	get: return season_lifecycle.deceased_characters
# ═══════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════

func _ready():
	_initialize_managers()
	_connect_signals()

func _initialize_managers():
	# Contract management
	contract_manager = ContractManager.new()
	add_child(contract_manager)
	
	# Season lifecycle
	season_lifecycle = SeasonLifecycle.new()
	add_child(season_lifecycle)
	
	# AI team management
	ai_team_manager = AITeamManager.new()
	ai_team_manager.league_size = league_size
	add_child(ai_team_manager)
	
	# Draft coordination
	draft_coordinator = DraftCoordinator.new()
	add_child(draft_coordinator)
	
	print("[Game] All managers initialized")

func _connect_signals():
	# Contract manager signals
	contract_manager.contract_signed.connect(_on_contract_signed)
	contract_manager.contract_expired.connect(_on_contract_expired)
	contract_manager.salary_cap_exceeded.connect(_on_salary_cap_exceeded)
	
	# Season lifecycle signals
	season_lifecycle.phase_changed.connect(_on_phase_changed)
	season_lifecycle.season_changed.connect(_on_season_changed)
	season_lifecycle.season_completed.connect(_on_season_completed)

# ═══════════════════════════════════════════════════════════════════
# CONTRACT API (delegates to ContractManager)
# ═══════════════════════════════════════════════════════════════════

func sign_contract(character, team_ref, seasons: int, salary: int) -> Dictionary:
	"""Sign contract with validation"""
	var result = contract_manager.sign_contract(character, team_ref, seasons, salary, season)
	
	if result.success:
		# Update roster only on success
		if team_ref == null:
			if character not in roster:
				roster.append(character)
		else:
			if character not in team_ref.roster:
				team_ref.roster.append(character)
	
	return result

func can_afford_contract(salary: int) -> bool:
	return contract_manager.can_afford_contract(null, salary)

func get_player_salary_space() -> int:
	return contract_manager.get_salary_space(null)

func get_player_total_salary() -> int:
	return contract_manager.get_total_salary(null)

func get_player_contracts() -> Array:
	return contract_manager.get_contracts_for_team(null)

func get_team_contracts(team) -> Array:
	return contract_manager.get_contracts_for_team(team)

func get_contract_for_character(character):
	return contract_manager.get_contract_for_character(character)

# ═══════════════════════════════════════════════════════════════════
# PHASE/SEASON API (delegates to SeasonLifecycle)
# ═══════════════════════════════════════════════════════════════════

func goto(new_phase: Phase) -> void:
	season_lifecycle.advance_to_phase(new_phase)

func record_dungeon_completion(gold_earned: int, monsters_defeated: int):
	gold += gold_earned  # Gold tracked at Game level
	season_lifecycle.record_dungeon_completion(gold_earned, monsters_defeated)

func get_season_summary(season_num: int = -1) -> Dictionary:
	return season_lifecycle.get_season_summary(season_num)

func get_all_time_stats() -> Dictionary:
	return season_lifecycle.get_all_time_stats()

func get_hall_of_fame() -> Array:
	return season_lifecycle.get_hall_of_fame()

func get_memorial() -> Array:
	return season_lifecycle.get_memorial()

# ═══════════════════════════════════════════════════════════════════
# DRAFT FLOW
# ═══════════════════════════════════════════════════════════════════

func can_start_draft() -> bool:
	return phase == Phase.GUILD and not draft_done_for_season

func start_draft_gate() -> bool:
	if not can_start_draft():
		return false
	
	draft_done_for_season = true
	playoffs_done_for_season = false
	
	# Initialize AI teams if needed
	if ai_team_manager.ai_teams.is_empty():
		ai_team_manager.initialize_teams()
	
	# Prepare draft coordinator
	draft_coordinator.initialize_draft(ai_team_manager.ai_teams)
	
	goto(Phase.DRAFT)
	return true

func start_new_draft_gate() -> bool:
	return start_draft_gate()

func finish_draft() -> void:
	"""Called when player completes draft"""
	draft_done_for_season = true
	
	# Simulate AI draft picks
	var player_picks = roster.duplicate()  # Characters player drafted
	var draft_results = draft_coordinator.simulate_ai_draft(ai_team_manager.ai_teams, player_picks)
	
	# CRITICAL: Assign AI picks AND create contracts
	var assign_results = ai_team_manager.assign_draft_picks(draft_results, contract_manager, season)
	
	if assign_results.failed_signings.size() > 0:
		push_warning("[Game] %d AI signings failed!" % assign_results.failed_signings.size())
	
	# Update salary tracking
	ai_team_manager.update_salary_commitments(contract_manager)
	
	print("[Game] Draft complete: %d AI contracts signed" % assign_results.success_count)
	
	goto(Phase.GUILD)

# ═══════════════════════════════════════════════════════════════════
# SEASON FLOW
# ═══════════════════════════════════════════════════════════════════

func start_regular_season() -> bool:
	if phase != Phase.GUILD or not draft_done_for_season:
		return false
	
	goto(Phase.DUNGEONS)
	return true

func finish_regular_season() -> void:
	print("[Game] Finishing regular season, starting playoffs...")
	goto(Phase.PLAYOFFS)
	_start_playoffs()

func can_start_playoffs() -> bool:
	return draft_done_for_season and not roster.is_empty()

func finish_playoffs_and_roll_season() -> void:
	"""Complete season and advance to next"""
	if phase != Phase.PLAYOFFS:
		return
	
	playoffs_done_for_season = true
	
	# Set playoff performance in season stats
	var performance = _calculate_player_playoff_performance()
	season_lifecycle.set_playoff_performance(performance)
	
	# Gather all rosters for aging
	var all_rosters = [roster]
	for ai_team in ai_team_manager.ai_teams:
		all_rosters.append(ai_team.roster)
	
	# Advance season (this emits season_completed signal internally)
	var season_results = season_lifecycle.advance_season(all_rosters, contract_manager)
	
	# FIX: Call start_new_season() on all AI teams to reset stats and evolve personalities
	for ai_team in ai_team_manager.ai_teams:
		ai_team.start_new_season()
	
	# Update rosters based on expirations
	var contract_expirations = season_results.contract_expirations
	for contract in contract_expirations.expired_contracts:
		if contract.is_player_contract:
			roster.erase(contract.character)
		else:
			contract.team.roster.erase(contract.character)
	
	# Reset season gates
	draft_done_for_season = false
	playoffs_done_for_season = false
	
	print("[Game] ===== SEASON %d COMPLETE =====" % (season - 1))
	print("[Game] Player losses: %d, AI losses: %d, New FAs: %d" % [
		contract_expirations.player_losses.size(),
		contract_expirations.ai_losses.size(),
		contract_manager.free_agent_pool.size()
	])
	print("[Game] AI teams refreshed: %d teams reset for new season" % ai_team_manager.ai_teams.size())
	
	goto(Phase.GUILD)

# ═══════════════════════════════════════════════════════════════════
# PLAYOFF MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

func _start_playoffs():
	if not playoff_system:
		playoff_system = PlayoffSystem.new()
		add_child(playoff_system)
		_connect_playoff_signals()
	
	# Ensure AI teams have rosters
	for ai_team in ai_team_manager.ai_teams:
		if ai_team.roster.is_empty():
			ai_team.roster = ai_team_manager.generate_emergency_roster()
	
	# Create player team
	create_player_team()
	
	season_lifecycle.initialize_season_summary()
	
	# Create tournament
	var all_teams = ai_team_manager.get_all_teams_with_player(player_team)
	playoff_system.season = season
	var tournament = playoff_system.create_tournament(all_teams, PlayoffSystem.TournamentFormat.SINGLE_ELIMINATION)
	
	if tournament:
		playoff_system.process_ai_matches()
		if get_next_player_match():
			emit_signal("playoff_match_available")

func create_player_team():
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

func get_all_teams() -> Array:
	return ai_team_manager.get_all_teams_with_player(player_team)

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
		
		match last_round:
			0, 1: return "First round exit"
			2: return "Quarterfinals"
			3: return "Semifinals"
			_: return "Early exit"

# ═══════════════════════════════════════════════════════════════════
# NEW GAME
# ═══════════════════════════════════════════════════════════════════

func start_new_game() -> void:
	# Reset Game.gd state
	gold = 20
	roster.clear()
	draft_done_for_season = false
	playoffs_done_for_season = false
	player_team = null
	
	# Reset managers
	contract_manager.active_contracts.clear()
	contract_manager.free_agent_pool.clear()
	scouting_database.clear()
	
	season_lifecycle.current_season = 1
	season_lifecycle.current_phase = Phase.GUILD
	season_lifecycle.season_results.clear()
	season_lifecycle.retired_characters.clear()
	season_lifecycle.deceased_characters.clear()
	
	ai_team_manager.ai_teams.clear()
	draft_coordinator.all_drafted_adventurers.clear()
	
	# Reset playoff system
	if playoff_system:
		playoff_system.queue_free()
		playoff_system = null
	
	goto(Phase.GUILD)
	emit_signal("season_changed", 1)

# ═══════════════════════════════════════════════════════════════════
# SIGNAL HANDLERS
# ═══════════════════════════════════════════════════════════════════

func _on_contract_signed(contract):
	print("[Game] Contract signed: %s" % contract.character.name)

func _on_contract_expired(contract):
	print("[Game] Contract expired: %s" % contract.character.name)

func _on_salary_cap_exceeded(team_id: String, overage: int):
	push_warning("[Game] Salary cap exceeded for %s by %dg!" % [team_id, overage])

func _on_phase_changed(new_phase):
	emit_signal("phase_changed", new_phase)

func _on_season_changed(new_season):
	emit_signal("season_changed", new_season)

func _on_season_completed(results):
	"""
	Handle season completion from SeasonLifecycle.
	This re-broadcasts to Game's listeners (like GuildScreen).
	"""
	emit_signal("season_completed", results)

# Playoff signals
func _on_match_completed(match_result: Dictionary):
	print("[Game] Match completed")
	if is_player_match_available():
		emit_signal("playoff_match_available")

func _on_round_completed(round_results: Array):
	print("[Game] Round completed")
	playoff_system.process_ai_matches()
	if is_player_match_available():
		emit_signal("playoff_match_available")

func _on_tournament_completed(final_result: Dictionary):
	print("[Game] Tournament completed!")
	
	# Extract champion info
	var champion = final_result.get("champion")
	if champion:
		# Champion is a Team object - access team_name directly
		var champion_name = champion.team_name
		var is_player_champion = (champion == player_team)
		
		# Record champion in season lifecycle BEFORE advancing season
		season_lifecycle.set_champion_info(champion_name, is_player_champion)
	
	# Record player's playoff performance
	var performance = _calculate_player_playoff_performance()
	season_lifecycle.set_playoff_performance(performance)
	
	# Finalize season results with all playoff data
	season_lifecycle.finalize_season_results()
	
	# Now advance to next season
	finish_playoffs_and_roll_season()

# ═══════════════════════════════════════════════════════════════════
# HELPER METHODS
# ═══════════════════════════════════════════════════════════════════

func phase_name(p: Phase = phase) -> String:
	"""Get phase name as string"""
	match p:
		Phase.GUILD: return "Guild"
		Phase.DUNGEONS: return "Dungeons"
		Phase.PLAYOFFS: return "Playoffs"
		Phase.DRAFT: return "Draft"
		_: return "Unknown"

func get_scouting_info(character_name: String) -> ScoutingInfo:
	"""Get or create scouting info for a character"""
	if not scouting_database.has(character_name):
		scouting_database[character_name] = ScoutingInfo.new(character_name)
	return scouting_database[character_name]

func get_character_by_name(character_name: String) -> AdventurerResource:
	"""Find a character by name acr oss all rosters"""
	# Check player roster
	for character in roster:
		if character.name == character_name:
			return character
	
	# Check AI rosters
	for team in ai_teams:
		for character in team.roster:
			if character.name == character_name:
				return character
	
	# Check free agents
	for character in contract_manager.free_agent_pool:
		if character.name == character_name:
			return character
	
	return null

func reveal_combat_stats(character_name: String, battle_data: Dictionary):
	"""Reveal stats based on combat performance"""
	var character = get_character_by_name(character_name)
	if not character:
		return
	
	var info = get_scouting_info(character_name)
	
	# General combat revelation
	info.reveal_from_combat(character)
	
	# Specific revelations based on battle data
	if battle_data.has("damage_taken") and battle_data.damage_taken > 0:
		info.reveal_from_damage_taken(battle_data.damage_taken, character)
	
	if battle_data.has("damage_dealt") and battle_data.damage_dealt > 0:
		var was_crit = battle_data.get("was_crit", false)
		info.reveal_from_damage_dealt(battle_data.damage_dealt, was_crit, character)
	
	if battle_data.has("survived_low_hp") and battle_data.survived_low_hp:
		info.reveal_from_near_death_survival(character)
	
	if battle_data.has("made_decisions") and battle_data.made_decisions:
		info.reveal_from_decision_making(character)
	
	if battle_data.has("made_observations") and battle_data.made_observations:
		info.reveal_from_observation(character)

func reveal_training_stats(character_name: String, stat_gain: float):
	"""Reveal stats based on training results"""
	var character = get_character_by_name(character_name)
	if not character:
		return
	
	var info = get_scouting_info(character_name)
	info.reveal_from_training_session(stat_gain, character)

func reveal_injury_stats(character_name: String, got_injured: bool):
	"""Reveal injury proneness based on injury events"""
	var character = get_character_by_name(character_name)
	if not character:
		return
	
	var info = get_scouting_info(character_name)
	
	if got_injured:
		info.reveal_from_injury(character)
	else:
		info.reveal_from_avoiding_injury(character)

func apply_initial_scouting(character: AdventurerResource, scout_level: int = 0):
	"""Apply initial scouting to a character (use in draft)"""
	var info = get_scouting_info(character.name)
	info.apply_scout_level(scout_level, character)

func apply_scouting_with_scout(scout: AdventurerResource, prospect: AdventurerResource):
	"""Apply scouting using a scout character's stats"""
	var info = get_scouting_info(prospect.name)
	info.apply_scout_with_stats(scout, prospect)

func process_knowledge_decay():
	"""Process knowledge decay for all characters at season end"""
	var current_season = season
	
	for char_name in scouting_database.keys():
		var info = scouting_database[char_name]
		var seasons_absent = current_season - info.last_observed_season
		
		if seasons_absent > 0:
			info.apply_knowledge_decay(seasons_absent)

func get_stat_display(character_name: String, stat_name: String) -> String:
	"""Get display string for a character's stat"""
	if scouting_database.has(character_name):
		return scouting_database[character_name].get_stat_display(stat_name)
	return "???"

func is_stat_known(character_name: String, stat_name: String, threshold: float = 0.5) -> bool:
	"""Check if a stat is known for a character"""
	if scouting_database.has(character_name):
		return scouting_database[character_name].is_stat_known(stat_name, threshold)
	return false

func get_overall_knowledge(character_name: String) -> float:
	"""Get overall knowledge percentage for a character"""
	if scouting_database.has(character_name):
		return scouting_database[character_name].get_overall_confidence()
	return 0.0

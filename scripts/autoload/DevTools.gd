# ═══════════════════════════════════════════════════════════════════
# DEV TOOLS AUTOLOAD
# ═══════════════════════════════════════════════════════════════════
# Save as: scripts/autoload/DevTools.gd
# 
# Add to Project Settings > Autoload:
# Name: DevTools
# Path: res://scripts/autoload/DevTools.gd
# ═══════════════════════════════════════════════════════════════════

extends Node

const RoleResource = preload("res://resources/Role.gd")

# Dev mode toggle
var dev_mode_enabled: bool = true  # Set to false for production builds
var dev_panel_visible: bool = false

# UI References
var dev_window: Window = null
var debug_label: Label = null
var update_timer: Timer = null

# Auto-refresh settings
var auto_refresh: bool = true
var refresh_rate: float = 0.5

func _ready():
	if not dev_mode_enabled:
		return
	
	print("[DevTools] Developer tools enabled - Press F12 to toggle")
	
	# Create update timer
	update_timer = Timer.new()
	update_timer.wait_time = refresh_rate
	update_timer.timeout.connect(_update_debug_info)
	add_child(update_timer)
	
	# Don't create window yet - wait for F12

func _input(event):
	if not dev_mode_enabled:
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			toggle_dev_panel()
		elif event.keycode == KEY_F11:
			# Quick season advance
			if dev_panel_visible:
				quick_advance_season()

func toggle_dev_panel():
	if not dev_window:
		_create_dev_window()
	
	dev_panel_visible = !dev_panel_visible
	
	if dev_panel_visible:
		dev_window.show()
		update_timer.start()
		_update_debug_info()
	else:
		dev_window.hide()
		update_timer.stop()

func _create_dev_window():
	# Create separate window for dev tools
	dev_window = Window.new()
	dev_window.title = "🛠️ DEVELOPER TOOLS"
	dev_window.size = Vector2i(800, 600)
	dev_window.position = Vector2i(100, 100)
	dev_window.close_requested.connect(func(): dev_panel_visible = false; dev_window.hide())
	
	# Main container with proper sizing
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	dev_window.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(main_vbox)
	
	# Title
	var title = Label.new()
	title.text = "🛠️ DEVELOPER TOOLS (F12 to toggle)"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.YELLOW)
	main_vbox.add_child(title)
	
	var sep1 = HSeparator.new()
	main_vbox.add_child(sep1)
	
	# Create tabbed interface
	var tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.custom_minimum_size = Vector2(700, 450)
	main_vbox.add_child(tab_container)
	
	# Tab 1: Game State
	var state_tab = _create_state_tab()
	state_tab.name = "Game State"
	tab_container.add_child(state_tab)
	
	# Tab 2: Quick Actions
	var actions_tab = _create_actions_tab()
	actions_tab.name = "Quick Actions"
	tab_container.add_child(actions_tab)
	
	# Tab 3: Cheats
	var cheats_tab = _create_cheats_tab()
	cheats_tab.name = "Cheats"
	tab_container.add_child(cheats_tab)
	
	# Tab 4: Testing
	var testing_tab = _create_testing_tab()
	testing_tab.name = "Testing"
	tab_container.add_child(testing_tab)
	
	add_child(dev_window)

func _create_state_tab() -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	
	# Debug info label (auto-updated)
	debug_label = Label.new()
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(debug_label)
	
	return scroll

func _create_actions_tab() -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)
	
	# Section: Season Management
	var season_header = Label.new()
	season_header.text = "⏰ SEASON MANAGEMENT"
	season_header.add_theme_font_size_override("font_size", 16)
	season_header.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(season_header)
	
	var season_grid = GridContainer.new()
	season_grid.columns = 2
	season_grid.add_theme_constant_override("h_separation", 12)
	season_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(season_grid)
	
	_add_button(season_grid, "Skip to Draft", func(): skip_to_draft())
	_add_button(season_grid, "Skip to Playoffs", func(): skip_to_playoffs())
	_add_button(season_grid, "Complete Season (F11)", func(): quick_advance_season())
	_add_button(season_grid, "Complete 5 Seasons", func(): advance_multiple_seasons(5))
	
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)
	
	# Section: Roster Management
	var roster_header = Label.new()
	roster_header.text = "👥 ROSTER MANAGEMENT"
	roster_header.add_theme_font_size_override("font_size", 16)
	roster_header.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(roster_header)
	
	var roster_grid = GridContainer.new()
	roster_grid.columns = 2
	roster_grid.add_theme_constant_override("h_separation", 12)
	roster_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(roster_grid)
	
	_add_button(roster_grid, "Add Random Character", func(): add_random_character())
	_add_button(roster_grid, "Clear All Contracts", func(): clear_all_contracts())
	_add_button(roster_grid, "Age All Characters +5", func(): age_all_characters(5))
	_add_button(roster_grid, "Heal All Injuries", func(): heal_all_injuries())
	
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	# Section: Simulation
	var sim_header = Label.new()
	sim_header.text = "🎲 SIMULATION"
	sim_header.add_theme_font_size_override("font_size", 16)
	sim_header.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(sim_header)
	
	var sim_grid = GridContainer.new()
	sim_grid.columns = 2
	sim_grid.add_theme_constant_override("h_separation", 12)
	sim_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(sim_grid)
	
	_add_button(sim_grid, "Simulate Draft", func(): simulate_draft())
	_add_button(sim_grid, "Win Next Playoff Match", func(): win_next_playoff())
	_add_button(sim_grid, "Complete Playoffs", func(): complete_playoffs())
	_add_button(sim_grid, "Random Injury", func(): cause_random_injury())
	
	return scroll

func _create_cheats_tab() -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)
	
	# Gold cheats
	var gold_header = Label.new()
	gold_header.text = "💰 GOLD CHEATS"
	gold_header.add_theme_font_size_override("font_size", 16)
	gold_header.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(gold_header)
	
	var gold_grid = GridContainer.new()
	gold_grid.columns = 3
	gold_grid.add_theme_constant_override("h_separation", 12)
	gold_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(gold_grid)
	
	_add_button(gold_grid, "+100g", func(): Game.gold += 100)
	_add_button(gold_grid, "+1000g", func(): Game.gold += 1000)
	_add_button(gold_grid, "Max Gold (9999)", func(): Game.gold = 9999)
	
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)
	
	# Character cheats
	var char_header = Label.new()
	char_header.text = "⚡ CHARACTER CHEATS"
	char_header.add_theme_font_size_override("font_size", 16)
	char_header.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(char_header)
	
	var char_grid = GridContainer.new()
	char_grid.columns = 2
	char_grid.add_theme_constant_override("h_separation", 12)
	char_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(char_grid)
	
	_add_button(char_grid, "Max All Stats", func(): max_all_stats())
	_add_button(char_grid, "Level Up All +5", func(): level_up_all(5))
	_add_button(char_grid, "Instant Max Loyalty", func(): max_all_loyalty())
	_add_button(char_grid, "Remove All Injuries", func(): heal_all_injuries())
	
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	# Unlock cheats
	var unlock_header = Label.new()
	unlock_header.text = "🔓 UNLOCK CHEATS"
	unlock_header.add_theme_font_size_override("font_size", 16)
	unlock_header.add_theme_color_override("font_color", Color.GREEN)
	vbox.add_child(unlock_header)
	
	var unlock_grid = GridContainer.new()
	unlock_grid.columns = 2
	unlock_grid.add_theme_constant_override("h_separation", 12)
	unlock_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(unlock_grid)
	
	_add_button(unlock_grid, "Unlock Draft", func(): unlock_draft())
	_add_button(unlock_grid, "Unlock Playoffs", func(): unlock_playoffs())
	_add_button(unlock_grid, "Infinite Salary Cap", func(): Game.salary_cap = 999999)
	_add_button(unlock_grid, "Reset Salary Cap", func(): Game.salary_cap = 100)
	
	return scroll

func _create_testing_tab() -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)
	
	var test_header = Label.new()
	test_header.text = "🧪 TESTING SCENARIOS"
	test_header.add_theme_font_size_override("font_size", 16)
	test_header.add_theme_color_override("font_color", Color.MAGENTA)
	vbox.add_child(test_header)
	
	var test_grid = GridContainer.new()
	test_grid.columns = 1
	test_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(test_grid)
	
	_add_button(test_grid, "Test: Complete Season Cycle", func(): test_complete_season())
	_add_button(test_grid, "Test: Contract Expiration", func(): test_contract_expiration())
	_add_button(test_grid, "Test: Character Aging", func(): test_character_aging())
	_add_button(test_grid, "Test: Retirement Cascade", func(): test_retirement_cascade())
	_add_button(test_grid, "Test: Free Agency Flow", func(): test_free_agency())
	
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)
	
	# Test results area
	var results_label = Label.new()
	results_label.text = "Test results will appear here..."
	results_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	vbox.add_child(results_label)
	
	return scroll

# ═══════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

func _add_button(parent: Node, text: String, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _update_debug_info():
	if not debug_label or not auto_refresh:
		return
	
	var info = "🎮 GAME STATE DEBUG INFO\n\n"
	
	# Basic game state
	info += "Season: %d\n" % Game.season
	info += "Phase: %s\n" % Game.phase_name()
	info += "Gold: %dg\n" % Game.gold
	info += "\n"
	
	# Roster info
	info += "👥 ROSTER:\n"
	info += "  Player Roster: %d characters\n" % Game.roster.size()
	info += "  Free Agents: %d\n" % Game.free_agent_pool.size()
	info += "  Retired: %d\n" % Game.retired_characters.size()
	info += "  Deceased: %d\n" % Game.deceased_characters.size()
	info += "\n"
	
	# Contract info
	info += "📜 CONTRACTS:\n"
	info += "  Active Contracts: %d\n" % Game.active_contracts.size()
	info += "  Player Contracts: %d\n" % Game.get_player_contracts().size()
	info += "  Salary Used: %d / %d\n" % [Game.get_player_total_salary(), Game.salary_cap]
	info += "  Cap Space: %dg\n" % Game.get_player_salary_space()
	info += "\n"
	
	# Season state
	info += "📅 SEASON STATE:\n"
	info += "  Draft Done: %s\n" % str(Game.draft_done_for_season)
	info += "  Playoffs Done: %s\n" % str(Game.playoffs_done_for_season)
	info += "  Dungeons: %d completed\n" % Game.season_stats.get("dungeons_completed", 0)
	info += "\n"
	
	# AI Teams
	info += "🤖 AI TEAMS:\n"
	info += "  Total Teams: %d\n" % Game.ai_teams.size()
	for i in range(min(3, Game.ai_teams.size())):
		var team = Game.ai_teams[i]
		info += "  • %s: %d chars\n" % [team.team_name, team.roster.size()]
	if Game.ai_teams.size() > 3:
		info += "  ... and %d more\n" % (Game.ai_teams.size() - 3)
	
	debug_label.text = info

# ═══════════════════════════════════════════════════════════════════
# QUICK ACTIONS
# ═══════════════════════════════════════════════════════════════════

func quick_advance_season():
	"""Complete an entire season cycle automatically"""
	print("[DevTools] Quick advancing season...")
	
	# If in draft, finish it
	if Game.phase == Game.Phase.DRAFT:
		simulate_draft()
	
	# If need draft, do it
	if not Game.draft_done_for_season:
		skip_to_draft()
		simulate_draft()
	
	# Skip to playoffs
	skip_to_playoffs()
	
	# Complete playoffs
	complete_playoffs()
	
	print("[DevTools] Season advanced to %d!" % Game.season)

func advance_multiple_seasons(count: int):
	"""Advance multiple seasons"""
	for i in count:
		quick_advance_season()
		await get_tree().create_timer(0.1).timeout
	print("[DevTools] Advanced %d seasons!" % count)

func skip_to_draft():
	"""Skip directly to draft phase"""
	Game.goto(Game.Phase.GUILD)
	Game.draft_done_for_season = false
	Game.playoffs_done_for_season = true
	print("[DevTools] Ready for draft")

func skip_to_playoffs():
	"""Skip to playoffs"""
	if not Game.draft_done_for_season:
		print("[DevTools] Must complete draft first!")
		return
	
	Game.finish_regular_season()
	print("[DevTools] Entered playoffs")

func simulate_draft():
	"""Auto-complete draft with 3 characters"""
	print("[DevTools] Simulating draft...")
	
	# Generate 3 random characters
	var role_files = [
		"res://data/roles/navigator_role.tres",
		"res://data/roles/healer_role.tres",
		"res://data/roles/tank_role.tres",
		"res://data/roles/damage_role.tres"
	]
	
	# FIX: Properly type the array
	var roles: Array[RoleResource] = []
	for role_path in role_files:
		var role = load(role_path) as RoleResource
		if role:
			roles.append(role)
	
	if roles.is_empty():
		print("[DevTools] No roles found!")
		return
	
	# Generate and sign 3 characters
	const AdventurerResource = preload("res://resources/Adventurer.gd")
	for i in 3:
		var character = AdventurerResource.generate_random_prospect(roles)
		Game.sign_contract(character, null, 3, character.wage)
		print("[DevTools] Drafted: %s" % character.name)
	
	Game.finish_draft()
	print("[DevTools] Draft complete!")

func complete_playoffs():
	"""Auto-complete playoffs (player wins championship)"""
	if Game.phase != Game.Phase.PLAYOFFS:
		print("[DevTools] Not in playoffs!")
		return
	
	print("[DevTools] Completing playoffs...")
	
	# Find all player matches and win them
	while Game.is_player_match_available():
		var match_item = Game.get_next_player_match()
		if match_item:
			Game.complete_player_match(Game.player_team, {"simulated": true})
			await get_tree().create_timer(0.1).timeout
	
	# Process any remaining AI matches
	if Game.playoff_system:
		Game.playoff_system.process_ai_matches()
		await get_tree().create_timer(0.1).timeout
		
		# Keep processing until tournament is complete
		while not Game.playoff_system.current_tournament.is_completed:
			Game.playoff_system.process_ai_matches()
			await get_tree().create_timer(0.1).timeout
	
	print("[DevTools] Playoffs complete!")

func win_next_playoff():
	"""Win the next playoff match"""
	var match_item = Game.get_next_player_match()
	if match_item:
		Game.complete_player_match(Game.player_team, {"simulated": true})
		print("[DevTools] Won playoff match!")
	else:
		print("[DevTools] No playoff match available")

# ═══════════════════════════════════════════════════════════════════
# ROSTER MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

func add_random_character():
	"""Add a random character to roster"""
	var role_files = [
		"res://data/roles/navigator_role.tres",
		"res://data/roles/healer_role.tres",
		"res://data/roles/tank_role.tres",
		"res://data/roles/damage_role.tres"
	]
	
	# FIX: Properly type the array
	var roles: Array[RoleResource] = []
	for role_path in role_files:
		var role = load(role_path) as RoleResource
		if role:
			roles.append(role)
	
	const AdventurerResource = preload("res://resources/Adventurer.gd")
	var character = AdventurerResource.generate_random_prospect(roles)
	Game.sign_contract(character, null, 3, character.wage)
	print("[DevTools] Added: %s" % character.name)

func clear_all_contracts():
	"""Clear all contracts (keep characters in roster)"""
	Game.active_contracts.clear()
	print("[DevTools] Cleared all contracts")

func age_all_characters(years: int):
	"""Age all characters by specified years"""
	for character in Game.roster:
		for i in years:
			character.apply_aging()
	print("[DevTools] Aged all characters +%d years" % years)

func heal_all_injuries():
	"""Heal all injuries on all characters"""
	var count = 0
	for character in Game.roster:
		while character.injuries.size() > 0:
			character.heal_injury(0)
			count += 1
	print("[DevTools] Healed %d injuries" % count)

func cause_random_injury():
	"""Give a random character an injury"""
	if Game.roster.is_empty():
		print("[DevTools] No characters in roster")
		return
	
	var character = Game.roster.pick_random()
	var injury = {
		"type": "test_injury",
		"affected_stat": "attack",
		"stat_penalty": 10,
		"recovery_time": 2,
		"description": "Dev test injury"
	}
	character.add_injury(injury)
	print("[DevTools] Injured: %s" % character.name)

# ═══════════════════════════════════════════════════════════════════
# CHEATS
# ═══════════════════════════════════════════════════════════════════

func max_all_stats():
	"""Max out all stats for player roster"""
	for character in Game.roster:
		character.attack = 200
		character.defense = 200
		character.hp = 200
		character.role_stat = 200
		character.observe_skill = 200
		character.decide_skill = 200
	print("[DevTools] Maxed all character stats!")

func level_up_all(levels: int):
	"""Level up all characters"""
	for character in Game.roster:
		for i in levels:
			character.level_up()
	print("[DevTools] Leveled up all characters +%d" % levels)

func max_all_loyalty():
	"""Max loyalty for all characters"""
	for character in Game.roster:
		character.loyalty_current = 100
	print("[DevTools] Maxed all loyalty!")

func unlock_draft():
	"""Force unlock draft"""
	Game.draft_done_for_season = false
	Game.playoffs_done_for_season = true
	print("[DevTools] Draft unlocked!")

func unlock_playoffs():
	"""Force unlock playoffs"""
	Game.draft_done_for_season = true
	print("[DevTools] Playoffs unlocked!")

# ═══════════════════════════════════════════════════════════════════
# TESTING SCENARIOS
# ═══════════════════════════════════════════════════════════════════

func test_complete_season():
	"""Test: Complete a full season cycle"""
	print("[DevTools] TEST: Complete Season Cycle")
	quick_advance_season()
	print("[DevTools] ✅ Season cycle test complete")

func test_contract_expiration():
	"""Test: Force contract expirations"""
	print("[DevTools] TEST: Contract Expiration")
	
	# Set all contracts to expire next season
	for contract in Game.active_contracts:
		contract.seasons_remaining = 1
	
	print("[DevTools] Set all contracts to expire in 1 season")
	print("[DevTools] Advance season to see expirations")
	print("[DevTools] ✅ Contract expiration test setup complete")

func test_character_aging():
	"""Test: Rapid aging"""
	print("[DevTools] TEST: Character Aging")
	age_all_characters(10)
	print("[DevTools] ✅ Aging test complete")

func test_retirement_cascade():
	"""Test: Force retirements"""
	print("[DevTools] TEST: Retirement Cascade")
	
	# Age characters to retirement age
	for character in Game.roster:
		character.age = character.peak_age + 6
	
	print("[DevTools] Set all characters near retirement")
	print("[DevTools] Advance season to see retirements")
	print("[DevTools] ✅ Retirement test setup complete")

func test_free_agency():
	"""Test: Free agency flow"""
	print("[DevTools] TEST: Free Agency")
	
	# Expire some contracts
	if Game.active_contracts.size() > 0:
		var contract = Game.active_contracts[0]
		contract.seasons_remaining = 0
		print("[DevTools] Will expire: %s" % contract.character.name)
	
	print("[DevTools] Advance season to see free agency")
	print("[DevTools] ✅ Free agency test setup complete")

# ═══════════════════════════════════════════════════════════════════
# SCOUTING SYSTEM TESTS
# ═══════════════════════════════════════════════════════════════════

func test_scouting():
	"""Test the scouting system"""
	print("[DevTools] Testing scouting system...")
	
	# Create test character
	var role_files = [
		"res://data/roles/damage_role.tres"
	]
	var roles: Array[RoleResource] = []
	for role_path in role_files:
		var role = load(role_path) as RoleResource
		if role:
			roles.append(role)
	
	if roles.is_empty():
		print("[DevTools] No roles found!")
		return
	
	const AdventurerResource = preload("res://resources/Adventurer.gd")
	var character = AdventurerResource.generate_random_prospect(roles)
	
	print("Character: %s" % character.name)
	print("True Attack: %d" % character.attack)
	
	# Apply scouting level 0 (no info)
	Game.apply_initial_scouting(character, 0)
	print("Level 0 scout: %s" % Game.get_stat_display(character.name, "attack"))
	
	# Apply scouting level 2
	Game.apply_initial_scouting(character, 2)
	print("Level 2 scout: %s" % Game.get_stat_display(character.name, "attack"))
	
	# Simulate combat
	for i in 5:
		var battle_data = {
			"damage_dealt": 50.0,
			"was_crit": false
		}
		Game.reveal_combat_stats(character.name, battle_data)
		print("After combat %d: %s" % [i + 1, Game.get_stat_display(character.name, "attack")])
	
	print("[DevTools] Scouting test complete!")

func print_scouting_info(character_name: String):
	"""Print detailed scouting info for a character"""
	if not Game.get_character_by_name(character_name):
		print("[DevTools] Character not found: %s" % character_name)
		return
	
	var info = Game.get_scouting_info(character_name)
	print("=== Scouting Info: %s ===" % character_name)
	print("Overall confidence: %.1f%%" % (info.get_overall_confidence() * 100))
	print("Combat experiences: %d" % info.combat_experiences)
	
	print("\nStats:")
	for stat_name in ["attack", "defense", "hp", "speed", "potential"]:
		var stat = info.stats_known[stat_name]
		print("  %s: %s (%.1f%% confidence)" % [
			stat_name,
			stat.get_display_value(),
			stat.confidence * 100
		])

func reveal_all_stats_for_roster():
	"""Fully reveal all stats for current roster"""
	for character in Game.roster:
		for i in 20:
			Game.reveal_combat_stats(character.name, {"damage_dealt": 50.0})
	print("[DevTools] Revealed all stats for %d characters" % Game.roster.size())

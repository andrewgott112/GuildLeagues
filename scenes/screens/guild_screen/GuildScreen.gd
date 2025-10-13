# scenes/screens/guild_screen/GuildScreen.gd
extends Control

@onready var season_label: Label = $Margin/Column/TopBar/SeasonLabel
@onready var lbl_gold: Label    = $Margin/Column/TopBar/GoldBox/GoldValue
@onready var roster_list: VBoxContainer = $Margin/Column/RosterPanel/MarginContainer/RosterPanelVBox/RosterScroll/RosterList

@onready var btn_to_draft: Button = $Margin/Column/BottomBar/ToDraft
@onready var btn_to_dungeons: Button = $Margin/Column/BottomBar/ToDungeon
@onready var btn_save: Button     = $Margin/Column/BottomBar/SaveBtn
@onready var btn_menu: Button     = $Margin/Column/BottomBar/ToMenu

# NEW: Optional playoff button (might not exist in scene yet)
@onready var btn_to_playoffs: Button = get_node_or_null("Margin/Column/BottomBar/ToPlayoffs")

# NEW: Optional progress panel (might not exist in scene yet)
@onready var progress_panel: Panel = get_node_or_null("Margin/Column/ProgressPanel")
@onready var progress_label: Label = get_node_or_null("Margin/Column/ProgressPanel/ProgressMargin/ProgressVBox/ProgressLabel")
@onready var season_stats_label: Label = get_node_or_null("Margin/Column/ProgressPanel/ProgressMargin/ProgressVBox/SeasonStatsLabel")

func _ready() -> void:
	_wire_buttons()
	_refresh_header()
	_refresh_cta()
	_populate_roster()
	_update_progress_panel()
	_update_contract_info()

	# Refresh when game state changes
	if Game.has_signal("phase_changed") and not Game.phase_changed.is_connected(_on_phase_or_season_changed):
		Game.phase_changed.connect(_on_phase_or_season_changed)
	if Game.has_signal("season_changed") and not Game.season_changed.is_connected(_on_phase_or_season_changed):
		Game.season_changed.connect(_on_phase_or_season_changed)
	
	# NEW: Connect playoff signals (only if they exist)
	if Game.has_signal("playoff_match_available") and not Game.playoff_match_available.is_connected(_on_playoff_match_available):
		Game.playoff_match_available.connect(_on_playoff_match_available)
	if Game.has_signal("season_completed") and not Game.season_completed.is_connected(_on_season_completed):
		Game.season_completed.connect(_on_season_completed)

func _wire_buttons() -> void:
	btn_to_draft.pressed.connect(_on_to_draft)
	btn_to_dungeons.pressed.connect(_on_to_dungeons)
	btn_save.pressed.connect(_on_save_pressed)
	btn_menu.pressed.connect(_on_main_menu)
	
	# Connect playoff button only if it exists
	if btn_to_playoffs:
		btn_to_playoffs.pressed.connect(_on_to_playoffs)

# ---------- Header + CTA ----------

func _refresh_header() -> void:
	season_label.text = "Season %d" % Game.season
	lbl_gold.text = str(Game.gold)
	_refresh_cta()

func _phase_text() -> String:
	if Game.has_method("season_progress_text"):
		return Game.season_progress_text()
	if Game.has_method("phase_name"):
		return Game.phase_name()

	if Game.phase == Game.Phase.DRAFT:
		return "Draft"
	elif Game.phase == Game.Phase.GUILD:
		return "Guild"
	elif Game.phase == Game.Phase.DUNGEONS:
		return "Dungeons"
	elif Game.phase == Game.Phase.PLAYOFFS:
		return "Playoffs"
	else:
		return "—"

func _refresh_cta() -> void:
	# Draft button logic
	var draft_unlocked: bool = Game.can_start_draft()
	btn_to_draft.disabled = not draft_unlocked
	btn_to_draft.tooltip_text = "Start the Draft" if draft_unlocked else "Complete the season cycle to unlock the Draft."
	btn_to_draft.modulate = Color(1, 1, 1, 1.0) if draft_unlocked else Color(1, 1, 1, 0.6)
	
	# Dungeons button logic
	var dungeons_unlocked: bool = _can_access_dungeons()
	btn_to_dungeons.disabled = not dungeons_unlocked
	var dungeon_tooltip = "Explore Dungeons"
	if Game.phase == Game.Phase.PLAYOFFS:
		dungeon_tooltip = "Dungeons unavailable during playoffs"
	elif not dungeons_unlocked:
		dungeon_tooltip = "Need at least one adventurer and completed draft"
	btn_to_dungeons.tooltip_text = dungeon_tooltip
	btn_to_dungeons.modulate = Color(1, 1, 1, 1.0) if dungeons_unlocked else Color(1, 1, 1, 0.6)
	
	# NEW: Playoffs button logic (only if button exists)
	if btn_to_playoffs:
		var playoffs_available: bool = _can_access_playoffs()
		btn_to_playoffs.disabled = not playoffs_available
		var playoff_tooltip = ""
		
		if Game.phase == Game.Phase.PLAYOFFS:
			playoff_tooltip = "View Current Playoffs"
			btn_to_playoffs.text = "View Playoffs"
			if Game.has_method("is_player_match_available") and Game.is_player_match_available():
				btn_to_playoffs.text = "⚔️ Playoff Match!"
				btn_to_playoffs.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Highlight
		elif Game.has_method("can_start_playoffs") and Game.can_start_playoffs():
			playoff_tooltip = "Start Playoffs"
			btn_to_playoffs.text = "Start Playoffs"
			btn_to_playoffs.modulate = Color(1, 1, 1, 1.0)
		else:
			playoff_tooltip = "Complete dungeon runs to unlock playoffs"
			btn_to_playoffs.text = "Playoffs Locked"
			btn_to_playoffs.modulate = Color(1, 1, 1, 0.6)
		
		btn_to_playoffs.tooltip_text = playoff_tooltip

func _can_access_dungeons() -> bool:
	return (Game.roster.size() > 0 
		and Game.phase in [Game.Phase.GUILD, Game.Phase.DUNGEONS]  # <-- FIX: Added Game. prefix
		and Game.draft_done_for_season)

func _can_access_playoffs() -> bool:
	# Make this more lenient for testing
	if Game.roster.is_empty():
		return false
	
	# Allow playoffs if:
	# 1. Currently in playoffs phase, OR
	# 2. Have a roster (we'll handle the draft requirement in the button handler)
	return (Game.phase == Game.Phase.PLAYOFFS or Game.roster.size() > 0)

func _can_start_draft() -> bool:
	if Game.has_method("can_start_draft"):
		return Game.can_start_draft()

	var playoffs_ok := true
	if "playoffs_done_for_season" in Game:
		playoffs_ok = Game.playoffs_done_for_season
	return Game.phase == Game.Phase.GUILD and playoffs_ok

# NEW: Progress panel update
func _update_progress_panel():
	if not progress_panel:
		return
	
	progress_panel.visible = true
	
	if not progress_label:
		return
	
	# Phase and season progress
	var progress_text = "Phase: %s\n" % _phase_text()
	
	# Add phase-specific information
	if Game.phase == Game.Phase.GUILD:
		if Game.draft_done_for_season and not Game.playoffs_done_for_season:
			progress_text += "Ready for dungeon exploration"
		elif Game.playoffs_done_for_season:
			progress_text += "Season complete - Draft available"
		else:
			progress_text += "Pre-season preparation"
	elif Game.phase == Game.Phase.DRAFT:
		progress_text += "Building your roster"
	elif Game.phase == Game.Phase.DUNGEONS:
		progress_text += "Explore dungeons to prepare for playoffs"
		if "season_stats" in Game:
			var season_stats = Game.season_stats
			if season_stats.dungeons_completed > 0:
				progress_text += "\nRuns completed: %d" % season_stats.dungeons_completed
	elif Game.phase == Game.Phase.PLAYOFFS:
		if Game.has_method("is_player_match_available") and Game.is_player_match_available():
			progress_text += "⚔️ PLAYOFF MATCH READY!"
		else:
			progress_text += "Tournament in progress"
	
	progress_label.text = progress_text
	
	# Season statistics
	if season_stats_label and "season_stats" in Game:
		var stats_text = ""
		var season_stats = Game.season_stats
		var all_time_stats = {}
		
		if Game.has_method("get_all_time_stats"):
			all_time_stats = Game.get_all_time_stats()
		
		if season_stats.dungeons_completed > 0 or season_stats.total_gold_earned > 0:
			stats_text += "This Season:\n"
			stats_text += "• Dungeons: %d\n" % season_stats.dungeons_completed
			stats_text += "• Gold earned: %d\n" % season_stats.total_gold_earned
			stats_text += "• Monsters defeated: %d\n" % season_stats.monsters_defeated
			if season_stats.playoff_performance != "":
				stats_text += "• Playoff result: %s\n" % season_stats.playoff_performance
		
		if all_time_stats.has("seasons_played") and all_time_stats.seasons_played > 0:
			stats_text += "\nCareer Record:\n"
			stats_text += "• Seasons: %d\n" % all_time_stats.seasons_played
			if all_time_stats.get("championships", 0) > 0:
				stats_text += "• 🏆 Championships: %d\n" % all_time_stats.championships
			stats_text += "• Playoff appearances: %d\n" % all_time_stats.get("playoff_appearances", 0)
			stats_text += "• Total gold: %d" % all_time_stats.get("total_gold", 0)
		
		season_stats_label.text = stats_text

func _update_contract_info():
	"""Display contract and salary cap information"""
	# This will be displayed in the existing progress panel or a new section
	var player_contracts = Game.get_player_contracts()
	var total_salary = Game.get_player_total_salary()
	var salary_space = Game.get_player_salary_space()
	
	print("[Guild] Player Contracts: %d" % player_contracts.size())
	print("[Guild] Total Salary: %d / %d" % [total_salary, Game.salary_cap])
	print("[Guild] Remaining Space: %d" % salary_space)
	
	# Add this info to the progress panel
	if season_stats_label:
		var current_text = season_stats_label.text
		if current_text != "":
			current_text += "\n"
		current_text += "\nContracts & Salary:\n"
		current_text += "• Active contracts: %d\n" % player_contracts.size()
		current_text += "• Salary commitments: %dg/%dg\n" % [total_salary, Game.salary_cap]
		current_text += "• Cap space: %dg" % salary_space
		season_stats_label.text = current_text

func _on_phase_or_season_changed(_arg: Variant = null) -> void:
	_refresh_header()
	_refresh_cta()
	_update_progress_panel()
	_update_contract_info()

# NEW: Handle playoff match availability
func _on_playoff_match_available():
	print("Playoff match available! Refreshing UI...")
	_refresh_cta()
	_update_progress_panel()

# NEW: Handle season completion
func _on_season_completed(season_result: Dictionary):
	print("Season completed: ", season_result)
	
	# Show season results popup
	_show_season_results(season_result)
	
	# Refresh UI
	_refresh_header()
	_refresh_cta()
	_update_progress_panel()

func _show_season_results(results: Dictionary):
	"""Show a popup with season results"""
	var popup = AcceptDialog.new()
	popup.title = "Season %d Results" % results.get("season", Game.season - 1)
	popup.size = Vector2i(400, 300)
	
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	
	# Championship result
	var champion_label = Label.new()
	if results.get("player_champion", false):
		champion_label.text = "🏆 CONGRATULATIONS! 🏆\nYou are the CHAMPION!"
		champion_label.add_theme_color_override("font_color", Color.GOLD)
		champion_label.add_theme_font_size_override("font_size", 18)
	else:
		champion_label.text = "Season Champion: %s" % results.get("champion", "Unknown")
		champion_label.add_theme_color_override("font_color", Color.CYAN)
		champion_label.add_theme_font_size_override("font_size", 16)
	
	champion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(champion_label)
	
	# Player performance
	var performance_label = Label.new()
	performance_label.text = "Your Performance: %s" % results.get("player_performance", "Unknown")
	performance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(performance_label)
	
	# Season stats
	var stats = results.get("stats", {})
	if not stats.is_empty():
		var stats_text = "\nSeason Statistics:\n"
		stats_text += "• Dungeons completed: %d\n" % stats.get("dungeons_completed", 0)
		stats_text += "• Gold earned: %d\n" % stats.get("total_gold_earned", 0)
		stats_text += "• Monsters defeated: %d" % stats.get("monsters_defeated", 0)
		
		var stats_label = Label.new()
		stats_label.text = stats_text
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(stats_label)
	
	# Next season info
	var next_season_label = Label.new()
	next_season_label.text = "\nSeason %d is now available!\nThe draft is open." % Game.season
	next_season_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	next_season_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(next_season_label)
	
	popup.add_child(content)
	add_child(popup)
	popup.popup_centered()
	
	# Auto-cleanup
	popup.confirmed.connect(popup.queue_free)
	popup.close_requested.connect(popup.queue_free)

# ---------- Roster UI ----------

func _populate_roster() -> void:
	# Clear old rows
	for c in roster_list.get_children():
		c.queue_free()

	if Game.roster.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No adventurers yet. Head to the draft!"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		roster_list.add_child(empty_label)
		return

	# Create a simple header row
	roster_list.add_child(_make_header_row())

	# One row per adventurer
	for adv in Game.roster:
		roster_list.add_child(_make_roster_row(adv))

func _make_header_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_col_label("Name", true, 200))
	row.add_child(_col_label("Role", true, 120))
	row.add_child(_col_label("Wage", true, 80))
	row.add_child(_col_label("Details", true, 80))
	return row

func _make_roster_row(adv: Resource) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_col_label(adv.name, false, 200))
	row.add_child(_col_label(adv.role.display_name if adv.role else "—", false, 120))
	row.add_child(_col_label("%dg" % adv.wage, false, 80))
	
	# Add View Details button with fixed width
	var details_btn := Button.new()
	details_btn.text = "View"
	details_btn.custom_minimum_size = Vector2(70, 28)
	details_btn.size_flags_horizontal = 0  # Don't expand
	details_btn.pressed.connect(func():
		_show_character_details(adv)
	)
	
	var button_container := Control.new()
	button_container.custom_minimum_size.x = 80
	button_container.size_flags_horizontal = 0
	button_container.add_child(details_btn)
	details_btn.position.x = 5  # Small offset from left edge
	
	row.add_child(button_container)
	
	return row

func _col_label(text: String, is_header := false, width: int = 120) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = width
	l.size_flags_horizontal = 0  # Don't expand - use fixed width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # Add ... if text too long
	if is_header:
		l.add_theme_color_override("font_color", Color(1,1,1))
		l.add_theme_constant_override("outline_size", 1)
	return l

# ---------- Buttons ----------

func _show_character_details(character) -> void:
	print("Attempting to show details for: %s" % character.name)
	
	# Load and show the character detail window
	var detail_scene_path = "res://scenes/ui/CharacterDetailWindow.tscn"
	
	if not ResourceLoader.exists(detail_scene_path):
		print("ERROR: Character detail window scene not found at: " + detail_scene_path)
		print("Please make sure you have created the scene file at that location")
		# Fallback: print to console
		print("=== CHARACTER DETAILS ===")
		print("Name: %s" % character.name)
		print("Role: %s" % (character.role.display_name if character.role else "None"))
		print("Attack: %d" % character.attack)
		print("Defense: %d" % character.defense)
		print("HP: %d" % character.hp)
		print("Role Stat: %d" % character.role_stat)
		print("Observe: %d" % character.observe_skill)
		print("Decide: %d" % character.decide_skill)
		print("Wage: %d" % character.wage)
		print("Monsters Killed: %d" % character.monsters_killed)
		print("Battles Won: %d" % character.battles_won)
		print("Battles Fought: %d" % character.battles_fought)
		print("========================")
		return
	
	print("Loading character detail window...")
	var detail_scene = load(detail_scene_path)
	var detail_window = detail_scene.instantiate()
	
	print("Adding window to scene tree...")
	add_child(detail_window)
	
	print("Calling show_character...")
	detail_window.show_character(character)
	
	# Auto-cleanup when the window is closed
	detail_window.visibility_changed.connect(func():
		if not detail_window.visible:
			detail_window.queue_free()
	)

func _on_to_draft() -> void:
	if Game.start_draft_gate():
		_switch_scene("res://scenes/screens/draft_screen/draft_screen.tscn")

func _on_to_dungeons() -> void:
	if _can_access_dungeons():
		Game.goto(Game.Phase.DUNGEONS)
		_switch_scene("res://scenes/screens/dungeon_screen/dungeon_screen.tscn")

# NEW: Playoff navigation (only if button exists)
func _on_to_playoffs() -> void:
	print("[Guild] Playoffs button pressed")
	print("[Guild] Current phase: %s" % Game.phase_name())
	print("[Guild] Draft done: %s" % Game.draft_done_for_season)
	print("[Guild] Roster size: %d" % Game.roster.size())
	
	# Debug: Check if we can start playoffs
	if not Game.can_start_playoffs():
		print("[Guild] Cannot start playoffs:")
		if not Game.draft_done_for_season:
			print("  - Draft not completed")
		if Game.roster.is_empty():
			print("  - No roster")
		return
	
	if Game.phase == Game.Phase.PLAYOFFS:  # <-- FIX: Added Game. prefix
		# Already in playoffs, just go to playoff screen
		print("[Guild] Already in playoffs, going to playoff screen")
		_switch_scene("res://scenes/screens/playoff_screen/playoff_screen.tscn")
	else:
		# Start playoffs
		print("[Guild] Starting playoffs...")
		
		# For testing, let's force the conditions to be right
		if not Game.draft_done_for_season:
			print("[Guild] Forcing draft_done_for_season = true for testing")
			Game.draft_done_for_season = true
		
		# Start playoffs directly
		Game.finish_regular_season()  # This triggers playoff start
		print("[Guild] Playoffs started, switching to playoff screen")
		_switch_scene("res://scenes/screens/playoff_screen/playoff_screen.tscn")

func _on_save_pressed() -> void:
	print("Save not implemented yet.")

func _on_main_menu() -> void:
	_switch_scene("res://scenes/screens/main_menu/main_menu.tscn")

func _switch_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

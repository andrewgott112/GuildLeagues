# scenes/screens/playoff_screen/PlayoffScreen.gd
extends Control

@onready var tournament_title: Label = $Margin/Column/TopBar/TournamentTitle
@onready var round_info: Label = $Margin/Column/TopBar/RoundInfo
@onready var player_status: Label = $Margin/Column/TopBar/PlayerStatus

@onready var bracket_scroll: ScrollContainer = $Margin/Column/BracketPanel/BracketScroll
@onready var bracket_container: VBoxContainer = $Margin/Column/BracketPanel/BracketScroll/BracketContainer

@onready var match_panel: Panel = $Margin/Column/MatchPanel
@onready var match_info: Label = $Margin/Column/MatchPanel/MatchVBox/MatchInfo
@onready var play_match_btn: Button = $Margin/Column/MatchPanel/MatchVBox/MatchButtons/PlayMatchBtn
@onready var view_opponent_btn: Button = $Margin/Column/MatchPanel/MatchVBox/MatchButtons/ViewOpponentBtn

@onready var standings_list: VBoxContainer = $Margin/Column/StandingsPanel/StandingsScroll/StandingsList
@onready var back_btn: Button = $Margin/Column/BottomBar/BackBtn
@onready var sim_round_btn: Button = $Margin/Column/BottomBar/SimRoundBtn

# Battle integration
var battle_window_scene = preload("res://scenes/ui/BattleWindow.tscn")
var current_battle_window = null
var current_player_match = null

# UI state
var bracket_data: Dictionary = {}
var update_timer: Timer

func _ready():
	print("PlayoffScreen: Initializing...")
	
	# Create update timer
	update_timer = Timer.new()
	update_timer.wait_time = 1.0
	update_timer.timeout.connect(_refresh_display)
	add_child(update_timer)
	
	# Connect buttons
	play_match_btn.pressed.connect(_on_play_match_pressed)
	view_opponent_btn.pressed.connect(_on_view_opponent_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	sim_round_btn.pressed.connect(_on_sim_round_pressed)
	
	# Connect game signals
	if Game.has_signal("playoff_match_available"):
		Game.playoff_match_available.connect(_on_match_available)
	
	# Initial display
	_refresh_display()
	update_timer.start()
	
	print("PlayoffScreen: Ready!")

func _refresh_display():
	_update_tournament_info()
	_update_player_match_panel()
	_update_bracket_display()
	_update_standings()

func _update_tournament_info():
	var playoff_system = Game.playoff_system
	if not playoff_system or not playoff_system.current_tournament:
		tournament_title.text = "No Tournament Active"
		round_info.text = ""
		player_status.text = ""
		return
	
	var tournament = playoff_system.current_tournament
	tournament_title.text = "%s - Season %d" % [playoff_system.league_name, Game.season]
	
	if tournament.is_completed:
		if tournament.champion:
			round_info.text = "TOURNAMENT COMPLETE"
			if tournament.champion == Game.player_team:
				player_status.text = "🏆 CHAMPION! 🏆"
			else:
				player_status.text = "Champion: %s" % tournament.champion.team_name
		else:
			round_info.text = "Tournament ended"
			player_status.text = "No champion determined"
	else:
		round_info.text = "Round %d of %d" % [tournament.current_round, tournament.max_rounds]
		
		# Player status
		current_player_match = Game.get_next_player_match()
		if current_player_match:
			var opponent = current_player_match.team1 if current_player_match.team2 == Game.player_team else current_player_match.team2
			player_status.text = "Next: vs %s" % opponent.team_name
		else:
			player_status.text = "Waiting for next round..."

func _update_player_match_panel():
	current_player_match = Game.get_next_player_match()
	
	if current_player_match:
		match_panel.visible = true
		var opponent = current_player_match.team1 if current_player_match.team2 == Game.player_team else current_player_match.team2
		
		var match_text = "Round %d Match\n" % current_player_match.round_number
		match_text += "Your Guild vs %s\n\n" % opponent.team_name
		match_text += opponent.get_team_description()
		
		# Add tactical preview
		var tactics = opponent.get_battle_tactics()
		match_text += "\n\nTactical Analysis:"
		if tactics.aggression_modifier > 0.1:
			match_text += "\n• Aggressive playstyle"
		elif tactics.aggression_modifier < -0.1:
			match_text += "\n• Defensive playstyle"
		else:
			match_text += "\n• Balanced approach"
		
		if tactics.experience_bonus > 0.05:
			match_text += "\n• Veteran experience"
		
		match_info.text = match_text
		play_match_btn.disabled = false
		view_opponent_btn.disabled = false
	else:
		match_panel.visible = false
		play_match_btn.disabled = true
		view_opponent_btn.disabled = true

func _update_bracket_display():
	# Clear existing bracket
	for child in bracket_container.get_children():
		child.queue_free()
	
	var playoff_system = Game.playoff_system
	if not playoff_system or not playoff_system.current_tournament:
		var no_tournament_label = Label.new()
		no_tournament_label.text = "No tournament data available"
		bracket_container.add_child(no_tournament_label)
		return
	
	_build_bracket_visualization(playoff_system.current_tournament)

func _build_bracket_visualization(tournament):
	"""Build a visual representation of the tournament bracket"""
	
	# Group matches by round
	var rounds_data = {}
	for match in tournament.matches:
		if not rounds_data.has(match.round_number):
			rounds_data[match.round_number] = []
		rounds_data[match.round_number].append(match)
	
	# Create round columns
	var rounds_container = HBoxContainer.new()
	rounds_container.add_theme_constant_override("separation", 20)
	bracket_container.add_child(rounds_container)
	
	var round_numbers = rounds_data.keys()
	round_numbers.sort()
	
	for round_num in round_numbers:
		var round_column = _create_round_column(round_num, rounds_data[round_num])
		rounds_container.add_child(round_column)

func _create_round_column(round_num: int, matches: Array) -> VBoxContainer:
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	
	# Round header
	var header = Label.new()
	header.text = _get_round_name(round_num, Game.playoff_system.current_tournament.max_rounds)
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color.CYAN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(header)
	
	# Match cards
	for match in matches:
		var match_card = _create_match_card(match)
		column.add_child(match_card)
	
	return column

func _create_match_card(match) -> Panel:
	var card = Panel.new()
	card.custom_minimum_size = Vector2(200, 80)
	
	# Style based on match status
	var style = StyleBoxFlat.new()
	match match.status:
		Game.playoff_system.MatchStatus.COMPLETED:
			style.bg_color = Color(0.2, 0.4, 0.2, 0.9)  # Green tint
		Game.playoff_system.MatchStatus.PENDING:
			if _is_player_match(match):
				style.bg_color = Color(0.4, 0.4, 0.2, 0.9)  # Yellow tint for player match
			else:
				style.bg_color = Color(0.3, 0.3, 0.3, 0.9)  # Gray
		_:
			style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	
	style.border_color = Color.WHITE
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	card.add_theme_stylebox_override("panel", style)
	
	# Card content
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	vbox.add_child(margin)
	
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	margin.add_child(content)
	
	# Team names with highlighting
	var team1_label = Label.new()
	team1_label.text = _get_team_display_name(match.team1)
	if match.status == Game.playoff_system.MatchStatus.COMPLETED and match.winner == match.team1:
		team1_label.add_theme_color_override("font_color", Color.GOLD)
		team1_label.text += " ✓"
	elif _is_player_team(match.team1):
		team1_label.add_theme_color_override("font_color", Color.CYAN)
	content.add_child(team1_label)
	
	var vs_label = Label.new()
	vs_label.text = "vs"
	vs_label.add_theme_font_size_override("font_size", 10)
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(vs_label)
	
	var team2_label = Label.new()
	team2_label.text = _get_team_display_name(match.team2)
	if match.status == Game.playoff_system.MatchStatus.COMPLETED and match.winner == match.team2:
		team2_label.add_theme_color_override("font_color", Color.GOLD)
		team2_label.text += " ✓"
	elif _is_player_team(match.team2):
		team2_label.add_theme_color_override("font_color", Color.CYAN)
	content.add_child(team2_label)
	
	# Match status
	var status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 9)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	match match.status:
		Game.playoff_system.MatchStatus.COMPLETED:
			status_label.text = "Final"
			status_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
		Game.playoff_system.MatchStatus.PENDING:
			if _is_player_match(match):
				status_label.text = "Your Match"
				status_label.add_theme_color_override("font_color", Color.YELLOW)
			else:
				status_label.text = "Pending"
				status_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	
	content.add_child(status_label)
	
	return card

func _update_standings():
	# Clear existing standings
	for child in standings_list.get_children():
		child.queue_free()
	
	# Header
	var header = _create_standings_header()
	standings_list.add_child(header)
	
	# Get standings data
	var standings = Game.get_league_standings()
	
	for i in range(standings.size()):
		var team_data = standings[i]
		var row = _create_standings_row(i + 1, team_data)
		standings_list.add_child(row)

func _create_standings_header() -> HBoxContainer:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	
	var rank_label = Label.new()
	rank_label.text = "Rank"
	rank_label.custom_minimum_size.x = 50
	rank_label.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(rank_label)
	
	var team_label = Label.new()
	team_label.text = "Team"
	team_label.custom_minimum_size.x = 150
	team_label.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(team_label)
	
	var record_label = Label.new()
	record_label.text = "W-L"
	record_label.custom_minimum_size.x = 60
	record_label.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(record_label)
	
	var rate_label = Label.new()
	rate_label.text = "Win%"
	rate_label.custom_minimum_size.x = 60
	rate_label.add_theme_color_override("font_color", Color.CYAN)
	header.add_child(rate_label)
	
	return header

func _create_standings_row(rank: int, team_data: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	
	var rank_label = Label.new()
	rank_label.text = str(rank)
	rank_label.custom_minimum_size.x = 50
	row.add_child(rank_label)
	
	var team_label = Label.new()
	team_label.text = _get_team_display_name(team_data.team)
	team_label.custom_minimum_size.x = 150
	if _is_player_team(team_data.team):
		team_label.add_theme_color_override("font_color", Color.CYAN)
	row.add_child(team_label)
	
	var record_label = Label.new()
	record_label.text = "%d-%d" % [team_data.wins, team_data.losses]
	record_label.custom_minimum_size.x = 60
	row.add_child(record_label)
	
	var rate_label = Label.new()
	rate_label.text = "%.1f%%" % (team_data.win_rate * 100)
	rate_label.custom_minimum_size.x = 60
	row.add_child(rate_label)
	
	return row

# Helper functions
func _get_round_name(round_num: int, max_rounds: int) -> String:
	if round_num == max_rounds:
		return "Championship"
	elif round_num == max_rounds - 1:
		return "Semifinals"
	elif round_num == max_rounds - 2:
		return "Quarterfinals"
	else:
		return "Round %d" % round_num

func _get_team_display_name(team: AITeamResource) -> String:
	if _is_player_team(team):
		return "Your Guild"
	return team.team_name

func _is_player_team(team: AITeamResource) -> bool:
	return team == Game.player_team

func _is_player_match(match) -> bool:
	return match.team1 == Game.player_team or match.team2 == Game.player_team

# Button handlers
func _on_play_match_pressed():
	if not current_player_match:
		print("No player match available!")
		return
	
	print("Starting player match...")
	
	# Get opponent team
	var opponent = current_player_match.team1 if current_player_match.team2 == Game.player_team else current_player_match.team2
	
	# Generate monsters based on opponent's roster
	var enemy_monsters = []
	for adventurer in opponent.roster:
		var monster = MonsterResource.new()
		monster.name = adventurer.name
		monster.level = 1
		monster.attack = adventurer.attack
		monster.defense = adventurer.defense
		monster.hp = adventurer.hp
		monster.max_hp = adventurer.hp
		monster.current_hp = adventurer.hp
		monster.observe_skill = adventurer.observe_skill
		monster.decide_skill = adventurer.decide_skill
		
		# Apply team tactics to monster behavior
		var tactics = opponent.get_battle_tactics()
		monster.aggression = 0.5 + tactics.aggression_modifier
		monster.intelligence = 0.3 + tactics.experience_bonus
		monster.survival_instinct = 0.4 + (tactics.risk_taking * -0.2)
		
		enemy_monsters.append(monster)
	
	# Create and show battle window
	current_battle_window = battle_window_scene.instantiate()
	add_child(current_battle_window)
	
	var encounter_name = "Playoff Match: vs %s" % opponent.team_name
	current_battle_window.setup_battle(Game.roster, enemy_monsters, encounter_name)
	current_battle_window.battle_window_closed.connect(_on_battle_finished)
	current_battle_window.show_battle()

func _on_view_opponent_pressed():
	if not current_player_match:
		return
	
	var opponent = current_player_match.team1 if current_player_match.team2 == Game.player_team else current_player_match.team2
	_show_team_details(opponent)

func _show_team_details(team: AITeamResource):
	# Create a simple popup with team details
	var popup = AcceptDialog.new()
	popup.title = "Team Details: %s" % team.team_name
	popup.size = Vector2i(400, 300)
	
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	
	var description = Label.new()
	description.text = team.get_team_description()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	
	var stats_label = Label.new()
	stats_label.text = "\nTeam Statistics:"
	stats_label.add_theme_color_override("font_color", Color.CYAN)
	content.add_child(stats_label)
	
	var record_label = Label.new()
	record_label.text = "Record: %d-%d (%.1f%%)" % [team.total_wins, team.total_losses, team.get_win_rate() * 100]
	content.add_child(record_label)
	
	var strength_label = Label.new()
	strength_label.text = "Team Strength: %d" % team.get_team_strength()
	content.add_child(strength_label)
	
	if team.championships > 0:
		var titles_label = Label.new()
		titles_label.text = "Championships: %d" % team.championships
		titles_label.add_theme_color_override("font_color", Color.GOLD)
		content.add_child(titles_label)
	
	popup.add_child(content)
	add_child(popup)
	popup.popup_centered()
	
	# Auto-cleanup
	popup.confirmed.connect(popup.queue_free)
	popup.close_requested.connect(popup.queue_free)

func _on_battle_finished(battle_result: Dictionary):
	print("Playoff battle finished: ", battle_result)
	
	# Clean up battle window
	if current_battle_window:
		current_battle_window.queue_free()
		current_battle_window = null
	
	# Determine winner
	var winner = Game.player_team if battle_result.get("victory", false) else (current_player_match.team1 if current_player_match.team2 == Game.player_team else current_player_match.team2)
	
	# Complete the match
	var battle_details = {
		"team1_survivors": battle_result.get("living_players", 0) if winner == Game.player_team else battle_result.get("living_enemies", 0),
		"team2_survivors": battle_result.get("living_enemies", 0) if winner == Game.player_team else battle_result.get("living_players", 0),
		"total_turns": battle_result.get("turn_count", 0)
	}
	
	Game.complete_player_match(winner, battle_details)
	
	# Refresh display
	_refresh_display()

func _on_sim_round_pressed():
	"""Simulate AI matches for current round"""
	if Game.playoff_system:
		Game.playoff_system.process_ai_matches()
		_refresh_display()

func _on_back_pressed():
	"""Return to guild (only if tournament is complete)"""
	if Game.playoff_system and Game.playoff_system.current_tournament.is_completed:
		get_tree().change_scene_to_file("res://scenes/screens/guild_screen/guild_screen.tscn")
	else:
		print("Cannot leave playoffs until tournament is complete!")

func _on_match_available():
	"""Handle when a new player match becomes available"""
	print("New playoff match available!")
	_refresh_display()

# Import MonsterResource for battle simulation
const MonsterResource = preload("res://resources/Monster.gd")

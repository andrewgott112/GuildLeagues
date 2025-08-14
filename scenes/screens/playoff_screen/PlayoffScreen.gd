# scenes/screens/playoff_screen/PlayoffScreen.gd
extends Control

# Safe references - use get_node_or_null for all UI elements
@onready var tournament_title: Label = get_node_or_null("Margin/Column/TopBar/TournamentTitle")
@onready var round_info: Label = get_node_or_null("Margin/Column/TopBar/RoundInfo")
@onready var player_status: Label = get_node_or_null("Margin/Column/TopBar/PlayerStatus")

@onready var bracket_scroll: ScrollContainer = get_node_or_null("Margin/Column/MainContent/LeftSide/BracketPanel/BracketScroll")
@onready var bracket_container: VBoxContainer = get_node_or_null("Margin/Column/MainContent/LeftSide/BracketPanel/BracketScroll/BracketContainer")

@onready var match_panel: Panel = get_node_or_null("Margin/Column/MainContent/LeftSide/MatchPanel")
@onready var match_info: Label = get_node_or_null("Margin/Column/MainContent/LeftSide/MatchPanel/MatchVBox/MatchInfo")
@onready var play_match_btn: Button = get_node_or_null("Margin/Column/MainContent/LeftSide/MatchPanel/MatchVBox/MatchButtons/PlayMatchBtn")
@onready var view_opponent_btn: Button = get_node_or_null("Margin/Column/MainContent/LeftSide/MatchPanel/MatchVBox/MatchButtons/ViewOpponentBtn")

@onready var standings_list: VBoxContainer = get_node_or_null("Margin/Column/MainContent/RightSide/StandingsPanel/StandingsScroll/StandingsList")
@onready var back_btn: Button = get_node_or_null("Margin/Column/BottomBar/BackBtn")
@onready var sim_round_btn: Button = get_node_or_null("Margin/Column/BottomBar/SimRoundBtn")

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
	
	# Connect buttons - with null checks
	if play_match_btn:
		play_match_btn.pressed.connect(_on_play_match_pressed)
	if view_opponent_btn:
		view_opponent_btn.pressed.connect(_on_view_opponent_pressed)
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)
	if sim_round_btn:
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
		if tournament_title != null:
			tournament_title.text = "No Tournament Active"
		if round_info != null:
			round_info.text = ""
		if player_status != null:
			player_status.text = ""
		return
	
	var tournament = playoff_system.current_tournament
	if tournament_title != null:
		tournament_title.text = "%s - Season %d" % [playoff_system.league_name, Game.season]
	
	if tournament.is_completed:
		if tournament.champion:
			if round_info != null:
				round_info.text = "TOURNAMENT COMPLETE"
			if player_status != null:
				if tournament.champion == Game.player_team:
					player_status.text = "🏆 CHAMPION! 🏆"
				else:
					player_status.text = "Champion: %s" % tournament.champion.team_name
		else:
			if round_info != null:
				round_info.text = "Tournament ended"
			if player_status != null:
				player_status.text = "No champion determined"
	else:
		if round_info != null:
			round_info.text = "Round %d of %d" % [tournament.current_round, tournament.max_rounds]
		
		# Player status
		current_player_match = Game.get_next_player_match()
		if player_status != null:
			if current_player_match:
				var opponent = current_player_match.team1 if current_player_match.team2 == Game.player_team else current_player_match.team2
				player_status.text = "Next: vs %s" % opponent.team_name
			else:
				player_status.text = "Waiting for next round..."

func _update_player_match_panel():
	current_player_match = Game.get_next_player_match()
	
	if current_player_match:
		if match_panel:
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
		
		if match_info:
			match_info.text = match_text
		if play_match_btn:
			play_match_btn.disabled = false
		if view_opponent_btn:
			view_opponent_btn.disabled = false
	else:
		# NULL CHECK: Only set visible if match_panel exists
		if match_panel != null:
			match_panel.visible = false
		if play_match_btn != null:
			play_match_btn.disabled = true
		if view_opponent_btn != null:
			view_opponent_btn.disabled = true

func _update_bracket_display():
	# Clear existing bracket - NULL CHECK
	if bracket_container != null:
		for child in bracket_container.get_children():
			child.queue_free()
	
	var playoff_system = Game.playoff_system
	if not playoff_system or not playoff_system.current_tournament:
		if bracket_container != null:
			var no_tournament_label = Label.new()
			no_tournament_label.text = "No tournament data available"
			bracket_container.add_child(no_tournament_label)
		return
	
	if bracket_container != null:
		_build_bracket_visualization(playoff_system.current_tournament)

func _build_bracket_visualization(tournament):
	"""Build a visual representation of the tournament bracket"""
	
	# NULL CHECK: Only proceed if bracket_container exists
	if bracket_container == null:
		print("Cannot build bracket - bracket_container is null")
		return
	
	# Simple version - just list matches
	var match_count = 0
	for match_item in tournament.matches:
		var match_label = Label.new()
		var status_text = ""
		if match_item.status == Game.playoff_system.MatchStatus.COMPLETED:
			status_text = " ✓ %s wins" % match_item.winner.team_name
		elif match_item.status == Game.playoff_system.MatchStatus.PENDING:
			status_text = " (Pending)"
		
		match_label.text = "Round %d: %s vs %s%s" % [
			match_item.round_number,
			match_item.team1.team_name,
			match_item.team2.team_name,
			status_text
		]
		bracket_container.add_child(match_label)
		match_count += 1
		
		if match_count > 10:  # Limit display to prevent overflow
			break

func _update_standings():
	# Clear existing standings - NULL CHECK
	if standings_list != null:
		for child in standings_list.get_children():
			child.queue_free()
	
	if standings_list == null:
		return
	
	# Header
	var header = Label.new()
	header.text = "Tournament Standings"
	header.add_theme_color_override("font_color", Color.CYAN)
	standings_list.add_child(header)
	
	# Get standings data
	var standings = Game.get_league_standings()
	
	for i in range(min(standings.size(), 8)):  # Limit to 8 teams
		var team_data = standings[i]
		var row = Label.new()
		row.text = "%d. %s (%d-%d)" % [
			i + 1,
			team_data.team.team_name if team_data.team == Game.player_team else team_data.team.team_name,
			team_data.wins,
			team_data.losses
		]
		if team_data.team == Game.player_team:
			row.add_theme_color_override("font_color", Color.CYAN)
		standings_list.add_child(row)

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

func _show_team_details(team):
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

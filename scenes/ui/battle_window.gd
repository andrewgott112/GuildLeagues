# scenes/ui/battle_window.gd
extends AcceptDialog

const BattleSystem = preload("res://scripts/systems/battle_system.gd")
const MonsterResource = preload("res://resources/Monster.gd")

# UI References
@onready var battle_title: Label = $MainContainer/MainVBox/HeaderSection/BattleTitle
@onready var battle_status: Label = $MainContainer/MainVBox/HeaderSection/BattleStatus
@onready var players_list: VBoxContainer = $MainContainer/MainVBox/CombatantsSection/PlayersPanel/PlayersScroll/PlayersList
@onready var enemies_list: VBoxContainer = $MainContainer/MainVBox/CombatantsSection/EnemiesPanel/EnemiesScroll/EnemiesList
@onready var log_text: RichTextLabel = $MainContainer/MainVBox/LogSection/LogScroll/LogText
@onready var start_battle_btn: Button = $MainContainer/MainVBox/ButtonsSection/StartBattleBtn
@onready var close_btn: Button = $MainContainer/MainVBox/ButtonsSection/CloseBtn

# Battle data
var battle_system: BattleSystem
var player_party: Array = []
var enemy_monsters: Array = []
var battle_finished: bool = false
var update_timer: Timer

signal battle_window_closed(result: Dictionary)

func _ready():
	print("BattleWindow _ready() called")
	
	# Connect buttons
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)
	
	# Create update timer for real-time updates during battle
	update_timer = Timer.new()
	update_timer.wait_time = 0.1  # Update every 100ms
	update_timer.timeout.connect(_update_display)
	add_child(update_timer)
	
	# Initialize battle system
	battle_system = BattleSystem.new()
	add_child(battle_system)
	
	# Connect battle system signals
	battle_system.battle_started.connect(_on_battle_started)
	battle_system.phase_changed.connect(_on_phase_changed)
	battle_system.action_completed.connect(_on_action_completed)
	battle_system.battle_finished.connect(_on_battle_finished)
	battle_system.combatant_died.connect(_on_combatant_died)
	
	print("BattleWindow setup complete")

func setup_battle(party: Array, monsters: Array, encounter_name: String = "Combat Encounter"):
	"""Setup the battle with given party and monsters"""
	print("Setting up battle: %s vs %d monsters" % [encounter_name, monsters.size()])
	
	player_party = party.duplicate()
	enemy_monsters = monsters.duplicate()
	battle_finished = false
	
	battle_title.text = encounter_name
	battle_status.text = "Press 'Start Battle' to begin combat"
	start_battle_btn.disabled = false
	start_battle_btn.text = "Start Battle"
	
	_populate_combatants()
	_clear_log()
	_add_log_message("Battle encounter: %s" % encounter_name)
	_add_log_message("Party: %d adventurers vs %d enemies" % [party.size(), monsters.size()])

func _populate_combatants():
	"""Populate the combatant lists in the UI"""
	# Clear existing lists
	for child in players_list.get_children():
		child.queue_free()
	for child in enemies_list.get_children():
		child.queue_free()
	
	# Add player party
	for adventurer in player_party:
		var card = _create_combatant_card(adventurer.name, adventurer, true)
		players_list.add_child(card)
	
	# Add enemies
	for monster in enemy_monsters:
		var card = _create_combatant_card(monster.name, monster, false)
		enemies_list.add_child(card)

func _create_combatant_card(combatant_name: String, combatant_data, is_player: bool) -> Control:
	"""Create a card showing combatant info"""
	var card = Panel.new()
	card.custom_minimum_size = Vector2(0, 80)
	
	# Add some styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8) if is_player else Color(0.3, 0.1, 0.1, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2  
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.8, 0.5, 1) if is_player else Color(0.8, 0.5, 0.5, 1)
	card.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	
	# Name and role
	var name_label = Label.new()
	name_label.text = combatant_name
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)
	
	# Stats
	var stats_label = Label.new()
	if is_player:
		var adv = combatant_data as AdventurerResource
		stats_label.text = "ATK: %d | DEF: %d | HP: %d" % [adv.attack, adv.defense, adv.hp]
		stats_label.add_theme_font_size_override("font_size", 11)
	else:
		var monster = combatant_data as MonsterResource
		stats_label.text = "ATK: %d | DEF: %d | HP: %d/%d" % [monster.attack, monster.defense, monster.current_hp, monster.max_hp]
		stats_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(stats_label)
	
	# Phase status (will be updated during battle)
	var phase_label = Label.new()
	phase_label.text = "Ready"
	phase_label.add_theme_font_size_override("font_size", 10)
	phase_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	phase_label.name = "PhaseLabel"
	vbox.add_child(phase_label)
	
	return card

func _on_start_battle_pressed():
	"""Start the battle when button is pressed"""
	if battle_system.is_battle_active():
		print("Battle already active!")
		return
	
	print("Starting battle with %d party members and %d enemies" % [player_party.size(), enemy_monsters.size()])
	
	if battle_system.start_battle(player_party, enemy_monsters):
		start_battle_btn.disabled = true
		start_battle_btn.text = "Battle in Progress..."
		battle_status.text = "Battle in progress - watch the action unfold!"
		update_timer.start()
		_add_log_message("[color=yellow]Battle has begun![/color]")
	else:
		_add_log_message("[color=red]Failed to start battle![/color]")

func _on_battle_started():
	"""Called when battle system starts the battle"""
	print("Battle started signal received")
	_add_log_message("[color=green]All combatants enter the battlefield![/color]")

func _on_phase_changed(combatant_name: String, phase: String):
	"""Called when a combatant changes phase"""
	_add_log_message("[color=cyan]%s: %s[/color]" % [combatant_name, phase])
	_update_combatant_phase_display(combatant_name, phase)

func _on_action_completed(combatant_name: String, action: String, result: Dictionary):
	"""Called when a combatant completes an action"""
	var message = "[color=white]%s completed: %s[/color]" % [combatant_name, action]
	
	if result.has("target") and result.has("damage"):
		message += " - %d damage to %s" % [result.damage, result.target]
	
	if result.get("target_defeated", false):
		message += " [color=red](DEFEATED!)[/color]"
	
	_add_log_message(message)

func _on_combatant_died(combatant_name: String):
	"""Called when a combatant dies"""
	_add_log_message("[color=red]%s has fallen in battle![/color]" % combatant_name)

func _on_battle_finished(result: Dictionary):
	"""Called when the battle ends"""
	battle_finished = true
	update_timer.stop()
	start_battle_btn.disabled = true
	
	if result.victory:
		battle_status.text = "Victory! Your party has won the battle!"
		_add_log_message("[color=green][b]VICTORY![/b] All enemies have been defeated![/color]")
	else:
		battle_status.text = "Defeat! Your party has been overwhelmed!"
		_add_log_message("[color=red][b]DEFEAT![/b] Your party has been defeated![/color]")
	
	close_btn.text = "Continue"
	
	# Update final stats for any surviving monsters
	_update_display()
	
	print("Battle finished: Victory = %s" % result.victory)

func _update_display():
	"""Update the display during battle"""
	if not battle_system.is_battle_active():
		return
	
	# Update combatant health and status
	var combatants = battle_system.get_combatants()
	
	# Update player cards
	var player_cards = players_list.get_children()
	var player_index = 0
	for i in range(combatants.size()):
		var combatant = combatants[i]
		if combatant.is_player_controlled and player_index < player_cards.size():
			_update_combatant_card(player_cards[player_index], combatant)
			player_index += 1
	
	# Update enemy cards  
	var enemy_cards = enemies_list.get_children()
	var enemy_index = 0
	for i in range(combatants.size()):
		var combatant = combatants[i]
		if not combatant.is_player_controlled and enemy_index < enemy_cards.size():
			_update_combatant_card(enemy_cards[enemy_index], combatant)
			enemy_index += 1

func _update_combatant_card(card: Control, combatant):
	"""Update a specific combatant card with current battle info"""
	var vbox = card.get_child(0).get_child(0)  # MarginContainer -> VBoxContainer
	if vbox.get_child_count() >= 3:
		# Update stats (second label)
		var stats_label = vbox.get_child(1) as Label
		if combatant.is_player_controlled and combatant.adventurer:
			stats_label.text = "ATK: %d | DEF: %d | HP: %d" % [
				combatant.adventurer.attack, 
				combatant.adventurer.defense, 
				combatant.adventurer.hp
			]
		elif combatant.monster:
			stats_label.text = "ATK: %d | DEF: %d | HP: %d/%d" % [
				combatant.monster.attack, 
				combatant.monster.defense, 
				combatant.monster.current_hp, 
				combatant.monster.max_hp
			]
		
		# Update phase (third label)
		var phase_label = vbox.get_child(2) as Label
		if not combatant.is_alive():
			phase_label.text = "DEFEATED"
			phase_label.add_theme_color_override("font_color", Color.RED)
		elif combatant.fled:
			phase_label.text = "FLED"
			phase_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			var phase_text = "Ready"
			match combatant.current_phase:
				BattleSystem.BattlePhase.OBSERVE:
					phase_text = "Observing... (%.1fs)" % combatant.phase_timer
				BattleSystem.BattlePhase.DECIDE:
					phase_text = "Deciding... (%.1fs)" % combatant.phase_timer
				BattleSystem.BattlePhase.ACTION:
					phase_text = "Acting... (%.1fs)" % combatant.phase_timer
			phase_label.text = phase_text
			phase_label.add_theme_color_override("font_color", Color.CYAN)

func _update_combatant_phase_display(combatant_name: String, phase: String):
	"""Update the phase display for a specific combatant"""
	# This is handled by _update_display() which runs regularly during battle
	pass

func _clear_log():
	"""Clear the battle log"""
	log_text.text = ""

func _add_log_message(message: String):
	"""Add a message to the battle log"""
	if log_text.text != "":
		log_text.text += "\n"
	log_text.text += message
	
	# Auto-scroll to bottom
	await get_tree().process_frame
	var scroll_container = log_text.get_parent() as ScrollContainer
	if scroll_container:
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

func _on_close_pressed():
	"""Handle close button press"""
	print("Battle window close pressed")
	
	# Stop battle if still active
	if battle_system.is_battle_active():
		battle_system.force_end_battle()
		_add_log_message("[color=orange]Battle was interrupted![/color]")
	
	# Emit result
	var result = {
		"completed": battle_finished,
		"victory": false,  # Default to false if interrupted
		"interrupted": not battle_finished
	}
	
	if battle_finished:
		# Get the actual battle result
		var battle_log = battle_system.get_battle_log()
		result.victory = "VICTORY" in battle_log[-1] if battle_log.size() > 0 else false
	
	battle_window_closed.emit(result)
	hide()

func show_battle():
	"""Show the battle window"""
	popup_centered()
	print("Battle window shown")

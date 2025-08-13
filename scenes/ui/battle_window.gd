extends AcceptDialog

const BattleSystem = preload("res://scripts/systems/battle_system.gd")

# UI References - found manually in _ready
var battle_title: Label
var battle_status: Label
var players_list: VBoxContainer
var enemies_list: VBoxContainer
var log_text: RichTextLabel
var start_battle_btn: Button
var close_btn: Button

# Battle data
var battle_system: BattleSystem
var player_party: Array = []
var enemy_monsters: Array = []
var battle_finished: bool = false
var update_timer: Timer

signal battle_window_closed(result: Dictionary)

func _ready():
	print("BattleWindow _ready() called")
	
	# Wait for scene to load
	await get_tree().process_frame
	
	# Find UI nodes
	_find_ui_nodes()
	
	# Connect signals
	if start_battle_btn:
		start_battle_btn.pressed.connect(_on_start_battle_pressed)
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)
	
	# Create battle system
	battle_system = BattleSystem.new()
	add_child(battle_system)
	
	# Create timer
	update_timer = Timer.new()
	update_timer.wait_time = 0.1
	update_timer.timeout.connect(_update_display)
	add_child(update_timer)
	
	# Connect battle signals
	battle_system.battle_started.connect(_on_battle_started)
	battle_system.battle_finished.connect(_on_battle_finished)
	
	print("BattleWindow ready!")

func _find_ui_nodes():
	"""Find all UI nodes"""
	battle_title = find_child("BattleTitle", true, false)
	battle_status = find_child("BattleStatus", true, false)
	players_list = find_child("PlayersList", true, false)
	enemies_list = find_child("EnemiesList", true, false)
	log_text = find_child("LogText", true, false)
	start_battle_btn = find_child("StartBattleBtn", true, false)
	close_btn = find_child("CloseBtn", true, false)
	
	print("Found UI nodes: title=%s, players=%s, enemies=%s" % [
		str(battle_title != null),
		str(players_list != null), 
		str(enemies_list != null)
	])

func setup_battle(party: Array, monsters: Array, encounter_name: String = "Combat"):
	"""Setup the battle"""
	print("Setting up battle: %s" % encounter_name)
	
	player_party = party.duplicate()
	enemy_monsters = monsters.duplicate()
	battle_finished = false
	
	# Set UI
	if battle_title:
		battle_title.text = encounter_name
	if battle_status:
		battle_status.text = "Press 'Start Battle' to begin"
	if start_battle_btn:
		start_battle_btn.disabled = false
		start_battle_btn.text = "Start Battle"
	
	# Setup log
	if log_text:
		log_text.text = "Battle: %s\nParty: %d vs %d enemies\nReady to fight!" % [encounter_name, party.size(), monsters.size()]
	
	# Create combatant cards
	_create_combatant_cards()

func _create_combatant_cards():
	"""Create simple combatant cards"""
	print("Creating combatant cards...")
	
	# Clear existing
	if players_list:
		for child in players_list.get_children():
			child.queue_free()
	if enemies_list:
		for child in enemies_list.get_children():
			child.queue_free()
	
	# Wait for cleanup
	await get_tree().process_frame
	
	# Add player cards
	if players_list:
		for adventurer in player_party:
			var card = _create_card(adventurer.name, adventurer, true)
			players_list.add_child(card)
		print("Added %d player cards" % players_list.get_child_count())
	
	# Add enemy cards
	if enemies_list:
		for monster in enemy_monsters:
			var card = _create_card(monster.name, monster, false)
			enemies_list.add_child(card)
		print("Added %d enemy cards" % enemies_list.get_child_count())
	
	# Force scroll container sizes
	_set_scroll_sizes()

func _create_card(name: String, data, is_player: bool) -> Panel:
	"""Create a simple combatant card"""
	var card = Panel.new()
	card.custom_minimum_size = Vector2(200, 60)
	
	# Style
	var style = StyleBoxFlat.new()
	if is_player:
		style.bg_color = Color(0.2, 0.4, 0.2, 0.9)
		style.border_color = Color(0.4, 0.8, 0.4)
	else:
		style.bg_color = Color(0.4, 0.2, 0.2, 0.9)
		style.border_color = Color(0.8, 0.4, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	card.add_theme_stylebox_override("panel", style)
	
	# Label
	var label = Label.new()
	label.text = name
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	return card

func _set_scroll_sizes():
	"""Set minimum sizes for scroll containers"""
	var players_scroll = find_child("PlayersScroll", true, false)
	var enemies_scroll = find_child("ScrollContainer", true, false)
	
	if players_scroll:
		players_scroll.custom_minimum_size = Vector2(0, 120)
		print("Set players scroll size")
	
	if enemies_scroll:
		enemies_scroll.custom_minimum_size = Vector2(0, 120)
		print("Set enemies scroll size")

func _on_start_battle_pressed():
	"""Start battle"""
	print("Starting battle...")
	
	if battle_system.start_battle(player_party, enemy_monsters):
		if start_battle_btn:
			start_battle_btn.disabled = true
			start_battle_btn.text = "Fighting..."
		if battle_status:
			battle_status.text = "Battle in progress!"
		update_timer.start()
		_log("⚔️ Battle begins!")
	else:
		_log("❌ Failed to start battle")

func _on_battle_started():
	"""Battle started"""
	_log("🎯 All combatants ready!")

func _on_battle_finished(result: Dictionary):
	"""Battle finished"""
	battle_finished = true
	update_timer.stop()
	
	if result.get("victory", false):
		_log("🎉 VICTORY!")
		if battle_status:
			battle_status.text = "Victory!"
	else:
		_log("💀 DEFEAT!")
		if battle_status:
			battle_status.text = "Defeat!"
	
	if close_btn:
		close_btn.text = "Continue"

func _on_close_pressed():
	"""Close window"""
	print("Closing battle window")
	
	if battle_system and battle_system.is_battle_active():
		battle_system.force_end_battle()
	
	var result = {"completed": battle_finished, "victory": false}
	battle_window_closed.emit(result)
	hide()

func _log(message: String):
	"""Add log message"""
	if log_text:
		if log_text.text != "":
			log_text.text += "\n"
		log_text.text += message

func _update_display():
	"""Update display during battle"""
	# Simple update - just keep the battle running
	pass

func show_battle():
	"""Show the battle window"""
	popup_centered()
	print("Battle window shown")

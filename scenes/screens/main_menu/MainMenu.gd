extends Control

@onready var btn_new_game: Button = $MarginContainer/VBoxContainer/Button
@onready var btn_load_game: Button = $MarginContainer/VBoxContainer/Button2
@onready var btn_settings: Button = $MarginContainer/VBoxContainer/Button3

func _ready() -> void:
	btn_new_game.pressed.connect(_on_new_game_pressed)
	btn_load_game.pressed.connect(_on_load_game_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)

func _on_new_game_pressed() -> void:
	Game.start_new_game()
	Game.goto(Game.Phase.GUILD)  # Sends player to Guild Management
	_switch_scene("res://scenes/screens/guild_screen/guild_screen.tscn")

func _on_load_game_pressed() -> void:
	# You can stub this until you implement saving
	print("Load Game pressed")

func _on_settings_pressed() -> void:
	print("Settings pressed")

func _switch_scene(scene_path: String) -> void:
	var new_scene = load(scene_path).instantiate()
	get_tree().root.add_child(new_scene)
	queue_free() # Remove the main menu

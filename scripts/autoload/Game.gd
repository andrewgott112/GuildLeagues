extends Node

enum Phase { MAIN_MENU, GUILD, DRAFT, DUNGEON_SELECT, BATTLE, RESULTS, PLAYOFFS, SEASON_SUMMARY }
var phase: Phase = Phase.MAIN_MENU
var season: int = 1
var gold: int = 20
var roster: Array = []

signal phase_changed(new_phase: Phase)

func goto(p: Phase) -> void:
	phase = p
	emit_signal("phase_changed", p)

func start_new_game() -> void:
	season = 1
	gold = 20
	roster.clear()
	goto(Phase.GUILD)

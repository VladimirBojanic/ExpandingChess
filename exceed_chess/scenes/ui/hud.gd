extends Control

@onready var turn_label: Label = $TurnLabel
@onready var sp_label: Label = $SPLabel
@onready var win_panel: Panel = $WinPanel
@onready var win_label: Label = $WinPanel/WinLabel
@onready var restart_button: Button = $WinPanel/RestartButton

func _ready() -> void:
	if win_panel:
		win_panel.hide()
	if restart_button:
		restart_button.pressed.connect(_on_restart)

func update(player_id: int, turn: int, sp: Array) -> void:
	var player_name := "White" if player_id == 0 else "Black"
	if turn_label:
		turn_label.text = "Turn %d — %s to move" % [turn, player_name]
	if sp_label:
		sp_label.text = "SP: White %d | Black %d" % [sp[0], sp[1]]

func show_win(winner_id: int, reason: String) -> void:
	var player_name := "White" if winner_id == 0 else "Black"
	if win_label:
		win_label.text = "%s wins!\n(%s)" % [player_name, reason]
	if win_panel:
		win_panel.show()

func _on_restart() -> void:
	get_tree().reload_current_scene()

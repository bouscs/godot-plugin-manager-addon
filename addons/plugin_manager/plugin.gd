@tool
extends EditorPlugin

const PANEL_SCENE := preload("res://addons/plugin_manager/ui/manager_panel.tscn")
const TOOL_MENU_LABEL := "Check Addon Updates"

var _panel: Control
var _manager: PluginManager


func _enter_tree() -> void:
	_panel = PANEL_SCENE.instantiate()
	_manager = _panel.get_manager()
	add_control_to_bottom_panel(_panel, "Addons")
	add_tool_menu_item(TOOL_MENU_LABEL, _on_check_updates_pressed)
	_start_deferred_check()


func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_MENU_LABEL)
	remove_control_from_bottom_panel(_panel)
	if _panel:
		_panel.queue_free()


func _on_check_updates_pressed() -> void:
	_manager.check_all()
	make_bottom_panel_item_visible(_panel)


func _start_deferred_check() -> void:
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = 0.5
	add_child(timer)
	timer.timeout.connect(func():
		if Engine.get_frames_per_second() >= 10:
			timer.stop()
			timer.queue_free()
			_manager.check_all()
	)
	timer.start()

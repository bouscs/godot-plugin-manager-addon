@tool
extends MarginContainer
## Bottom panel UI for the Plugin Manager addon.

const ADDON_ROW_SCENE := preload("res://addons/plugin_manager/ui/addon_row.tscn")

@onready var _status_label: Label = %StatusLabel
@onready var _check_button: Button = %CheckButton
@onready var _update_all_button: Button = %UpdateAllButton
@onready var _addon_list: VBoxContainer = %AddonList
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _manager: PluginManager = %PluginManager


func get_manager() -> PluginManager:
	return %PluginManager


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_check_button.pressed.connect(_on_check_pressed)
	_update_all_button.pressed.connect(_on_update_all_pressed)
	_update_all_button.hide()
	_manager.addon_status_changed.connect(_on_addon_status_changed)
	_manager.all_checks_completed.connect(_on_all_checks_completed)
	_manager.update_completed.connect(_on_update_completed)
	_manager.update_failed.connect(_on_update_failed)


func _on_check_pressed() -> void:
	_clear_addon_list()
	_status_label.text = "Checking..."
	_check_button.disabled = true
	_log_label.text = ""
	_manager.check_all()


func _on_update_all_pressed() -> void:
	for addon_id in _manager.addons:
		var state: Dictionary = _manager.addons[addon_id]
		if state.status == PluginManager.AddonStatus.UPDATE_AVAILABLE:
			_manager.update_addon(addon_id)


func _on_addon_status_changed(addon_id: String) -> void:
	_ensure_row_exists(addon_id)
	_update_row(addon_id)
	_update_summary()


func _on_all_checks_completed() -> void:
	_check_button.disabled = false
	_update_summary()


func _on_update_completed(addon_id: String) -> void:
	_log("[color=green]Updated %s successfully.[/color] Restart the editor to reload." % addon_id)


func _on_update_failed(addon_id: String, error: String) -> void:
	_log("[color=red]Update failed for %s: %s[/color]" % [addon_id, error])


func _ensure_row_exists(addon_id: String) -> void:
	for child in _addon_list.get_children():
		if child.addon_id == addon_id:
			return
	var row: Control = ADDON_ROW_SCENE.instantiate()
	row.addon_id = addon_id
	row.update_requested.connect(_on_row_update_requested)
	_addon_list.add_child(row)


func _update_row(addon_id: String) -> void:
	for child in _addon_list.get_children():
		if child.addon_id == addon_id:
			child.update_display(_manager.addons[addon_id])
			return


func _on_row_update_requested(addon_id: String) -> void:
	_manager.update_addon(addon_id)


func _update_summary() -> void:
	var total := _manager.addons.size()
	var updates := 0
	var errors := 0
	for addon_id in _manager.addons:
		match _manager.addons[addon_id].status:
			PluginManager.AddonStatus.UPDATE_AVAILABLE:
				updates += 1
			PluginManager.AddonStatus.ERROR:
				errors += 1
	var parts: Array[String] = ["%d addon(s)" % total]
	if updates > 0:
		parts.append("%d update(s)" % updates)
	if errors > 0:
		parts.append("%d error(s)" % errors)
	_status_label.text = ", ".join(parts)
	_update_all_button.visible = updates > 0


func _clear_addon_list() -> void:
	for child in _addon_list.get_children():
		child.queue_free()


func _log(bbcode: String) -> void:
	_log_label.append_text(bbcode + "\n")

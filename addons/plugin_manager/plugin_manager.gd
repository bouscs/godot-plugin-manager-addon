@tool
class_name PluginManager
extends Node
## Scans addons for plugin_manager.json configs, checks GitHub for updates,
## and coordinates the update process.

signal addon_status_changed(addon_id: String)
signal all_checks_completed
signal update_started(addon_id: String)
signal update_completed(addon_id: String)
signal update_failed(addon_id: String, error: String)

const CONFIG_FILENAME := "plugin_manager.json"

enum AddonStatus {
	UNKNOWN,
	CHECKING,
	UP_TO_DATE,
	UPDATE_AVAILABLE,
	DOWNLOADING,
	INSTALLING,
	ERROR,
}

## addon_id -> state dictionary
var addons: Dictionary = {}

var _github_client: PMGitHubClient
var _installer: PMUpdateInstaller
var _pending_checks: int = 0


func _ready() -> void:
	_github_client = PMGitHubClient.new()
	_github_client.release_fetched.connect(_on_release_fetched)
	_github_client.request_failed.connect(_on_request_failed)
	add_child(_github_client)

	_installer = PMUpdateInstaller.new()
	_installer.install_completed.connect(_on_install_completed)
	_installer.install_failed.connect(_on_install_failed)
	_installer.download_progress_changed.connect(_on_download_progress)
	add_child(_installer)


func scan_addons() -> void:
	addons.clear()
	var dir := DirAccess.open("res://addons/")
	if dir == null:
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and folder != "plugin_manager":
			var json_path := "res://addons/%s/%s" % [folder, CONFIG_FILENAME]
			if FileAccess.file_exists(json_path):
				var config := _load_config(json_path)
				if config.size() > 0:
					addons[folder] = {
						addon_id = folder,
						config = config,
						config_path = json_path,
						status = AddonStatus.UNKNOWN,
						remote_version = "",
						download_url = "",
						changelog = "",
						error_message = "",
						download_progress = 0.0,
					}
		folder = dir.get_next()


func check_all() -> void:
	scan_addons()
	if addons.is_empty():
		all_checks_completed.emit()
		return
	_pending_checks = addons.size()
	for addon_id in addons:
		var state: Dictionary = addons[addon_id]
		state.status = AddonStatus.CHECKING
		addon_status_changed.emit(addon_id)
		_github_client.fetch_latest_release(addon_id, state.config.repo)


func update_addon(addon_id: String) -> void:
	if not addons.has(addon_id):
		return
	var state: Dictionary = addons[addon_id]
	if state.status != AddonStatus.UPDATE_AVAILABLE:
		return
	state.status = AddonStatus.DOWNLOADING
	addon_status_changed.emit(addon_id)
	update_started.emit(addon_id)

	var config: Dictionary = state.config
	var addon_folder: String = config.get("addon_folder", "addons/%s" % addon_id)
	_installer.start_update(
		addon_id,
		state.download_url,
		addon_folder,
		config.get("strip_root_dir", true),
		config.get("path_match", "addons/"),
	)


func _load_config(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[PluginManager] Cannot open: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("[PluginManager] Invalid JSON: %s" % path)
		return {}
	var data: Dictionary = json.data
	if not data.has("repo"):
		push_warning("[PluginManager] Missing 'repo' in: %s" % path)
		return {}
	if not data.has("current_version"):
		push_warning("[PluginManager] Missing 'current_version' in: %s" % path)
		return {}
	return data


func _on_release_fetched(addon_id: String, release: Dictionary) -> void:
	if not addons.has(addon_id):
		_decrement_pending()
		return
	var state: Dictionary = addons[addon_id]
	var tag: String = release.get("tag_name", "")
	var remote_version := tag.trim_prefix("v")
	state.remote_version = remote_version
	state.changelog = release.get("body", "")

	# Resolve download URL
	var download_url := ""
	var config: Dictionary = state.config
	if config.get("use_zipball", false):
		download_url = release.get("zipball_url", "")
	elif config.has("asset_name") and not str(config.asset_name).is_empty():
		var assets: Array = release.get("assets", [])
		var pattern: String = config.asset_name
		for asset in assets:
			var asset_name: String = asset.get("name", "")
			if asset_name.matchn(pattern):
				download_url = asset.get("browser_download_url", "")
				break
		if download_url.is_empty():
			download_url = release.get("zipball_url", "")
	else:
		download_url = release.get("zipball_url", "")
	state.download_url = download_url

	if remote_version != state.config.current_version and not remote_version.is_empty():
		state.status = AddonStatus.UPDATE_AVAILABLE
	else:
		state.status = AddonStatus.UP_TO_DATE
	addon_status_changed.emit(addon_id)
	_decrement_pending()


func _on_request_failed(addon_id: String, error: String) -> void:
	if not addons.has(addon_id):
		_decrement_pending()
		return
	var state: Dictionary = addons[addon_id]
	state.status = AddonStatus.ERROR
	state.error_message = error
	addon_status_changed.emit(addon_id)
	_decrement_pending()


func _on_install_completed(addon_id: String) -> void:
	if not addons.has(addon_id):
		return
	var state: Dictionary = addons[addon_id]
	state.config.current_version = state.remote_version
	_save_config(state.config_path, state.config)
	state.status = AddonStatus.UP_TO_DATE
	addon_status_changed.emit(addon_id)
	update_completed.emit(addon_id)


func _on_install_failed(addon_id: String, error: String) -> void:
	if not addons.has(addon_id):
		return
	var state: Dictionary = addons[addon_id]
	state.status = AddonStatus.ERROR
	state.error_message = error
	addon_status_changed.emit(addon_id)
	update_failed.emit(addon_id, error)


func _on_download_progress(addon_id: String, progress: float) -> void:
	if not addons.has(addon_id):
		return
	addons[addon_id].download_progress = progress
	addon_status_changed.emit(addon_id)


func _decrement_pending() -> void:
	_pending_checks -= 1
	if _pending_checks <= 0:
		_pending_checks = 0
		all_checks_completed.emit()


func _save_config(path: String, config: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[PluginManager] Cannot write: %s" % path)
		return
	file.store_string(JSON.stringify(config, "\t"))

@tool
class_name PMUpdateInstaller
extends Node
## Downloads a release zip, replaces the old addon folder, and extracts the new version.

signal install_completed(addon_id: String)
signal install_failed(addon_id: String, error: String)
signal download_progress_changed(addon_id: String, progress: float)

const STAGING_DIR := "res://addons/plugin_manager/staging/"

var _http: HTTPRequest
var _current_addon_id: String
var _current_addon_folder: String
var _zip_path: String


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	_http.use_threads = true
	_http.request_completed.connect(_on_download_completed)
	add_child(_http)
	DirAccess.make_dir_recursive_absolute(STAGING_DIR)


func start_update(addon_id: String, url: String, addon_folder: String,
		_strip_root: bool, _path_match: String) -> void:
	_current_addon_id = addon_id
	_current_addon_folder = addon_folder
	_zip_path = STAGING_DIR + addon_id + "_update.zip"

	var headers := ["User-Agent: GodotPluginManager"]
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		install_failed.emit(addon_id, "Download request failed: %d" % err)


func _process(_delta: float) -> void:
	if _http.get_body_size() > 0 and not _current_addon_id.is_empty():
		var progress := float(_http.get_downloaded_bytes()) / float(_http.get_body_size())
		download_progress_changed.emit(_current_addon_id, progress)


func _on_download_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[PM] Download completed: result=%d, code=%d, body_size=%d" % [result, response_code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		install_failed.emit(_current_addon_id, "Download failed (result %d)" % result)
		return
	if response_code != 200:
		install_failed.emit(_current_addon_id, "Download HTTP %d" % response_code)
		return

	# Save zip to staging
	var file := FileAccess.open(_zip_path, FileAccess.WRITE)
	if file == null:
		install_failed.emit(_current_addon_id, "Cannot write zip to staging")
		return
	file.store_buffer(body)
	file.close()
	print("[PM] Zip saved to: %s" % _zip_path)

	# Small delay before extraction
	await get_tree().create_timer(0.25).timeout
	_extract_and_replace()


## Find the addon root inside the zip by locating plugin.cfg.
## Returns the zip path prefix that maps to the addon folder,
## e.g. "game-database-addon/addons/game_database/" or "addons/game_database/".
func _find_addon_root(files: PackedStringArray) -> String:
	for path in files:
		if path.get_file() == "plugin.cfg":
			var base := path.get_base_dir()
			return (base + "/") if not base.is_empty() else ""
	return ""


func _extract_and_replace() -> void:
	var zip := ZIPReader.new()
	var err := zip.open(_zip_path)
	if err != OK:
		print("[PM] ERROR: Cannot open zip file, err=%d" % err)
		install_failed.emit(_current_addon_id, "Cannot open zip file")
		return

	var files := zip.get_files()
	print("[PM] Zip contains %d entries" % files.size())
	for i in mini(files.size(), 10):
		print("[PM]   %s" % files[i])
	if files.size() > 10:
		print("[PM]   ... and %d more" % (files.size() - 10))

	if files.is_empty():
		zip.close()
		install_failed.emit(_current_addon_id, "Zip is empty")
		return

	# Find where the addon lives inside the zip
	var zip_addon_root := _find_addon_root(files)
	print("[PM] Detected addon root in zip: '%s'" % zip_addon_root)
	if zip_addon_root.is_empty():
		zip.close()
		install_failed.emit(_current_addon_id,
				"Cannot find plugin.cfg in zip — unable to determine addon root")
		return

	# Verify we can extract at least some files before trashing the old folder
	var extractable_files: Array[String] = []
	for zip_path in files:
		if not zip_path.begins_with(zip_addon_root):
			continue
		if zip_path == zip_addon_root:
			continue
		extractable_files.append(zip_path)

	print("[PM] Extractable files: %d" % extractable_files.size())
	if extractable_files.is_empty():
		zip.close()
		install_failed.emit(_current_addon_id, "No addon files found in zip")
		return

	# Backup plugin_manager.json before deleting
	var full_addon_path := "res://" + _current_addon_folder
	var pm_json_path := full_addon_path.path_join(PluginManager.CONFIG_FILENAME)
	var pm_json_backup := ""
	if FileAccess.file_exists(pm_json_path):
		var f := FileAccess.open(pm_json_path, FileAccess.READ)
		if f:
			pm_json_backup = f.get_as_text()
	print("[PM] Addon path: %s, backup pm.json: %s" % [full_addon_path, not pm_json_backup.is_empty()])

	# Delete old addon folder (moves to trash for recovery)
	if DirAccess.dir_exists_absolute(full_addon_path):
		var trash_err := OS.move_to_trash(ProjectSettings.globalize_path(full_addon_path))
		print("[PM] move_to_trash result: %d" % trash_err)
		await get_tree().create_timer(0.5).timeout
	print("[PM] Dir exists after trash: %s" % DirAccess.dir_exists_absolute(full_addon_path))

	# Extract addon files — map zip_addon_root -> full_addon_path
	var extracted_count := 0
	var skipped_count := 0
	for zip_path in extractable_files:
		var relative := zip_path.substr(zip_addon_root.length())
		var dest_path := full_addon_path.path_join(relative)

		if zip_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest_path)
		else:
			var parent := dest_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(parent):
				var mkdir_err := DirAccess.make_dir_recursive_absolute(parent)
				if mkdir_err != OK:
					print("[PM] ERROR mkdir '%s': %d" % [parent, mkdir_err])
			var out := FileAccess.open(dest_path, FileAccess.WRITE)
			if out == null:
				print("[PM] SKIP (can't open): %s — error: %d" % [dest_path, FileAccess.get_open_error()])
				skipped_count += 1
				continue
			out.store_buffer(zip.read_file(zip_path))
			out.close()
			extracted_count += 1

	zip.close()
	print("[PM] Extracted: %d, Skipped: %d" % [extracted_count, skipped_count])

	# Restore plugin_manager.json
	if not pm_json_backup.is_empty():
		DirAccess.make_dir_recursive_absolute(full_addon_path)
		var f := FileAccess.open(pm_json_path, FileAccess.WRITE)
		if f:
			f.store_string(pm_json_backup)
			f.close()

	# Cleanup staging zip
	DirAccess.remove_absolute(_zip_path)

	# Trigger editor filesystem rescan
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

	print("[PM] Install complete for %s" % _current_addon_id)
	install_completed.emit(_current_addon_id)
	_current_addon_id = ""

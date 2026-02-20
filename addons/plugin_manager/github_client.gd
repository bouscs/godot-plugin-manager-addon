@tool
class_name PMGitHubClient
extends Node
## Lightweight GitHub API client for fetching latest release info.

signal release_fetched(addon_id: String, release_data: Dictionary)
signal request_failed(addon_id: String, error: String)

const API_URL := "https://api.github.com/repos/%s/releases/latest"
const REQUEST_HEADERS := [
	"Accept: application/vnd.github.v3+json",
	"User-Agent: GodotPluginManager",
]

var _http: HTTPRequest
var _current_addon_id: String
var _queue: Array[Dictionary] = []
var _busy: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func fetch_latest_release(addon_id: String, repo: String) -> void:
	_queue.append({addon_id = addon_id, repo = repo})
	_process_queue()


func _process_queue() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var item: Dictionary = _queue.pop_front()
	_current_addon_id = item.addon_id
	var url := API_URL % item.repo
	var err := _http.request(url, REQUEST_HEADERS, HTTPClient.METHOD_GET)
	if err != OK:
		request_failed.emit(_current_addon_id, "HTTP request error: %d" % err)
		_busy = false
		_process_queue()


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(_current_addon_id, "Connection error (result %d)" % result)
		_process_queue()
		return
	if response_code == 403:
		request_failed.emit(_current_addon_id, "GitHub rate limit exceeded")
		_process_queue()
		return
	if response_code == 404:
		request_failed.emit(_current_addon_id, "Repository or release not found")
		_process_queue()
		return
	if response_code != 200:
		request_failed.emit(_current_addon_id, "HTTP %d" % response_code)
		_process_queue()
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		request_failed.emit(_current_addon_id, "JSON parse error")
		_process_queue()
		return
	release_fetched.emit(_current_addon_id, json.data)
	_process_queue()

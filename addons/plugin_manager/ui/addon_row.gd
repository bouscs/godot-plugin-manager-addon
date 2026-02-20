@tool
extends HBoxContainer
## A single row in the plugin manager panel representing one managed addon.

signal update_requested(addon_id: String)

var addon_id: String

@onready var _name_label: Label = %NameLabel
@onready var _version_label: Label = %VersionLabel
@onready var _status_label: Label = %StatusLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _update_button: Button = %UpdateButton


func _ready() -> void:
	_update_button.pressed.connect(func(): update_requested.emit(addon_id))
	_progress_bar.hide()
	_update_button.hide()


func update_display(state: Dictionary) -> void:
	_name_label.text = state.addon_id

	match state.status:
		PluginManager.AddonStatus.UNKNOWN:
			_status_label.text = "..."
			_version_label.text = state.config.current_version
			_update_button.hide()
			_progress_bar.hide()
		PluginManager.AddonStatus.CHECKING:
			_status_label.text = "Checking..."
			_version_label.text = state.config.current_version
			_update_button.hide()
			_progress_bar.hide()
		PluginManager.AddonStatus.UP_TO_DATE:
			_status_label.text = "Up to date"
			_version_label.text = state.config.current_version
			_update_button.hide()
			_progress_bar.hide()
		PluginManager.AddonStatus.UPDATE_AVAILABLE:
			_status_label.text = "Update available"
			_version_label.text = "%s -> %s" % [state.config.current_version, state.remote_version]
			_update_button.show()
			_update_button.disabled = false
			_progress_bar.hide()
		PluginManager.AddonStatus.DOWNLOADING:
			_status_label.text = "Downloading..."
			_progress_bar.show()
			_progress_bar.value = state.download_progress * 100.0
			_update_button.hide()
		PluginManager.AddonStatus.INSTALLING:
			_status_label.text = "Installing..."
			_progress_bar.show()
			_progress_bar.value = 100.0
			_update_button.hide()
		PluginManager.AddonStatus.ERROR:
			_status_label.text = "Error: %s" % state.error_message
			_version_label.text = state.config.current_version
			_update_button.hide()
			_progress_bar.hide()

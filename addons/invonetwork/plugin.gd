@tool
extends EditorPlugin
## Editor integration: registers the `Invo` autoload, defines the project
## settings, and adds the INVO dock.

const AUTOLOAD_NAME: String = "Invo"
const DOCK_SCENE: String = "res://addons/invonetwork/dock/invo_dock.tscn"

var _dock: Control
var _export_guard: InvoExportGuard


func _enter_tree() -> void:
	_define_setting("invonetwork/config/environment", TYPE_STRING, "sandbox",
			PROPERTY_HINT_ENUM, "sandbox,production")
	_define_setting("invonetwork/config/sandbox_game_id", TYPE_STRING, "")
	_define_setting("invonetwork/config/production_game_id", TYPE_STRING, "")
	_define_setting("invonetwork/config/game_id", TYPE_STRING, "")
	_define_setting("invonetwork/config/player_token_endpoint", TYPE_STRING, "")
	_define_setting("invonetwork/sandbox_only/game_secret", TYPE_STRING, "",
			PROPERTY_HINT_PASSWORD)
	for key: String in ["game_name", "game_icon_url", "currency_name", "currency_icon_url",
			"game_version"]:
		_define_setting("invonetwork/display/" + key, TYPE_STRING, "")
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/invonetwork/invo.gd")
	_export_guard = InvoExportGuard.new()
	add_export_plugin(_export_guard)
	_dock = (load(DOCK_SCENE) as PackedScene).instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _export_guard != null:
		remove_export_plugin(_export_guard)
		_export_guard = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	remove_autoload_singleton(AUTOLOAD_NAME)


static func _define_setting(setting_name: String, type: int, default_value: Variant,
		hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(setting_name):
		ProjectSettings.set_setting(setting_name, default_value)
	ProjectSettings.set_initial_value(setting_name, default_value)
	ProjectSettings.add_property_info({
		"name": setting_name,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	})

@tool
class_name InvoExportGuard
extends EditorExportPlugin
## Export-time secret check. The release-build lockout stops the sandbox
## secret from being USED in an exported game, but a secret saved in
## project.godot still SHIPS inside the export (project settings are packed
## into the PCK, where any player can extract them). There is no supported
## way to strip a setting during export, so this guard makes the leak
## impossible to miss: every export with a persisted secret gets a loud
## error pointing at the fix (clear the setting; use INVO_SANDBOX_SECRET).

const SETTING_SANDBOX_SECRET: String = "invonetwork/sandbox_only/game_secret"


func _get_name() -> String:
	return "InvoExportGuard"


func _export_begin(_features: PackedStringArray, is_debug: bool, _path: String,
		_flags: int) -> void:
	var secret: String = str(ProjectSettings.get_setting(
			SETTING_SANDBOX_SECRET, "")).strip_edges()
	if secret.is_empty():
		return
	var msg: String = (
		"[INVO] The sandbox game secret is saved in project.godot and is being " +
		"PACKED INTO THIS EXPORT (%s). Players can extract it from the PCK. " +
		"Clear Project Settings -> Invonetwork -> Sandbox Only -> Game Secret " +
		"and use the INVO_SANDBOX_SECRET environment variable instead, then " +
		"re-export."
	) % ("debug build" if is_debug else "RELEASE build")
	push_error(msg)

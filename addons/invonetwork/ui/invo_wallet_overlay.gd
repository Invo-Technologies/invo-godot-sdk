extends CanvasLayer
## InvoWalletOverlay — the zero-integration path: add this scene as an
## autoload (or instance it anywhere) and the wallet toggles over the game.
##
## The toggle action is `invo_wallet_toggle`. If the project hasn't defined
## it, a default binding (F8) is registered at runtime so drop-in stays
## drop-in; define the action in the InputMap to pick your own key.

const ACTION: String = "invo_wallet_toggle"

@onready var _panel: Control = $Center/InvoWalletPanel

var _was_mouse_captured: bool = false


func _ready() -> void:
	layer = 100
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_F8
		InputMap.action_add_event(ACTION, key)
	$Center.visible = false
	# No credentials configured anywhere? Fall back to the offline mock so the
	# panel still demonstrates the flows (dev builds only — never ship the mock).
	if OS.is_debug_build() \
			and OS.get_environment(Invo.SECRET_ENV_VAR).strip_edges().is_empty() \
			and str(ProjectSettings.get_setting(Invo.SETTING_SANDBOX_SECRET, "")).is_empty() \
			and str(ProjectSettings.get_setting(Invo.SETTING_TOKEN_ENDPOINT, "")).is_empty():
		Invo.enable_mock()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	$Center.visible = not $Center.visible
	if $Center.visible:
		_was_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _was_mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

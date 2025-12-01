extends Node

#what are the settings?
#SFX VOL
#MUSIC VOL
#LANGUAGE
#FULLSCREEN MODE
#CONTROLS

var default_values:Dictionary = {
	"SFX_VOL": 10,
	"MUSIC_VOL": 10,
	"ENVIRONMENT_VOL": 10,
	"LANGUAGE": "en-GB",
	"LANGUAGE_SELECTED": 0,
	"GFX_FULLSCREEN_MODE": 2,
	"GFX_QUALITY": 1,
	"MOUSE_Y_INVERT": 0,
	"MOUSE_CONTROLS": 0,
	"RUMBLE": 1,
	"LEVEL_EDITOR": 0,
	"MOUSE_SENSITIVITY": 6,
	"MULTIPLAYER_SKIN_INDEX": 0
}

const SETTINGS_PATH:String = "user://settings.txt"

var settings_values:Dictionary = {}

var default_sfx_channel_volume:float
var default_music_channel_volume:float
var default_environment_channel_volume:float
var default_outside_channel_volume:float
var default_gui_channel_volume:float

var invert_mouse_y:bool = false
var mouse_moves_camera:bool = false

func _ready():
	var sfx_channel_idx:int = AudioServer.get_bus_index("SFX")
	var music_channel_idx:int = AudioServer.get_bus_index("Music")
	var environment_channel_idx:int = AudioServer.get_bus_index("Environment")
	var outside_channel_idx:int = AudioServer.get_bus_index("Outside")
	var gui_channel_idx:int = AudioServer.get_bus_index("GUI")
	default_sfx_channel_volume = AudioServer.get_bus_volume_linear(sfx_channel_idx)
	default_music_channel_volume = AudioServer.get_bus_volume_linear(music_channel_idx)
	default_environment_channel_volume = AudioServer.get_bus_volume_linear(environment_channel_idx)
	default_outside_channel_volume = AudioServer.get_bus_volume_linear(outside_channel_idx)
	default_gui_channel_volume = AudioServer.get_bus_volume_linear(gui_channel_idx)
	print(default_sfx_channel_volume,", ",default_music_channel_volume,", ",default_environment_channel_volume,", ",default_outside_channel_volume)
	load_settings()
	apply_settings()

func revert_settings():
	print("revert_settings")
	#when reverting, remember language
	var language = settings_values["LANGUAGE"]
	if !FileAccess.file_exists(SETTINGS_PATH):
		return
	DirAccess.remove_absolute(SETTINGS_PATH)
	load_settings()
	settings_values["LANGUAGE"] = language
	settings_values["LANGUAGE_SELECTED"] = 1
	apply_settings()
	save_settings()

func load_settings():
	#populate settings_values from default_values
	for key in default_values.keys():
		settings_values[key] = default_values[key]

	if FileAccess.file_exists(SETTINGS_PATH):
		var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var content = file.get_as_text()
		var settings_lines:PackedStringArray = content.split("\n")
		for setting_line in settings_lines:
			var key_value : PackedStringArray = setting_line.split("=")
			if key_value.size() == 2:
				if !settings_values.has(key_value[0]):
					print("unknown setting: ",key_value[0])
					continue
				var current_value = settings_values[key_value[0]]
				var is_current_value_int = typeof(current_value) == TYPE_INT
				if is_current_value_int:
					settings_values[key_value[0]] = int(key_value[1])
				else:
					settings_values[key_value[0]] = key_value[1]
		file.close()

func save_settings():
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	for key in settings_values.keys():
		file.store_string(key + "=" + str(settings_values[key]) + "\n")
	file.close()

var default_font:Font = preload("res://VoxelWorld/Fonts/Cormorant/static/Cormorant-Stripped.ttf")
var font_overrides:Dictionary[String,Font] = {
	"ar": preload("res://Menus/Fonts/Amiri-Regular-Narrow.ttf"),
	"el": preload("res://Menus/Fonts/GFSDidot-Regular.ttf"),
	"hi": preload("res://Menus/Fonts/AnekDevanagariExpanded-Regular-Narrow.ttf"),
	# "eu": preload("res://Menus/Fonts/Vasca.ttf"),
	"fa": preload("res://Menus/Fonts/Parastoo-Medium-Narrow.ttf"),
	"ja": preload("res://Menus/Fonts/KaiseiOpti-Medium-Narrow.ttf"),
	"te": preload("res://Menus/Fonts/TiroTelugu-Regular-Narrow.ttf"),
	"zh_CN": preload("res://Menus/Fonts/LXGWWenKai-Regular.ttf"),
	"zh_TW": preload("res://Menus/Fonts/LXGWWenKaiTC-Regular.ttf")
	}
	

var menu_theme:Theme = preload("res://Menus/Themes/MenuTheme.tres")

func set_locale_specific_fonts(locale:String):
	var target_font:Font = default_font
	if font_overrides.has(locale):
		target_font = font_overrides[locale]
	menu_theme.default_font = target_font

func set_locale(locale:String):
	set_locale_specific_fonts(locale)
	TranslationServer.set_locale(locale)
	
func apply_settings():
	var sfx_channel_idx:int = AudioServer.get_bus_index("SFX")
	var music_channel_idx:int = AudioServer.get_bus_index("Music")
	var environment_channel_idx:int = AudioServer.get_bus_index("Environment")
	var outside_channel_idx:int = AudioServer.get_bus_index("Outside")
	var gui_channel_idx:int = AudioServer.get_bus_index("GUI")
	AudioServer.set_bus_volume_linear(sfx_channel_idx, default_sfx_channel_volume*settings_values["SFX_VOL"]/10.0)
	AudioServer.set_bus_volume_linear(music_channel_idx, default_music_channel_volume*settings_values["MUSIC_VOL"]/10.0)
	AudioServer.set_bus_volume_linear(environment_channel_idx, default_environment_channel_volume*settings_values["ENVIRONMENT_VOL"]/10.0)
	AudioServer.set_bus_volume_linear(outside_channel_idx, default_outside_channel_volume*settings_values["ENVIRONMENT_VOL"]/10.0)
	AudioServer.set_bus_volume_linear(gui_channel_idx, default_gui_channel_volume*settings_values["SFX_VOL"]/10.0)
	set_locale( settings_values["LANGUAGE"] )
	var window_mode_idx:int=settings_values["GFX_FULLSCREEN_MODE"]
	var window_mode:DisplayServer.WindowMode = SettingsMenu.gfx_windowmodes[window_mode_idx]
	DisplayServer.window_set_mode(window_mode)
	invert_mouse_y = settings_values["MOUSE_Y_INVERT"] == 1
	mouse_moves_camera = settings_values["MOUSE_CONTROLS"] == 0
	QualityManager.set_quality(settings_values["GFX_QUALITY"])
	#if player exists
	if ModeManager.editor_node && ModeManager.editor_node.player:
		ModeManager.editor_node.player.mouse_sensitivity = mouse_sensitivity()

#value is normally an int, but i change it to a str sometimes for language...
func set_value(property_name:String, value, apply_settings:bool=true):
	if property_name == "LANGUAGE":
		var locale_list = TranslationServer.get_loaded_locales()
		var locale_name = locale_list[value]
		value = locale_name
			
	if settings_values[property_name] != value:
		settings_values[property_name] = value
		if apply_settings:
			apply_settings()
		save_settings()

func get_value(property_name:String)->Variant:
	if settings_values.has(property_name):
		return settings_values[property_name]
	else:
		return null

func level_editor_enabled()->bool:
	return settings_values["LEVEL_EDITOR"] == 1 && !Glob.DEMO_VERSION
	
func mouse_sensitivity()->float:
	var sensitivity = settings_values["MOUSE_SENSITIVITY"]
	return (sensitivity+1)/6.0

# static func find_all_labels(root:Node=null)->Array[Label]:
# 	#calculate recursively
# 	var labels:Array[Label] = []
# 	for child in root.get_children():
# 		if child is Label:
# 			labels.append(child)
# 		labels.append_array(find_all_labels(child))
# 	return labels

# static func print_all_labels_with_font_override(root:Node):
# 	print("Printing all labels with font override:")
# 	var labels:Array[Label] = find_all_labels(root)
# 	for label:Label in labels:
# 		if label.has_theme_font_override("font"):
# 			print(label.get_path())
			
static func find_all_Controls(root:Node=null)->Array[Control]:
	#calculate recursively
	var controls:Array[Control] = []
	for child in root.get_children():
		if child is Control:
			controls.append(child)
		controls.append_array(find_all_Controls(child))
	return controls

static func print_all_controls_with_theme(root:Node):
	print("Printing all controls with font override:")
	var controls:Array[Control] = find_all_Controls(root)
	for control:Control in controls:
		if control.theme!=null:
			var theme:Theme = control.theme			
			print(control.get_path())
			#print resource path
			print(theme.resource_path+"\n")

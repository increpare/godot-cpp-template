extends Node

const CONFIG_FILE_PATH = "user://config.ini"

const DEFAULTS = {
	editor = {
		level_name = "eggworld"
	}
}

var config_file := ConfigFile.new()

func load_settings():
	config_file.load(CONFIG_FILE_PATH)
	# Initialize defaults for values not found in the existing configuration file,
	# so we don't have to specify them every time we use `ConfigFile.get_value()`.
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if not config_file.has_section_key(section, key):
				config_file.set_value(section, key, DEFAULTS[section][key])

func save_settings():
	config_file.save(CONFIG_FILE_PATH)
	
func _init():
	load_settings()

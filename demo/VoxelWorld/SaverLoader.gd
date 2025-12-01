extends Node

var data : Variant = {}

func _init() -> void:
	print("initializating Bonfire")
	load_dat()
	
func adjust_key(key:String):
	if key=="checkpoint":
		key = get_val("level_name")+"_checkpoint"
		#if multiplayer, prefix with ("mp_")
		if ModeManager.editor_node.multiplayer_menu.network_manager.is_connected_to_network():
			key = "mp_"+key
	return key

func remove_val(key:String):
	key = adjust_key(key)
	if !data.has(key):
		return
	data.erase(key)
	save_dat()
	
func has_val(key:String)->bool:
	key = adjust_key(key)
	return data.has(key)

func get_val(key):
	key = adjust_key(key)
	if data.has(key):
		return data[key]
	else:
		return null
	
func set_val(key,value):
	key = adjust_key(key)
	if data.get(key) == value:
		return
	data[key]=value
	save_dat()
	
func _exit_tree() -> void:
	save_dat()
	
func save_dat():
	print("save_dat")
	var config : ConfigFile = ConfigFile.new()
	for key in data.keys():
		var val = data[key]
		config.set_value("settings",key,val)
	config.save("user://savestate.cfg")
		
func load_dat():
	# Load data from a file.
	var config = ConfigFile.new()
	var err = config.load("user://savestate.cfg")

	# If the file didn't load, ignore it.
	if err != OK:
		print("save file not found/invalid")
		return

	data={}
	# Iterate over all sections.
	for section in config.get_sections():
		var section_keys = config.get_section_keys(section)
		for section_key in section_keys:
			var value = config.get_value(section,section_key);
			data[section_key] = value
			
	print("loaded config file")

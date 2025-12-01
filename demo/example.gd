extends Node

func load_text_file(path):
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not open file")
		return ""
	return f.get_as_text()


func save_text_file(text, path):
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("Could not open file.")
		return
	f.store_string(text)
	
func _ready() -> void:
	var example := ExampleClass.new()
	var i:int = 3
	example.print_type(example)
	example.print_type(i)
	
	var arr:Array[Vector3i] = [ Vector3i(1,1,1), Vector3i(1,2,3), Vector3i(4,5,6) ]
	example.print_array(arr)
	var packed_array:PackedByteArray = example.serialize_array(arr)
	print("Simple array size: ", packed_array.size())
	print(packed_array)

	# --- Game Data Test ---
	
	var voxel_data = []
	# [ Voxel:Vector3i, blocktype:int, tx:int, ty:int, rot:int, vflip:bool ]
	voxel_data.append([Vector3i(0,0,0), 1, 0, 0, 0, false])
	voxel_data.append([Vector3i(1,0,0), 2, 1, 0, 0, true])

	var layers = []
	layers.append({ "name": "Base", "visible": true })
	layers.append({ "name": "Decor", "visible": false })

	var level_state_data = [
		1, # version
		voxel_data,
		layers,
		0 # selected_layer_idx
	]

	var entities = []
	entities.append({
		"name": "Player",
		"type": 1,
		"position": Vector3(10.5, 0, 10.5),
		"dir": 2,
		"meta": "health=100"
	})

	var savedat = [
		level_state_data,
		Vector3(10, 5, 10), # camera_pos
		Vector3(0, 45, 0), # camera_base_rotation
		Vector3(0, 0, 0), # camera_rot_rotation
		entities
	]
	
	print("Serializing game data...")
	var game_data_bytes = example.serialize_game_data(savedat)
	print("Game data serialized size: ", game_data_bytes.size())
	print(game_data_bytes)

	# We actually have a test file saved with var_to_str in Resources/minimal.txt, so let's load it and print it
	var test_file : String = load_text_file("res://Resources/eggworld.txt")
	print("test file length = " + str(test_file.length()))
	var test_file_var = str_to_var(test_file)
	print(test_file_var.size())
	var test_file_binary_serialized = example.serialize_game_data(test_file_var)
	print("Test file binary serialized size: ", test_file_binary_serialized.size())
	#print(test_file_binary_serialized)
	
	print("Deserializing...")
	var deserialized_data = example.deserialize_game_data(test_file_binary_serialized)
	print("Deserialized structure size: ", deserialized_data.size())
	
	# Basic check
	if deserialized_data.size() == 5:
		print("Level version: ", deserialized_data[0]["version"])
		print("Camera pos: ", deserialized_data[1])
		print("Entities count: ", deserialized_data[4].size())

	var re_stringified:String = var_to_str(deserialized_data)
	var all_same = re_stringified == test_file
	if all_same:
		print("File invariant, passes test")
	else:
		print("Files different, fails test.")
		print("re_stringified.length() = " +str(re_stringified.length()))
		print("test_file.length() = " + str(test_file.length()))
		
		# Save both to disk for diffing
		save_text_file(re_stringified, "res://re_stringified.txt")
		
		# Find first difference
		var limit = min(test_file.length(), re_stringified.length())
		for j in range(limit):
			if test_file[j] != re_stringified[j]:
				print("First difference at index ", j)
				print("Original: ...", test_file.substr(max(0, j-20), 40), "...")
				print("New:      ...", re_stringified.substr(max(0, j-20), 40), "...")
				break

	Run_Profiler(example)

func Run_Profiler(example:ExampleClass):
	#compare our serializer against var_to_str and str_to_var
	#eggworld is the test file

	#first we load the test-file into the variable
	var test_file : String = load_text_file("res://Resources/eggworld.txt")
	var test_file_var = str_to_var(test_file)

	#now we wait a frame for the profiler to isolate what we're about to do
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	#TEST 1 - VAR_TO_STR
	
	# time: 117.06
	var builtin_data_var_to_str:String = var_to_str(test_file_var) 
	await get_tree().process_frame
	# time: 118.78ms
	var builtin_data_str_to_var:Variant = str_to_var(builtin_data_var_to_str)
	await get_tree().process_frame

	# time: 16.39ms
	var builtin_data_var_to_bytes:PackedByteArray = var_to_bytes(test_file_var)
	await get_tree().process_frame

	# time: 48.80ms
	var builtin_data_bytes_to_var:PackedByteArray = bytes_to_var(builtin_data_var_to_bytes)
	await get_tree().process_frame

	# time: 15.88ms
	var my_serialized = example.serialize_game_data(test_file_var)
	await get_tree().process_frame

	# time: 44.61ms
	var my_deserialized = example.deserialize_game_data(my_serialized)
	await get_tree().process_frame

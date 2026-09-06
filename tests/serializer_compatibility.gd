extends SceneTree

func _initialize() -> void:
	var serializer = ClassDB.instantiate("OeufSerializer")
	for filename in ["eggworld.txt","mini_city.txt"]:
		var parsed: Array = serializer.deserialize_from_string(FileAccess.get_file_as_string("res://sample_files/" + filename))
		print(filename, " ", serializer.serialize_to_string(parsed).sha256_text(), " ", serializer.serialize_game_data(parsed).hex_encode().sha256_text())
	var entity := {"name":"🥚 multiline\n\"\\", "type":3,"position":Vector3i(-17,3,201),"layer":1,"dir":-1,"meta":"日本語\nline","asset_name":"café.asset","colour":5,"placed_user_id":"123", "placed_user_display_name":"José 🥚", "edited_user_id":"456","edited_user_display_name":"李", "size_EDS":Vector3i(1,2,3),"size_WUN":Vector3i(4,5,6)}
	var data := [{"version":2,"voxel_data":[[Vector3i(-129,128,0),2,3,4,3,true,0]],"layers":[{"name":"🥚", "visible":true}],"selected_layer_idx":0},Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,{}]
	for version in [0,5,6]:
		data[4] = [entity] if version == 0 else {"version":version,"entities":[entity]}
		print("entity_", version, " ", serializer.serialize_to_string(data).sha256_text())
	quit()

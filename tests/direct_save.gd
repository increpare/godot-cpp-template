extends SceneTree

var serializer = ClassDB.instantiate("OeufSerializer")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		failures += 1

func flattened(savedat: Array, chunks: Dictionary) -> Array:
	var rows: Array[Array] = []
	for coord: Vector3i in chunks:
		var chunk: Dictionary = chunks[coord]
		for v: Vector3i in chunk.voxels:
			var p: Array = chunk.voxel_dict[v]
			# Same row construction as VoxelWorld.save_to_variant, with legacy
			# layer supplied without changing the shared source array.
			if p.size() < 6:
				p = p.duplicate()
				p.push_back(0)
			rows.push_back([v,p[0],p[1],p[2],p[3],p[4],p[5]])
	var result := savedat.duplicate(false)
	result[0] = savedat[0].duplicate(false)
	result[0].voxel_data = rows
	return result

func direct(savedat: Array, chunks: Dictionary) -> String:
	var positions: Array = []
	var properties: Array = []
	for coord: Vector3i in chunks:
		positions.append(chunks[coord].voxels)
		properties.append(chunks[coord].voxel_properties)
	return serializer.call("serialize_chunks_to_string", savedat, positions, properties)

func chunk(positions: Array, properties: Array) -> Dictionary:
	var voxels: Array[Vector3i] = []
	voxels.assign(positions)
	var props: Array[Array] = []
	props.assign(properties)
	var lookup := {}
	for i in voxels.size(): lookup[voxels[i]] = props[i]
	return {"voxels":voxels,"voxel_properties":props,"voxel_dict":lookup}

func _initialize() -> void:
	if not serializer.has_method("serialize_chunks_to_string"):
		check(false, "direct chunk text serialization API is missing")
		quit(1)
		return
	var meta := {"version":2,"layers":[{"name":"café 蛋 🥚\n\"\\", "visible":true},{"name":"hidden", "visible":false}],"selected_layer_idx":1}
	var entity := {"name":"🥚 multiline\n\"\\", "type":3,"position":Vector3i(-17,3,201),"layer":1,"dir":-1,"meta":"日本語\nline","asset_name":"café.asset","colour":5,"placed_user_id":"123", "placed_user_display_name":"José 🥚", "edited_user_id":"456","edited_user_display_name":"李", "size_EDS":Vector3i(1,2,3),"size_WUN":Vector3i(4,5,6)}
	var data := [meta,Vector3(-1.25,2.5,-3.75),Vector3.ZERO,Vector3(1,2,3),{"version":6,"entities":[entity]}]
	# Insertion order, empty middle chunk, negative positions, deltas at -128/127
	# and absolute positions at -129/128, including across chunk boundaries.
	var chunks := {}
	chunks[Vector3i(5,0,0)] = chunk([Vector3i(128,0,0),Vector3i(0,-128,127)],[[12,2,3,3,true,1],[0,0,0,0,false]])
	chunks[Vector3i(3,0,0)] = chunk([],[])
	chunks[Vector3i(-1,0,0)] = chunk([Vector3i(-129,-128,127),Vector3i(-2,-1,-1)],[[2,4,5,1,0,0],[3,7,8,2,1,1]])
	var source_before := var_to_bytes(chunks)
	for version in [0,5,6]:
		data[4] = [entity] if version == 0 else {"version":version,"entities":[entity]}
		check(direct(data,chunks) == serializer.serialize_to_string(flattened(data,chunks)), "exact chunk text including entities version %d" % version)
	check(var_to_bytes(chunks) == source_before, "serialization must not mutate chunk arrays or legacy property rows")
	check(direct(data,{}) == serializer.serialize_to_string(flattened(data,{})), "zero chunks exact output")
	check(direct(data,{Vector3i.ZERO:chunk([],[])}) == serializer.serialize_to_string(flattened(data,{})), "only empty chunk exact output")
	if failures == 0: print("PASS direct chunk serializer edge cases")
	for filename in ["eggworld.txt","mini_city.txt"]:
		var parsed: Array = serializer.deserialize_from_string(FileAccess.get_file_as_string("res://sample_files/" + filename))
		var sample_chunks := {}
		for row: Array in parsed[0].voxel_data:
			var v: Vector3i = row[0]
			var coord := Vector3i(floori(float(v.x)/24),floori(float(v.y)/24),floori(float(v.z)/24))
			if not sample_chunks.has(coord): sample_chunks[coord] = chunk([],[])
			var c: Dictionary = sample_chunks[coord]
			var props: Array = row.slice(1)
			c.voxels.append(v)
			c.voxel_properties.append(props)
			c.voxel_dict[v] = props
		var expected: String = serializer.serialize_to_string(flattened(parsed,sample_chunks))
		check(direct(parsed,sample_chunks) == expected, filename + " exact full text")
		print("FIXTURE %s voxels=%d chunks=%d text_sha256=%s" % [filename,parsed[0].voxel_data.size(),sample_chunks.size(),expected.sha256_text()])
		# Warm both paths, then alternate to reduce ordering/thermal bias.
		serializer.serialize_to_string(flattened(parsed,sample_chunks))
		direct(parsed,sample_chunks)
		var old_times: Array[int] = []
		var new_times: Array[int] = []
		for i in 11:
			for mode in ([0,1] if i%2 == 0 else [1,0]):
				var start := Time.get_ticks_usec()
				if mode == 0:
					serializer.serialize_to_string(flattened(parsed,sample_chunks))
					old_times.append(Time.get_ticks_usec()-start)
				else:
					direct(parsed,sample_chunks)
					new_times.append(Time.get_ticks_usec()-start)
		old_times.sort()
		new_times.sort()
		print("BENCH %s old_us=%s new_us=%s medians=%d/%d speedup=%.3fx" % [filename,old_times,new_times,old_times[5],new_times[5],float(old_times[5])/new_times[5]])
	print("FAILURES ",failures)
	quit(0 if failures == 0 else 1)

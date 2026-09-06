extends SceneTree
var mesher = ClassDB.instantiate("VoxelMesher")
var serializer = ClassDB.instantiate("OeufSerializer")
const DIRS := [Vector3i(0,0,-1),Vector3i(0,0,1),Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,1,0),Vector3i(0,-1,0)]
const ITERATIONS := 7
func _initialize():
	call_deferred("run")
func mesh_all(chunks: Dictionary, layers: Array, with_neighbors: bool) -> int:
	var triangles := 0
	for coord: Vector3i in chunks:
		var chunk: Dictionary = chunks[coord]
		var result: Dictionary
		if with_neighbors:
			var neighbors: Array = []
			for dir: Vector3i in DIRS:
				var adjacent: Vector3i = coord+dir
				neighbors.append(chunks[adjacent].voxel_dict if chunks.has(adjacent) else {})
			result = mesher.call("generate_chunk_mesh_with_neighbors",coord,chunk.voxels,chunk.props,layers,24,24,24,neighbors)
		else:
			result = mesher.generate_chunk_mesh(coord,chunk.voxels,chunk.props,layers,24,24,24)
		triangles += result.tri_voxel_info.size()/2
	return triangles
func run():
	var shapes = root.get_node("Shapes")
	mesher.parse_shapes(shapes.database,shapes.uvpatterns,shapes.face_cull_actions,shapes.face_cull_action_size)
	mesher.initialize_noise(0)
	mesher.set_texture_dimensions(1024,1024)
	var files := ["res://sample_files/eggworld.txt","res://sample_files/mini_city.txt"]
	files.append_array(OS.get_cmdline_user_args())
	for filename: String in files:
		var text := FileAccess.get_file_as_string(filename)
		if text.is_empty():
			push_error("Missing fixture "+filename)
			quit(1)
			return
		var parsed: Array = serializer.deserialize_from_string(text)
		var chunks := {}
		for row: Array in parsed[0].voxel_data:
			var v: Vector3i = row[0]
			var coord := Vector3i(floori(float(v.x)/24),floori(float(v.y)/24),floori(float(v.z)/24))
			if not chunks.has(coord): chunks[coord] = {"voxels":[],"props":[],"voxel_dict":{}}
			var c: Dictionary = chunks[coord]
			var props: Array = row.slice(1)
			c.voxels.append(v)
			c.props.append(props)
			c.voxel_dict[v] = props
		var layers: Array = []
		for layer: Dictionary in parsed[0].layers: layers.append(layer.visible)
		var old_count := mesh_all(chunks,layers,false)
		var new_count := mesh_all(chunks,layers,true)
		print("FIXTURE %s voxels=%d chunks=%d old_triangles=%d new_triangles=%d saved=%d" % [filename.get_file(),parsed[0].voxel_data.size(),chunks.size(),old_count,new_count,old_count-new_count])
		var old_times: Array[int] = []
		var new_times: Array[int] = []
		for i in ITERATIONS:
			for mode in ([false,true] if i%2 == 0 else [true,false]):
				var start := Time.get_ticks_usec()
				var count := mesh_all(chunks,layers,mode)
				var elapsed := Time.get_ticks_usec()-start
				if count != (new_count if mode else old_count):
					push_error("Unstable triangle count")
					quit(1)
					return
				if mode: new_times.append(elapsed)
				else: old_times.append(elapsed)
		old_times.sort()
		new_times.sort()
		print("BENCH %s old_us=%s new_us=%s medians=%d/%d" % [filename.get_file(),old_times,new_times,old_times[ITERATIONS/2],new_times[ITERATIONS/2]])
	print("BOUNDARY BENCH PASS")
	quit()

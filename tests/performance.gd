extends Node

var serializer := OeufSerializer.new()
var mesher := VoxelMesher.new()
var signatures: Dictionary = {}
var failures := 0
const ITERATIONS := 7
var chunk_size: Vector3i = ProjectSettings.get_setting("native_performance/chunk_size", Vector3i(24,24,24))

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		failures += 1

func digest(value: Variant) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()

func timed(label: String, action: Callable) -> void:
	action.call()
	var samples: Array[int] = []
	for i in ITERATIONS:
		var start := Time.get_ticks_usec()
		action.call()
		samples.append(Time.get_ticks_usec() - start)
	samples.sort()
	print("TIMING %s %d us" % [label, samples[ITERATIONS / 2]])

func mesh_signature(coord: Vector3i, voxels: Array, props: Array, layers: Array, size: Vector3i) -> Array:
	var result: Dictionary = mesher.generate_chunk_mesh(coord, voxels, props, layers, size.x, size.y, size.z)
	var mesh: ArrayMesh = result.arraymesh
	var arrays: Array = mesh.surface_get_arrays(0) if mesh.get_surface_count() else []
	var simple: ArrayMesh = mesher.generate_simplified_mesh(coord, voxels, size.x, size.y, size.z)
	var simple_arrays: Array = simple.surface_get_arrays(0) if simple != null else []
	if not arrays.is_empty():
		check(arrays[Mesh.ARRAY_VERTEX].size() / 3 * 2 == result.tri_voxel_info.size(), "triangle attribution count")
	return [arrays, result.tri_voxel_info, simple_arrays]

func run() -> void:
	mesher.parse_shapes(Shapes.database, Shapes.uvpatterns, Shapes.face_cull_actions, Shapes.face_cull_action_size)
	mesher.initialize_noise(0)
	mesher.set_texture_dimensions(1024, 1024)
	var regression = load("res://FaceOccupancyTestRunner.gd").new()
	check(regression.run_all_tests(), "existing face occupancy suite")
	signatures["chunk_size"] = str(chunk_size)
	print("PRODUCTION CHUNK SIZE ", chunk_size)
	for filename in ["eggworld.txt", "mini_city.txt"]:
		var text := FileAccess.get_file_as_string("res://sample_files/" + filename)
		check(not text.is_empty(), "sample exists")
		var parsed := serializer.deserialize_from_string(text)
		var binary := serializer.serialize_game_data(parsed)
		var decoded := serializer.deserialize_game_data(binary)
		check(serializer.serialize_game_data(decoded) == binary, filename + " binary roundtrip")
		signatures[filename + "/binary"] = digest(binary)
		signatures[filename + "/decoded"] = digest(decoded)
		signatures[filename + "/text"] = digest(serializer.serialize_to_string(parsed))
		timed(filename + "/text_load", func(): serializer.deserialize_from_string(text))
		timed(filename + "/text_save", func(): serializer.serialize_to_string(parsed))
		timed(filename + "/binary_load", func(): serializer.deserialize_game_data(binary))
		timed(filename + "/binary_save", func(): serializer.serialize_game_data(parsed))
		var chunks: Dictionary = {}
		for row: Array in parsed[0].voxel_data:
			var v: Vector3i = row[0]
			var c := Vector3i(floori(float(v.x) / chunk_size.x), floori(float(v.y) / chunk_size.y), floori(float(v.z) / chunk_size.z))
			if not chunks.has(c): chunks[c] = [[], []]
			chunks[c][0].append(v)
			chunks[c][1].append(row.slice(1))
		var layers: Array = []
		for layer in parsed[0].layers: layers.append(layer.visible)
		var mesh_hashes: Array = []
		for c in chunks:
			mesh_hashes.append(digest(mesh_signature(c, chunks[c][0], chunks[c][1], layers, chunk_size)))
		signatures[filename + "/meshes"] = digest(mesh_hashes)
		print("FIXTURE %s voxels=%d chunks=%d" % [filename, parsed[0].voxel_data.size(), chunks.size()])
		timed(filename + "/mesh", func():
			for c in chunks: mesher.generate_chunk_mesh(c, chunks[c][0], chunks[c][1], layers, chunk_size.x,chunk_size.y,chunk_size.z))
		timed(filename + "/simplified", func():
			for c in chunks: mesher.generate_simplified_mesh(c, chunks[c][0], chunk_size.x,chunk_size.y,chunk_size.z))
	var shapes: Array = []
	for shape in Shapes.database.size():
		for rot in 4:
			for flip in 2:
				shapes.append(digest(mesh_signature(Vector3i(-1,0,1), [Vector3i(-1,0,16), Vector3i(-2,0,16)], [[shape,2,3,rot,flip != 0,0],[0,1,2,0,false,0]], [true], Vector3i(16,16,16))))
	signatures["all_shape_variants"] = digest(shapes)
	signatures["hidden"] = digest(mesh_signature(Vector3i.ZERO,[Vector3i.ZERO],[[0,0,0,0,false,0]],[false],Vector3i(8,12,20)))
	signatures["empty"] = digest(mesh_signature(Vector3i.ZERO,[],[],[true],Vector3i(16,16,16)))
	var edge := [{"version":1,"voxel_data":[[Vector3i(-32768,32767,-129),12,255,254,3,true,1],[Vector3i(-32640,32639,-1),0,0,0,0,false,0]],"layers":[{"name":"café 蛋 🥚\n\"\\", "visible":true},{"name":"", "visible":false}],"selected_layer_idx":1},Vector3(-1.25,2.5,-3.75),Vector3.ZERO,Vector3(100,200,-300),{"version":6,"entities":[]}]
	var bytes := serializer.serialize_game_data(edge)
	check(serializer.deserialize_game_data(bytes) == edge, "signed coordinates and unicode roundtrip")
	signatures["binary_edges"] = digest(bytes)
	var truncated: Array = []
	for length in bytes.size():
		truncated.append(digest(serializer.deserialize_game_data(bytes.slice(0, length))))
	signatures["truncated_binary"] = digest(truncated)
	for kind in ["solid", "checkerboard", "mixed"]:
		var voxels: Array = []
		var props: Array = []
		for z in 16:
			for y in 16:
				for x in 16:
					if kind == "checkerboard" and (x+y+z)%2: continue
					voxels.append(Vector3i(x,y,z))
					props.append([(x+y+z)%13 if kind == "mixed" else 0, x%8, y%8, z%4, x%2 == 0, 0])
		signatures[kind] = digest(mesh_signature(Vector3i.ZERO, voxels, props, [true], Vector3i(16,16,16)))
		timed(kind + "/mesh", func(): mesher.generate_chunk_mesh(Vector3i.ZERO,voxels,props,[true],16,16,16))
	for sign_value in [-1,1]:
		var c := Vector3i(sign_value * 1048576,0,0)
		if sign_value < 0: c.x -= 1
		var v := c * 16 + Vector3i(13 if sign_value < 0 else 1,0,0)
		signatures["large_coordinates%d" % sign_value] = digest(mesh_signature(c, [v, v+Vector3i(1,0,0)], [[0,0,0,0,false,0],[0,0,0,0,false,0]], [true], Vector3i(16,16,16)))
	# Reparse and change texture dimensions after populated caches, then restore.
	mesher.parse_shapes(Shapes.database, Shapes.uvpatterns, Shapes.face_cull_actions, Shapes.face_cull_action_size)
	mesher.set_texture_dimensions(512,256)
	mesher.initialize_noise(5)
	signatures["reconfigured"] = digest(mesh_signature(Vector3i.ZERO,[Vector3i.ZERO],[[0,2,3,0,false,0]],[true],Vector3i(3,4,5)))
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--record":
		FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(signatures,"\t"))
	elif args.size() == 2 and args[0] == "--compare":
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		check(expected == signatures,"baseline signatures match exactly")
		for key in signatures:
			check(expected.get(key) == signatures[key],"signature " + key)
	else:
		check(false,"use --record PATH or --compare PATH")
	print("PERFORMANCE REGRESSION ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(failures)

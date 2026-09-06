extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var mesher = ClassDB.instantiate("VoxelMesher")
	var shapes = root.get_node("Shapes")
	mesher.parse_shapes(shapes.database,shapes.uvpatterns,shapes.face_cull_actions,shapes.face_cull_action_size)
	mesher.initialize_noise(0)
	mesher.set_texture_dimensions(1024,1024)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var pairs := 0
	for dir in [Vector3i(0,0,-1),Vector3i(0,0,1),Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,1,0),Vector3i(0,-1,0)]:
		for shape in shapes.database.size():
			for rotation in 4:
				for flip in 2:
					var positions := [Vector3i(-2,-2,-2),Vector3i(-2,-2,-2)+dir]
					var props := [[shape,2,3,rotation,flip!=0,0],[0,4,5,0,false,0]]
					var result: Dictionary = mesher.generate_chunk_mesh(Vector3i(-1,-1,-1),positions,props,[true],4,4,4)
					var mesh: ArrayMesh = result.arraymesh
					hash.update(var_to_bytes([mesh.surface_get_arrays(0) if mesh.get_surface_count() else [],result.tri_voxel_info]))
					pairs += 1
	print("OLD API SIGNATURE ",pairs," ",hash.finish().hex_encode())
	quit()

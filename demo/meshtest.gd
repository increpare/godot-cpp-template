extends MeshInstance3D

func _ready() -> void:
	# 1. Initialize VoxelMesher
	var mesher = VoxelMesher.new()
	
	# Ensure Shapes database is initialized
	if Shapes.database.size() == 0:
		if Shapes.has_method("_ready"):
			Shapes._ready()
			
	mesher.parse_shapes(Shapes.database, Shapes.uvpatterns)
	mesher.set_texture_dimensions(Shapes.TEX_WIDTH, Shapes.TEX_HEIGHT)
	
	# 2. Load and Parse Data
	print("Loading eggworld.txt...")
	var f = FileAccess.open("res://Resources/eggworld.txt", FileAccess.READ)
	if !f:
		print("Failed to open eggworld.txt")
		return
		
	var content = f.get_as_text()
	var data = str_to_var(content)
	
	if typeof(data) != TYPE_ARRAY or data.size() == 0:
		print("Invalid data format")
		return

	var save_struct = data[0]
	var loaded_voxels = save_struct.get("voxel_data", [])
	var layers = save_struct.get("layers", [])
	
	print("Loaded ", loaded_voxels.size(), " voxels.")

	# 3. Organize into Chunks
	var chunks = {}
	var size_x = VoxelChunk.SIZE_X
	var size_y = VoxelChunk.SIZE_Y
	var size_z = VoxelChunk.SIZE_Z
	
	for row in loaded_voxels:
		# row structure: [Vector3i(x,y,z), type, tx, ty, rot, vflip, layer]
		var v: Vector3i = row[0]
		
		# Calculate chunk coordinate (using floor division)
		var cx = floori(float(v.x) / size_x)
		var cy = floori(float(v.y) / size_y)
		var cz = floori(float(v.z) / size_z)
		var chunk_coord = Vector3i(cx, cy, cz)
		
		if !chunks.has(chunk_coord):
			chunks[chunk_coord] = { "voxels": [], "props": [] }
			
		chunks[chunk_coord].voxels.push_back(v)
		# Properties are the rest of the array
		var props = row.slice(1)
		chunks[chunk_coord].props.push_back(props)

	# 4. Generate Meshes
	print("Generating meshes for ", chunks.size(), " chunks...")
	var combined_mesh = ArrayMesh.new()
	
	# Prepare layer visibility (assume all visible)
	var layer_visibility = []
	for i in range(max(layers.size(), 10)): # Ensure enough size
		layer_visibility.push_back(true)

	for chunk_coord in chunks:
		var chunk_data = chunks[chunk_coord]
		
		var result = mesher.generate_chunk_mesh(
			chunk_coord,
			chunk_data.voxels,
			chunk_data.props,
			layer_visibility,
			size_x, size_y, size_z
		)
		
		var arrays = result["mesh_arrays"]
		if arrays[Mesh.ARRAY_VERTEX].size() > 0:
			combined_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	self.mesh = combined_mesh
	
	# 5. Set Material
	var mat = StandardMaterial3D.new()
	var tex = load("res://VoxelWorld/Textures/tilemap.png")
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Vertex colors are used for ambient occlusion/smoothing in VoxelMesher
	mat.vertex_color_use_as_albedo = true 
	self.material_override = mat
	
	print("Mesh generation complete.")

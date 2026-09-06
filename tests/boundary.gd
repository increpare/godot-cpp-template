extends SceneTree
var mesher = ClassDB.instantiate("VoxelMesher")
var failures := 0
const DIRS := [Vector3i(0,0,-1),Vector3i(0,0,1),Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,1,0),Vector3i(0,-1,0)]
const OPP := [1,0,3,2,5,4]
const ATTRS := [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV]
func _initialize():
	call_deferred("run")
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		if failures <= 10: push_error(label)
func empty_neighbors() -> Array:
	return [{},{},{},{},{},{}]
func mesh(coord: Vector3i, voxels: Array, props: Array, layers: Array, size: int, neighbors = null) -> Dictionary:
	if neighbors == null:
		return mesher.generate_chunk_mesh(coord,voxels,props,layers,size,size,size)
	return mesher.call("generate_chunk_mesh_with_neighbors",coord,voxels,props,layers,size,size,size,neighbors)
func surface(result: Dictionary) -> Array:
	var m: ArrayMesh = result.arraymesh
	return m.surface_get_arrays(0) if m.get_surface_count() else []
func compare_pair(p: Array, q: Array, direction: int, base: Vector3i, layers: Array) -> bool:
	var other: Vector3i = base+DIRS[direction]
	var neighbors := empty_neighbors()
	neighbors[direction][other] = q
	var a := mesh(base,[base],[p],layers,1,neighbors)
	neighbors = empty_neighbors()
	neighbors[OPP[direction]][base] = p
	var b := mesh(other,[other],[q],layers,1,neighbors)
	var unified_coord := Vector3i.ZERO if base.x >= 0 else Vector3i(-1,-1,-1)
	var whole := mesh(unified_coord,[base,other],[p,q],layers,4)
	var aa := surface(a)
	var bb := surface(b)
	var ww := surface(whole)
	if ww.is_empty(): return aa.is_empty() and bb.is_empty()
	# Native vertices already contain world positions, so no chunk rebase needed.
	for attr in ATTRS:
		var combined = ww[attr].slice(0,0)
		if not aa.is_empty(): combined.append_array(aa[attr])
		if not bb.is_empty(): combined.append_array(bb[attr])
		if combined != ww[attr]: return false
	var attribution: PackedInt32Array = a.tri_voxel_info.duplicate()
	var second: PackedInt32Array = b.tri_voxel_info.duplicate()
	for i in range(0,second.size(),2): second[i] += 1
	attribution.append_array(second)
	return attribution == whole.tri_voxel_info
func run():
	if not mesher.has_method("generate_chunk_mesh_with_neighbors"):
		check(false,"boundary neighbor API is missing")
		quit(1)
		return
	var shapes = root.get_node("Shapes")
	mesher.parse_shapes(shapes.database,shapes.uvpatterns,shapes.face_cull_actions,shapes.face_cull_action_size)
	mesher.initialize_noise(0)
	mesher.set_texture_dimensions(1024,1024)
	var cube := [0,2,3,0,false,0]
	for direction in 6:
		check(compare_pair(cube,cube,direction,Vector3i.ONE,[true]),"cube faces direction%d" % direction)
		check(compare_pair(cube,[0,2,3,0,false,1],direction,Vector3i(-2,-2,-2),[true,false]),"hidden neighbor direction%d" % direction)
		check(compare_pair([0,2,3,0,false,1],cube,direction,Vector3i(-2,-2,-2),[true,false]),"hidden subject direction%d" % direction)
	var pos := Vector3i(-1,-1,-1)
	var old := mesh(pos,[pos],[cube],[true],1)
	check(surface(old) == surface(mesh(pos,[pos],[cube],[true],1,empty_neighbors())),"empty neighbors preserve every surface field")
	var missing := empty_neighbors()
	missing[0][Vector3i(100,100,100)] = cube
	check(surface(old) == surface(mesh(pos,[pos],[cube],[true],1,missing)),"neighbor dictionary missing exact position")
	check(surface(mesh(pos,[],[],[true],1,empty_neighbors())).is_empty(),"empty subject chunk")
	var interior_neighbors := empty_neighbors()
	interior_neighbors[0][Vector3i(1,1,0)] = cube
	check(surface(mesh(Vector3i.ZERO,[Vector3i.ONE],[cube],[true],4)) == surface(mesh(Vector3i.ZERO,[Vector3i.ONE],[cube],[true],4,interior_neighbors)),"external dictionaries never replace interior grid lookup")
	var before := var_to_bytes(interior_neighbors)
	mesh(Vector3i.ZERO,[Vector3i.ZERO],[cube],[true],1,interior_neighbors)
	check(var_to_bytes(interior_neighbors) == before,"neighbor input dictionaries remain unchanged")
	var variants: Array = []
	for shape in shapes.database.size():
		for rotation in 4:
			for flip in 2:
				variants.append([shape,2,3,rotation,flip!=0,0])
	var pairs := 0
	for direction in 6:
		for p in variants:
			for q in variants:
				# Alternate positive/negative world positions across variant pairs.
				var base := Vector3i.ONE if pairs%2 == 0 else Vector3i(-2,-2,-2)
				check(compare_pair(p,q,direction,base,[true]),"all variant pair d%d p%s q%s" % [direction,p,q])
				pairs += 1
		print("DIRECTION ",direction," pairs=",pairs," failures=",failures)
	print("PAIR TESTS ",pairs)
	if failures == 0: print("BOUNDARY REGRESSION PASS")
	quit(0 if failures == 0 else 1)

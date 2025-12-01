class_name VoxelWorld extends Node3D

signal on_voxel_loading_over(cancelled:bool)

@export var mat:Material


var layers : Array = []#array of structs { name:String, visible:bool }

# A dictionary of VoxelChunks, indexed by chunk Vector3i
var chunks: Dictionary = {}

#VOXEL DATA END

# lookupdate - face index -> voxel coordinate + side
# array of arrays of [ voxel index, Direction ]
var tri_voxel_info : Array[Variant] = []

const offsets:Array[Vector3i] =[
	Vector3i(0,0,-1), 	#S
	Vector3i(0,0,1),	#N
	Vector3i(1,0,0),	#W
	Vector3i(-1,0,0),	#E
	Vector3i(0,1,0),	#U
	Vector3i(0,-1,0),	#D
]

# array of pairs, where first element is timestamp
var undo_history:Array[Array]=[]
var cur_undo_stack:Array[Array]=[]

const SAVE_VERSION : int = 2

func save_to_variant()->Variant:
	# each entry looks like
	# [ Voxel:Vector3, blocktype,tx,ty,rot,vflip ]

	var data:Array[Array]=[]
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		for voxel:Vector3i in chunk.voxels:
			var voxel_props:Array = chunk.voxel_dict[voxel]
			if voxel_props.size()<6:
				voxel_props.push_back(0)
			data.push_back([voxel,voxel_props[0],voxel_props[1],voxel_props[2],voxel_props[3],voxel_props[4],voxel_props[5]])
	var save_struct = {
		version  = SAVE_VERSION,
		voxel_data = data,
		layers = layers,
		selected_layer_idx = 0
	}
	return save_struct
	
func clear_world():
	clear_undo_history()
	#remove all chunks
	var chunk_coords = chunks.keys().duplicate()
	for chunk_coord:Vector3i in chunk_coords:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunks.erase(chunk_coord)
		chunk.queue_free()

func clear_undo_history():
	undo_history=[]
	cur_undo_stack=[]
	
func new_level():
	clear_world()
	add_range(Vector3i(-10,0,-10),Vector3i(10,0,10),0,0,0,0,false,0,Vector3(0,0,0),Vector3(0,0,0))
	clear_undo_history()
	
var loading:bool=false
var loadingpc:float=0.0

var cancel_load:bool=false

func restore_from_data(data:Variant):
	cancel_load=false
	loadingpc = 0.0
	loading = true
	
	var save_struct = data
	
	clear_undo_history()
	
	clear_world()

	await get_tree().process_frame
	await get_tree().process_frame
	
	loading = 0.2
	# strategy - for older files, update the structure to the 
	# current version, rather than doing more checking during loading
	
	#if pre-version
	if save_struct is Array:
		#print("upgrading from V-1 to 0")
		save_struct = {
			version=0,
			voxel_data = save_struct,
			layers = [{
				name="default",
				visible=true
			}],
		}
	
	if save_struct.version==0:
		#print("upgrading from V0 to 1")
		for row:Array in save_struct.voxel_data:
			#have to add a layer in
			row.push_back(0)			
		save_struct.version = 1
		
	if !save_struct.has("layers"):
		save_struct.layers=["default"]

	
	#if it's an array of strings, convert to array of structs
	for i in range(save_struct.layers.size()):
		if save_struct.layers[i] is String:
			save_struct.layers[i] = {
				name=save_struct.layers[i],
				visible=true
			}
		if !(save_struct.layers[i].name is String):
			#oops, print error and fix
			save_struct.layers[i].name = save_struct.layers[i].name.name
			print("ERROR FOUND IN LAYER DATA FOR LAYER "+save_struct.layers[i].name )
	
	if !save_struct.has("selected_layer_idx"):
		save_struct.selected_layer_idx = 0
		
	var data_array = save_struct.voxel_data
	layers = save_struct.layers
	
	ModeManager.editor_node._layerlist_selected(save_struct.selected_layer_idx)
	
	var cached_chunk_coord : Vector3i = Vector3i.MAX 
	var cached_chunk : VoxelChunk = null
	var cached_min : Vector3i = Vector3i.ZERO
	var cached_max : Vector3i = Vector3i.ZERO

	for row in data_array:
		var voxel_coord : Vector3i = row[0]
		row.remove_at(0)
		var voxel_props = row
		var layer_idx = voxel_props[5]
		while layer_idx>=layers.size():
			var layer_struct = {
				name="Layer "+str(layer_idx),
				visible=true
			}
			layers.push_back(layer_struct)
			print("layer index " + str(layer_idx) + " not found, adding layer "+str(layer_idx))
		if layer_idx<0:
			print("invalid layer index "+str(layer_idx))
			layer_idx = 0
		voxel_props[5] = layer_idx
		
		var chunk_coord:Vector3i
		var chunk:VoxelChunk

		if voxel_coord.x >= cached_min.x and voxel_coord.x < cached_max.x and \
		   voxel_coord.y >= cached_min.y and voxel_coord.y < cached_max.y and \
		   voxel_coord.z >= cached_min.z and voxel_coord.z < cached_max.z:
			chunk_coord = cached_chunk_coord
			chunk = cached_chunk
		else:
			chunk_coord = get_chunk_coord(voxel_coord)
			chunk = get_or_create_chunk(chunk_coord)
			cached_chunk_coord = chunk_coord
			cached_chunk = chunk
			cached_min = Vector3i(chunk_coord.x * VoxelChunk.SIZE_X, chunk_coord.y * VoxelChunk.SIZE_Y, chunk_coord.z * VoxelChunk.SIZE_Z)
			cached_max = cached_min + Vector3i(VoxelChunk.SIZE_X, VoxelChunk.SIZE_Y, VoxelChunk.SIZE_Z)

		chunk.add_voxel_unsafer(voxel_coord,voxel_props)
	

	var ASYNC_LOAD : bool = true # ModeManager.mode == ModeManager.MODE_EDITOR


	var time_start = Time.get_ticks_msec()

	# twice because this is called from a _ready function and it seems
	# process gets called right away on the same frame.
	await get_tree().process_frame
	await get_tree().process_frame
	
	
	var chunk_keys_list = chunks.keys()

	#if loading async, sort chunks by distance from camera
	if ASYNC_LOAD:
		var source_pos:Vector3 
		if ModeManager.mode==ModeManager.MODE_EDITOR:
			source_pos = ModeManager.editor_node.global_position 
		else:
			source_pos = Vector3(ModeManager.editor_node.entity_manager.get_start_position())
		var source_pos_i:Vector3i = Vector3i(source_pos)+Vector3i.DOWN
		var source_chunk = get_chunk_coord(source_pos_i)
		var checkpoint_direction = SaverLoader.get_val("checkpoint_direction")
		if checkpoint_direction==null:
			checkpoint_direction = Vector3.FORWARD
		checkpoint_direction = checkpoint_direction.rotated(Vector3.UP,-PI/2)
		chunk_keys_list.sort_custom(
			func(a:Vector3i, b:Vector3i): 
				#prioritize things in front of the camera
				var angleA = Vector3(a-source_chunk).angle_to(checkpoint_direction)
				if angleA>PI/2:
					return false
				var angleB = Vector3(b-source_chunk).angle_to(checkpoint_direction)
				if angleB>PI/2:
					return true
				return (a-source_chunk).length() < (b-source_chunk).length()) 
				
	for chunk_coord:Vector3i in chunk_keys_list:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.regen_mesh()
		if ASYNC_LOAD:			
			await get_tree().process_frame
			if cancel_load:
				print("cancelling loading early")
				ModeManager.editor_node.last_level_loaded = ""
				cancel_load = false
				loading = false
				loadingpc = 0.0
				on_voxel_loading_over.emit(true)
				return
				

	loading = false
	loadingpc = 1.0
	on_voxel_loading_over.emit(false)
	
func set_layer_name(index:int,lname:String):
	if layers[index].name==lname:
		return
	cur_undo_stack.push_back(["LAYERS",layers.duplicate()])
	layers[index].name=lname
	normalize_layer_names();
	
func commit_backup():
	if cur_undo_stack.size()>0:
		#print("committing voxel backup. length: "+str(cur_undo_stack.size()))
		undo_history.push_back([Time.get_ticks_msec(),cur_undo_stack])
		cur_undo_stack=[]
	
func last_undo_time()->int:
	if undo_history.size()==0:
		return 0
	return undo_history[undo_history.size()-1][0]
	
func restore_backup():
	if undo_history.size()==0:
		print("no voxel stuff to undo")
		return
	var undo_delta:Array = undo_history.pop_back()[1]
	
	if cur_undo_stack.size()>0:
		undo_delta.append_array(cur_undo_stack)
		cur_undo_stack=[]
	
	var chunks_to_regen:Array[Vector3i]=[]
	print("undoing voxels - modified "+str(undo_delta.size()))

	for i in range(undo_delta.size()-1,-1,-1):
		var toundo = undo_delta[i]
		if toundo[0] is String and toundo[0]=="LAYERS":
			self.layers = toundo[1].duplicate(true)
			continue
			
		var voxel:Vector3i = toundo[0]
		var chunk_coord : Vector3i = get_chunk_coord(voxel)
		var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
		chunk.remove_voxel_unsafe(voxel,[])
			
		if toundo.size()>1:
			var prop:Array = toundo[1]
			chunk.add_voxel_unsafe(voxel,prop,[])	
		
		if !chunks_to_regen.has(chunk_coord):
			chunks_to_regen.push_back(chunk_coord)
		
	for chunk_coord:Vector3i in chunks_to_regen:
		var chunk:VoxelChunk = chunks[chunk_coord]
		if chunk.voxels.size()==0:
			chunks.erase(chunk_coord)
			chunk.queue_free()
		else:
			chunk.regen_mesh()
			
	
var mesher: VoxelMesher

func _ready():
	mesher = VoxelMesher.new()
	# Ensure Shapes is ready/initialized if it hasn't run _ready yet
	if Shapes.database.size() == 0:
		if Shapes.has_method("_ready"):
			Shapes._ready()
	
	mesher.parse_shapes(Shapes.database, Shapes.uvpatterns)
	mesher.set_texture_dimensions(Shapes.TEX_WIDTH, Shapes.TEX_HEIGHT)
	
	ModeManager.editor_node.voxel_world.set_game_mode(false)
	add_layer()
	add_voxel(Vector3i(0,0,0),[ 0, 0, 0, 0, false, 0 ])
	clear_undo_history()
	expand_grout_patterns()

#divide, rounding towards negative infinity
func idiv(a,b)->int:
	var result = a/b
	if (a<0 && ((a%b)!=0)):
		result = result-1
	return result
	
	
func get_chunk_coord(voxel: Vector3i) -> Vector3i:
	return Vector3i(
		idiv(voxel.x, VoxelChunk.SIZE_X),
		idiv(voxel.y, VoxelChunk.SIZE_Y),
		idiv(voxel.z, VoxelChunk.SIZE_Z)
	)
	
func get_or_create_chunk(chunk_coord: Vector3i) -> VoxelChunk:
	if chunks.has(chunk_coord):
		return chunks[chunk_coord]
	
	var new_chunk : VoxelChunk = VoxelChunk.new(chunk_coord,entity_manager)
	new_chunk.chunk_coord = chunk_coord	
	new_chunk.name=str(chunk_coord)
	self.add_child(new_chunk)
	
	chunks[chunk_coord] = new_chunk
	return new_chunk
	
func add_voxel(voxel: Vector3i, prop: Array) -> void:
	var chunk_coord : Vector3i = get_chunk_coord(voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	chunk.add_voxel(voxel,prop,cur_undo_stack)

func add_voxel_unsafe(voxel: Vector3i, prop: Array):
	var chunk_coord : Vector3i = get_chunk_coord(voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	chunk.add_voxel_unsafe(voxel,prop,cur_undo_stack)
	

func remove_voxel_unsafe(voxel:Vector3i) -> bool:
	var chunk_coord = get_chunk_coord(voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	return chunk.remove_voxel_unsafe(voxel,cur_undo_stack)
	
func regen_all_chunks():
	for chunk:VoxelChunk in chunks.values():
		chunk.regen_mesh()
		
#this doesn't set ModeManager.mode idk but it doesn't
func set_game_mode(editor_mode:bool):
	print("sgm",editor_mode)
	for chunk:VoxelChunk in chunks.values():
		chunk.set_game_mode(editor_mode)
	


var layermask:Array[bool]=[true,true,true,true,true,true,true,true,true,true];


func v2darray_equality(a:Array,b:Array)->bool:
	for i in range(a.size()):
		if a[i]!=b[i]:
			return false
	return true
	

func get_all_chunks()->Array:
	return chunks.keys()

func get_piece_count_in_column(x:int,z:int)->int:
	var chunk_coords = get_all_chunks()
	var chunkx:int = idiv(x,VoxelChunk.SIZE_X)
	var chunkz:int = idiv(z,VoxelChunk.SIZE_Z)
	
	var count:int=0
	for chunk_coord in chunk_coords:
		if chunk_coord.x==chunkx && chunk_coord.z==chunkz:
			var chunk = get_or_create_chunk(chunk_coord)
			count+=chunk.get_piece_count_in_column(x,z)
			
	return count

func get_voxel_property(v:Vector3i)->Array:
	var chunk_coord = get_chunk_coord(v)
	var chunk = get_or_create_chunk(chunk_coord)
	return chunk.voxel_dict[v]
	
#returns colum, sorted from bottom to top
func get_column_voxels(x:int,z:int)->Array[Vector3i]:
	var chunk_coords=get_all_chunks()
	var chunkx:int = idiv(x,VoxelChunk.SIZE_X)
	var chunkz:int = idiv(z,VoxelChunk.SIZE_Z)	
	var col_pieces:Array[Vector3i]=[]
	for chunk_coord in chunk_coords:
		if chunk_coord.x==chunkx && chunk_coord.z==chunkz:
			var chunk = get_or_create_chunk(chunk_coord)
			var chunk_col_pieces:Array[Vector3i] = chunk.get_column_voxels(x,z)
			col_pieces.append_array(chunk_col_pieces)			
	col_pieces.sort_custom(func(a:Vector3i, b:Vector3i): return a.y < b.y)
	return col_pieces

func get_height_at(x:int,z:int)->int:
	var chunk_coords=get_all_chunks()
	var chunkx:int = idiv(x,VoxelChunk.SIZE_X)
	var chunkz:int = idiv(z,VoxelChunk.SIZE_Z)
	
	var maxheight=-6666
	for chunk_coord in chunk_coords:
		if chunk_coord.x==chunkx && chunk_coord.z==chunkz:
			var chunk = get_or_create_chunk(chunk_coord)
			var chunk_height = chunk.get_height_at(x,z)
			if chunk_height>maxheight:
				maxheight=chunk_height
	return maxheight
			
func occupied_by_voxel(voxel:Vector3i)->bool:
	var chunk_coord : Vector3i = get_chunk_coord(voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	return chunk.is_occupied(voxel)

func occupied_by_visible_voxel(voxel:Vector3i)->bool:
	var chunk_coord : Vector3i = get_chunk_coord(voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	return chunk.is_occupied_by_visible_voxel(voxel,layers)
	
func get_voxel(tri_index:int,chunk_coord:Vector3i)->Vector3i:
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	return chunk.get_voxel(tri_index)
	
func get_side(tri_index:int,chunk_coord:Vector3i)->int:
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	return chunk.get_side(tri_index)

func add_face(tri_index:int,chunk_coord:Vector3i,position_offset:Vector3i,tx:int,ty:int,blocktype:int,rot:int,vflip:bool,layer_idx:int):
	#need to be careful - new cube might not be in same chunk as the old one, lol
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	var source_voxel:Vector3i = chunk.get_voxel(tri_index)
	var direction:int = chunk.get_side(tri_index)
	var target_voxel = source_voxel+Glob.dirOffsets[direction]
	print(str(target_voxel))
	var target_chunk_coord : Vector3i = get_chunk_coord(target_voxel)
	var target_chunk : VoxelChunk = get_or_create_chunk(target_chunk_coord)
	return target_chunk.add_face_at(target_voxel+position_offset,tx,ty,blocktype,rot,vflip,layer_idx,cur_undo_stack)
		
func add_face_at(new_voxel:Vector3i,tx:int,ty:int,blocktype:int,rot:int,vflip:bool,layer_idx):
	var chunk_coord = get_chunk_coord(new_voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	chunk.add_face_at(new_voxel,tx,ty,blocktype,rot,vflip,layer_idx,cur_undo_stack)
	
func remove_range(a:Vector3i,b:Vector3i,ramp:Vector3i,ramp_origin:Vector3i):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(mini(a.x,b.x),mini(a.y,b.y),mini(a.z,b.z))
	var vmax:Vector3i = Vector3i(maxi(a.x,b.x),maxi(a.y,b.y),maxi(a.z,b.z))
	
	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var chunk_coord : Vector3i = get_chunk_coord(Vector3i(x,y,z))
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.remove_range(vmin,vmax,cur_undo_stack,ramp,ramp_origin)


func add_range(a:Vector3i,b:Vector3i,tx:int,ty:int,blocktype:int,rot:int,vflip:bool,layer:int,ramp:Vector3i,ramp_origin:Vector3i):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(mini(a.x,b.x),mini(a.y,b.y),mini(a.z,b.z))
	var vmax:Vector3i = Vector3i(maxi(a.x,b.x),maxi(a.y,b.y),maxi(a.z,b.z))	
	
	var chunks_to_visit:Array[Vector3i]=[]
	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z):
				var voxel : Vector3i = Vector3i(x,y,z)
				voxel += Glob.vtrace((voxel-ramp_origin)*ramp)*Vector3i.UP
				var chunk_coord : Vector3i = get_chunk_coord(voxel)
				if !chunks_to_visit.has(chunk_coord):
					chunks_to_visit.push_back(chunk_coord)			
	
	for chunk_coord:Vector3i in chunks_to_visit:		
		var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
		chunk.add_range(vmin,vmax,tx,ty,blocktype,rot,vflip,layer,cur_undo_stack,ramp,ramp_origin)

func fill_volume(a:Vector3i,b:Vector3i,blockinfo:Array):
	var vmin:Vector3i = Vector3i(mini(a.x,b.x),mini(a.y,b.y),mini(a.z,b.z))
	var vmax:Vector3i = Vector3i(maxi(a.x,b.x),maxi(a.y,b.y),maxi(a.z,b.z))

	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var voxel : Vector3i = Vector3i(x,y,z)
				var chunk_coord : Vector3i = get_chunk_coord(voxel)
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.fill_volume(vmin,vmax,blockinfo[2],blockinfo[1],0,blockinfo[3],blockinfo[4],blockinfo[5],cur_undo_stack)
	
func delete_volume(a:Vector3i,b:Vector3i):
	var vmin:Vector3i = Vector3i(mini(a.x,b.x),mini(a.y,b.y),mini(a.z,b.z))
	var vmax:Vector3i = Vector3i(maxi(a.x,b.x),maxi(a.y,b.y),maxi(a.z,b.z))

	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var voxel : Vector3i = Vector3i(x,y,z)
				var chunk_coord : Vector3i = get_chunk_coord(voxel)
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.delete_volume(vmin,vmax,cur_undo_stack)

func extrude(a:Vector3i,extrude_origin_face:int,b:Vector3i,extrusion_amount:int,payload:Array,layer: int):	
	var diag :Vector3i= b-a
	var dw:Vector3i = Glob.dirOffsets[extrude_origin_face]
	var du:Vector3i = Glob.normal_du(extrude_origin_face)
	var dv:Vector3i = Glob.normal_dv(extrude_origin_face)
	var u:int = Glob.idot(diag,du)
	var v:int = Glob.idot(diag,dv)
	
	if u<0:
		du=-du
		u=-u
	if v<0:
		dv=-dv
		v=-v

	var dirtychunks:Array=[]

	# We want to fill in the cuboid between a and b+extrusion_amount*dw - 
	# but we need to do each w-ray separately in order to find out what the
	# base-tile is that we're extruding (if there's nothing we don't draw the ray)
	for i_u in range(u+1):
		for i_v in range(v+1):
			var targetvoxel:Vector3i = a+du*i_u+dv*i_v
			var chunk_coord = get_chunk_coord(targetvoxel)
			var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
			if !chunk.is_occupied(targetvoxel):
				continue
			
			var voxel_info = chunk.voxel_dict[targetvoxel].duplicate()
			if payload.size()>0:
				#[block_type_selected,selected_tileset_column,selected_tileset_row,place_rotation,place_vflip,layer]
				# only copy texture
				voxel_info[1]=payload[2]
				voxel_info[2]=payload[1]
			voxel_info[5] = layer
			#now go along the ray
			for i_w in range(1,extrusion_amount+1):
				var target_v = targetvoxel+dw*i_w
				var chunk_coord_r = get_chunk_coord(target_v)
				var chunk_r : VoxelChunk = get_or_create_chunk(chunk_coord_r)
				#add voxel with voxel_info here
				chunk_r.add_voxel_unsafe(target_v,voxel_info.duplicate(),cur_undo_stack)
				if dirtychunks.has(chunk_r)==false:
					dirtychunks.push_back(chunk_r)
					
	for chunk in dirtychunks:
		chunk.regen_mesh()

func assign_layer(a:Vector3i,origin_face:int,b:Vector3i,extrusion_amount:int,layer: int):	
	var dirtychunks:Array=[]

	var diag :Vector3i= b-a
	var dw:Vector3i = Glob.dirOffsets[origin_face]
	var du:Vector3i = Glob.normal_du(origin_face)
	var dv:Vector3i = Glob.normal_dv(origin_face)
	var u:int = Glob.idot(diag,du)
	var v:int = Glob.idot(diag,dv)
	
	if u<0:
		du=-du
		u=-u
	if v<0:
		dv=-dv
		v=-v

	#find all voxes in this box and assign them to the layer
	for i_u in range(u+1):
		for i_v in range(v+1):
			for i_w in range(extrusion_amount+1):
				var targetvoxel:Vector3i = a+du*i_u+dv*i_v+dw*i_w
				var chunk_coord = get_chunk_coord(targetvoxel)
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				if chunk.is_occupied(targetvoxel):
					var voxel_info = chunk.voxel_dict[targetvoxel];
					cur_undo_stack.push_back([targetvoxel,voxel_info.duplicate()])
					if layers[voxel_info[5]].visible:
						voxel_info[5] = layer					
						if !dirtychunks.has(chunk):
							dirtychunks.push_back(chunk)

	for chunk in dirtychunks:
		chunk.regen_mesh()
	
func extrude_negative(a:Vector3i,extrude_origin_face:int,b:Vector3i,extrusion_amount:int):
	#want to delete all pieces in the cuboid between a and b+extrusion_amount*dw
	var dw:Vector3i = Glob.dirOffsets[extrude_origin_face]
	b += extrusion_amount*dw
	var vmin:Vector3i = Vector3i(mini(a.x,b.x),mini(a.y,b.y),mini(a.z,b.z))
	var vmax:Vector3i = Vector3i(maxi(a.x,b.x),maxi(a.y,b.y),maxi(a.z,b.z))

	var dirtychunks:Array=[]
	for x in range(vmin.x,vmax.x+1):
		for y in range(vmin.y,vmax.y+1):
			for z in range(vmin.z,vmax.z+1):
				var chunk_coord : Vector3i = get_chunk_coord(Vector3i(x,y,z))
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.remove_voxel_unsafe(Vector3i(x,y,z),cur_undo_stack)
				if !dirtychunks.has(chunk):
					dirtychunks.push_back(chunk)
	
	for chunk in dirtychunks:
		chunk.regen_mesh()		

func roomify(a:Vector3i,extrude_origin_face:int,b:Vector3i,extrusion_amount:int,remove_floor:bool,payload:Array,endcap:bool,mirrored:bool):	


	#this essentially functions like an extrude on an expanded range, and then a negative extrude on the original range
	var dw:Vector3i = Glob.dirOffsets[extrude_origin_face]
	var du:Vector3i = Glob.normal_du(extrude_origin_face)
	var dv:Vector3i = Glob.normal_dv(extrude_origin_face)

	if mirrored:
		a -= dw*(extrusion_amount+1)
		b -= dw*(extrusion_amount+1)
		extrusion_amount = extrusion_amount*2+1

	var diag :Vector3i= b-a
	var u:int = Glob.idot(diag,du)
	var v:int = Glob.idot(diag,dv)
	if u<0:
		du=-du
		u=-u
	if v<0:
		dv=-dv
		v=-v
	var a_expanded:Vector3i = a-du-dv
	var b_expanded:Vector3i = b+du+dv
	var endcapdiff:Vector3i = (1 if endcap else 0)*dw
	fill_volume(a_expanded+dw-endcapdiff,b_expanded+(extrusion_amount)*dw+endcapdiff,payload)
	if remove_floor==false:
		a+=dw
	delete_volume(a,b+extrusion_amount*dw)

func get_layer_bbox(layer_idx:int) -> Array[Vector3i]:
	var min_pos : Vector3i = Vector3i.MAX
	var max_pos : Vector3i = Vector3i.MIN	

	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		for voxel:Vector3i in chunk.voxels:
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_idx:
				continue
				
			if voxel.y<min_pos.y:
				min_pos.y=voxel.y
			if voxel.y>max_pos.y:
				max_pos.y=voxel.y
			if voxel.x<min_pos.x:
				min_pos.x=voxel.x
			if voxel.x>max_pos.x:
				max_pos.x=voxel.x
			if voxel.z<min_pos.z:
				min_pos.z=voxel.z
			if voxel.z>max_pos.z:
				max_pos.z=voxel.z
	var result:Array[Vector3i] = [min_pos,max_pos]
	return result

func add_hill(targetvoxel:Vector3i,selected_tileset_item:int,selected_tileset_row:int,layer_idx:int,lumpdropper_radius:int,lumpdropper_height:int):
	var minx:int = targetvoxel.x-lumpdropper_radius
	var maxx:int = targetvoxel.x+lumpdropper_radius
	var minz:int = targetvoxel.z-lumpdropper_radius
	var maxz:int = targetvoxel.z+lumpdropper_radius
	
	var chunk_coords_to_rebuild:Array[Vector3i]=[]

	var prop = [0,selected_tileset_item,selected_tileset_row,randi_range(0,3),false,layer_idx]

	for x in range(minx,maxx+1):
		for z in range(minz,maxz+1):
			var ground_point = Vector3i(x,targetvoxel.y,z)
			var radius = (ground_point-targetvoxel).length()
			if radius>lumpdropper_radius:
				continue
			var altitude = get_height_at(x,z)
			if altitude==-6666:
				continue
			
			var height = roundi(Glob.hill_height(lumpdropper_radius,lumpdropper_height,radius))
			for i in range(height):
				var targetpos:Vector3i = Vector3i(x,altitude+1+i,z)
				add_voxel_unsafe(targetpos,prop)
				
				#keep track of what chunks to regenerate meshes for				
				var chunk_coord = get_chunk_coord(targetpos)
				if !chunk_coords_to_rebuild.has(chunk_coord):
					chunk_coords_to_rebuild.push_back(chunk_coord)
	
	for chunk_coord:Vector3i in chunk_coords_to_rebuild:
		var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
		chunk.regen_mesh()


func remove_hill(targetvoxel:Vector3i,lumpdropper_radius:int,lumpdropper_height:int):	
	var chunk_coords_to_rebuild:Array[Vector3i]=[]
	
	var minx:int = targetvoxel.x-lumpdropper_radius
	var maxx:int = targetvoxel.x+lumpdropper_radius
	var minz:int = targetvoxel.z-lumpdropper_radius
	var maxz:int = targetvoxel.z+lumpdropper_radius
	for x in range(minx,maxx+1):
		for z in range(minz,maxz+1):
			var ground_point = Vector3i(x,targetvoxel.y,z)
			var radius = (ground_point-targetvoxel).length()
			if radius>lumpdropper_radius:
				continue
			var altitude = get_height_at(x,z)
			if altitude==-6666:
				continue
			
			var height = roundi(Glob.hill_height(lumpdropper_radius,lumpdropper_height,radius))
			
			var voxels_present : Array[Vector3i] = get_column_voxels(x,z)
			if height+1>=voxels_present.size():
				height=voxels_present.size()-1
			
			var voxels_to_remove = voxels_present.slice(max(0, voxels_present.size() - height), voxels_present.size())
			
			for v in voxels_to_remove:
				var chunk_coord:Vector3i = get_chunk_coord(v)
				if !chunk_coords_to_rebuild.has(chunk_coord):
					chunk_coords_to_rebuild.push_back(chunk_coord)
				remove_voxel_unsafe(v)
		
	for chunk_coord:Vector3i in chunk_coords_to_rebuild:
		var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
		chunk.regen_mesh()
	
func add_ball(centre:Vector3i,selected_tileset_item:int,selected_tileset_row:int,ball_radius:int,selected_layer_idx:int):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(centre.x-ball_radius,centre.y-ball_radius,centre.z-ball_radius)
	var vmax:Vector3i = Vector3i(centre.x+ball_radius,centre.y+ball_radius,centre.z+ball_radius)	
	
	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var chunk_coord : Vector3i = get_chunk_coord(Vector3i(x,y,z))
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.add_ball(centre,selected_tileset_item,selected_tileset_row,ball_radius,selected_layer_idx,cur_undo_stack)
				
					
func add_grout(centre:Vector3i,selected_tileset_item:int,selected_tileset_row:int,ball_radius:int,layer_idx:int):
	# removing all cubes inside the bounding box of a and b
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(centre.x-ball_radius,centre.y-ball_radius,centre.z-ball_radius)
	var vmax:Vector3i = Vector3i(centre.x+ball_radius,centre.y+ball_radius,centre.z+ball_radius)	

	var chunk_coords_to_rebuild:Array[Vector3i]=[]
	
	# calculate what voxels to change
	for x in range(vmin.x,vmax.x+1):
		for y in range(vmin.y,vmax.y+1):
			for z in range(vmin.z,vmax.z+1):
				var v:Vector3i = Vector3i(x,y,z)
				var radius = (v-centre).length()
				if round(radius)>=ball_radius:
					continue
				
				var added = add_grout_to_point(v,selected_tileset_item,selected_tileset_row,layer_idx)
				if added:
					var chunk_coord = get_chunk_coord(v)
					if !chunk_coords_to_rebuild.has(chunk_coord):
						chunk_coords_to_rebuild.push_back(chunk_coord)
	
	for chunk_coord:Vector3i in chunk_coords_to_rebuild:
		var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
		chunk.regen_mesh()

var grout_replacements : Array = [	
	
	{
		from_voxel = [ Shapes.VOXEL_EMPTY, -1, -1 ],
		neighbour_pattern = 
			[
				null, #S
				[ Shapes.FaceOccupancy.TRI0 ], #N
				null, #W
				[ Shapes.FaceOccupancy.TRI1 ], #E
				[ Shapes.FaceOccupancy.EMPTY ], #U
				[ Shapes.FaceOccupancy.QUAD ], #D
			],
		to_voxel = [ Shapes.CLIPPED_RAMP, 0, false]
	},		
	
	{
		from_voxel = [ Shapes.VOXEL_EMPTY, -1, -1 ],
		neighbour_pattern = 
			[
				null, #S
				null, #N
				[ Shapes.FaceOccupancy.TRI1 ], #W
				null, #E
				[ Shapes.FaceOccupancy.EMPTY ], #U
				[ Shapes.FaceOccupancy.TRI2 ], #D
			],
		to_voxel = [ Shapes.CLIPPED_RAMP, 3, false]
	},	
	##flip of above:	
	{
		from_voxel = [ Shapes.VOXEL_EMPTY, -1, -1 ],
		neighbour_pattern = 
			[
				null, #S
				[ Shapes.FaceOccupancy.TRI3 ], #N
				null, #W
				null, #E
				[ Shapes.FaceOccupancy.EMPTY ], #U
				[ Shapes.FaceOccupancy.TRI2 ], #D
			],
		to_voxel = [ Shapes.CLIPPED_RAMP, 3, false]
	},		
	{
		from_voxel = [ Shapes.VOXEL_EMPTY, -1, -1 ],
		neighbour_pattern = 
			[
				null, #S
				[ Shapes.FaceOccupancy.QUAD ], #N
				null, #W
				[ Shapes.FaceOccupancy.QUAD ], #E
				[ Shapes.FaceOccupancy.EMPTY ], #U
				[ Shapes.FaceOccupancy.QUAD], #D
			],
		to_voxel = [ Shapes.CLIPPED_CORNER, 0, false]
	},
	{
		from_voxel = [ Shapes.VOXEL_EMPTY, -1, -1 ],
		neighbour_pattern = 
			[
				null, #S
				[ Shapes.FaceOccupancy.QUAD], #N
				null, #W
				null, #E
				[ Shapes.FaceOccupancy.EMPTY ], #U
				[ Shapes.FaceOccupancy.QUAD], #D
			],
		to_voxel = [ Shapes.RAMP, 0, false]
	},	
		
	{
		from_voxel = [ Shapes.RAMP, 0, 0 ],
		neighbour_pattern = 
			[
				[ Shapes.FaceOccupancy.QUAD ], #S
				null, #N
				[ Shapes.FaceOccupancy.QUAD], #W
				[ Shapes.FaceOccupancy.QUAD], #E
				null, #U
				null, #D
			],
		to_voxel = [ Shapes.CUBE, 0, false]
	},	
	
	
	{
		from_voxel = [ Shapes.RAMP, 0, 0 ],
		neighbour_pattern = 
			[
				[ Shapes.FaceOccupancy.TRI0 ], #S
				null, #N
				null, #W
				[ Shapes.FaceOccupancy.QUAD], #E
				null, #U
				null, #D
			],
		to_voxel = [ Shapes.CLIPPED_CORNER, 0, false]
	},	
	#flip of above
	{
		from_voxel = [ Shapes.RAMP, 0, 0 ],
		neighbour_pattern = 
			[
				[ Shapes.FaceOccupancy.TRI0 ], #S
				null, #N
				[ Shapes.FaceOccupancy.QUAD], #W
				null, #E
				null, #U
				null, #D
			],
		to_voxel = [ Shapes.CLIPPED_CORNER, 0, false]
	},	
	
		{
		from_voxel = [ Shapes.CLIPPED_CORNER, 0, 0 ],
		neighbour_pattern = 
			[
				[ Shapes.FaceOccupancy.QUAD ], #S
				null, #N
				[ Shapes.FaceOccupancy.QUAD ], #W
				null, #E
				null, #U
				null, #D
			],
		to_voxel = [ Shapes.CUBE, 0, false]
	},
]


func expand_grout_patterns():
	#return
	#creates new grout patterns by rotating existing ones
	#print("start grout count : "+str(grout_replacements.size()))
	var new_grout_replacements:Array=[]
	var oldsize=grout_replacements.size()
	for i in range(oldsize):
		# for each existing pattern
		var cur_replacement : Dictionary = grout_replacements[i]
		for rots in range(0,4):
			# we want to create all 'rotated' versions of it (including the null 
			# rotation).
			var new_replacement = cur_replacement.duplicate(true)
			var pattern = [null,null,null,null,null,null]
			for was_dir in range(pattern.size()):
				# if this rule previously was in the west slot, rotate it clockwise X steps, and 
				# (if r=1, say) put it in  north slot
				var to_dir = Glob.rot_dir(was_dir,rots)
				pattern[to_dir]=new_replacement.neighbour_pattern[was_dir]
				if pattern[to_dir]!=null:
					for pattern_i in range(pattern[to_dir].size()):
						pattern[to_dir][pattern_i]=Shapes.z_rotate_face_occupancy_n_times(pattern[to_dir][pattern_i],was_dir,rots)

			new_replacement.neighbour_pattern=pattern
			if new_replacement.from_voxel!=null && new_replacement.from_voxel[1]!=-1:
				new_replacement.from_voxel[1]=(new_replacement.from_voxel[1]+rots)%4	
			new_replacement.to_voxel[1]=(new_replacement.to_voxel[1]+rots)%4
			new_grout_replacements.push_back(new_replacement)
			
	grout_replacements=new_grout_replacements
	#print("middle grout count : "+str(grout_replacements.size()))
	new_grout_replacements=[]
	##do it one more time, but add vertical flips
	oldsize=grout_replacements.size()
	for i in range(oldsize):
		# for each existing pattern
		var cur_replacement : Dictionary = grout_replacements[i]
		for times in range(0,2):
			# we want to create all 'rotated' versions of it (including the null 
			# rotation).
			var new_replacement = cur_replacement.duplicate(true)
			var pattern = [null,null,null,null,null,null]
			for was_dir in range(pattern.size()):
				# if this rule previously was in the west slot, rotate it clockwise X steps, and 
				# (if r=1, say) put it in  north slot
				var to_dir = Glob.do_flip(was_dir,times)
				pattern[to_dir]=new_replacement.neighbour_pattern[was_dir]
				if pattern[to_dir]!=null:
					for pattern_i in range(pattern[to_dir].size()):
						if times==1:
							pattern[to_dir][pattern_i]=Shapes.vflip_face_occupancy(pattern[to_dir][pattern_i],was_dir)
			new_replacement.neighbour_pattern=pattern
			if times==1:
				if new_replacement.from_voxel!=null && new_replacement.from_voxel[2]!=-1:
					new_replacement.from_voxel[2]=1-new_replacement.from_voxel[2]
				new_replacement.to_voxel[2]=!new_replacement.to_voxel[2]
			new_grout_replacements.push_back(new_replacement)			
	grout_replacements=new_grout_replacements
	#print("end grout count : "+str(grout_replacements.size()))
	
func add_grout_to_point(v:Vector3i,_tx:int,_ty:int,layer_idx:int)->bool:
	var occupied = occupied_by_voxel(v)		
	var v_props = null
	if occupied:
		v_props = get_voxel_property(v)
	var applied_something:bool=false
	var tx:int=0
	var ty:int=0
	for replacement_index in range(grout_replacements.size()):
		var replacement : Dictionary = grout_replacements[replacement_index]
		if replacement.from_voxel[0]==Shapes.VOXEL_EMPTY:
			if occupied:
				continue
		else:
			if !occupied:
				continue
			#need to compare desired initial contents with props
			var from_voxel:Array=replacement.from_voxel
			if v_props[0]!=from_voxel[0] || \
				( from_voxel[1]!=-1 && from_voxel[1]!=v_props[3]) || \
				( from_voxel[2]!=-1 && (true if from_voxel[2]==1 else false)!=v_props[4]):
					continue
		var passes : bool = true
		for pattern_d in range(replacement.neighbour_pattern.size()):
			var pattern = replacement.neighbour_pattern[pattern_d]
			var target_voxel = v+Glob.dirOffsets[pattern_d]
			var target_occupied = occupied_by_voxel(target_voxel)
			if pattern==null:
				pass
			else: 
				if !target_occupied:
					if pattern.has(Shapes.FaceOccupancy.EMPTY):
						#we're good - we want nothing and we have it :)
						continue
					else:
						passes=false
						break
				#= [blocktype,tx,ty,rot,vflip,layer]
				var target_voxel_properties = get_voxel_property(target_voxel)
				# need to get the FaceOccupancy of the target face of the target foxel
				var dir_facing = Glob.oppositeDir[pattern_d]
				var target_voxel_occupancy:Shapes.FaceOccupancy = Shapes.get_face_occupancy(target_voxel_properties[0],target_voxel_properties[3],target_voxel_properties[4],dir_facing)				
				if target_voxel_occupancy!=pattern[0]:
					passes=false
					break
					
				tx = target_voxel_properties[1]
				ty = target_voxel_properties[2]
					
		if passes:
			var to:Array=replacement.to_voxel;
			if Input.is_key_pressed(KEY_SHIFT):
				tx=_tx
				ty=_ty
			if occupied:
				remove_voxel_unsafe(v)
			add_voxel_unsafe(v,[to[0],tx,ty,to[1],to[2],layer_idx])
			applied_something = true
		
	return applied_something
				
func remove_ball(centre:Vector3i,ball_radius:int):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(centre.x-ball_radius,centre.y-ball_radius,centre.z-ball_radius)
	var vmax:Vector3i = Vector3i(centre.x+ball_radius,centre.y+ball_radius,centre.z+ball_radius)	
	
	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var chunk_coord : Vector3i = get_chunk_coord(Vector3i(x,y,z))
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.remove_ball(centre,ball_radius,cur_undo_stack,true,-1,-1)
				
func remove_ball_noncube(centre:Vector3i,ball_radius:int,tx:int,ty:int):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(centre.x-ball_radius,centre.y-ball_radius,centre.z-ball_radius)
	var vmax:Vector3i = Vector3i(centre.x+ball_radius,centre.y+ball_radius,centre.z+ball_radius)	
	
	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var chunk_coord : Vector3i = get_chunk_coord(Vector3i(x,y,z))
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				chunk.remove_ball(centre,ball_radius,cur_undo_stack,false,tx,ty)

#counts cell given, as well as all orthogonally adjacent cells - returns  [ 0->8 , voxelproperties ]
func neighbourhood_occupancy(v:Vector3i)->Array:
	var count=0
	var propertyfound:Array=[]
	var neighbourhood_coords : Array[Vector3i] = [
			v,
			v+Vector3i(0,-1,0),
			v+Vector3i(0,0,-1),
			v+Vector3i(1,0,0),
			v+Vector3i(-1,0,0),
			v+Vector3i(0,0,1),
			v+Vector3i(0,1,0),
		]
	for vec in neighbourhood_coords:
		if occupied_by_voxel(vec):
			if propertyfound==[]:
				propertyfound = get_voxel_property(vec)
			count=count+1
	return [count,propertyfound]

func do_smooth(centre:Vector3i,ball_radius:int,smoothness_threshold:int):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(centre.x-ball_radius,centre.y-ball_radius,centre.z-ball_radius)
	var vmax:Vector3i = Vector3i(centre.x+ball_radius,centre.y+ball_radius,centre.z+ball_radius)	

	var to_add:Array=[]#contains for each block an array [count, props]
	var to_remove:Array[Vector3i]=[]
	
	# calculate what voxels to change
	for x in range(vmin.x,vmax.x+1):
		for y in range(vmin.y,vmax.y+1):
			for z in range(vmin.z,vmax.z+1):
				var v:Vector3i = Vector3i(x,y,z)
				var radius = (v-centre).length()
				if round(radius)>=ball_radius:
					continue
				var count_props:Array = neighbourhood_occupancy(v)
				var c = count_props[0]
				
				var there = occupied_by_voxel(v)
							
				if there && c<smoothness_threshold:
					to_remove.push_back(v)
				elif (!there) && c>smoothness_threshold:
					var props = count_props[1]
					to_add.push_back([v,props])

	# add/remove voxels
	var chunk_coords_to_rebuild:Array[Vector3i]=[]
	for vox_props in to_add:
		var v:Vector3i = vox_props[0]
		var props:Array = vox_props[1]
		add_voxel_unsafe(v,props)
		
		var chunk:Vector3i = get_chunk_coord(v)
		if !chunk_coords_to_rebuild.has(chunk):
			chunk_coords_to_rebuild.push_back(chunk)
	for v in to_remove:
		var chunk:Vector3i = get_chunk_coord(v)
		if !chunk_coords_to_rebuild.has(chunk):
			chunk_coords_to_rebuild.push_back(chunk)
		remove_voxel_unsafe(v)
		
	# rebuild chunks
	for chunk_coord:Vector3i in chunk_coords_to_rebuild:
		var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
		chunk.regen_mesh()

func replace_tiles(from_tileset_item:int,from_tileset_row:int, to_tileset_item:int, to_tileset_row:int,in_layer_idx:int):
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.replace_tiles(from_tileset_item,from_tileset_row, to_tileset_item, to_tileset_row,in_layer_idx,cur_undo_stack)

func paint_ball(centre:Vector3i,ball_radius:int,selected_tileset_column:int,selected_tileset_row:int,rot:int,vflip:bool,layer:int):
	# removing all cubes inside the bounding box of a and b
	var vmin:Vector3i = Vector3i(centre.x-ball_radius,centre.y-ball_radius,centre.z-ball_radius)
	var vmax:Vector3i = Vector3i(centre.x+ball_radius,centre.y+ball_radius,centre.z+ball_radius)	
	
	for x in range(vmin.x,vmax.x+VoxelChunk.SIZE_X,VoxelChunk.SIZE_X):
		for y in range(vmin.y,vmax.y+VoxelChunk.SIZE_Y,VoxelChunk.SIZE_Y):
			for z in range(vmin.z,vmax.z+VoxelChunk.SIZE_Z,VoxelChunk.SIZE_Z):
				var chunk_coord : Vector3i = get_chunk_coord(Vector3i(x,y,z))
				var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
				#print("painting chunk "+str(chunk))
				chunk.paint_ball(centre,ball_radius,selected_tileset_column,selected_tileset_row,rot,vflip,layer,cur_undo_stack)
	
func remove_at(voxel:Vector3i) -> bool:
	var chunk_coord = get_chunk_coord(voxel)
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	return chunk.remove_at(voxel,cur_undo_stack)
	
func removeFace(tri_index:int,chunk_coord:Vector3i):
	var chunk : VoxelChunk = get_or_create_chunk(chunk_coord)
	chunk.remove_face(tri_index,cur_undo_stack)

func delete_layer(layer_idx:int):
	if layers.size()==1:
		return
		
	cur_undo_stack.push_back(["LAYERS",layers.duplicate()])
	
	layers.remove_at(layer_idx)	
	var dirtychunks:Array=[]
			
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var chunk_voxel_count = chunk.voxels.size()
		for i in range(chunk_voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_props = chunk.voxel_dict[voxel]
			var layer = voxel_props[5]
			if layer==layer_idx:
				chunk.remove_voxel_unsafe(voxel,cur_undo_stack)				
				if dirtychunks.has(chunk)==false:
					dirtychunks.push_back(chunk)
			elif layer>layer_idx:
				chunk.set_voxel_properties(voxel,voxel_props[1],voxel_props[2],voxel_props[3],voxel_props[4],layer-1,cur_undo_stack)
				
	for chunk in dirtychunks:
		chunk.regen_mesh()	
		
		
			
func move_layer_idx(layer_idx:int,direction:int):
	var layer_a_idx : int = layer_idx
	var layer_b_idx : int = layer_idx+direction
	if layer_a_idx<0 ||layer_a_idx>=layers.size():
		return
	if layer_b_idx<0 ||layer_b_idx>=layers.size():
		return
	
	cur_undo_stack.push_back(["LAYERS",layers.duplicate()])
	
	#step 1, swap layers
	var tmp = layers[layer_a_idx]
	layers[layer_a_idx]=layers[layer_b_idx]
	layers[layer_b_idx]=tmp
	
	#now, go throguh all voxels and swap
	
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		for voxel:Vector3i in chunk.voxels:
			var voxel_props = chunk.voxel_dict[voxel]
			var layer = voxel_props[5]
			if layer==layer_a_idx:
				voxel_props[5] = layer_b_idx
			elif layer==layer_b_idx:
				voxel_props[5] = layer_a_idx

#func set_layer_names_ui():
	#var layer_container = get_tree().get_first_node_in_group("Layer_Container_Group")
	#var children = layer_container.get_children()
	#children = children.slice(0,children.size()-1)
	#for child_idx:int in range(children.size()):
		#var layer_item : LayerItem = children[child_idx]
		#layer_item.set_layer_name(layers[child_idx])
		#layer_item.index = child_idx
	#
	
func strip_digits_from_end(s:String):
	if s.length()==0:
		return s
	while s.length()>0 && (s[s.length()-1]).is_valid_int():
		s = s.substr(0,s.length()-1)
	return s
	
func add_layer(layer_name:String="layer"):
	var layer_struct = {
		name=layer_name,
		visible=true
	}
	layers.push_back(layer_struct)
	normalize_layer_names();
	
func normalize_layer_names():
	var haschanged=false
	for i in range(1,layers.size()):
		var layer_name = layers[i].name
		var preceeding = layers.slice(0,i)
		var preceeding_names = []
		for layer in preceeding:
			preceeding_names.push_back(layer.name)
		if preceeding_names.has(layer_name):
			#strip number from end
			var stripped = strip_digits_from_end(layer_name)
			var test_index=0
			while true:
				test_index+=1
				var cand_name = stripped+str(test_index)
				if !preceeding_names.has(cand_name):
					layers[i].name=cand_name
					haschanged=true
					break				
	return haschanged


func round_to_even(f:float)->int:
	#don't use int(), because that rounds to zero
	var integer_part:int = floori(f)
	#var decimal_part:float = f-integer_part
	if integer_part%2==0:
		return integer_part
	else:
		return integer_part+1
	
		
func rotate_layer(layer_idx:int,clockwise:bool):
	
	var chunks_to_regen:Array[Vector3i]=[]


	var layer_voxels : Array[Vector3i] = [];
	var layer_voxel_dict : Array = [];
	
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var voxel_count = chunk.voxels.size()
		for i in range(voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_idx:
				continue
			#add to layer list
			layer_voxels.push_back(voxel)
			var voxel_props = voxel_info
			layer_voxel_dict.push_back(voxel_props)

			#remove from chunk
			chunk.remove_voxel_unsafe(voxel,cur_undo_stack)
						
			if !chunks_to_regen.has(chunk_coord):
				chunks_to_regen.push_back(chunk_coord)

	#get min/max
	var min_pos : Vector3i = Vector3i.MAX
	var max_pos : Vector3i = Vector3i.MIN
	for voxel:Vector3i in layer_voxels:
		if voxel.x<min_pos.x:
			min_pos.x=voxel.x
		if voxel.x>max_pos.x:
			max_pos.x=voxel.x
		if voxel.y<min_pos.y:
			min_pos.y=voxel.y
		if voxel.y>max_pos.y:
			max_pos.y=voxel.y
		if voxel.z<min_pos.z:
			min_pos.z=voxel.z
		if voxel.z>max_pos.z:
			max_pos.z=voxel.z

	# Store the original min_pos to preserve after rotation
	var original_min_pos : Vector3i = min_pos

	var rot_offset = 3 if clockwise else 1
	var rotated_voxels : Array[Vector3i] = []
	
	# First pass: rotate all voxels around origin (0,0)
	for i:int in range(0,layer_voxels.size()):
		var voxel:Vector3i = layer_voxels[i]
		#make copy of dict because i will want to undo it
		var voxel_props = layer_voxel_dict[i].duplicate()
	
		#rotate the individual voxel
		voxel_props[3] = (voxel_props[3]+rot_offset)%4

		# Rotate around origin (0,0)
		var rotated_pos : Vector2i
		if clockwise: # 90° clockwise rotation: (x,z) -> (z,-x)
			rotated_pos.x = voxel.z
			rotated_pos.y = -voxel.x
		else: # 90° counter-clockwise rotation: (x,z) -> (-z,x)
			rotated_pos.x = -voxel.z
			rotated_pos.y = voxel.x

		var rotated_voxel = Vector3i(rotated_pos.x, voxel.y, rotated_pos.y)
		rotated_voxels.push_back(rotated_voxel)
		layer_voxel_dict[i] = voxel_props

	# Second pass: find new min_pos after rotation
	var new_min_pos : Vector3i = Vector3i.MAX
	for rotated_voxel:Vector3i in rotated_voxels:
		if rotated_voxel.x < new_min_pos.x:
			new_min_pos.x = rotated_voxel.x
		if rotated_voxel.y < new_min_pos.y:
			new_min_pos.y = rotated_voxel.y
		if rotated_voxel.z < new_min_pos.z:
			new_min_pos.z = rotated_voxel.z

	# Calculate translation needed to make new_min_pos equal original_min_pos
	var translation_offset : Vector3i = original_min_pos - new_min_pos

	# Third pass: apply translation and place voxels
	for i:int in range(0,rotated_voxels.size()):
		var rotated_voxel = rotated_voxels[i]
		var voxel_props = layer_voxel_dict[i]
		
		#add translation to preserve min_pos
		var new_voxel = rotated_voxel + translation_offset
		var new_voxel_chunk_coord = get_chunk_coord(new_voxel)
		var new_voxel_chunk = get_or_create_chunk(new_voxel_chunk_coord)
		new_voxel_chunk.remove_voxel_unsafe(new_voxel,cur_undo_stack)
		new_voxel_chunk.add_voxel_unsafe(new_voxel,voxel_props,cur_undo_stack)

		if !chunks_to_regen.has(new_voxel_chunk_coord):
			chunks_to_regen.push_back(new_voxel_chunk_coord)

	for chunk_coord:Vector3i in chunks_to_regen:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.regen_mesh()

func mirror_layer(layer_idx:int,mirror_axis:int):	
	var chunks_to_regen:Array[Vector3i]=[]


	var layer_voxels : Array[Vector3i] = [];
	var layer_voxel_dict : Array = [];
	
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var voxel_count = chunk.voxels.size()
		for i in range(voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_idx:
				continue
			#add to layer list
			layer_voxels.push_back(voxel)
			var voxel_props = voxel_info
			layer_voxel_dict.push_back(voxel_props)

			#remove from chunk
			chunk.remove_voxel_unsafe(voxel,cur_undo_stack)
						
			if !chunks_to_regen.has(chunk_coord):
				chunks_to_regen.push_back(chunk_coord)

	#get min/max
	var min_pos : Vector3i = Vector3i.MAX
	var max_pos : Vector3i = Vector3i.MIN
	for voxel:Vector3i in layer_voxels:
		if voxel.x<min_pos.x:
			min_pos.x=voxel.x
		if voxel.x>max_pos.x:
			max_pos.x=voxel.x
		if voxel.y<min_pos.y:
			min_pos.y=voxel.y
		if voxel.y>max_pos.y:
			max_pos.y=voxel.y
		if voxel.z<min_pos.z:
			min_pos.z=voxel.z
		if voxel.z>max_pos.z:
			max_pos.z=voxel.z

	# first pass: flip all voxes by carefully rotating them depending on their type and the axis
	for i:int in range(0,layer_voxels.size()):
		# var voxel = layer_voxels[i]
		var voxel_props = layer_voxel_dict[i].duplicate()
		var voxel_type = voxel_props[0]
		var voxel_rotation = voxel_props[3]
		
		match voxel_type:
			#Shapes that don't need to be flipped
			Shapes.CUBE,Shapes.PILLAR,Shapes.WALL:
				pass #don't need to do anyfink
			#shapes that need to be rotated twice (that have mirror symmetry along the other axis)
			Shapes.RAMP,Shapes.SHALLOW_RAMP_LOW,Shapes.SHALLOW_RAMP_HIGH,Shapes.STAIRS:
				if mirror_axis == Glob.X:
					if voxel_rotation%2==1:
						voxel_rotation = (voxel_rotation+2)%4
				elif mirror_axis == Glob.Z:
					if voxel_rotation%2==0:
						voxel_rotation = (voxel_rotation+2)%4

			#corner pieces that need to be rotated 0/1/2
			Shapes.CLIPPED_CORNER,Shapes.CLIPPED_EDGE,Shapes.CLIPPED_RAMP,Shapes.INNERCORNER2:
				#rotation is clockwise
				#by default pieces face SW
				if mirror_axis == Glob.Z: 
					match voxel_rotation:
						0:
							voxel_rotation = 1
						1:
							voxel_rotation = 0
						2:
							voxel_rotation = 3
						3:
							voxel_rotation = 2
				else:
					match voxel_rotation:
						0:
							voxel_rotation = 3
						1:
							voxel_rotation = 2
						2:
							voxel_rotation = 1
						3:
							voxel_rotation = 0
		
		voxel_props[3] = voxel_rotation
		layer_voxel_dict[i] = voxel_props

		



	# Third pass: apply translation and place voxels
	for i:int in range(0,layer_voxels.size()):
		var flipped_voxel = layer_voxels[i]
		var voxel_props = layer_voxel_dict[i]
		
		#add translation to preserve min_pos
		if mirror_axis == Glob.X:
			flipped_voxel.x = max_pos.x - (flipped_voxel.x - min_pos.x)
		elif mirror_axis == Glob.Z:
			flipped_voxel.z = max_pos.z - (flipped_voxel.z - min_pos.z)
		
		#add translation to preserve min_pos
		var new_voxel_chunk_coord = get_chunk_coord(flipped_voxel)
		var new_voxel_chunk = get_or_create_chunk(new_voxel_chunk_coord)
		new_voxel_chunk.remove_voxel_unsafe(flipped_voxel,cur_undo_stack)
		new_voxel_chunk.add_voxel_unsafe(flipped_voxel,voxel_props,cur_undo_stack)
		
		if !chunks_to_regen.has(new_voxel_chunk_coord):
			chunks_to_regen.push_back(new_voxel_chunk_coord)

	for chunk_coord:Vector3i in chunks_to_regen:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.regen_mesh()
	
	
func translate_layer(layer_idx:int,offset:Vector3i):
	var layer_voxels : Array[Vector3i] = [];
	var layer_voxel_dict : Dictionary = {};
	
	var chunks_to_regen:Array[Vector3i]=[]

	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var voxel_count = chunk.voxels.size()
		for i in range(voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_idx:
				continue
			#add to layer list
			layer_voxels.push_back(voxel)
			var voxel_props = voxel_info
			layer_voxel_dict[voxel] = voxel_props
			#remove it from the chunk
			chunk.remove_voxel_unsafe(voxel,cur_undo_stack)

			if !chunks_to_regen.has(chunk_coord):
				chunks_to_regen.push_back(chunk_coord)
	
	#now for each layer voxel, translate it and add it back
	for voxel:Vector3i in layer_voxels:
		var voxel_props = layer_voxel_dict[voxel]
		var new_voxel = voxel + offset
		var new_voxel_chunk_coord = get_chunk_coord(new_voxel)
		var new_voxel_chunk = get_or_create_chunk(new_voxel_chunk_coord)
		new_voxel_chunk.remove_voxel_unsafe(new_voxel,cur_undo_stack)
		new_voxel_chunk.add_voxel_unsafe(new_voxel,voxel_props,cur_undo_stack)

		if !chunks_to_regen.has(new_voxel_chunk_coord):
			chunks_to_regen.push_back(new_voxel_chunk_coord)

	for chunk_coord:Vector3i in chunks_to_regen:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.regen_mesh()

#JUST NORMIE LAYER COPY, NOT THE INTER_LEVEL LAYER COPY
func duplicate_layer(layer_from_idx:int,layer_to_idx:int,translate_direction:Vector3i):
		
	var chunks_to_regen:Array[Vector3i]=[]

	var layer_voxels : Array[Vector3i] = [];
	var layer_voxel_dict : Array = [];
	
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var voxel_count = chunk.voxels.size()
		for i in range(voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_from_idx:
				continue
			#add to layer list
			layer_voxels.push_back(voxel)
			var voxel_props = voxel_info
			layer_voxel_dict.push_back(voxel_props)

	#get min/max
	var min_pos : Vector3i = Vector3i.MAX
	var max_pos : Vector3i = Vector3i.MIN
	for voxel:Vector3i in layer_voxels:
		if voxel.x<min_pos.x:
			min_pos.x=voxel.x
		if voxel.x>max_pos.x:
			max_pos.x=voxel.x
		if voxel.y<min_pos.y:
			min_pos.y=voxel.y
		if voxel.y>max_pos.y:
			max_pos.y=voxel.y
		if voxel.z<min_pos.z:
			min_pos.z=voxel.z
		if voxel.z>max_pos.z:
			max_pos.z=voxel.z

	var translate_delta : Vector3i = (max_pos-min_pos+Vector3i.ONE)*translate_direction

	#for each voxel, translate it and add it to the new layer
	for voxel_idx:int in range(0,layer_voxels.size()):
		var voxel:Vector3i = layer_voxels[voxel_idx]
		var voxel_props = layer_voxel_dict[voxel_idx].duplicate()
		voxel_props[5] = layer_to_idx
		var new_voxel = voxel + translate_delta
		var new_voxel_chunk_coord = get_chunk_coord(new_voxel)
		var new_voxel_chunk = get_or_create_chunk(new_voxel_chunk_coord)
		new_voxel_chunk.remove_voxel_unsafe(new_voxel,cur_undo_stack)
		new_voxel_chunk.add_voxel_unsafe(new_voxel,voxel_props,cur_undo_stack)

		if !chunks_to_regen.has(new_voxel_chunk_coord):
			chunks_to_regen.push_back(new_voxel_chunk_coord)

	for chunk_coord:Vector3i in chunks_to_regen:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.regen_mesh()

#returns max and min coords of the layer
func get_layer_bounds(layer_idx:int)->Array[Vector3i]:
	var min_pos : Vector3i = Vector3i.MAX
	var max_pos : Vector3i = Vector3i.MIN
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var voxel_count = chunk.voxels.size()
		for i in range(voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_idx:
				continue
			if voxel.x<min_pos.x:
				min_pos.x=voxel.x
			if voxel.x>max_pos.x:
				max_pos.x=voxel.x
			if voxel.y<min_pos.y:
				min_pos.y=voxel.y
			if voxel.y>max_pos.y:
				max_pos.y=voxel.y
			if voxel.z<min_pos.z:
				min_pos.z=voxel.z
			if voxel.z>max_pos.z:
				max_pos.z=voxel.z
	return [min_pos,max_pos]

func copy_layer_to_clipboard(layer_idx:int,clipboard:Dictionary):
	clipboard.clear()
	for chunk_coord:Vector3i in chunks:
		var chunk:VoxelChunk = chunks[chunk_coord]
		var voxel_count = chunk.voxels.size()
		for i in range(voxel_count-1,-1,-1):
			var voxel:Vector3i = chunk.voxels[i]
			var voxel_info = chunk.voxel_dict[voxel]
			var voxel_layer = voxel_info[5]
			if voxel_layer!=layer_idx:
				continue
			clipboard[voxel] = voxel_info


func add_layer_from_clipboard_dict(clipboard:Dictionary,clipboard_layer_name:String,offset:Vector3i):
	add_layer(clipboard_layer_name)
	var layer_idx = layers.size()-1

	var chunks_to_regen:Array[Vector3i]=[]

	for voxel:Vector3i in clipboard.keys():
		var voxel_info = clipboard[voxel].duplicate()
		voxel_info[5] = layer_idx
		var new_voxel = voxel + offset
		var new_voxel_chunk_coord = get_chunk_coord(new_voxel)
		var new_voxel_chunk = get_or_create_chunk(new_voxel_chunk_coord)
		new_voxel_chunk.remove_voxel_unsafe(new_voxel,cur_undo_stack)
		new_voxel_chunk.add_voxel_unsafe(new_voxel,voxel_info,cur_undo_stack)
		
		if !chunks_to_regen.has(new_voxel_chunk_coord):
			chunks_to_regen.push_back(new_voxel_chunk_coord)

	for chunk_coord:Vector3i in chunks_to_regen:
		var chunk:VoxelChunk = chunks[chunk_coord]
		chunk.regen_mesh()

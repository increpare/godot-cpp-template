class_name EntityManager extends Node3D

var entity_billboarded_icon = preload("res://VoxelWorld/Editor/Scenes/Entity_Billboarded_Icon.tscn")
var entity_icon_materials:Array[StandardMaterial3D]=[
	preload("res://VoxelWorld/Editor/Materials/Entity_Icon_Object.tres"),
	preload("res://VoxelWorld/Editor/Materials/Entity_Icon_Door.tres"),
	preload("res://VoxelWorld/Editor/Materials/Entity_Icon_Actor.tres"),
	preload("res://VoxelWorld/Editor/Materials/Entity_Icon_Trigger.tres"),
	preload("res://VoxelWorld/Editor/Materials/Entity_Icon_Rope.tres"),
	preload("res://VoxelWorld/Editor/Materials/Entity_Icon_Water.tres"),
]
#var entity = {
#	type = "Actor",
#	position = Vector3(1,2,3),
#	dir = Glob.N
#}
var entities:Array[Dictionary] = []
var associated_objects:Array[MeshInstance3D] = []

const margin:float=0.05

# array of pairs, where first element is timestamp
var undo_history:Array[Array]=[]
var cur_undo_stack:Array[Array]=[]

func get_start_position()->Vector3i:
	var checkpoint_name = SaverLoader.get_val("checkpoint")
	if checkpoint_name==null:
		checkpoint_name="START"
	if checkpoint_name=="START":
		checkpoint_name = "SACRED_NEST"	
	if has_entity_of_name(checkpoint_name):
		var bonfire = find_entity_by_name(checkpoint_name)				
		return Vector3(bonfire.position)
	return Vector3i.ZERO
	
func commit_backup():
	if cur_undo_stack.size()>0:
		undo_history.push_back([Time.get_ticks_msec(),cur_undo_stack])
		cur_undo_stack=[]
	
func restore_backup():
	if undo_history.size()==0:
		print(("no entity stuff to undo")
		return
	var undo_delta:Array = undo_history.pop_back()[1]
	
	if cur_undo_stack.size()>0:
		undo_delta.append_array(cur_undo_stack)
		cur_undo_stack=[]
		
	print(("undoing entities - modified "+str(undo_delta.size()))

	for i in range(undo_delta.size()-1,-1,-1):
		var toundo = undo_delta[i]
		var before=toundo[0]
		var after=toundo[1]
		if after!=null:
			#deleting object
			print(("deleting entity at "+str(after.position))
			remove_entity_at(after.position,false)
		if before!=null:
			print(("adding entity at "+str(before.position))
			remove_entity_at(before.position,false)
			add_entity_from_dict(before,false)

func clear_undo_history():
	undo_history=[]
	cur_undo_stack=[]
	
func last_undo_time()->int:
	if undo_history.size()==0:
		return 0
	return undo_history[undo_history.size()-1][0]
	
func restore_from_data(data:Variant):
	clear_all();
	var new_entities = data
	for new_entity:Dictionary in new_entities:
		add_entity_from_dict(new_entity,false)
	
func save_to_data()->Variant:
	return entities
	
func clear_all():
	clear_undo_history()
	for i in range(entities.size()-1,-1,-1):
		entities.remove_at(i)
		if associated_objects[i]!=null:
			associated_objects[i].queue_free()
		associated_objects.remove_at(i)		
	associated_objects=[]	
	entities=[]
	
func remove_entity_at(pos:Vector3i,do_backup:bool=true):
	for i in range(entities.size()):
		if entities[i].position==pos:
			var entity_dict=entities[i]		
			if do_backup:	
				cur_undo_stack.push_back([entity_dict.duplicate(true),null])
			entities.remove_at(i)
			if associated_objects[i] != null:
				associated_objects[i].queue_free()
			associated_objects.remove_at(i)			
			return

func entity_at(pos:Vector3i):
	for i in range(entities.size()):
		if entities[i].position==pos:
			return entities[i]
	return null

func entity_idx_at(pos:Vector3i)->int:
	for i in range(entities.size()):
		if entities[i].position==pos:
			return i
	return -1
	
func occupied_by_entity(pos:Vector3i)->bool:
	for i in range(entities.size()):
		if entities[i].position==pos:
			return true
	return false

static func skeleton3d_aabb(skel:Skeleton3D)->AABB:	
	var bones = skel.get_bone_count()
	var result = AABB(skel.get_bone_pose_position(0),Vector3.ZERO)
	for i in range(1,bones):	
		var bone_vertex:Vector3 = skel.get_bone_pose_position(i)
		result = result.expand(bone_vertex)	
	return result
	
#from https://www.reddit.com/r/godot/comments/18bfn0n/how_to_calculate_node3d_bounding_box/
static func _calculate_spatial_bounds(parent : Node3D, exclude_top_level_transform: bool) -> AABB:
	var bounds : AABB = AABB()
	if parent is MeshInstance3D:
		bounds = parent.get_aabb()
	elif parent is Skeleton3D:
		bounds = skeleton3d_aabb(parent)

	for i in range(parent.get_child_count()):
		var child : Node = parent.get_child(i)
		if (child is Node3D) && child.visible:
			var child_bounds : AABB = _calculate_spatial_bounds(child, false)
			if bounds.size == Vector3.ZERO && parent:
				bounds = child_bounds
			else:
				bounds = bounds.merge(child_bounds)
	if bounds.size == Vector3.ZERO && !parent:
		bounds = AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))
	if !exclude_top_level_transform:
		bounds = parent.transform * bounds
	return bounds

func _delete_all_collisions(parent : Node):	
	#remove all collisions recursively
	for i in range(parent.get_child_count()):
		var child : Node = parent.get_child(i)
		if child is CollisionShape3D:
			child.queue_free()
		else:
			_delete_all_collisions(child)

func generate_water_box(entity_dict:Dictionary)->WireframeBox:
	var boxcol = entity_icon_materials[entity_dict.type].albedo_color
	#var center = entity_dict.position
	var upper_extents = entity_dict.size_WUN
	var lower_extents = entity_dict.size_EDS
	var bounds:AABB = AABB(Vector3(-0.5,0,-0.5)-Vector3(lower_extents),lower_extents+upper_extents+Vector3i.ONE)	
	var wireframe_box = WireframeBox.new(entity_dict.position-lower_extents,entity_dict,bounds,boxcol,false);
	
	return wireframe_box
	
func create_wireframe_preview(entity_dict:Dictionary)->WireframeBox:
	var boxcol : Color= entity_icon_materials[entity_dict.type].albedo_color
	var extents : Vector3 = Vector3.ONE
	if entity_dict.type==EditorUI.EntityType.ACTOR:
		extents.y=2
	var bounds : AABB = AABB(Vector3(-0.5,0,-0.5),extents)	
	var instantiated_asset_preview : Node3D
	
	var generate_model = ModeManager.editor_node.entitytype_has_assets(entity_dict.type) && entity_dict.has("asset_name")
	

		
	if generate_model:
		var asset = EditorUI.ENTITY_CACHE[entity_dict.type][entity_dict.asset_name]
		if asset!=null:
			instantiated_asset_preview = asset.instantiate()
			if instantiated_asset_preview.has_method("setup_asset"):
				instantiated_asset_preview.setup_asset(entity_dict)
				
				
			if entity_dict.has("animation"):
				var animation_player:AnimationPlayer = Glob.find_child_of_type(instantiated_asset_preview,AnimationPlayer)
				if animation_player==null:
					printerr("error, AnimationPlayer sought for ",entity_dict.name," but not found.")
				else:
					animation_player.play(entity_dict.animation)
					
			_delete_all_collisions(instantiated_asset_preview)
			instantiated_asset_preview.transform.origin=Vector3(entity_dict.position)-Vector3(0,0.5,0)	
			bounds = _calculate_spatial_bounds(instantiated_asset_preview,true)
	elif entity_dict.type==EditorUI.EntityType.WATER || entity_dict.type==EditorUI.EntityType.TRIGGER:
		instantiated_asset_preview=generate_water_box(entity_dict)
		generate_model=true
			
	var wireframe_box = WireframeBox.new(entity_dict.position,entity_dict,bounds,boxcol,true);

	#set rotation of box
	if entity_dict.has("dir"):
		wireframe_box.rotation.y = -entity_dict.dir*PI/2

	wireframe_box.transform.origin=Vector3(entity_dict.position)-Vector3(0,0.5,0)
	
	if generate_model && instantiated_asset_preview!=null:
		wireframe_box.add_child(instantiated_asset_preview)
		instantiated_asset_preview.transform.origin=Vector3(0,0,0)
	else:
		var icon:MeshInstance3D = entity_billboarded_icon.instantiate()
		icon.material_override = entity_icon_materials[entity_dict.type]
		icon.transform.origin=Vector3.ZERO+Vector3(0,extents.y/2.0,0)
		wireframe_box.add_child(icon)
	
	return wireframe_box
		
func add_entity_from_dict(entity_dict:Dictionary,do_backup:bool=true):
	#if entity doesn't have a name, but has an asset_name, set the name to the asset_name
	if !entity_dict.has("name") && entity_dict.has("asset_name"):
		entity_dict.name=entity_dict.asset_name
		
	#if the entity is a trigger, and has no meta, add it and set it equal to the name
	if entity_dict.type==EditorUI.EntityType.TRIGGER && !entity_dict.has("meta"):
		entity_dict.meta=entity_dict.name
	if entity_dict.type==EditorUI.EntityType.OBJECT && !entity_dict.has("meta"):
		entity_dict.meta=entity_dict.name
		
	var wireframe_box:WireframeBox = null
	
	if ModeManager.mode == ModeManager.MODE_EDITOR:
		wireframe_box = create_wireframe_preview(entity_dict)
		%Editormode_Entities.add_child(wireframe_box,true)

	entities.push_back(entity_dict)
	associated_objects.push_back(wireframe_box)
	
	if do_backup:
		cur_undo_stack.push_back([null,entity_dict.duplicate(true)])
	
#suggests a name for the object - cannot already be used (e.g. "table" -> "table1")
func pickname(type:int)->String:
	var type_str = EditorUI.EntityType.keys()[type]
	var i=1
	#find the first empty slot
	var found_higher:bool=true
	while found_higher:
		found_higher=false
		for entity in entities:
			if entity.name==type_str+str(i):
				i+=1
				found_higher=true
				break
	return type_str+str(i)

func find_object_with_name(o_name:String)->Variant:
	for entity in entities:
		if entity.name==o_name:
			return entity
	return null
	
func add_water(_position:Vector3i,side:int,radii:Vector3i):
	var offset_dir : Vector3i = Vector3(Glob.dirOffsets[side])
	var side_offset : Vector3i =  (offset_dir*(radii-Vector3i.ONE))
	var dict = {
		type=EditorUI.EntityType.WATER,
		name=pickname(EditorUI.EntityType.WATER),
		position=_position,
		size_WUN=radii-Vector3i(1,1,1)+side_offset,
		size_EDS=radii-Vector3i(1,1,1)-side_offset,
	}
	add_entity_from_dict(dict)

func add_trigger(_position:Vector3i,side:int,radii:Vector3i):
	var offset_dir : Vector3i = Vector3(Glob.dirOffsets[side])
	var side_offset : Vector3i =  (offset_dir*(radii-Vector3i.ONE))
	var dict = {
		type=EditorUI.EntityType.TRIGGER,
		name=pickname(EditorUI.EntityType.TRIGGER),
		position=_position,
		size_WUN=radii-Vector3i(1,1,1)+side_offset,
		size_EDS=radii-Vector3i(1,1,1)-side_offset,
		meta=""
	}
	add_entity_from_dict(dict)
	

func add_object(_position:Vector3i,_dir:int,_asset_name:String):
	var dict = {
		type=EditorUI.EntityType.OBJECT,
		name=pickname(EditorUI.EntityType.OBJECT),
		position=_position,
		dir=_dir,
		asset_name=_asset_name,
	}
	#we need to check the 
	add_entity_from_dict(dict)
	
func add_actor(_position:Vector3i,_dir:int,_asset_name:String):
	var dict = {
		type=EditorUI.EntityType.ACTOR,
		name=pickname(EditorUI.EntityType.ACTOR),
		position=_position,
		dir=_dir,
		asset_name=_asset_name,
		animation="Stand"
	}
	add_entity_from_dict(dict)
	
func add_rope(_position:Vector3i,_dir:int,_asset_name:String,_length:int):
	var dict = {
		type=EditorUI.EntityType.ROPE,
		name=pickname(EditorUI.EntityType.ROPE),
		position=_position,
		dir=_dir,
		asset_name=_asset_name,
		length=_length
	}
	add_entity_from_dict(dict)
	
func add_entity(_position:Vector3i,_dir:int,type:EditorUI.EntityType):

	var dict = {
		type=type,
		name=pickname(type),
		asset_name="22 table",
		position=_position,
		dir=_dir
	}
	
	add_entity_from_dict(dict)

func has_entity_of_name(_name:String)->bool:
	for entity in entities:
		if entity.name==_name:
			return true
	return false
	
func find_entity_by_name(_name:String):
	for entity in entities:
		if entity.name==_name:
			return entity
	return null

func find_node3d_by_name(_name:String):
	for i in range(associated_objects.size()):
		if entities[i].name==_name:
			return associated_objects[i]
	return null

func delete_all_entities():
	for child in $Editormode_Entities.get_children():
		child.queue_free()
	for child in $Gamemode_Entities.get_children():
		child.queue_free()
		
func spawn_playmode_entities():
	
	ModeManager.editor_node.pause_menu.area_name_label.text=""
	$Editormode_Entities.visible=false
	for child in $Editormode_Entities.get_children():
		child.queue_free()
		
	for entity : Dictionary in entities:
		if ModeManager.editor_node.entitytype_has_assets(entity.type):		
			#var entity_type_name = EditorUI.EntityType.keys()[entity.type]
			var asset = EditorUI.ENTITY_CACHE[entity.type][entity.asset_name]
			var instantiated : Node3D = asset.instantiate()
			if instantiated.has_method("setup_asset"):
				instantiated.setup_asset(entity)
			
			if entity.has("animation"):
				var animation_player:AnimationPlayer = Glob.find_child_of_type(instantiated,AnimationPlayer)
				if animation_player==null:
					printerr("error, AnimationPlayer sought for ",entity.name," but not found.")
				else:
					animation_player.play(entity.animation)
					
			
			$Gamemode_Entities.add_child(instantiated)			
			instantiated.rotation.y = -entity.dir*PI/2
			instantiated.global_transform.origin=Vector3(entity.position)-Vector3(0,0.5,0)
			
		elif entity.type==EditorUI.EntityType.WATER:
			var epath = "res://VoxelWorld/Models/WATER/WaterVolume.tscn"
			var asset = load(epath)
			var instantiated : Node3D = asset.instantiate()
			if instantiated.has_method("setup_asset"):
				instantiated.setup_asset(entity)
			$Gamemode_Entities.add_child(instantiated)
			instantiated.global_transform.origin=Vector3(entity.position)-Vector3(0,0.5,0)

		elif entity.type==EditorUI.EntityType.TRIGGER:
			var epath = "res://VoxelWorld/Models/TRIGGER/TriggerVolume.tscn"
			var asset = load(epath)
			var instantiated : Node3D = asset.instantiate()
			if instantiated.has_method("setup_asset"):
				instantiated.setup_asset(entity)
			$Gamemode_Entities.add_child(instantiated)
			instantiated.global_transform.origin=Vector3(entity.position)-Vector3(0,0.5,0)			
			
func property_changed(entity_idx:int,key:String,value)->bool:
	var dict:Dictionary = entities[entity_idx]
	var old_dict = dict.duplicate(true)
	if old_dict[key]==value:
		return true
		
	match key:
		"position":
			var v:Vector3i=value
			if (%EntityManager.occupied_by_entity(v)||%VoxelWorld.occupied_by_voxel(v)):
				print(("invalid position")
				return false
		"name":
			var proposed_name=value
			if find_object_with_name(proposed_name)!=null:
				print(("name already in use")
				return false
	
	dict[key]=value
	if associated_objects[entity_idx] != null:
		associated_objects[entity_idx].queue_free()

	draw_selected_box(entity_idx)
	
	cur_undo_stack.push_back([old_dict,dict.duplicate(true)])
	commit_backup()
	return true
	
func draw_selected_box(entity_idx:int):
	var dict:Dictionary = entities[entity_idx]

	var new_wireframe:WireframeBox = create_wireframe_preview(dict)
	associated_objects[entity_idx]=new_wireframe
	%Editormode_Entities.add_child(new_wireframe,true)
	var bb= new_wireframe.bb
	var global_bb = AABB(new_wireframe.bb.position+Vector3(new_wireframe.pos)+new_wireframe.bb.size/2-Vector3.UP/2,new_wireframe.bb.size)
	if new_wireframe.dict.has("dir"):
		%GizmoManager.draw_entity_selection_free_cube_with_dir(global_bb,new_wireframe.dict.position,new_wireframe.dict.dir)
	else:
		%GizmoManager.draw_entity_selection_free_cube(global_bb,new_wireframe.dict.position)

	return null

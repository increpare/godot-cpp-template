class_name DialogueBox extends Control

@export var target:Node3D
const margin:float=0.9
const pixelmargin:float=20
var last_point:Vector2 = Vector2.INF

func get_top_point()->Vector3:
	#look in children for staticbody
	var skeleton : Skeleton3D = Glob.find_child_of_type(target,Skeleton3D)
	if skeleton==null:
		return Vector3.ZERO
		
	var head_idx:int = skeleton.find_bone("Head")
	var head_transform_local:Transform3D = skeleton.get_bone_global_pose(head_idx)	
	var head_position_global:Vector3 = skeleton.to_global(head_transform_local.origin)
	
	return head_position_global

func _physics_process(delta: float) -> void:
	#get target's position in screen-space
	var character_pos : Vector3 = target.global_transform.origin
	var camera_pos : Vector3 = get_top_point() + Vector3.UP*margin
	var edges :PackedVector3Array = [ 
		camera_pos + Vector3.LEFT/5 ,
		camera_pos - Vector3.LEFT/5 ,
		camera_pos + Vector3.FORWARD/5,
		camera_pos - Vector3.FORWARD/5,		
		]
		

	var edge_positions_screenspace :PackedVector2Array= []
	for edge_pos:Vector3 in edges:
		edge_positions_screenspace.push_back(get_viewport().get_camera_3d().unproject_position(edge_pos))
	var highest_y_coord : float = 10000
	for coord:Vector2 in edge_positions_screenspace:
		highest_y_coord = min(coord.y,highest_y_coord)
	
	var target_position:Vector2 = get_viewport().get_camera_3d().unproject_position(camera_pos)
	target_position.y=highest_y_coord-pixelmargin
	
	if last_point==Vector2.INF:
		last_point=target_position
	
	#last_point.x = PlayerController.lazydamp(last_point.x,target_position.x,20,0.1,delta)
	#last_point.y = PlayerController.lazydamp(last_point.y,target_position.y,20,0.1,delta)
		
	#set the position of the dialogue box to the target's position
	set_position(last_point)

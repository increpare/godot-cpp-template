class_name Rope extends Node3D

@export var armature:Skeleton3D

var rope_top_local:Vector3
var rope_bottom_local:Vector3
var dict:Dictionary

func setup_asset(_dict:Dictionary):
	dict=_dict
	
	var bottom_bone_index = armature.find_bone("rope_bottom")
	
	var rope_bottom_pos:Vector3=armature.get_bone_pose_position(bottom_bone_index)
	rope_bottom_pos.y = rope_bottom_pos.y - (dict.length-1)
	armature.set_bone_pose_position(bottom_bone_index,rope_bottom_pos)
	
	var trigger_cube_shape : BoxShape3D = %CollisionShape3D.shape.duplicate()

	var centre:Vector3 = %CollisionShape3D.position
	
	#DebugDraw3D.draw_sphere(centre,0.2,Color.CHARTREUSE,100000)
	var collision_box_size:Vector3 = trigger_cube_shape.size
	var top:Vector3 = centre+Vector3.UP*collision_box_size.y/2
	#DebugDraw3D.draw_sphere(top,0.2,Color.YELLOW,100000)
	
	var height_margin:float = collision_box_size.y-1
	
	var desired_height:float = height_margin+dict.length
	
	var new_center:Vector3 = top+(desired_height/2)*Vector3.DOWN
		
		
	collision_box_size.y=desired_height
	trigger_cube_shape.size=collision_box_size
	
	rope_top_local = top
	rope_bottom_local = top+Vector3.DOWN*collision_box_size.y
	
	%CollisionShape3D.position = new_center
	%CollisionShape3D.shape = trigger_cube_shape

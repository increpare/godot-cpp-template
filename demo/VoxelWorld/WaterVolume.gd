class_name WaterVolume extends Node3D

var dict:Dictionary
func setup_asset(_dict:Dictionary):
	self.dict=_dict
	var extent_lower:Vector3i = dict.size_EDS	
	var extent_upper:Vector3i = dict.size_WUN	
	var water_size:Vector3i=extent_lower+extent_upper+Vector3i.ONE
	self.scale = water_size
	var mesh:PlaneMesh = %MeshInstance3D.mesh.duplicate()
	mesh.subdivide_width=water_size.x*2-1
	mesh.subdivide_depth=water_size.z*2-1
	mesh.center_offset*=self.scale.y
	%MeshInstance3D.mesh=mesh
	%OffsetNode.position = Vector3(extent_upper-extent_lower)/Vector3(2*water_size)+Vector3.UP/(2.0*self.scale)
	%MeshInstance3D.scale.y=1/self.scale.y


func _on_area_3d_body_entered(body: Node3D) -> void:
	body.on_enter_water()

func _on_area_3d_body_exited(body: Node3D) -> void:
	body.on_exit_water()

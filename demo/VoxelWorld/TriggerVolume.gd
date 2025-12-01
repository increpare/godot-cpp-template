class_name TriggerVolume extends Node3D

var dict:Dictionary
func setup_asset(_dict:Dictionary):
	self.dict=_dict
	var extent_lower:Vector3i = dict.size_EDS	
	var extent_upper:Vector3i = dict.size_WUN	
	var water_size:Vector3i=extent_lower+extent_upper+Vector3i.ONE
	self.scale = water_size
	%OffsetNode.position = Vector3(extent_upper-extent_lower)/Vector3(2*water_size)+Vector3.UP/(2.0*self.scale)


func _on_area_3d_body_entered(body: Node3D) -> void:
	body.on_enter_trigger(dict.name,dict.meta)

func _on_area_3d_body_exited(body: Node3D) -> void:
	body.on_exit_trigger(dict.name,dict.meta)

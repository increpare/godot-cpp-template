extends Node

#canonical directions
const S:int = 0
const N:int = 1 #Z
const W:int = 2 #X
const E:int = 3
const U:int = 4 #Y
const D:int = 5
# C -1 (need to be careful about center!)

#aliases for above
const Z:int = 1 #N
const X:int = 2 #W
const Y:int = 4 #U

static var DEMO_VERSION:bool = OS.has_feature("demo_version")

func hill_height(max_radius:float,max_height:float,sample_radius:float)->float:
	if sample_radius<=-max_radius || sample_radius>=max_radius:
		return 0
	var cosval = cos(PI*sample_radius/max_radius)
	return max_height*(cosval+1)/2 #normalises height

const axis_index_to_dir:Array[int] = [
	2,#X Right West
	5,#Y Up Top
	1,#Z Back North
]

const plane_index_to_dir:Array[Array] = [
	[5,1],#YZ Up North
	[1,2],#ZX Back Right 
	[2,5],#XY Right Up
]

const oppositeDir:Array[int] = [	
	1, 	#S
	0,	#N	
	3,	#W
	2,	#E
	5,	#U
	4	#D
]

const vflipDir:Array = [
	0, 	#S
	1,	#N	
	2,	#W
	3,	#E
	5,	#U
	4	#D	
]

#rotates clockwise
func do_flip(d:int,times:int)->int:
	if times%2==0:
		return d
	return vflipDir[d]
	
const rotDir:Array[int] = [
	2, 	#S->W
	3,	#N->E
	1,	#W->N
	0,	#E->S
	4,	#U->U
	5	#D->D
]

#rotates clockwise
func rot_dir(d:int,rot:int)->int:
	for i in range(rot):
		d = rotDir[d]
	return d	

	
func vtrace(v:Vector3i)->int:
	return v.x+v.y+v.z
	
const dirOffsets:Array[Vector3i] =[
	Vector3i(0,0,-1), 	#S
	Vector3i(0,0,1),	#N	
	Vector3i(1,0,0),	#W
	Vector3i(-1,0,0),	#E
	Vector3i(0,1,0),	#U
	Vector3i(0,-1,0),	#D
]	

const cube_vertices : Array[Vector3i] = [
	Vector3(-1, -1, -1), Vector3(1, -1, -1),
	Vector3(1, 1, -1), Vector3(-1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1),
	Vector3(1, 1, 1), Vector3(-1, 1, 1) 
]

const cube_faces = [
	[0, 1, 2, 0, 2, 3], # Front
	[5, 4, 7, 5, 7, 6], # Back
	[1, 5, 6, 1, 6, 2], # Right
	[4, 0, 3, 4, 3, 7], # Left
	[3, 2, 6, 3, 6, 7], # Top
	[4, 5, 1, 4, 1, 0]  # Bottom
]

func normal_du(dir:int) -> Vector3i:
	var a:Vector3i = cube_vertices[cube_faces[dir][0]]
	var b:Vector3i = cube_vertices[cube_faces[dir][1]]
	return (b-a)/2
	
func normal_dv(dir:int) -> Vector3i:
	var a:Vector3i = cube_vertices[cube_faces[dir][0]]
	var b:Vector3i = cube_vertices[cube_faces[dir][5]]
	return (b-a)/2

func vector3i_cross(a:Vector3i,b:Vector3i)->Vector3i:
	return  Vector3i(
		(a.y * b.z) - (a.z * b.y),
		(a.z * b.x) - (a.x * b.z),
		(a.x * b.y) - (a.y * b.x)) 

func get_corner_dir(face_side:int,edge_side:int)->int:
	return get_ortho(face_side,edge_side)
	
func get_ortho(d1:int,d2:int)->int:
	var v1:Vector3i = dirOffsets[d1]
	var v2:Vector3i = dirOffsets[d2]
	var o = vector3i_cross(v1,v2)
	return vector3i_to_dir(o)
	
func vector3i_to_dir(v:Vector3i)->int:
	for i in range(dirOffsets.size()):
		if dirOffsets[i]==v:
			return i
	return -1
	
func project(v:Vector3,dir:int)->Vector2:
	var du : Vector3 = normal_du(dir)
	var dv : Vector3 = normal_dv(dir)
	var x : float = v.dot(du)
	var y : float = v.dot(dv)
	return Vector2(x,y)

func getSelectedEdge(voxel:Vector3, side:int, target:Vector3)->int:#returns global dir
	# we calculate the locations of five relevant points, and return a value 
	# based on which point target is closest to.
	
	var dirOffset: Vector3  = Vector3(dirOffsets[side])/2
	var center = voxel+dirOffset
	var du:Vector3 = Vector3(normal_du(side))/2
	var dv:Vector3 = Vector3(normal_dv(side))/2
	var p_u:Vector3 = center+du
	var p_mu:Vector3 = center-du
	var p_v:Vector3 = center+dv
	var p_mv:Vector3 = center-dv
	var points:PackedVector3Array=[center,p_u,p_mu,p_v,p_mv]
	
		
	var closest_index: int = 0
	var min_distance: float = target.distance_squared_to(points[0])  # Start with first point
	for i in range(1, points.size()):  # Start from second element
		var dist = target.distance_squared_to(points[i])
		if dist < min_distance:
			min_distance = dist
			closest_index = i
		
		
	match closest_index:
		0:
			return -1
		1: 
			return  vector3i_to_dir(normal_du(side))
		2: 
			return  vector3i_to_dir(-normal_du(side))
		3: 
			return  vector3i_to_dir(normal_dv(side))
		4: 
			return  vector3i_to_dir(-normal_dv(side))
		
	printerr("OH DEAR HOW HAVE WE GOTTEN TO",closest_index)
	return -1

func idot(a:Vector3i,b:Vector3i)->int:
	return a.x*b.x+a.y*b.y+a.z*b.z
	
#indent a multi-line string
func indent(s:String):
	var s_lines:PackedStringArray = s.split("\n")
	var indented = ""
	for line in s_lines:
		indented+="\t"+line+"\n"
	return indented

func find_child_of_type(parent, type)->Node:
	return find_child_of_type_rec(parent, type)

func find_child_of_type_rec(node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for oneChild in node.get_children():
		var possibility = find_child_of_type_rec(oneChild, type)
		if possibility!=null:
			return possibility
	return null


func is_ltr()->bool:
	var locale:String = TranslationServer.get_locale().to_lower()
	return !locale.begins_with("ar") and !locale.begins_with("fa")

func is_ui_left_pressed()->bool:
	if is_ltr():
		return Input.is_action_just_pressed("ui_left")
	else:
		return Input.is_action_just_pressed("ui_right")

func is_ui_right_pressed()->bool:
	if is_ltr():
		return Input.is_action_just_pressed("ui_right")
	else:
		return Input.is_action_just_pressed("ui_left")

var macOS:bool = OS.get_name()=="macOS"

func rumble_explode():	
	var rumble_enabled = SettingsManager.get_value("RUMBLE") == 1
	if !rumble_enabled:
		return
	if  InputHelper.device != InputHelper.DEVICE_KEYBOARD && InputHelper.device_index>=0:
		Input.start_joy_vibration(InputHelper.device_index, 0, 1, 0.3)

func rumble_thunder():
	var rumble_enabled = SettingsManager.get_value("RUMBLE") == 1
	if !rumble_enabled:
		return
	if  InputHelper.device != InputHelper.DEVICE_KEYBOARD && InputHelper.device_index>=0:
		#rumble at full intensity for two seconds, then tween to 0 intensity over 1 second
		var tween = get_tree().create_tween()
		tween.tween_method(_thunder_rumble_tween,0.0,2.0,2.0)
		#at the end, force rumble to 0
		tween.tween_callback(func(): 
			Input.stop_joy_vibration(InputHelper.device_index)
			print("rumble stopped")
			)

func _thunder_rumble_tween(value:float):
	if value<1.0:
		Input.start_joy_vibration(InputHelper.device_index, 0, 1, 0.1)
	else:
		#tween from 1 to 0 over one second
		var strength = 1.0 - (value-1.0)
		Input.start_joy_vibration(InputHelper.device_index, 0, strength/2, 0.1)

func rumble_little():
	var rumble_enabled = SettingsManager.get_value("RUMBLE") == 1
	if !rumble_enabled:
		return
	if  InputHelper.device != InputHelper.DEVICE_KEYBOARD && InputHelper.device_index>=0:
		InputHelper.rumble_medium(InputHelper.device_index)

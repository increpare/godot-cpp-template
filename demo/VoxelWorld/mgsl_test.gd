extends Node3D

var mgsl:MGSL
var current_page:int=0

var edges_labels:Dictionary[Array,MGSLEdgeLabel]

func create_all_edges():	
	var children =	%Edges.get_children()
	for child in children:
		child.queue_free()
		
	edges_labels={}

	#step 1, check location nodes are same as those in MGSL
	var locations:Array[String] = mgsl.mgsl.ENUMS.Location
	var locs = %Locations
	var location_nodes:Array[Node]=locs.get_children()
	if locations.size()!=location_nodes.size():
		printerr("LOCATIONS NODES WRONG SIZE ",locations.size(), " vs ", location_nodes.size())
	for i in range(locations.size()):
		if location_nodes[i].name!=locations[i]:
			printerr("LOCATIONS NODES WRONG. FOUND NODE ",location_nodes[i].name, " but was expecting ", locations[i])
	
	#for every pair of locations in the MGSL, create an edge (visibility will be tackled elsewhere)
	for from_s : String in locations:
		for to_s : String in locations:
			if from_s>=to_s:
				continue
			var from : MGSL.LocationRef = mgsl.mgsl.location(from_s)
			var to : MGSL.LocationRef = mgsl.mgsl.location(to_s)
			var from_node : MGSLNode = %Locations.find_child(from.name)
			var to_node : MGSLNode = %Locations.find_child(to.name)
			var from_pos : Vector2 = from_node.global_position
			var to_pos : Vector2 = to_node.global_position
			
			var edge_label : MGSLEdgeLabel = preload("res://VoxelWorld/Editor/Scenes/MGSLEdgeLabel.tscn").instantiate()		
			%Edges.add_child(edge_label)
			edge_label.global_position = (from_pos+to_pos)/2
			var diff = to_pos-from_pos
			var angle:float = diff.angle() 
			var flip : bool = abs(angle)>=PI/2.0
			
			if flip:
				var t:MGSL.LocationRef = from
				from = to
				to = t
				angle+=PI
			
			edge_label.rotation = angle 

			edges_labels[[from.name,to.name]]=edge_label
		
func update_edge_label_labels():
	for key in edges_labels:
		var from : MGSL.LocationRef = mgsl.mgsl.location(key[0])
		var to : MGSL.LocationRef = mgsl.mgsl.location(key[1])		
		var edge_label : MGSLEdgeLabel = edges_labels[key]		
		edge_label.set_contents(mgsl.get_connections_bidi(from,to),from,to)


func get_occupancy(state_dat:MGSL.StateDat,loc:MGSL.LocationRef)->Array[int]:
	var occupancy : Array = state_dat.location_occupancy[loc.name]
	var occupancy_ints : Array[int] = []
	for chr_s in state_dat.ENUMS.Characters:
		var chr : MGSL.CharacterRef = state_dat.character(chr_s)
		var chr_hometown : MGSL.LocationRef = state_dat.CHARACTERS[chr.name].Location
		var locked : bool = !MGSL.array_has(state_dat.unlocked_characters,chr)
		if !MGSL.array_has(occupancy,chr):
			occupancy_ints.append(0)
		else:
			if locked:
				occupancy_ints.append(1)
			elif chr_hometown.equals(loc):
				occupancy_ints.append(3)		
			else:
				occupancy_ints.append(2)	
	return occupancy_ints	
			

func update_ui():	
	mgsl.mgsl = mgsl.playthrough[current_page]
	
	var remaining_quests : Array[MGSL.QuestDat] = mgsl.mgsl.QUESTS
	var command_text=""
	for cmd : MGSL.QuestDat in remaining_quests:
		var line_no=cmd.line_number
		if command_text!="":
			command_text+="\n"
		command_text+=mgsl.lines[line_no]
	%Console_Header.text="OUTSTANDING QUESTS ("+str(remaining_quests.size())+")"
	%Console.text=command_text
		
	var connections : Array[MGSL.ConnectionDat] = mgsl.mgsl.CONNECTIONS
	for connection : MGSL.ConnectionDat in connections:
		var from = connection.from
		var to = connection.to
		var from_node : MGSLNode = %Locations.find_child(from.name)
		var to_node : MGSLNode = %Locations.find_child(to.name)
		var from_pos : Vector2 = from_node.global_position
		var to_pos : Vector2 = to_node.global_position
		var from_pos_3D : Vector3 = %Camera.project_position(from_pos,10.0)
		var to_pos_3D : Vector3 = %Camera.project_position(to_pos,10.0)
		#DebugDraw3D.draw_line(from_pos_3D,to_pos_3D,Color.GRAY)
		
	#step 1, check location nodes are same as those in MGSL
	var locations:Array[String] = mgsl.mgsl.ENUMS.Location
	var locs = %Locations
	var location_nodes:Array[Node]=locs.get_children()
	if locations.size()!=location_nodes.size():
		printerr("LOCATIONS NODES WRONG SIZE ",locations.size(), " vs ", location_nodes.size())
	for i in range(locations.size()):
		if location_nodes[i].name!=locations[i]:
			printerr("LOCATIONS NODES WRONG. FOUND NODE ",location_nodes[i].name, " but was expecting ", locations[i])	
	
	var previous_frame:MGSL.StateDat = mgsl.playthrough[max(current_page-1,0)]
	#for each location, get the occupancy as a boolean array and call set_occupancy
	for location in locations:
		var location_ref:MGSL.LocationRef = mgsl.mgsl.location(location)
		var actions_here:Array[MGSL.QuestDat]=[]
		for action:MGSL.QuestDat in mgsl.mgsl.actions_this_turn:
			if action.location.equals(location_ref):
				actions_here.push_back(action)
		#0 not present, 1 locked, 2 unlocked, 3 domain
		var occupancy_ints : Array[int] = get_occupancy(mgsl.mgsl,location_ref)
		var node : MGSLNode = %Locations.find_child(location)
		
		var old_frame_occupancy_ints : Array[int] = get_occupancy(previous_frame,location_ref)
		
		var newness:Array[bool]=[]
		for i in range(old_frame_occupancy_ints.size()):
			var changed:bool = old_frame_occupancy_ints[i]!=occupancy_ints[i]
			newness.push_back(changed)
		
		node.set_occupancy(occupancy_ints,newness,actions_here)
		
	update_edge_label_labels()			
	
	var simulation_pages = mgsl.playthrough.size()
	%LabelPage.text= str(current_page+1)+"/"+str(simulation_pages)
	
	
	
func _ready():
	var path = "res://Resources/MGSL/outline.txt"
	if FileAccess.file_exists(path)==false:
		return
		
	var file = FileAccess.open(path,FileAccess.READ)
	var filedat_str = file.get_as_text()
	self.mgsl = MGSL.new(filedat_str)
	
	mgsl.mgsl.character_domains = mgsl.build_domain_dictionary()
	mgsl.mgsl.location_occupancy = mgsl.build_location_occupancy()

	create_all_edges()
	update_ui()

func _process(_delta:float):		
	#now to draw connections
	var connections : Array[MGSL.ConnectionDat] = mgsl.mgsl.CONNECTIONS
	for connection : MGSL.ConnectionDat in connections:
		var from : MGSL.LocationRef = connection.from
		var to : MGSL.LocationRef = connection.to
		var from_node : MGSLNode = %Locations.find_child(from.name)
		var to_node : MGSLNode = %Locations.find_child(to.name)
		var from_pos : Vector2 = from_node.global_position
		var to_pos : Vector2 = to_node.global_position
		var from_pos_3D : Vector3 = %Camera.project_position(from_pos,10.0)
		var to_pos_3D : Vector3 = %Camera.project_position(to_pos,10.0)
		#DebugDraw3D.draw_line(from_pos_3D,to_pos_3D,Color.GRAY)


func _on_pressed(dir: int) -> void:
	match dir:
		-2:	current_page=0
		-1:	current_page = max(current_page-1,0)
		1:	current_page = min(current_page+1,mgsl.playthrough.size()-1)
		2: current_page=  mgsl.playthrough.size()-1
	update_ui()
	get_viewport().gui_release_focus()

class_name PrioryMaster extends Node3D

var level_name:String
var script_library:Dictionary[String,PrioryScript]

func _init():
	load_levels("stairs_test")

func load_levels(_level_name:String):
	print("loading levels")
	var path = "res://Resources/MGSL/outline.txt"
	if FileAccess.file_exists(path)==false:
		printerr("MGSL FILE NOT FOUND")
		return
		
	var msg_file = FileAccess.open(path,FileAccess.READ)
	var mgs_filedat_str = msg_file.get_as_text()
	var mgsl:MGSL=MGSL.new(mgs_filedat_str)
	
	self.level_name = _level_name
	var root_path : String = "res://Resources/Scripts/"+level_name+"/"
	print("looking at path ",root_path)
	var dir := DirAccess.open(root_path)
	if dir == null: printerr("Could not open folder"); return
	dir.list_dir_begin()
	for file_name : String in dir.get_files():
		print("reading level "+file_name)
		var file_path : String = root_path+file_name
		var base_name : String = file_name.get_basename()
		var file = FileAccess.open(file_path,FileAccess.READ)
		var filedat_str = file.get_as_text()
		
		var priory_script : PrioryScript = PrioryScript.new(filedat_str,mgsl.mgsl)
		
		script_library[base_name]=priory_script

		
		
		


	

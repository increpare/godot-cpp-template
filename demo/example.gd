extends Node


func _ready() -> void:
	var example := ExampleClass.new()
	var i:int = 3
	example.print_type(example)
	example.print_type(i)
	
	var arr:Array[Vector3i] = [ Vector3i(1,1,1), Vector3i(1,2,3), Vector3i(4,5,6) ]
	example.print_array(arr)
	var packed_array:PackedByteArray = example.serialize_array(arr)
	print(packed_array)
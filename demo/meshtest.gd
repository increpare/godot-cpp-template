extends MeshInstance3D

func _ready() -> void:
	var serializer:OeufSerializer = OeufSerializer.new()
	self.mesh = serializer.create_cube_mesh()

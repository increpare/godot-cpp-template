extends Node

var database = []

var TEX_TILEMAP:Texture2D = load("res://VoxelWorld/Textures/tilemap.png")
var TEX_WIDTH:float = TEX_TILEMAP.get_width()
var TEX_HEIGHT:float = TEX_TILEMAP.get_height()
const TILE_W:float=16
const TILE_H:float=16
var TILE_W_LOCAL : float = TILE_W/TEX_WIDTH
var TILE_H_LOCAL : float = TILE_H/TEX_HEIGHT

var du : Vector2 = Vector2(TILE_W_LOCAL,0)
var dv : Vector2 = Vector2(0,TILE_H_LOCAL)

const SHALLOW_THICKNESS:float = 0.5

const FACE_UV_COLGROUP_SIZE:int=3

enum DirEnum{
	N=0,
	S=1,
	E=2,
	W=3,
	U=4,
	D=5
}

#subdivisions into four parts
var du1 : Vector2 = du*1.0/4.0
var du2 : Vector2 = du*2.0/4.0
var du3 : Vector2 = du*3.0/4.0

var dv1 : Vector2 = dv*1.0/4.0
var dv2 : Vector2 = dv*2.0/4.0
var dv3 : Vector2 = dv*3.0/4.0

const N:Vector3 = Vector3(0,0,1)/2
const S:Vector3 = Vector3(0,0,-1)/2
const E:Vector3 = Vector3(-1,0,0)/2
const W:Vector3 = Vector3(1,0,0)/2
const U:Vector3 = Vector3(0,1,0)/2
const D:Vector3 = Vector3(0,-1,0)/2

#dividing DU up into four pieces
const U1 = D + (U-D)*1.0/4.0
const U2 = D + (U-D)*2.0/4.0
const U3 = D + (U-D)*3.0/4.0

#dividing SN up into four pieces
const N1 = S + (N-S)*1.0/4.0
const N2 = S + (N-S)*2.0/4.0
const N3 = S + (N-S)*3.0/4.0

#dividing we up into four pieces
const E1 = W + (E-W)*1.0/4.0
const E2 = W + (E-W)*2.0/4.0
const E3 = W + (E-W)*3.0/4.0



var cube_dat = {
	vertices =
		[
			D+E+S,
			D+W+S,
			U+W+S,
			U+E+S,
			D+E+N,
			D+W+N,
			U+W+N,
			U+E+N
		],
	faces =
		[
			[0, 1, 2, 0, 2, 3], # Front
			[5, 4, 7, 5, 7, 6], # Back
			[1, 5, 6, 1, 6, 2], # Right
			[4, 0, 3, 4, 3, 7], # Left
			[3, 2, 6, 3, 6, 7], # Top
			[4, 5, 1, 4, 1, 0]  # Bottom
		],
		uvs =
		[
			"square",
			"square",
			"square",
			"square",
			"square",
			"square"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			true, 	#S
			true,	#N
			true,	#W
			true,	#E
			true,	#U
			true,	#D
		]
}


var ramp_dat = {
	vertices =
		[
			D+W+S,
			D+E+S,
			D+W+N,
			D+E+N,
			U+W+N,
			U+E+N
		],
	faces =
		[
			[0, 4, 5, 0, 5, 1], # Front
			[2, 3, 5, 2, 5, 4], # Back
			[0, 2, 4], # Right
			[5, 3, 1], # Left
			[], # Top
			[0, 1, 3, 0, 3, 2]  # Bottom
		],
	uvs =
		[
			"square_wedgeflip",
			"square",
			"dtriangle_wedge",
			"dtriangle_wedge_f",
			"",
			"square"
		],
	face_tile_voffset =
		[
			0, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			true,	#N
			true,	#W
			true,	#E
			true,	#U
			true,	#D
		]
}


var clipped_edge_dat = {
	vertices =
		[
			D+E+S,
			D+W+N,
			D+E+N,
			U+E+S,
			U+W+N,
			U+E+N
		],
	faces =
		[
			[0, 1, 4, 0, 4, 3], # Front
			[1, 2, 5, 1, 5, 4], # Back
			[], # Right
			[2, 0, 3, 2, 3, 5], # Left
			[4,5,3], # Top
			[0,2,1]  # Bottom
		],
	uvs =
		[
			"square",
			"square",
			"",
			"square",
			"triangle",
			"triangle"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			true,	#N
			true,	#W
			true,	#E
			true,	#U
			true,	#D
		]
}

var clipped_ramp_dat = {
	vertices =
		[
			D+E+S,
			D+W+N,
			D+E+N,
			U+E+N
		],
	faces =
		[
			[], # Front
			[1,2,3], # Back
			[], # Right
			[3,2,0], # Left
			[1,3,0], # Top
			[0,2,1]  # Bottom
		],
	uvs =
		[
			"",
			"dtriangle_corner",
			"",
			"dtriangle_corner_f",
			"triangle_corner_top",
			"triangle"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			true,	#N
			true,	#W
			true,	#E
			false,	#U
			true,	#D
		]
}


var clipped_corner_dat = {
	vertices =
		[
			D+W+S,
			D+E+S,
			D+E+N,
			D+W+N,
			U+E+S,
			U+E+N,
			U+W+N
		],
	faces =
		[
			[4,1,0], # Front
			[3,2,5,3,5,6], # Back
			[0,3,6], # Right
			[2,1,4,2,4,5], # Left
			[4,0,6,4,6,5], # Top
			[0,1,2,0,2,3]  # Bottom
		],
	uvs =
		[
			"dtriangle",
			"square",
			"dtriangle",
			"square",
			"square",
			"square"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			true, 	#S
			true,	#N
			true,	#W
			true,	#E
			false,	#U
			true,	#D
		]
}


var pyramid_dat = {
	vertices =
		[
			D+W+S,
			D+E+S,
			D+E+N,
			D+W+N,
			U
		],
	faces =
		[
			[0,4,1], # Front
			[2,4,3], # Back
			[3,4,0], # Right
			[1,4,2], # Left
			[], # Top
			[0,1,2,0,2,3]  # Bottom
		],
	uvs =
		[
			"dtriangle_cone",
			"dtriangle_cone",
			"dtriangle_cone",
			"dtriangle_cone",
			"",
			"square"
		],
	face_tile_voffset =
		[
			0, 	#S
			0,	#N
			0,	#W
			0,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			false,	#N
			false,	#W
			false,	#E
			false,	#U
			true,	#D
		]
}

var stairs_dat = {
	vertices =
		[
			D+S+E,
			D+S+W,
			D+N+W,
			D+N+E,
			U1+S+E,
			U1+S+W,
			U1+N1+W,
			U1+N1+E,
			U2+N1+E,
			U2+N1+W,
			U2+N2+W,
			U2+N2+E,
			U3+N2+E,
			U3+N2+W,
			U3+N3+W,
			U3+N3+E,
			U+N3+E,
			U+N3+W,
			U+N+W,
			U+N+E
		],
	faces =
		[
			[ # Front
				0,1,5,0,5,4,
				7,6,9,7,9,8,
				11,10,13,11,13,12,
				15,14,17,15,17,16
			], 
			[2,3,19,2,19,18], # Back
			[ # Left
				5,1,6,6,1,2,9,6,10,10,6,2,13,10,14,14,10,2,17,14,18,18,14,2
			], 
			[ # Right
				0,4,7,0,7,3,7,8,11,7,11,3,11,12,15,11,15,3,15,16,19,15,19,3
			], 
			[ # Top
				4,5,6,4,6,7,
				8,9,10,8,10,11,
				12,13,14,12,14,15,
				16,17,18,16,18,19
			], 
			[0,3,2,0,2,1]  # Bottom
		],
	uvs =
		[
			"steps_front",
			"steps_back",
			"steps_right",
			"steps_left",
			"steps_top",
			"steps_bottom"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			true,	#N
			false,	#W
			false,	#E
			false,	#U
			true,	#D
		]
}

var pillar_dat = {
	vertices =
		[
			D+E+N1,
			D+E3+S,
			D+E1+S,
			D+W+N1,
			D+W+N3,
			D+E1+N,
			D+E3+N,
			D+E+N3,
			U+E+N1,
			U+E3+S,
			U+E1+S,
			U+W+N1,
			U+W+N3,
			U+E1+N,
			U+E3+N,
			U+E+N3,
		],
	faces =
		[
			[# Front
				0,1,9,0,9,8,
				1,2,10,1,10,9,
				2,3,11,2,11,10
			], 
			[	# Back
				6,7,15,6,15,14,
				5,6,14,5,14,13,
				4,5,13,4,13,12
			], 
			[3,4,12,3,12,11], # Right
			[7,0,8,7,8,15], # Left
			[	# Top
				14,15,9,15,8,9,				
				9,10,13,9,13,14,
				10,11,13,11,12,13				
			], 
			[ # Bottom
				1,0,6,0,7,6,
				2,1,6,2,6,5,
				3,2,5,3,5,4
			]  
		],
		uvs =
		[
			"pillar_front",
			"pillar_back",
			"pillar_right",
			"pillar_left",
			"pillar_top",
			"pillar_bottom"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			false,	#N
			false,	#W
			false,	#E
			true,	#U
			true,	#D
		]
}


var wall_dat = {
	vertices =
		[
			D+E+S*wall_slimness,
			D+W+S*wall_slimness,
			U+W+S*wall_slimness,
			U+E+S*wall_slimness,
			D+E+N*wall_slimness,
			D+W+N*wall_slimness,
			U+W+N*wall_slimness,
			U+E+N*wall_slimness
		],
	faces =
		[
			[0, 1, 2, 0, 2, 3], # Front
			[5, 4, 7, 5, 7, 6], # Back
			[1, 5, 6, 1, 6, 2], # Right
			[4, 0, 3, 4, 3, 7], # Left
			[3, 2, 6, 3, 6, 7], # Top
			[4, 5, 1, 4, 1, 0]  # Bottom
		],
		uvs =
		[
			"square",
			"square",
			"square_slim",
			"square_slim",
			"square_slim_rot",
			"square_slim_rot"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			false, 	#S
			false,	#N
			true,	#W
			true,	#E
			false,	#U
			false,	#D
		]
}


var clipped_innercorner2 = {
	vertices =
		[
			D+W+S, #0
			D+W+N, #1
			D+E+N, #2 
			D+E+S, #3 
			U+W+N, #4 
			U+E+N, #5
			U+E+S  #6
		],
	faces =
		[
			[6,3,0], # Front
			[1,2,5,1,5,4], # Back
			[0,1,4], # Right
			[2,3,6,2,6,5], # Left
			[0,4,5,0,5,6], # Top
			[0,3,2,0,2,1]  # Bottom
		],
	uvs =
		[
			"dtriangle",
			"square",
			"dtriangle",
			"square",
			"square",
			"square"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			true, 	#S
			true,	#N
			true,	#W
			true,	#E
			false,	#U
			true,	#D
		]
}



var shallow_ramp_low_dat = {
	vertices =
		[
			D*(1+SHALLOW_THICKNESS)+W+S,
			D*(1+SHALLOW_THICKNESS)+E+S,
			D+W+S,
			D+E+S,
			D*(SHALLOW_THICKNESS)+W+N,
			D*(SHALLOW_THICKNESS)+E+N,
			W+N,
			E+N,
		],
	faces =
		[
			[1, 0, 2, 1, 2, 3], # Front
			[4, 5, 7, 4, 7, 6], # Back
			[0, 4, 6, 0, 6, 2], # Right
			[5, 1, 3, 5, 3, 7], # Left
			[3, 2, 6, 3, 6, 7], # Top
			[5, 4, 0, 5, 0, 1]  # Bottom
		],
	uvs =
		[
			"square_shallow",
			"square_shallow",
			"square_shallow",
			"square_shallow",
			"square",
			"square"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			true, 	#S - can cull against neighbor
			true,	#N - can cull against neighbor
			true,	#W - can cull against neighbor
			true,	#E - can cull against neighbor
			false,	#U - sloped, don't cull
			false,	#D - sloped, don't cull
		]
}


var shallow_ramp_high_dat = {
	vertices =
		[
			D*(1+SHALLOW_THICKNESS)+W+S + U,
			D*(1+SHALLOW_THICKNESS)+E+S + U,
			D+W+S+ U,
			D+E+S+ U,
			D*(SHALLOW_THICKNESS)+W+N+ U,
			D*(SHALLOW_THICKNESS)+E+N+ U,
			W+N+ U,
			E+N+ U,
		],
	faces =
		[
			[1, 0, 2, 1, 2, 3], # Front
			[4, 5, 7, 4, 7, 6], # Back
			[0, 4, 6, 0, 6, 2], # Right
			[5, 1, 3, 5, 3, 7], # Left
			[3, 2, 6, 3, 6, 7], # Top
			[5, 4, 0, 5, 0, 1]  # Bottom
		],
	uvs =
		[
			"square_shallow",
			"square_shallow",
			"square_shallow",
			"square_shallow",
			"square",
			"square"
		],
	face_tile_voffset =
		[
			1, 	#S
			1,	#N
			1,	#W
			1,	#E
			0,	#U
			2,	#D
		],
	occupyface =
		[
			true, 	#S - can cull against neighbor
			true,	#N - can cull against neighbor
			true,	#W - can cull against neighbor
			true,	#E - can cull against neighbor
			false,	#U - sloped, don't cull
			false,	#D - sloped, don't cull
		]
}

var pipe_dat = {}

const wall_slimness:float = 7.0/16.0

var uvpatterns = {
	"":[],
	"square":[
		du+dv,
		dv,
		Vector2(0,0),
		du+dv,
		Vector2(0,0),
		du],
	"square_f":[du,Vector2(0,0),dv,du,dv,du+dv],
	"square_wedgeflip":[du+dv,dv,Vector2(0,0),du+dv,Vector2(0,0),du],
	"square_wedgeflip_inverted":[du-dv,du+dv-dv,dv-dv,du-dv,dv-dv,Vector2(0,0)-dv],
	"square_slim": [
						dv+du*wall_slimness,
						dv,
						Vector2(0,0),
						dv+du*wall_slimness,
						Vector2(0,0),
						du*wall_slimness
					],
	"square_slim_rot": [
						du+dv*wall_slimness,
						dv*wall_slimness,
						Vector2(0,0),
						du+dv*wall_slimness,
						Vector2(0,0),
						du,
						
					],

	"square_shallow": [
		du+dv*SHALLOW_THICKNESS,
		dv*SHALLOW_THICKNESS,
		Vector2(0,0),
		du+dv*SHALLOW_THICKNESS,
		Vector2(0,0),
		du

	],
	
	"triangle": [dv,Vector2(0,0),du],
	"triangle_f": [du,Vector2(0,0),dv],
	
	"triangle_corner_top": [dv,Vector2(0,0),du],
	"triangle_corner_top_vflipped": [du-dv,du*0.5+dv-dv,Vector2(0,0)-dv,],
	
	"dtriangle": [du,du*0.5+dv*0.707,Vector2(0,0)],
	"dtriangle_f":[Vector2(0,0),du*0.5+dv*0.707,du],
	"dtriangle_vflipped":[dv,dv+du,du],
	"dtriangle_f_vflipped":[du,dv+du,dv],
	
	"dtriangle_cone": [du,du*0.5+dv,Vector2(0,0)],
	
	"dtriangle_wedge": [du,du*0.5+dv*0.707,Vector2(0,0)],
	"dtriangle_wedge_f":[Vector2(0,0),du*0.5+dv*0.707,du],
	
	"dtriangle_corner": [du,du*0.5+dv*0.707,Vector2(0,0)],
	"dtriangle_corner_f":[Vector2(0,0),du*0.5+dv*0.707,du],
	"dtriangle_corner_vflipped":[du,Vector2(0,0),dv],
	"dtriangle_corner_f_vflipped":[dv,Vector2(0,0),du],
	
}


var flippable_uvs = [
	["dtriangle","dtriangle_vflipped"],
	["dtriangle_f","dtriangle_f_vflipped"],
	["dtriangle_wedge","triangle_f"],
	["dtriangle_wedge_f","triangle"],
	["square_wedgeflip","square_wedgeflip_inverted"],
	["square","square_f"],
	["dtriangle_corner","dtriangle_corner_vflipped"],
	["dtriangle_corner_f","dtriangle_corner_f_vflipped"],
	["triangle_corner_top","triangle_corner_top_vflipped"],
]

func generateShapeDats():
	# fills the shape database -
	# structure is - shape_database[shape][rotation][vflip]
	database=[]
	for shape_i in range(shape_dats.size()):
		var shape_dat = shape_dats[shape_i]		
		var shape_rots = []
		for rot in range(0,4):
			#create new rotated version of shape_dat
			var rotated_shape = {}
			rotated_shape.vertices=[]
			for v in shape_dat.vertices:
				var vt : Vector3 = v.rotated(Vector3.UP,-rot*PI/2)
				rotated_shape.vertices.push_back(vt)
				
			rotated_shape.faces=[[],[],[],[],[],[]]
			rotated_shape.uvs=["","","","","",""]
			rotated_shape.face_tile_voffset=[0,0,0,0,0,0]
			rotated_shape.occupyface=[false,false,false,false,false,false]
			rotated_shape.face_occupancy=[FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY]
			
			var base_occupancy = BLOCK_OCCUPANCIES.get(shape_i, [FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY])
			
			for face_i in range(shape_dat.faces.size()):
				var new_i : int = Glob.rot_dir(face_i,rot)
				rotated_shape.faces[new_i]=shape_dat.faces[face_i]
				rotated_shape.uvs[new_i]=shape_dat.uvs[face_i]
				rotated_shape.face_tile_voffset[new_i]=shape_dat.face_tile_voffset[face_i]
				rotated_shape.occupyface[new_i]=shape_dat.occupyface[face_i]
				
				if base_occupancy.size() > face_i:
					rotated_shape.face_occupancy[new_i]=z_rotate_face_occupancy_n_times(base_occupancy[face_i],face_i,rot)
								
			var shape_flips = []
			for vflip_i in range(0,2):
				var vflip:bool = vflip_i==1
				if !vflip:
					shape_flips.push_back(rotated_shape)
				else:
					var vflipped_shape = {}
					vflipped_shape.vertices=[]
					for v in rotated_shape.vertices:
						var vt : Vector3 = Vector3(v.x,-v.y,v.z)
						vflipped_shape.vertices.push_back(vt)
						
					vflipped_shape.faces=[[],[],[],[],[],[]]
					vflipped_shape.uvs=["","","","","",""]
					vflipped_shape.face_tile_voffset=[0,0,0,0,0,0]
					vflipped_shape.occupyface=[false,false,false,false,false,false]
					vflipped_shape.face_occupancy=[FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY,FaceOccupancy.EMPTY]
					
					for face_i in range(rotated_shape.faces.size()):
						var new_i : int = Glob.vflipDir[face_i]
						vflipped_shape.faces[new_i]=rotated_shape.faces[face_i].duplicate()
						
						var uvs = rotated_shape.uvs[face_i]
						for idx in range(flippable_uvs.size()):
							var flip_pair = flippable_uvs[idx]
							if uvs==flip_pair[0]:
								uvs=flip_pair[1]
								break
						
						vflipped_shape.uvs[new_i]=uvs
							
						vflipped_shape.face_tile_voffset[new_i]=2-rotated_shape.face_tile_voffset[face_i]
						vflipped_shape.occupyface[new_i]=rotated_shape.occupyface[face_i]
						vflipped_shape.face_occupancy[new_i]=vflip_face_occupancy(rotated_shape.face_occupancy[face_i],face_i)
					
						# Triangles in faces (+therefore uvs), are now facing the wrong direction;
						# Flip them by swapping vertices 1+3
						var facearray = vflipped_shape.faces[new_i]
						vflipped_shape.uvs[new_i]=vflipped_shape.uvs[new_i]+"s13"
						for i in range(0,facearray.size(),3):
							var tmp_face_index : int = facearray[i]
							facearray[i]=facearray[i+2]
							facearray[i+2]=tmp_face_index
							
							
					
					
					shape_flips.push_back(vflipped_shape)
			shape_rots.push_back(shape_flips)
		database.push_back(shape_rots)
		

func generate_projected_uvs(shape_dat: Dictionary) -> void:	
	
	for dir in range(shape_dat.faces.size()):		
		var face = shape_dat.faces[dir]		
		var uv_list = []
		for face_idx in face:
			var v = shape_dat.vertices[face_idx]
			var v_p :Vector2 = Glob.project(v,dir)
			var uv = Vector2(v_p.x*TILE_W_LOCAL,v_p.y*TILE_H_LOCAL)+du/2+dv/2	
			#if dir<4:	
			uv.y = dv.y-uv.y
			uv_list.push_back(uv)	
		
		var pattern_name = shape_dat.uvs[dir]
		uvpatterns[pattern_name]=uv_list
		
func generateUVPatterns():
	var keys = uvpatterns.keys().duplicate()
	for key in keys:
		var uvarray = uvpatterns[key].duplicate()
		for i in range(0,uvarray.size(),3):
			var tmp_uv : Vector2 = uvarray[i]
			uvarray[i]=uvarray[i+2]
			uvarray[i+2]=tmp_uv
		uvpatterns[key+"s13"]=uvarray



#shape type indices
const VOXEL_EMPTY:int = -1
const CUBE:int = 0
const RAMP:int = 1
const CLIPPED_EDGE:int = 2
const CLIPPED_RAMP:int = 3
const CLIPPED_CORNER:int = 4
const PYRAMID:int = 5
const STAIRS:int = 6
const PILLAR:int = 7
const WALL:int = 8
const INNERCORNER2:int = 9
const SHALLOW_RAMP_LOW:int = 10
const SHALLOW_RAMP_HIGH:int = 11
const PIPE:int = 12


enum FaceOccupancy {
	EMPTY=-1,
	TRI0=0,
	TRI1=1,
	TRI2=2,
	TRI3=3,
	QUAD=4,
	OCTAGON=5,
	SLIM=6,#for wall slim sides - not for top and bottom
	# Shallow ramp end pieces - rectangles at different heights
	SHALLOW_END_LOW=7,   # Low end (y = -0.75 to -0.5)
	SHALLOW_END_MED=8,   # Medium end (y = -0.25 to 0)
	SHALLOW_END_HIGH=9,  # High end (y = 0.25 to 0.5)
	# Shallow ramp side pieces - trapezoids encoded by SLOPE DIRECTION (world-space)
	# Two sides cull only if same height AND same slope direction
	SHALLOW_SIDE_LOW_N=10,  # LOW trapezoid, ramp slopes toward +Z (north)
	SHALLOW_SIDE_LOW_S=11,  # LOW trapezoid, ramp slopes toward -Z (south)
	SHALLOW_SIDE_LOW_E=12,  # LOW trapezoid, ramp slopes toward -X (east)
	SHALLOW_SIDE_LOW_W=13,  # LOW trapezoid, ramp slopes toward +X (west)
	SHALLOW_SIDE_HIGH_N=14, # HIGH trapezoid, ramp slopes toward +Z (north)
	SHALLOW_SIDE_HIGH_S=15, # HIGH trapezoid, ramp slopes toward -Z (south)
	SHALLOW_SIDE_HIGH_E=16, # HIGH trapezoid, ramp slopes toward -X (east)
	SHALLOW_SIDE_HIGH_W=17, # HIGH trapezoid, ramp slopes toward +X (west)
}

func occupancy_fits(subject: FaceOccupancy, container: FaceOccupancy) -> bool:
	if container == FaceOccupancy.QUAD && subject >= FaceOccupancy.TRI0 && subject <= FaceOccupancy.QUAD:
		return true
	if subject == FaceOccupancy.EMPTY:
		return true
	if container == FaceOccupancy.EMPTY:
		return false
	if subject == container:
		return true
	if subject < 4 && container == FaceOccupancy.QUAD:
		return true
	# For triangles, they must match exactly (assuming standard 4 quadrants)
	return subject == container

const BLOCK_OCCUPANCIES : Dictionary = {
	0: [ # CUBE 
		FaceOccupancy.QUAD,	#S
		FaceOccupancy.QUAD,	#N
		FaceOccupancy.QUAD,	#W
		FaceOccupancy.QUAD,	#E
		FaceOccupancy.QUAD,	#U
		FaceOccupancy.QUAD,	#D
	],
	1: [ # RAMP
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.QUAD, #N
		FaceOccupancy.TRI1, #W
		FaceOccupancy.TRI1, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.QUAD, #D
	],
	2: [ # CLIPPED_EDGE
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.QUAD, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.QUAD, #E
		FaceOccupancy.TRI3, #U
		FaceOccupancy.TRI3, #D
	],
	3: [ # CLIPPED_RAMP
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.TRI0, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.TRI1, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.TRI3, #D
	],
	4: [ # CLIPPED_CORNER
		FaceOccupancy.TRI0, #S
		FaceOccupancy.QUAD, #N
		FaceOccupancy.TRI1, #W
		FaceOccupancy.QUAD, #E
		FaceOccupancy.TRI3, #U
		FaceOccupancy.QUAD	, #D
	],
	5: [ # PYRAMID
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.EMPTY, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.EMPTY, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.QUAD, #D
	],
	6: [ # STAIRS
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.QUAD, #N
		FaceOccupancy.TRI0, #W
		FaceOccupancy.TRI0, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.QUAD, #D
	],
	7: [ # PILLAR
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.EMPTY, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.EMPTY, #E
		FaceOccupancy.OCTAGON, #U
		FaceOccupancy.OCTAGON, #D
	],
	8: [ # WALL
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.EMPTY, #N
		FaceOccupancy.SLIM, #W
		FaceOccupancy.SLIM, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.EMPTY, #D
	],
	9: [ # some kinda clipped corner
		FaceOccupancy.TRI0, #S
		FaceOccupancy.QUAD, #N
		FaceOccupancy.TRI1, #W
		FaceOccupancy.QUAD, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.QUAD, #D
	],
	10: [ # SHALLOW_RAMP_LOW - base orientation slopes toward N (+Z)
		FaceOccupancy.SHALLOW_END_LOW, #S - low end
		FaceOccupancy.SHALLOW_END_MED, #N - medium end (meets high's S)
		FaceOccupancy.SHALLOW_SIDE_LOW_N, #W - trapezoid, slope toward N
		FaceOccupancy.SHALLOW_SIDE_LOW_N, #E - trapezoid, slope toward N
		FaceOccupancy.EMPTY, #U - sloped top, doesn't cull
		FaceOccupancy.EMPTY, #D - sloped bottom, doesn't cull
	],
	11: [ # SHALLOW_RAMP_HIGH - base orientation slopes toward N (+Z)
		FaceOccupancy.SHALLOW_END_MED, #S - medium end (meets low's N)
		FaceOccupancy.SHALLOW_END_HIGH, #N - high end
		FaceOccupancy.SHALLOW_SIDE_HIGH_N, #W - trapezoid, slope toward N
		FaceOccupancy.SHALLOW_SIDE_HIGH_N, #E - trapezoid, slope toward N
		FaceOccupancy.EMPTY, #U - sloped top, doesn't cull
		FaceOccupancy.EMPTY, #D - sloped bottom, doesn't cull
	],
	12: [ # PIPE
		FaceOccupancy.OCTAGON, #S
		FaceOccupancy.OCTAGON, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.EMPTY, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.EMPTY, #D
	],
	
}

#rotates clockwise once around the Z axis
func z_rotate_face_occupancy(face:FaceOccupancy,side:int)->FaceOccupancy:
	if face<FaceOccupancy.TRI0 || face>FaceOccupancy.TRI3:
		# Non-triangle occupancies (QUAD, OCTAGON, SLIM, SHALLOW_*) don't need
		# value transformation when rotated - the face mapping handles geometry,
		# and identical ramps side-by-side will have matching occupancies
		return face
	#TRI
	match(side):
		DirEnum.S,DirEnum.N: return [0,3,2,1,4,5,6][face] as FaceOccupancy
		DirEnum.E,DirEnum.W: return [3,0,1,2,4,5,6][face] as FaceOccupancy
		DirEnum.U,DirEnum.D:
			return ((face+1)%4) as FaceOccupancy
	%EditorUI.do_print("eep face not found")
	return FaceOccupancy.QUAD

func z_rotate_face_occupancy_n_times(face_occupancy:FaceOccupancy,side:int,n:int)->FaceOccupancy:
	# Special handling for shallow ramp occupancies - need full rotation context
	if face_occupancy >= FaceOccupancy.SHALLOW_END_LOW:
		return transform_shallow_occupancy(face_occupancy, n)
	
	# Original logic for triangles and other shapes
	for i in range(n):
		face_occupancy = z_rotate_face_occupancy(face_occupancy,side)
		side = Glob.rotDir[side]
	return face_occupancy

# Transform shallow ramp occupancies based on total rotation amount
func transform_shallow_occupancy(occ: FaceOccupancy, rotations: int) -> FaceOccupancy:
	rotations = rotations % 4  # Normalize to 0-3
	if rotations == 0:
		return occ
	
	# END occupancies don't change direction, just position (handled by face mapping)
	if occ >= FaceOccupancy.SHALLOW_END_LOW and occ <= FaceOccupancy.SHALLOW_END_HIGH:
		return occ
	
	# SIDE occupancies: rotate the slope direction
	# Direction rotation: N→E→S→W→N (clockwise when viewed from above)
	var dir_rotate = [
		[DirEnum.N, DirEnum.E, DirEnum.S, DirEnum.W],  # from N
		[DirEnum.S, DirEnum.W, DirEnum.N, DirEnum.E],  # from S
		[DirEnum.E, DirEnum.S, DirEnum.W, DirEnum.N],  # from E
		[DirEnum.W, DirEnum.N, DirEnum.E, DirEnum.S],  # from W
	]
	# Index: 0=N, 1=S, 2=E, 3=W
	
	# Determine if LOW or HIGH and extract direction
	var is_low = (occ >= FaceOccupancy.SHALLOW_SIDE_LOW_N and occ <= FaceOccupancy.SHALLOW_SIDE_LOW_W)
	var dir_idx: int
	if is_low:
		dir_idx = occ - FaceOccupancy.SHALLOW_SIDE_LOW_N  # 0=N, 1=S, 2=E, 3=W
	else:
		dir_idx = occ - FaceOccupancy.SHALLOW_SIDE_HIGH_N  # 0=N, 1=S, 2=E, 3=W
	
	# Get rotated direction
	var new_dir = dir_rotate[dir_idx][rotations]
	
	# Convert back to occupancy
	# dir_idx mapping: N=0, S=1, E=2, W=3
	var dir_to_idx = {DirEnum.N: 0, DirEnum.S: 1, DirEnum.E: 2, DirEnum.W: 3}
	var new_dir_idx = dir_to_idx[new_dir]
	
	if is_low:
		return (FaceOccupancy.SHALLOW_SIDE_LOW_N + new_dir_idx) as FaceOccupancy
	else:
		return (FaceOccupancy.SHALLOW_SIDE_HIGH_N + new_dir_idx) as FaceOccupancy

var vflip_occupancies:Array[FaceOccupancy] = [
	FaceOccupancy.TRI3,           # 0: TRI0 -> TRI3
	FaceOccupancy.TRI2,           # 1: TRI1 -> TRI2
	FaceOccupancy.TRI1,           # 2: TRI2 -> TRI1
	FaceOccupancy.TRI0,           # 3: TRI3 -> TRI0
	FaceOccupancy.QUAD,           # 4: QUAD -> QUAD
	FaceOccupancy.OCTAGON,        # 5: OCTAGON -> OCTAGON
	FaceOccupancy.SLIM,           # 6: SLIM -> SLIM
	FaceOccupancy.SHALLOW_END_HIGH,    # 7: SHALLOW_END_LOW -> SHALLOW_END_HIGH
	FaceOccupancy.SHALLOW_END_MED,     # 8: SHALLOW_END_MED -> SHALLOW_END_MED
	FaceOccupancy.SHALLOW_END_LOW,     # 9: SHALLOW_END_HIGH -> SHALLOW_END_LOW
	# Vflip swaps LOW↔HIGH but keeps direction the same
	FaceOccupancy.SHALLOW_SIDE_HIGH_N, # 10: SHALLOW_SIDE_LOW_N -> SHALLOW_SIDE_HIGH_N
	FaceOccupancy.SHALLOW_SIDE_HIGH_S, # 11: SHALLOW_SIDE_LOW_S -> SHALLOW_SIDE_HIGH_S
	FaceOccupancy.SHALLOW_SIDE_HIGH_E, # 12: SHALLOW_SIDE_LOW_E -> SHALLOW_SIDE_HIGH_E
	FaceOccupancy.SHALLOW_SIDE_HIGH_W, # 13: SHALLOW_SIDE_LOW_W -> SHALLOW_SIDE_HIGH_W
	FaceOccupancy.SHALLOW_SIDE_LOW_N,  # 14: SHALLOW_SIDE_HIGH_N -> SHALLOW_SIDE_LOW_N
	FaceOccupancy.SHALLOW_SIDE_LOW_S,  # 15: SHALLOW_SIDE_HIGH_S -> SHALLOW_SIDE_LOW_S
	FaceOccupancy.SHALLOW_SIDE_LOW_E,  # 16: SHALLOW_SIDE_HIGH_E -> SHALLOW_SIDE_LOW_E
	FaceOccupancy.SHALLOW_SIDE_LOW_W,  # 17: SHALLOW_SIDE_HIGH_W -> SHALLOW_SIDE_LOW_W
]
func vflip_face_occupancy(face_occupancy:FaceOccupancy,side:int)->FaceOccupancy:
	if side==DirEnum.U or side==DirEnum.D:
		return face_occupancy
	if face_occupancy==FaceOccupancy.EMPTY:
		return face_occupancy
	return vflip_occupancies[face_occupancy]
	
func get_face_occupancy(block_type:int,block_rot:int,vflip:bool,side:int)->FaceOccupancy:
	var block_occupancy = BLOCK_OCCUPANCIES[block_type]
	var result:FaceOccupancy;
	if side==DirEnum.U or side==DirEnum.D:		
		var original_side = Glob.do_flip(side,vflip)
		var original_occupancy = block_occupancy[original_side]
		#we just need to rotate the face
		result = z_rotate_face_occupancy_n_times(original_occupancy,original_side,block_rot)
	else:
		#if we're rotating, we need to find where our face comes from on the unrotated
		#block
		var original_side = Glob.rot_dir(side,4-block_rot)
		var original_occupancy = block_occupancy[original_side]
		result = z_rotate_face_occupancy_n_times(original_occupancy,original_side,block_rot)
		if vflip:
			result = vflip_face_occupancy(result,side)
	return result
	

var shape_dats : Array
func _ready() -> void:
	# Generate pipe_dat from pillar_dat (rotated 90 deg around X)
	pipe_dat.vertices = []
	for v in pillar_dat.vertices:
		pipe_dat.vertices.push_back(v.rotated(Vector3.RIGHT, PI/2))
	
	pipe_dat.faces = [[],[],[],[],[],[]]
	pipe_dat.uvs = ["","","","","",""]
	pipe_dat.face_tile_voffset = [0,0,0,0,0,0]
	pipe_dat.occupyface = [true,true,false,false,false,false]
	
	# Mapping: 
	# New S (0) <- Old D (5)
	# New N (1) <- Old U (4)
	# New W (2) <- Old W (2)
	# New E (3) <- Old E (3)
	# New U (4) <- Old S (0)
	# New D (5) <- Old N (1)
	var face_map = {0:5, 1:4, 2:2, 3:3, 4:0, 5:1}
	
	for new_face_i in range(6):
		var old_face_i = face_map[new_face_i]
		pipe_dat.faces[new_face_i] = pillar_dat.faces[old_face_i]
		# pipe_dat.uvs[new_face_i] = pillar_dat.uvs[old_face_i].replace("pillar", "pipe")
		# pipe_dat.face_tile_voffset[new_face_i] = pillar_dat.face_tile_voffset[old_face_i]
		pipe_dat.occupyface[new_face_i] = pillar_dat.occupyface[old_face_i]

	# Fix texture assignments for Pipe
	# Ends (N/S) use Side texture (1)
	pipe_dat.face_tile_voffset[0] = 1 # S
	pipe_dat.face_tile_voffset[1] = 1 # N
	pipe_dat.face_tile_voffset[2] = 1 # W
	pipe_dat.face_tile_voffset[3] = 1 # E
	# Top/Bottom (U/D) use Top/Bottom textures (0/2)
	pipe_dat.face_tile_voffset[4] = 0 # U
	pipe_dat.face_tile_voffset[5] = 2 # D
	
	# Assign specific UV names
	pipe_dat.uvs[0] = "pipe_front"
	pipe_dat.uvs[1] = "pipe_back"
	pipe_dat.uvs[2] = "pipe_right"
	pipe_dat.uvs[3] = "pipe_left"
	pipe_dat.uvs[4] = "pipe_top"
	pipe_dat.uvs[5] = "pipe_bottom"

	shape_dats = [
		cube_dat,#0
		ramp_dat,#1
		clipped_edge_dat,#2
		clipped_ramp_dat,#3
		clipped_corner_dat,#4
		pyramid_dat,#5
		stairs_dat,#6
		pillar_dat,#7
		wall_dat,#8
		clipped_innercorner2,#9
		shallow_ramp_low_dat,#10
		shallow_ramp_high_dat,#11
		pipe_dat,#12
	]
	generate_projected_uvs(stairs_dat)
	generate_projected_uvs(pillar_dat)
	generate_projected_uvs(pipe_dat)
	generateUVPatterns()
	generateShapeDats()
	#test_shallow_ramp_occupancies()  # Commented out - tests passed
	

# ============ SHALLOW RAMP OCCUPANCY DEBUG/TEST ============
func test_shallow_ramp_occupancies():
	var face_names = ["S", "N", "W", "E", "U", "D"]
	
	print("\n========== SHALLOW RAMP OCCUPANCY TEST ==========")
	
	# Print occupancies for all rotations of LOW and HIGH ramps
	for shape_i in [SHALLOW_RAMP_LOW, SHALLOW_RAMP_HIGH]:
		var shape_name = "LOW" if shape_i == SHALLOW_RAMP_LOW else "HIGH"
		print("\n--- SHALLOW_RAMP_", shape_name, " ---")
		
		for rot in range(4):
			for vflip in [false, true]:
				var vflip_i = 1 if vflip else 0
				var shape = database[shape_i][rot][vflip_i]
				var occ_str = ""
				for face_i in range(6):
					occ_str += face_names[face_i] + "=" + str(shape.face_occupancy[face_i]) + " "
				print("  rot=", rot, " vflip=", vflip, ": ", occ_str)
	
	print("\n--- ADJACENCY TESTS ---")
	# Test: Two LOW ramps side by side, same rotation (should cull)
	test_adjacency("LOW rot=0 E-face vs LOW rot=0 W-face (same dir, should cull)", 
		SHALLOW_RAMP_LOW, 0, false, 3,  # E face of first
		SHALLOW_RAMP_LOW, 0, false, 2)  # W face of second
	
	# Test: Two LOW ramps side by side, opposite rotation (should NOT cull)
	test_adjacency("LOW rot=0 E-face vs LOW rot=2 W-face (opposite dir, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 3,
		SHALLOW_RAMP_LOW, 2, false, 2)
	
	# Test: LOW N-face vs HIGH S-face (should cull - same height SHALLOW_END_MED)
	test_adjacency("LOW rot=0 N-face vs HIGH rot=0 S-face (end-to-end, should cull)", 
		SHALLOW_RAMP_LOW, 0, false, 1,  # N face
		SHALLOW_RAMP_HIGH, 0, false, 0) # S face
	
	# Test: Two HIGH ramps, rot=0 and rot=0 (should cull)
	test_adjacency("HIGH rot=0 E-face vs HIGH rot=0 W-face (same dir, should cull)", 
		SHALLOW_RAMP_HIGH, 0, false, 3,
		SHALLOW_RAMP_HIGH, 0, false, 2)
	
	# Test: Rotational invariance - rot=1 same dir
	# Note: For rot=1, SIDES are on S/N faces (trapezoids), W/E are ENDS (rectangles)
	test_adjacency("LOW rot=1 N-face vs LOW rot=1 S-face (sides, same dir rot=1, should cull)", 
		SHALLOW_RAMP_LOW, 1, false, 1,  # N face = trapezoid
		SHALLOW_RAMP_LOW, 1, false, 0)  # S face = trapezoid
	
	# Test: rot=1 W/E faces are ENDS (rectangles at different heights) - should NOT cull
	test_adjacency("LOW rot=1 E-face vs LOW rot=1 W-face (ends, different heights, should NOT cull)", 
		SHALLOW_RAMP_LOW, 1, false, 3,  # E face = SHALLOW_END_MED
		SHALLOW_RAMP_LOW, 1, false, 2)  # W face = SHALLOW_END_LOW
	
	# Test: LOW rot=0 vs LOW rot=1 (perpendicular, probably shouldn't cull?)
	test_adjacency("LOW rot=0 E-face vs LOW rot=1 W-face (perpendicular, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 3,
		SHALLOW_RAMP_LOW, 1, false, 2)
	
	# Test: rot=2 sides (W/E are trapezoids for rot=0,2)
	test_adjacency("LOW rot=2 E-face vs LOW rot=2 W-face (sides, same dir rot=2, should cull)", 
		SHALLOW_RAMP_LOW, 2, false, 3,
		SHALLOW_RAMP_LOW, 2, false, 2)
	
	# Test: rot=3 sides (S/N are trapezoids for rot=1,3)
	test_adjacency("LOW rot=3 N-face vs LOW rot=3 S-face (sides, same dir rot=3, should cull)", 
		SHALLOW_RAMP_LOW, 3, false, 1,
		SHALLOW_RAMP_LOW, 3, false, 0)
	
	# Test: LOW and HIGH same rotation side-by-side (different heights, same dir)
	test_adjacency("LOW rot=0 E-face vs HIGH rot=0 W-face (LOW vs HIGH sides, same dir, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 3,
		SHALLOW_RAMP_HIGH, 0, false, 2)
	
	print("\n--- CRISS-CROSS TESTS (opposite slope directions) ---")
	# Criss-cross: two ramps facing opposite directions side-by-side
	# These should NEVER cull because their diagonal edges don't meet flush
	
	# E/W adjacency, opposite slopes
	test_adjacency("CRISS-CROSS: LOW rot=0 E vs LOW rot=2 W (N-slope vs S-slope, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 3,   # E face, slopes toward N
		SHALLOW_RAMP_LOW, 2, false, 2)   # W face, slopes toward S
	
	test_adjacency("CRISS-CROSS: HIGH rot=0 E vs HIGH rot=2 W (N-slope vs S-slope, should NOT cull)", 
		SHALLOW_RAMP_HIGH, 0, false, 3,
		SHALLOW_RAMP_HIGH, 2, false, 2)
	
	# N/S adjacency, opposite slopes (rot=1 vs rot=3)
	test_adjacency("CRISS-CROSS: LOW rot=1 N vs LOW rot=3 S (E-slope vs W-slope, should NOT cull)", 
		SHALLOW_RAMP_LOW, 1, false, 1,   # N face, slopes toward E
		SHALLOW_RAMP_LOW, 3, false, 0)   # S face, slopes toward W
	
	# Mixed: rot=0 vs rot=1 (perpendicular - one is END, one is SIDE)
	test_adjacency("CRISS-CROSS: LOW rot=0 N vs LOW rot=1 S (end vs side, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 1,   # N face = END (SHALLOW_END_MED)
		SHALLOW_RAMP_LOW, 1, false, 0)   # S face = SIDE (trapezoid)
	
	# Same direction but different heights (LOW next to HIGH, side faces)
	test_adjacency("ADJACENT: LOW rot=0 W vs HIGH rot=0 E (same dir N, LOW vs HIGH trapezoid, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 2,   # W face = SHALLOW_SIDE_LOW_N
		SHALLOW_RAMP_HIGH, 0, false, 3)  # E face = SHALLOW_SIDE_HIGH_N
	
	# What about vflipped criss-cross?
	test_adjacency("CRISS-CROSS VFLIP: LOW rot=0 vflip E vs LOW rot=2 vflip W (should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, true, 3,
		SHALLOW_RAMP_LOW, 2, true, 2)
	
	print("\n--- END CAP TESTS (N/S adjacency at z=0 and z=1) ---")
	# For tiles at z=0 and z=1: z=0's N-face touches z=1's S-face
	
	# Continuous slope: LOW followed by HIGH (should cull - both MED height)
	test_adjacency("END CAP: LOW(z=0) N vs HIGH(z=1) S (MED meets MED, should cull)", 
		SHALLOW_RAMP_LOW, 0, false, 1,   # N face = SHALLOW_END_MED (8)
		SHALLOW_RAMP_HIGH, 0, false, 0)  # S face = SHALLOW_END_MED (8)
	
	# Two LOWs in a row (step - should NOT cull, different heights)
	test_adjacency("END CAP: LOW(z=0) N vs LOW(z=1) S (MED meets LOW, should NOT cull)", 
		SHALLOW_RAMP_LOW, 0, false, 1,   # N face = SHALLOW_END_MED (8)
		SHALLOW_RAMP_LOW, 0, false, 0)   # S face = SHALLOW_END_LOW (7)
	
	# Two HIGHs in a row (step - should NOT cull)
	test_adjacency("END CAP: HIGH(z=0) N vs HIGH(z=1) S (HIGH meets MED, should NOT cull)", 
		SHALLOW_RAMP_HIGH, 0, false, 1,  # N face = SHALLOW_END_HIGH (9)
		SHALLOW_RAMP_HIGH, 0, false, 0)  # S face = SHALLOW_END_MED (8)
	
	# HIGH followed by LOW (big step - should NOT cull)
	test_adjacency("END CAP: HIGH(z=0) N vs LOW(z=1) S (HIGH meets LOW, should NOT cull)", 
		SHALLOW_RAMP_HIGH, 0, false, 1,  # N face = SHALLOW_END_HIGH (9)
		SHALLOW_RAMP_LOW, 0, false, 0)   # S face = SHALLOW_END_LOW (7)
	
	# Rotated: rot=1 uses W/E as ends
	test_adjacency("END CAP ROT1: LOW(x=0) E vs HIGH(x=1) W (MED meets MED, should cull)", 
		SHALLOW_RAMP_LOW, 1, false, 3,   # E face = SHALLOW_END_MED (8)
		SHALLOW_RAMP_HIGH, 1, false, 2)  # W face = SHALLOW_END_MED (8)
	
	print("\n========== END TEST ==========\n")

func test_adjacency(desc: String, shape1: int, rot1: int, vflip1: bool, face1: int, 
					shape2: int, rot2: int, vflip2: bool, face2: int):
	var vf1 = 1 if vflip1 else 0
	var vf2 = 1 if vflip2 else 0
	var occ1 = database[shape1][rot1][vf1].face_occupancy[face1]
	var occ2 = database[shape2][rot2][vf2].face_occupancy[face2]
	
	# Check if they would cull (for sides: L matches R, for ends: same matches same)
	var would_cull = check_occupancy_match(occ1, occ2)
	
	print("  ", desc)
	print("    occ1=", occ1, " occ2=", occ2, " -> ", "CULL" if would_cull else "NO CULL")

func check_occupancy_match(occ1: int, occ2: int) -> bool:
	# EMPTY never culls
	if occ1 == FaceOccupancy.EMPTY or occ2 == FaceOccupancy.EMPTY:
		return false
	# With direction-based scheme, same value = same geometry = cull
	return occ1 == occ2

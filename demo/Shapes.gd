extends Node

var database = []

var TEX_TILEMAP:Texture2D = load("res://VoxelWorld/Textures/tilemap.png")
var TEX_WIDTH:float = 16#TEX_TILEMAP.get_width()
var TEX_HEIGHT:float = 16#TEX_TILEMAP.get_height()
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
			false, 	#S
			false,	#N
			false,	#W
			false,	#E
			false,	#U
			false,	#D
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
			false, 	#S
			false,	#N
			false,	#W
			false,	#E
			false,	#U
			false,	#D
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
	["triangle_corner_top","triangle_corner_top_vflipped"]
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
	10: [ # SHALLOW_RAMP_LOW
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.EMPTY, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.EMPTY, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.EMPTY, #D
	],
	11: [ # SHALLOW_RAMP_HIGH
		FaceOccupancy.EMPTY, #S
		FaceOccupancy.EMPTY, #N
		FaceOccupancy.EMPTY, #W
		FaceOccupancy.EMPTY, #E
		FaceOccupancy.EMPTY, #U
		FaceOccupancy.EMPTY, #D
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
	for i in range(n):
		face_occupancy = z_rotate_face_occupancy(face_occupancy,side)
		side = Glob.rotDir[side]
	return face_occupancy

var vflip_occupancies:Array[FaceOccupancy] = [FaceOccupancy.TRI3,FaceOccupancy.TRI2,FaceOccupancy.TRI1,FaceOccupancy.TRI0,FaceOccupancy.QUAD,FaceOccupancy.OCTAGON,FaceOccupancy.SLIM]
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

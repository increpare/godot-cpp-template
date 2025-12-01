#include "voxel_mesher.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// Enum from Shapes.gd
enum FaceOccupancy {
	OCCUPANCY_EMPTY = -1,
	OCCUPANCY_TRI0 = 0,
	OCCUPANCY_TRI1 = 1,
	OCCUPANCY_TRI2 = 2,
	OCCUPANCY_TRI3 = 3,
	OCCUPANCY_QUAD = 4,
	OCCUPANCY_OCTAGON = 5,
	OCCUPANCY_SLIM = 6
};

// Ported from Shapes.gd
static bool occupancy_fits(int subject, int container) {
	if (container == OCCUPANCY_QUAD && subject >= OCCUPANCY_TRI0 && subject <= OCCUPANCY_QUAD) {
		return true;
	}
	if (subject == OCCUPANCY_EMPTY) {
		return true;
	}
	if (container == OCCUPANCY_EMPTY) {
		return false;
	}
	if (subject == container) {
		return true;
	}
	if (subject < 4 && container == OCCUPANCY_QUAD) {
		return true;
	}
	// For triangles, they must match exactly (assuming standard 4 quadrants)
	return subject == container;
}

static const Vector3i DIR_OFFSETS[6] = {
	Vector3i(0, 0, -1), // S
	Vector3i(0, 0, 1),  // N
	Vector3i(1, 0, 0),  // W
	Vector3i(-1, 0, 0), // E
	Vector3i(0, 1, 0),  // U
	Vector3i(0, -1, 0)  // D
};

static const int OPPOSITE_DIR[6] = {
	1, // S -> N
	0, // N -> S
	3, // W -> E
	2, // E -> W
	5, // U -> D
	4  // D -> U
};

VoxelMesher::VoxelMesher() {
	noise1.instantiate();
	noise2.instantiate();
	noise3.instantiate();

	// Default initialization matching GDScript
	noise1->set_frequency(12424.12);
	noise2->set_frequency(23123.23);
	noise3->set_frequency(4123.4124);

	noise1->set_noise_type(FastNoiseLite::TYPE_VALUE);
	noise2->set_noise_type(FastNoiseLite::TYPE_VALUE);
	noise3->set_noise_type(FastNoiseLite::TYPE_VALUE);
}

VoxelMesher::~VoxelMesher() {
}

void VoxelMesher::initialize_noise(int seed) {
	noise1->set_seed(13123123); // Fixed seeds from GDScript
	noise2->set_seed(123123);
	noise3->set_seed(132);
}

void VoxelMesher::set_texture_dimensions(float width, float height) {
	tex_width = width;
	tex_height = height;
	tile_w_local = TILE_W / tex_width;
	tile_h_local = TILE_H / tex_height;
	du = Vector2(tile_w_local, 0);
	dv = Vector2(0, tile_h_local);
}

void VoxelMesher::parse_shapes(const Array &gd_database, const Dictionary &gd_uv_patterns) {
	shape_database.clear();
	uv_patterns.clear();

	// Parse UV patterns
	Array keys = gd_uv_patterns.keys();
	for (int i = 0; i < keys.size(); i++) {
		String key = keys[i];
		Array uvs = gd_uv_patterns[key];
		std::vector<Vector2> uv_vec;
		for (int j = 0; j < uvs.size(); j++) {
			uv_vec.push_back(uvs[j]);
		}
		uv_patterns[key] = uv_vec;
	}

	// Parse Shape Database
	// database[shape_index][rotation][vflip]
	for (int i = 0; i < gd_database.size(); i++) {
		Array shape_rots_arr = gd_database[i];
		std::vector<std::vector<ShapeVariant>> rots_vec;
		
		for (int r = 0; r < shape_rots_arr.size(); r++) {
			Array shape_flips_arr = shape_rots_arr[r];
			std::vector<ShapeVariant> flips_vec;

			for (int f = 0; f < shape_flips_arr.size(); f++) {
				Dictionary shape_dict = shape_flips_arr[f];
				ShapeVariant sv;

				// Vertices
				Array verts = shape_dict["vertices"];
				for (int v = 0; v < verts.size(); v++) {
					sv.vertices.push_back(verts[v]);
				}

				// Faces
				Array faces = shape_dict["faces"];
				Array uvs = shape_dict["uvs"];
				Array voffsets = shape_dict["face_tile_voffset"];
				Array occupyface = shape_dict["occupyface"];
				Array face_occupancy = shape_dict["face_occupancy"];

				for (int face_idx = 0; face_idx < faces.size(); face_idx++) {
					FaceData fd;
					
					// Indices
					Array indices = faces[face_idx];
					for (int k = 0; k < indices.size(); k++) {
						fd.indices.push_back(indices[k]);
					}

					fd.uv_name = uvs[face_idx];
					fd.tile_voffset = voffsets[face_idx];
					fd.occupy_face = occupyface[face_idx];
					fd.face_occupancy = face_occupancy[face_idx];

					sv.faces.push_back(fd);
				}

				flips_vec.push_back(sv);
			}
			rots_vec.push_back(flips_vec);
		}
		shape_database.push_back(rots_vec);
	}
}

void VoxelMesher::_cache_wobbled_verts(const Vector3i &voxel, const ShapeVariant &shape, 
		const Vector3i &offset, std::vector<Vector3> &out_verts, std::vector<Color> &out_colors) {
	
	out_verts.clear();
	out_colors.clear();
	
	Vector3 v_vec = Vector3(voxel);
	
	// Pre-resize for performance
	out_verts.reserve(shape.vertices.size());
	out_colors.reserve(shape.vertices.size());

	for (size_t i = 0; i < shape.vertices.size(); i++) {
		Vector3 base_local = shape.vertices[i];
		Vector3 world_pos = base_local + v_vec;

		float nx = noise1->get_noise_3dv(world_pos) * 0.1f;
		float ny = noise2->get_noise_3dv(world_pos) * 0.1f;
		float nz = noise3->get_noise_3dv(world_pos) * 0.1f;

		Vector3 wobbled_local = base_local + Vector3(nx, ny, nz);
		out_verts.push_back(wobbled_local);

		Vector3 ns = (wobbled_local.normalized() + Vector3(1, 1, 1)) * 0.5f;
		out_colors.push_back(Color(ns.x, ns.y, ns.z));
	}
}

Dictionary VoxelMesher::generate_chunk_mesh(
		const Vector3i &chunk_coord,
		const Array &voxels,
		const Array &voxel_properties,
		const Array &layer_visibility,
		int size_x, int size_y, int size_z) {
	
	// Output buffers
	PackedVector3Array final_vertices;
	PackedVector3Array final_normals;
	PackedColorArray final_normals_smoothed;
	PackedVector2Array final_uvs;
	
	// Tri-voxel info to return for raycasting/interaction logic
	// Each entry: [voxel_index_in_input_array, face_index]
	// In GDScript this is tri_voxel_info. 
	// Since we are returning a mesh, we might need to return this auxiliary data too if GDScript uses it.
	Array tri_voxel_info;

	int voxel_count = voxels.size();
	if (voxel_count == 0) {
		Dictionary result;
		result["mesh_arrays"] = Array(); // Empty
		result["tri_voxel_info"] = tri_voxel_info;
		return result;
	}

	// Grid Cache
	std::vector<int> grid_cache(size_x * size_y * size_z, -1);
	
	Vector3i offset = Vector3i(chunk_coord.x * size_x, chunk_coord.y * size_y, chunk_coord.z * size_z);
	int stride_y = size_x;
	int stride_z = size_x * size_y;

	// Populate grid cache
	for (int i = 0; i < voxel_count; i++) {
		Vector3i v = voxels[i];
		int lx = v.x - offset.x;
		int ly = v.y - offset.y;
		int lz = v.z - offset.z;
		
		if (lx >= 0 && lx < size_x && ly >= 0 && ly < size_y && lz >= 0 && lz < size_z) {
			grid_cache[lx + ly * stride_y + lz * stride_z] = i;
		}
	}

	std::vector<bool> layers_vis;
	for(int i=0; i<layer_visibility.size(); ++i) {
		layers_vis.push_back(layer_visibility[i]);
	}

	// Temporary buffers
	std::vector<Vector3> cached_wobbled_local_verts;
	std::vector<Color> cached_vertex_colors;

	for (int voxel_index = 0; voxel_index < voxel_count; voxel_index++) {
		Vector3i voxel = voxels[voxel_index];
		Array props = voxel_properties[voxel_index];
		int layer = props[5];

		if (layer >= layers_vis.size() || !layers_vis[layer]) {
			continue;
		}

		int shape_type = props[0];
		int tx = props[1];
		int ty = props[2];
		int rot = props[3];
		bool vflip = props[4];
		int vflip_index = vflip ? 1 : 0;

		// Access shape data safely
		if (shape_type < 0 || shape_type >= shape_database.size()) continue;
		const auto &rots = shape_database[shape_type];
		if (rot < 0 || rot >= rots.size()) continue;
		const auto &flips = rots[rot];
		if (vflip_index < 0 || vflip_index >= flips.size()) continue;
		const ShapeVariant &shape_data = flips[vflip_index];

		// Calculate wobbled vertices
		_cache_wobbled_verts(voxel, shape_data, offset, cached_wobbled_local_verts, cached_vertex_colors);

		Vector3 v_vec = Vector3(voxel);
		int local_x = voxel.x - offset.x;
		int local_y = voxel.y - offset.y;
		int local_z = voxel.z - offset.z;

		for (size_t face_idx = 0; face_idx < shape_data.faces.size(); face_idx++) {
			const FaceData &face = shape_data.faces[face_idx];
			if (face.indices.empty()) continue;

			// Neighbor check
			if (face.occupy_face && face.face_occupancy != OCCUPANCY_EMPTY) {
				Vector3i dir_offset = DIR_OFFSETS[face_idx];
				int nlx = local_x + dir_offset.x;
				int nly = local_y + dir_offset.y;
				int nlz = local_z + dir_offset.z;

				Array neighbour_props; // Null by default
				bool has_neighbour = false;

				if (nlx >= 0 && nlx < size_x && nly >= 0 && nly < size_y && nlz >= 0 && nlz < size_z) {
					int n_idx = grid_cache[nlx + nly * stride_y + nlz * stride_z];
					if (n_idx != -1) {
						neighbour_props = voxel_properties[n_idx];
						has_neighbour = true;
					}
				} else {
					// Boundary check? GDScript checks voxel_dict which is LOCAL.
					// So it doesn't find neighbours outside. 
					// We replicate that behavior: if outside, no neighbour found.
				}

				if (has_neighbour) {
					int neigh_shape_type = neighbour_props[0];
					int neigh_rot = neighbour_props[3];
					bool neigh_vflip = neighbour_props[4];
					int neigh_vflip_index = neigh_vflip ? 1 : 0;
					
					// Safe access
					if (neigh_shape_type >= 0 && neigh_shape_type < shape_database.size()) {
						const ShapeVariant &neigh_shape = shape_database[neigh_shape_type][neigh_rot][neigh_vflip_index];
						int opp_dir = OPPOSITE_DIR[face_idx];
						if (opp_dir < neigh_shape.faces.size()) {
							int neigh_occupancy = neigh_shape.faces[opp_dir].face_occupancy;
							if (occupancy_fits(face.face_occupancy, neigh_occupancy)) {
								continue; // Skip this face
							}
						}
					}
				}
			}

			// UV Calculation
			Vector2 uv_offset = (du * (float)tx) + (dv * (float)(FACE_UV_COLGROUP_SIZE * ty + face.tile_voffset));
			
			std::vector<Vector2> *uv_ptr = nullptr;
			auto it = uv_patterns.find(face.uv_name);
			if (it != uv_patterns.end()) {
				uv_ptr = &it->second;
			}

			// Triangulate
			for (size_t tri_start = 0; tri_start < face.indices.size(); tri_start += 3) {
				// Record source for raycasting
				Array info;
				info.push_back(voxel_index);
				info.push_back((int)face_idx);
				tri_voxel_info.push_back(info);

				int i0 = face.indices[tri_start + 0];
				int i1 = face.indices[tri_start + 1];
				int i2 = face.indices[tri_start + 2];

				Vector3 v0_local = cached_wobbled_local_verts[i0];
				Vector3 v1_local = cached_wobbled_local_verts[i1];
				Vector3 v2_local = cached_wobbled_local_verts[i2];

				final_vertices.push_back(v0_local + v_vec);
				final_vertices.push_back(v1_local + v_vec);
				final_vertices.push_back(v2_local + v_vec);

				final_normals_smoothed.push_back(cached_vertex_colors[i0]);
				final_normals_smoothed.push_back(cached_vertex_colors[i1]);
				final_normals_smoothed.push_back(cached_vertex_colors[i2]);

				// Face Normal
				Vector3 edge1 = v1_local - v0_local;
				Vector3 edge2 = v2_local - v0_local;
				Vector3 face_norm = -edge1.cross(edge2).normalized();

				final_normals.push_back(face_norm);
				final_normals.push_back(face_norm);
				final_normals.push_back(face_norm);

				if (uv_ptr && (tri_start + 2 < uv_ptr->size())) {
					final_uvs.push_back((*uv_ptr)[tri_start + 0] + uv_offset);
					final_uvs.push_back((*uv_ptr)[tri_start + 1] + uv_offset);
					final_uvs.push_back((*uv_ptr)[tri_start + 2] + uv_offset);
				} else {
					final_uvs.push_back(Vector2());
					final_uvs.push_back(Vector2());
					final_uvs.push_back(Vector2());
				}
			}
		}
	}

	Array mesh_arrays;
	mesh_arrays.resize(Mesh::ARRAY_MAX);
	mesh_arrays[Mesh::ARRAY_VERTEX] = final_vertices;
	mesh_arrays[Mesh::ARRAY_NORMAL] = final_normals;
	mesh_arrays[Mesh::ARRAY_COLOR] = final_normals_smoothed;
	mesh_arrays[Mesh::ARRAY_TEX_UV] = final_uvs;

	Dictionary result;
	result["mesh_arrays"] = mesh_arrays;
	result["tri_voxel_info"] = tri_voxel_info;
	
	return result;
}

void VoxelMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize_noise", "seed"), &VoxelMesher::initialize_noise);
	ClassDB::bind_method(D_METHOD("set_texture_dimensions", "width", "height"), &VoxelMesher::set_texture_dimensions);
	ClassDB::bind_method(D_METHOD("parse_shapes", "gd_database", "gd_uv_patterns"), &VoxelMesher::parse_shapes);
	ClassDB::bind_method(D_METHOD("generate_chunk_mesh", "chunk_coord", "voxels", "voxel_properties", "layer_visibility", "size_x", "size_y", "size_z"), &VoxelMesher::generate_chunk_mesh);
}


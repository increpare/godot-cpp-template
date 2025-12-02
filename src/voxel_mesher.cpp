#include "voxel_mesher.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstring>
#include <cstdint>
#include <cmath>

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

// Ported from Shapes.gd - optimized with early returns
static inline bool occupancy_fits(int subject, int container) {
	// Early exit for common cases
	if (subject == OCCUPANCY_EMPTY) {
		return true;
	}
	if (container == OCCUPANCY_EMPTY) {
		return false;
	}
	if (subject == container) {
		return true;
	}
	// QUAD can contain triangles and quads
	if (container == OCCUPANCY_QUAD) {
		return (subject >= OCCUPANCY_TRI0 && subject <= OCCUPANCY_QUAD);
	}
	// For triangles, they must match exactly
	return false;
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
	
	std::map<String, int> pattern_name_to_index;

	// Parse UV patterns
	Array keys = gd_uv_patterns.keys();
	for (int i = 0; i < keys.size(); i++) {
		String key = keys[i];
		Array uvs = gd_uv_patterns[key];
		std::vector<Vector2> uv_vec;
		for (int j = 0; j < uvs.size(); j++) {
			uv_vec.push_back(uvs[j]);
		}
		pattern_name_to_index[key] = uv_patterns.size();
		uv_patterns.push_back(uv_vec);
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

					String uv_name = uvs[face_idx];
					auto it = pattern_name_to_index.find(uv_name);
					if (it != pattern_name_to_index.end()) {
						fd.uv_pattern_index = it->second;
					} else {
						fd.uv_pattern_index = -1;
					}

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
	
	int voxel_count = voxels.size();

	// Output buffers - using std::vector for performance
	std::vector<Vector3> final_vertices;
	std::vector<Vector3> final_normals;
	std::vector<Color> final_normals_smoothed;
	std::vector<Vector2> final_uvs;
	
	// Tri-voxel info to return for raycasting/interaction logic
	// Each entry: [voxel_index_in_input_array, face_index]
	// OPTIMIZATION: Use PackedInt32Array to avoid thousands of small Array allocations
	PackedInt32Array tri_voxel_info;

	if (voxel_count == 0) {
		Dictionary result;
		result["mesh_arrays"] = Array(); 
		result["tri_voxel_info"] = tri_voxel_info;
		return result;
	}

	// Heuristic reservation
	int reserve_size = voxel_count * 24; 
	final_vertices.reserve(reserve_size);
	final_normals.reserve(reserve_size);
	final_normals_smoothed.reserve(reserve_size);
	final_uvs.reserve(reserve_size);
	// 2 ints per triangle (3 verts) -> approx 2/3 ints per vertex
	tri_voxel_info.resize(0); 

	// 1. Unpack Data Structures
	struct VoxelData {
		int16_t shape_type;
		int16_t tx, ty;
		int8_t rot;
		bool vflip;
		int8_t layer;
	};

	std::vector<VoxelData> unpacked_props;
	unpacked_props.reserve(voxel_count);

	std::vector<Vector3i> unpacked_voxels;
	unpacked_voxels.reserve(voxel_count);

	// OPTIMIZATION: Unpack data in a single pass, avoiding repeated Array access
	for (int i = 0; i < voxel_count; i++) {
		unpacked_voxels.push_back(voxels[i]);

		const Array &props = voxel_properties[i];
		VoxelData vd;
		// Direct access without bounds checking (assumes valid data)
		vd.shape_type = (int16_t)(int)props[0];
		vd.tx = (int16_t)(int)props[1];
		vd.ty = (int16_t)(int)props[2];
		vd.rot = (int8_t)(int)props[3];
		vd.vflip = (bool)props[4];
		vd.layer = (int8_t)(int)props[5];
		unpacked_props.push_back(vd);
	}

	std::vector<bool> layers_vis;
	layers_vis.reserve(layer_visibility.size());
	for(int i=0; i<layer_visibility.size(); ++i) {
		layers_vis.push_back(layer_visibility[i]);
	}

	// Grid Cache
	std::vector<int> grid_cache(size_x * size_y * size_z, -1);
	
	const Vector3i offset = Vector3i(chunk_coord.x * size_x, chunk_coord.y * size_y, chunk_coord.z * size_z);
	const int stride_y = size_x;
	const int stride_z = size_x * size_y;

	// Populate grid cache - optimized bounds checking
	for (int i = 0; i < voxel_count; i++) {
		const Vector3i &v = unpacked_voxels[i];
		const int lx = v.x - offset.x;
		const int ly = v.y - offset.y;
		const int lz = v.z - offset.z;
		
		// Single bounds check using unsigned comparison trick
		if ((unsigned)lx < (unsigned)size_x && (unsigned)ly < (unsigned)size_y && (unsigned)lz < (unsigned)size_z) {
			grid_cache[lx + ly * stride_y + lz * stride_z] = i;
		}
	}

	// Temporary buffers
	std::vector<Vector3> cached_wobbled_local_verts;
	std::vector<Color> cached_vertex_colors;
	// Reserve some space to avoid reallocations
	cached_wobbled_local_verts.reserve(256);
	cached_vertex_colors.reserve(256);

	FastNoiseLite *n1 = noise1.ptr();
	FastNoiseLite *n2 = noise2.ptr();
	FastNoiseLite *n3 = noise3.ptr();

	for (int voxel_index = 0; voxel_index < voxel_count; voxel_index++) {
		const VoxelData &props = unpacked_props[voxel_index];

		if (props.layer >= (int)layers_vis.size() || !layers_vis[props.layer]) {
			continue;
		}

		if (props.shape_type < 0 || props.shape_type >= (int)shape_database.size()) continue;
		const auto &rots = shape_database[props.shape_type];
		if (props.rot < 0 || props.rot >= (int)rots.size()) continue;
		const auto &flips = rots[props.rot];
		int vflip_index = props.vflip ? 1 : 0;
		if (vflip_index < 0 || vflip_index >= (int)flips.size()) continue;
		const ShapeVariant &shape_data = flips[vflip_index];

		// LAZY CALCULATION: Don't calculate noise unless we actually render a face
		bool wobbled_calculated = false;

		const Vector3i &voxel = unpacked_voxels[voxel_index];
		const Vector3 v_vec(voxel);
		const int local_x = voxel.x - offset.x;
		const int local_y = voxel.y - offset.y;
		const int local_z = voxel.z - offset.z;

		for (size_t face_idx = 0; face_idx < shape_data.faces.size(); face_idx++) {
			const FaceData &face = shape_data.faces[face_idx];
			if (face.indices.empty()) continue;

			// Neighbor check - optimized bounds checking
			if (face.occupy_face && face.face_occupancy != OCCUPANCY_EMPTY) {
				const Vector3i &dir_offset = DIR_OFFSETS[face_idx];
				const int nlx = local_x + dir_offset.x;
				const int nly = local_y + dir_offset.y;
				const int nlz = local_z + dir_offset.z;

				// Use unsigned comparison for faster bounds checking (single comparison per axis)
				if ((unsigned)nlx < (unsigned)size_x && (unsigned)nly < (unsigned)size_y && (unsigned)nlz < (unsigned)size_z) {
					const int n_idx = grid_cache[nlx + nly * stride_y + nlz * stride_z];
					if (n_idx != -1) {
						const VoxelData &n_props = unpacked_props[n_idx];
						
						if (n_props.shape_type >= 0 && n_props.shape_type < (int)shape_database.size()) {
							const int n_vflip_index = n_props.vflip ? 1 : 0;
							const ShapeVariant &neigh_shape = shape_database[n_props.shape_type][n_props.rot][n_vflip_index];
							const int opp_dir = OPPOSITE_DIR[face_idx];
							if (opp_dir < (int)neigh_shape.faces.size()) {
								const int neigh_occupancy = neigh_shape.faces[opp_dir].face_occupancy;
								if (occupancy_fits(face.face_occupancy, neigh_occupancy)) {
									continue; // Skip this face
								}
							}
						}
					}
				}
			}

			// We are going to render this face, ensure vertices are ready
			if (!wobbled_calculated) {
				cached_wobbled_local_verts.clear();
				cached_vertex_colors.clear();
				cached_wobbled_local_verts.reserve(shape_data.vertices.size());
				cached_vertex_colors.reserve(shape_data.vertices.size());

				// OPTIMIZATION: Batch noise calculations and use fast normalized approximation
				const size_t vert_count = shape_data.vertices.size();
				for (size_t i = 0; i < vert_count; i++) {
					const Vector3 &base_local = shape_data.vertices[i];
					Vector3 world_pos = base_local + v_vec;

					// Single noise call per component (already optimized in FastNoiseLite)
					const float nx = n1->get_noise_3dv(world_pos) * 0.1f;
					const float ny = n2->get_noise_3dv(world_pos) * 0.1f;
					const float nz = n3->get_noise_3dv(world_pos) * 0.1f;

					const Vector3 wobbled_local = base_local + Vector3(nx, ny, nz);
					cached_wobbled_local_verts.push_back(wobbled_local);

					// OPTIMIZATION: Fast normalized using length_squared to avoid sqrt when possible
					// For color calculation, we can use a faster approximation
					const float len_sq = wobbled_local.length_squared();
					if (len_sq > 0.0001f) {
						const float inv_len = 1.0f / std::sqrt(len_sq);
						const Vector3 ns = wobbled_local * inv_len;
						cached_vertex_colors.push_back(Color(
							(ns.x + 1.0f) * 0.5f,
							(ns.y + 1.0f) * 0.5f,
							(ns.z + 1.0f) * 0.5f
						));
					} else {
						cached_vertex_colors.push_back(Color(0.5f, 0.5f, 0.5f));
					}
				}
				wobbled_calculated = true;
			}

			// UV Calculation - pre-compute once per face
			const Vector2 uv_offset = (du * (float)props.tx) + (dv * (float)(FACE_UV_COLGROUP_SIZE * props.ty + face.tile_voffset));
			
			const std::vector<Vector2> *uv_ptr = nullptr;
			if (face.uv_pattern_index >= 0 && face.uv_pattern_index < (int)uv_patterns.size()) {
				uv_ptr = &uv_patterns[face.uv_pattern_index];
			}

			// Triangulate - optimized inner loop
			const size_t indices_size = face.indices.size();
			for (size_t tri_start = 0; tri_start < indices_size; tri_start += 3) {
				// OPTIMIZATION: Push integers directly instead of allocating Arrays
				tri_voxel_info.push_back(voxel_index);
				tri_voxel_info.push_back((int)face_idx);

				const int i0 = face.indices[tri_start + 0];
				const int i1 = face.indices[tri_start + 1];
				const int i2 = face.indices[tri_start + 2];

				const Vector3 &v0_local = cached_wobbled_local_verts[i0];
				const Vector3 &v1_local = cached_wobbled_local_verts[i1];
				const Vector3 &v2_local = cached_wobbled_local_verts[i2];

				// Pre-compute world positions
				const Vector3 v0_world = v0_local + v_vec;
				const Vector3 v1_world = v1_local + v_vec;
				const Vector3 v2_world = v2_local + v_vec;

				final_vertices.push_back(v0_world);
				final_vertices.push_back(v1_world);
				final_vertices.push_back(v2_world);

				final_normals_smoothed.push_back(cached_vertex_colors[i0]);
				final_normals_smoothed.push_back(cached_vertex_colors[i1]);
				final_normals_smoothed.push_back(cached_vertex_colors[i2]);

				// Face Normal - optimized calculation
				const Vector3 edge1 = v1_local - v0_local;
				const Vector3 edge2 = v2_local - v0_local;
				Vector3 cross = edge1.cross(edge2);
				const float len_sq = cross.length_squared();
				if (len_sq > 0.0001f) {
					cross *= (1.0f / std::sqrt(len_sq));
				}
				const Vector3 face_norm = -cross;

				final_normals.push_back(face_norm);
				final_normals.push_back(face_norm);
				final_normals.push_back(face_norm);

				// UV coordinates
				if (uv_ptr && (tri_start + 2 < uv_ptr->size())) {
					final_uvs.push_back((*uv_ptr)[tri_start + 0] + uv_offset);
					final_uvs.push_back((*uv_ptr)[tri_start + 1] + uv_offset);
					final_uvs.push_back((*uv_ptr)[tri_start + 2] + uv_offset);
				} else {
					final_uvs.push_back(uv_offset);
					final_uvs.push_back(uv_offset);
					final_uvs.push_back(uv_offset);
				}
			}
		}
	}

	// Bulk convert to PackedArrays
	PackedVector3Array p_vertices;
	p_vertices.resize(final_vertices.size());
	if (!final_vertices.empty()) {
		memcpy(p_vertices.ptrw(), final_vertices.data(), final_vertices.size() * sizeof(Vector3));
	}

	PackedVector3Array p_normals;
	p_normals.resize(final_normals.size());
	if (!final_normals.empty()) {
		memcpy(p_normals.ptrw(), final_normals.data(), final_normals.size() * sizeof(Vector3));
	}

	PackedColorArray p_colors;
	p_colors.resize(final_normals_smoothed.size());
	if (!final_normals_smoothed.empty()) {
		memcpy(p_colors.ptrw(), final_normals_smoothed.data(), final_normals_smoothed.size() * sizeof(Color));
	}

	PackedVector2Array p_uvs;
	p_uvs.resize(final_uvs.size());
	if (!final_uvs.empty()) {
		memcpy(p_uvs.ptrw(), final_uvs.data(), final_uvs.size() * sizeof(Vector2));
	}

	Array mesh_arrays;
	mesh_arrays.resize(Mesh::ARRAY_MAX);
	mesh_arrays[Mesh::ARRAY_VERTEX] = p_vertices;
	mesh_arrays[Mesh::ARRAY_NORMAL] = p_normals;
	mesh_arrays[Mesh::ARRAY_COLOR] = p_colors;
	mesh_arrays[Mesh::ARRAY_TEX_UV] = p_uvs;

	Ref<ArrayMesh> array_mesh;
	array_mesh.instantiate();


	array_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, mesh_arrays);

	Dictionary result;
	result["arraymesh"] = array_mesh;
	result["tri_voxel_info"] = tri_voxel_info;
	
	return result;
}

Ref<ArrayMesh> VoxelMesher::generate_simplified_mesh(
		const Vector3i &chunk_coord,
		const Array &voxels,
		int size_x, int size_y, int size_z) {

	int limit_x = size_x;
	int limit_y = size_y;
	int limit_z = size_z;

	std::vector<uint8_t> solid_array(limit_x * limit_y * limit_z, 0);

	Vector3i offset(chunk_coord.x * size_x, chunk_coord.y * size_y, chunk_coord.z * size_z);

	int stride_x = 1;
	int stride_y = limit_x;
	int stride_z = limit_x * limit_y;
	int strides[3] = {stride_x, stride_y, stride_z};

	int voxel_count = voxels.size();
	for (int i = 0; i < voxel_count; i++) {
		Vector3i v = voxels[i];
		int lx = v.x - offset.x;
		int ly = v.y - offset.y;
		int lz = v.z - offset.z;

		if (lx >= 0 && lx < limit_x && ly >= 0 && ly < limit_y && lz >= 0 && lz < limit_z) {
			solid_array[lx + ly * stride_y + lz * stride_z] = 1;
		}
	}

	PackedVector3Array vertices;
	PackedVector3Array normals;

	int dims[3] = {limit_x, limit_y, limit_z};

	for (int axis = 0; axis < 3; axis++) {
		int u_axis = (axis + 1) % 3;
		int v_axis = (axis + 2) % 3;

		Vector3i axis_dir;
		axis_dir[axis] = 1;

		int dim_main = dims[axis];
		int dim_u = dims[u_axis];
		int dim_v = dims[v_axis];

		int s_main = strides[axis];
		int s_u = strides[u_axis];
		int s_v = strides[v_axis];

		std::vector<bool> mask(dim_u * dim_v);

		int directions[2] = {-1, 1};
		for (int d_idx = 0; d_idx < 2; d_idx++) {
			int direction = directions[d_idx];
			Vector3 normal_vec = Vector3(axis_dir) * (float)direction;
			int neighbor_offset = s_main * direction;

			for (int i = 0; i < dim_main; i++) {
				// 1. Generate mask
				bool neighbor_in_bounds = (i + direction >= 0 && i + direction < dim_main);
				int n = 0;
				int base_idx = i * s_main;

				for (int v = 0; v < dim_v; v++) {
					int row_idx = base_idx + v * s_v;
					for (int u = 0; u < dim_u; u++) {
						int idx = row_idx + u * s_u;
						bool current_solid = (solid_array[idx] == 1);
						bool neighbor_solid = false;
						if (neighbor_in_bounds) {
							neighbor_solid = (solid_array[idx + neighbor_offset] == 1);
						}
						
						mask[n] = current_solid && !neighbor_solid;
						n++;
					}
				}

				// 2. Greedy merge
				n = 0;
				for (int v = 0; v < dim_v; v++) {
					for (int u = 0; u < dim_u; u++) {
						if (mask[n]) {
							// Start of a quad
							int width = 1;
							while (u + width < dim_u && mask[n + width]) {
								width++;
							}

							int height = 1;
							bool done = false;
							while (v + height < dim_v) {
								for (int w = 0; w < width; w++) {
									if (!mask[n + w + height * dim_u]) {
										done = true;
										break;
									}
								}
								if (done) {
									break;
								}
								height++;
							}

							// Add quad vertices
							int pos_on_axis = i + (direction == 1 ? 1 : 0);

							Vector3 v0;
							v0[axis] = (float)pos_on_axis;
							v0[u_axis] = (float)u;
							v0[v_axis] = (float)v;

							Vector3 v1 = v0;
							v1[u_axis] += (float)width;

							Vector3 v2 = v0;
							v2[u_axis] += (float)width;
							v2[v_axis] += (float)height;

							Vector3 v3 = v0;
							v3[v_axis] += (float)height;

							Vector3 offset_vec((float)offset.x, (float)offset.y, (float)offset.z);

							Vector3 p0 = v0 + offset_vec;
							Vector3 p1 = v1 + offset_vec;
							Vector3 p2 = v2 + offset_vec;
							Vector3 p3 = v3 + offset_vec;

							if (direction == 1) {
								vertices.push_back(p0);
								vertices.push_back(p3);
								vertices.push_back(p2);

								vertices.push_back(p0);
								vertices.push_back(p2);
								vertices.push_back(p1);
							} else {
								vertices.push_back(p0);
								vertices.push_back(p1);
								vertices.push_back(p2);

								vertices.push_back(p0);
								vertices.push_back(p2);
								vertices.push_back(p3);
							}

							for (int k = 0; k < 6; k++) {
								normals.push_back(normal_vec);
							}

							// Clear mask
							for (int h = 0; h < height; h++) {
								for (int w = 0; w < width; w++) {
									mask[n + w + h * dim_u] = false;
								}
							}
						}
						n++;
					}
				}
			}
		}
	}

	if (vertices.size() == 0) {
		return Ref<ArrayMesh>();
	}

	Ref<ArrayMesh> mesh;
	mesh.instantiate();

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;

	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);

	return mesh;
}

void VoxelMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize_noise", "seed"), &VoxelMesher::initialize_noise);
	ClassDB::bind_method(D_METHOD("set_texture_dimensions", "width", "height"), &VoxelMesher::set_texture_dimensions);
	ClassDB::bind_method(D_METHOD("parse_shapes", "gd_database", "gd_uv_patterns"), &VoxelMesher::parse_shapes);
	ClassDB::bind_method(D_METHOD("generate_chunk_mesh", "chunk_coord", "voxels", "voxel_properties", "layer_visibility", "size_x", "size_y", "size_z"), &VoxelMesher::generate_chunk_mesh);
	ClassDB::bind_method(D_METHOD("generate_simplified_mesh", "chunk_coord", "voxels", "size_x", "size_y", "size_z"), &VoxelMesher::generate_simplified_mesh);
}

#include "voxel_mesher.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <cstring>
#include <cstdint>
#include <cmath>
#include <algorithm>


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
	
	// Cache noise pointers once - reused across all 195 chunk generations!
	cached_noise1 = noise1.ptr();
	cached_noise2 = noise2.ptr();
	cached_noise3 = noise3.ptr();
	
	// Initialize cached dimensions to invalid values
	cached_size_x = cached_size_y = cached_size_z = -1;
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
	// Clear direct array lookup - initialize all entries as invalid
	for (int i = 0; i < 256; i++) {
		shape_lookup_valid[i] = false;
		shape_lookup_array[i] = nullptr;
		// Initialize face occupancies to EMPTY for safety (flattened indexing)
		for (int face_dir = 0; face_dir < 6; face_dir++) {
			face_occupancy_cache[i * 6 + face_dir] = OCCUPANCY_EMPTY;
		}
	}
	
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

	// Parse Shape Database - store directly into flattened array
	// Key format: shape_type | (rotation << 4) | (vflip << 6)
	// Encodes all combinations in a single byte (shape_type: 0-12, rotation: 0-3, vflip: 0-1)
	for (int i = 0; i < gd_database.size(); i++) {
		Array shape_rots_arr = gd_database[i];
		
		for (int r = 0; r < shape_rots_arr.size(); r++) {
			Array shape_flips_arr = shape_rots_arr[r];

			for (int f = 0; f < shape_flips_arr.size(); f++) {
				Dictionary shape_dict = shape_flips_arr[f];
				uint8_t key = ((uint8_t)i) | ((uint8_t)r << 4) | ((uint8_t)f << 6);
				
				ShapeVariant &sv = shape_database[key];

				// Vertices
				Array verts = shape_dict["vertices"];
				sv.vertices.clear();
				for (int v = 0; v < verts.size(); v++) {
					sv.vertices.push_back(verts[v]);
				}

				// Faces
				Array faces = shape_dict["faces"];
				Array uvs = shape_dict["uvs"];
				Array voffsets = shape_dict["face_tile_voffset"];
				Array occupyface = shape_dict["occupyface"];
				Array face_occupancy = shape_dict["face_occupancy"];

				sv.faces.clear();
				for (int face_idx = 0; face_idx < faces.size(); face_idx++) {
					FaceData fd;
					
					// Indices
					Array indices = faces[face_idx];
					fd.indices.clear();
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

				// Build direct array lookup for O(1) shape access with zero overhead!
				shape_lookup_array[key] = &shape_database[key];
				shape_lookup_valid[key] = true;
				
				// Pre-cache face occupancies for all 6 faces - eliminates shape->faces[dir] indirection
				const size_t face_count = sv.faces.size();
				for (int face_dir = 0; face_dir < 6; face_dir++) {
					if (face_dir < (int)face_count) {
						face_occupancy_cache[key * 6 + face_dir] = (int8_t)sv.faces[face_dir].face_occupancy;
					} else {
						face_occupancy_cache[key * 6 + face_dir] = OCCUPANCY_EMPTY;
					}
				}
			}
		}
	}
	
	// Pre-compute occupancy_fits lookup table - eliminates function call overhead
	// Map occupancy values (-1 to 6) to indices (0 to 7) by adding 1
	// occupancy_fits_table[subject+1][container+1] = true if subject fits in container
	for (int subject = -1; subject <= 6; subject++) {
		for (int container = -1; container <= 6; container++) {
			int sub_idx = subject + 1;
			int cont_idx = container + 1;
			
			bool fits = false;
			if (subject == OCCUPANCY_EMPTY) {
				fits = true;
			} else if (container == OCCUPANCY_EMPTY) {
				fits = false;
			} else if (subject == container) {
				fits = true;
			} else if (container == OCCUPANCY_QUAD) {
				fits = (subject >= OCCUPANCY_TRI0 && subject <= OCCUPANCY_QUAD);
			} else {
				fits = false;
			}
			
			occupancy_fits_table[sub_idx * 8 + cont_idx] = fits;
		}
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

// Fast inverse square root approximation (Quake III algorithm)
static inline float fast_inv_sqrt(float x) {
	union { float f; std::uint32_t i; } conv;
	conv.f = x;
	conv.i = 0x5f3759df - (conv.i >> 1);
	conv.f *= 1.5f - (x * 0.5f * conv.f * conv.f);
	return conv.f;
}

// Simple scalar helpers - SIMD overhead isn't worth it for small operations
static inline void cross_product_normalized(
	const float v0x, const float v0y, const float v0z,
	const float v1x, const float v1y, const float v1z,
	const float v2x, const float v2y, const float v2z,
	float &out_x, float &out_y, float &out_z,
	float norm_threshold) {
	
	// Calculate edges: e1 = v1 - v0, e2 = v2 - v0
	const float e1x = v1x - v0x;
	const float e1y = v1y - v0y;
	const float e1z = v1z - v0z;
	const float e2x = v2x - v0x;
	const float e2y = v2y - v0y;
	const float e2z = v2z - v0z;
	
	// Cross product: e1 × e2
	out_x = e1y * e2z - e1z * e2y;
	out_y = e1z * e2x - e1x * e2z;
	out_z = e1x * e2y - e1y * e2x;
	
	// Normalize using fast inverse sqrt
	const float len_sq = out_x * out_x + out_y * out_y + out_z * out_z;
	if (len_sq > norm_threshold) {
		const float inv_len = fast_inv_sqrt(len_sq);
		out_x *= -inv_len; // Negate for face normal
		out_y *= -inv_len;
		out_z *= -inv_len;
	} else {
		out_x = out_y = 0.0f;
		out_z = -1.0f; // Default normal
	}
}

Dictionary VoxelMesher::generate_chunk_mesh(
		const Vector3i &chunk_coord,
		const Array &voxels,
		const Array &voxel_properties,
		const Array &layer_visibility,
		int size_x, int size_y, int size_z) {
	
	const int voxel_count = voxels.size();

	// Early exit for empty chunks
	if (voxel_count == 0) {
		Dictionary result;
		result["arraymesh"] = nullptr;
		result["tri_voxel_info"] = PackedInt32Array();
		return result;
	}

	// Clear reusable output buffers (memory stays allocated)
	final_vertices.clear();
	final_normals.clear();
	final_normals_smoothed.clear();
	final_uvs.clear();
	
	// Tri-voxel info to return for raycasting/interaction logic
	PackedInt32Array tri_voxel_info;

	// Reserve space if needed (only grows, never shrinks)
	const int reserve_size = voxel_count * 32;
	if (final_vertices.capacity() < reserve_size) {
		final_vertices.reserve(reserve_size);
		final_normals.reserve(reserve_size);
		final_normals_smoothed.reserve(reserve_size);
		final_uvs.reserve(reserve_size);
	}
	tri_voxel_info.resize(0); 

	// 1. Unpack Data Structures - reuse member buffers
	unpacked_props.clear();
	unpacked_voxels.clear();
	
	if (unpacked_props.capacity() < voxel_count) {
		unpacked_props.reserve(voxel_count);
		unpacked_voxels.reserve(voxel_count);
	}

	// OPTIMIZATION: Unpack data in a single pass with minimal allocations
	for (int i = 0; i < voxel_count; i++) {
		unpacked_voxels.push_back(voxels[i]);

		const Array &props = voxel_properties[i];
		VoxelData vd;
		// Direct access - assumes valid data structure
		vd.shape_type = (int16_t)(int)props[0];
		vd.tx = (int16_t)(int)props[1];
		vd.ty = (int16_t)(int)props[2];
		vd.rot = (int8_t)(int)props[3];
		vd.vflip = (bool)props[4];
		vd.layer = (int8_t)(int)props[5];
		unpacked_props.push_back(vd);
	}

	// Layer visibility - convert once, reuse buffer
	const int layer_count = layer_visibility.size();
	layers_vis.clear();
	if (layers_vis.capacity() < layer_count) {
		layers_vis.reserve(layer_count);
	}
	for(int i = 0; i < layer_count; ++i) {
		layers_vis.push_back(layer_visibility[i]);
	}

	// Grid Cache - resize only if dimensions changed (they're constant, so this happens once)
	const int grid_size = size_x * size_y * size_z;
	if (cached_size_x != size_x || cached_size_y != size_y || cached_size_z != size_z) {
		grid_cache.resize(grid_size);
		cached_size_x = size_x;
		cached_size_y = size_y;
		cached_size_z = size_z;
	}
	
	// Clear grid cache (fill with -1)
	std::fill(grid_cache.begin(), grid_cache.end(), -1);
	
	const Vector3i offset(chunk_coord.x * size_x, chunk_coord.y * size_y, chunk_coord.z * size_z);
	const int stride_y = size_x;
	const int stride_z = size_x * size_y;

	// Populate grid cache - optimized bounds checking with single comparison
	for (int i = 0; i < voxel_count; i++) {
		const Vector3i &v = unpacked_voxels[i];
		const int lx = v.x - offset.x;
		const int ly = v.y - offset.y;
		const int lz = v.z - offset.z;
		
		// Single bounds check using unsigned comparison trick
		if ((unsigned)lx < (unsigned)size_x && 
		    (unsigned)ly < (unsigned)size_y && 
		    (unsigned)lz < (unsigned)size_z) {
			grid_cache[lx + ly * stride_y + lz * stride_z] = i;
		}
	}

	// ALGORITHMIC OPTIMIZATION: Pre-cache shape variant pointers to avoid repeated lookups
	// Reuse member buffer
	voxel_cache.clear();
	voxel_cache.resize(voxel_count);
	
	// Pre-cache all shape variants (one-time cost, eliminates repeated 3-level lookups)
	for (int voxel_index = 0; voxel_index < voxel_count; voxel_index++) {
		const VoxelData &props = unpacked_props[voxel_index];
		CachedVoxelInfo &cache_entry = voxel_cache[voxel_index];
		
		// Early exit for invisible layers
		if (props.layer >= layer_count || !layers_vis[props.layer]) {
			cache_entry.valid = false;
			continue;
		}

		// Validate and cache shape access using direct array lookup - single byte key!
		// Encoding: shape_type | (rotation << 4) | (vflip << 6) - fits in 8 bits
		uint8_t lookup_key = ((uint8_t)props.shape_type) | ((uint8_t)props.rot << 4) | ((props.vflip ? 1 : 0) << 6);
		
		// Direct array access - O(1) with zero hash overhead!
		if (!shape_lookup_valid[lookup_key]) {
			cache_entry.valid = false;
			continue;
		}
		
		// Cache the shape variant pointer - direct array access, fastest possible lookup!
		cache_entry.shape_ptr = shape_lookup_array[lookup_key];
		cache_entry.lookup_key = lookup_key; // Store for direct face occupancy cache access
		cache_entry.voxel_pos = unpacked_voxels[voxel_index];
		cache_entry.local_x = cache_entry.voxel_pos.x - offset.x;
		cache_entry.local_y = cache_entry.voxel_pos.y - offset.y;
		cache_entry.local_z = cache_entry.voxel_pos.z - offset.z;
		cache_entry.valid = true;
	}

	// Temporary buffers - reuse member buffers (cleared per voxel)
	cached_wobbled_local_verts.clear();
	cached_vertex_colors.clear();
	if (cached_wobbled_local_verts.capacity() < 512) {
		cached_wobbled_local_verts.reserve(512);
		cached_vertex_colors.reserve(512);
	}

	// Use cached noise pointers - no .ptr() calls needed!
	FastNoiseLite *n1 = cached_noise1;
	FastNoiseLite *n2 = cached_noise2;
	FastNoiseLite *n3 = cached_noise3;

	// Pre-compute constants
	const float noise_scale = 0.1f;
	const float half_scale = 0.5f;
	const float norm_threshold = 0.0001f;
	const float default_color = 0.5f;

	// Main voxel processing loop - single pass with lazy evaluation preserved
	for (int voxel_index = 0; voxel_index < voxel_count; voxel_index++) {
		const CachedVoxelInfo &cache_entry = voxel_cache[voxel_index];
		
		// Skip invalid/invisible voxels
		if (!cache_entry.valid) {
			continue;
		}

		const VoxelData &props = unpacked_props[voxel_index];
		const ShapeVariant &shape_data = *cache_entry.shape_ptr; // Direct cached access!

		// LAZY CALCULATION: Don't calculate noise unless we actually render a face
		bool wobbled_calculated = false;

		const Vector3 v_vec(cache_entry.voxel_pos.x, cache_entry.voxel_pos.y, cache_entry.voxel_pos.z);

		// Process faces
		const size_t face_count = shape_data.faces.size();
		for (size_t face_idx = 0; face_idx < face_count; face_idx++) {
			const FaceData &face = shape_data.faces[face_idx];
			const size_t indices_size = face.indices.size();
			if (indices_size == 0) continue;

			// Neighbor check - optimized with early exits and cached shape access
			if (face.occupy_face && face.face_occupancy != OCCUPANCY_EMPTY) {
				const Vector3i &dir_offset = DIR_OFFSETS[face_idx];
				const int nlx = cache_entry.local_x + dir_offset.x;
				const int nly = cache_entry.local_y + dir_offset.y;
				const int nlz = cache_entry.local_z + dir_offset.z;

				// Fast bounds check
				if ((unsigned)nlx < (unsigned)size_x && 
				    (unsigned)nly < (unsigned)size_y && 
				    (unsigned)nlz < (unsigned)size_z) {
					const int n_idx = grid_cache[nlx + nly * stride_y + nlz * stride_z];
					if (n_idx != -1 && voxel_cache[n_idx].valid) {
						const CachedVoxelInfo &n_cache = voxel_cache[n_idx];
						
						// Direct access to cached face occupancy - no shape->faces[dir] indirection!
						const int opp_dir = OPPOSITE_DIR[face_idx];
						const int neigh_occupancy = face_occupancy_cache[n_cache.lookup_key * 6 + opp_dir];
						
						// Direct lookup table access - eliminates function call overhead!
						const int sub_idx = face.face_occupancy + 1;
						const int cont_idx = neigh_occupancy + 1;
						if (occupancy_fits_table[sub_idx * 8 + cont_idx]) {
							continue; // Skip this face
						}
					}
				}
			}

			// Calculate wobbled vertices if needed (lazy evaluation)
			if (!wobbled_calculated) {
				cached_wobbled_local_verts.clear();
				cached_vertex_colors.clear();
				const size_t vert_count = shape_data.vertices.size();
				cached_wobbled_local_verts.reserve(vert_count);
				cached_vertex_colors.reserve(vert_count);

				// OPTIMIZATION: Batch noise calculations with fast normalization
				for (size_t i = 0; i < vert_count; i++) {
					const Vector3 &base_local = shape_data.vertices[i];
					
					// Direct member access for world position
					const Vector3 world_pos(
						base_local.x + v_vec.x,
						base_local.y + v_vec.y,
						base_local.z + v_vec.z
					);

					// Noise calculations
					const float nx = n1->get_noise_3dv(world_pos) * noise_scale;
					const float ny = n2->get_noise_3dv(world_pos) * noise_scale;
					const float nz = n3->get_noise_3dv(world_pos) * noise_scale;

					// Wobbled vertex
					const Vector3 wobbled_local(
						base_local.x + nx,
						base_local.y + ny,
						base_local.z + nz
					);
					cached_wobbled_local_verts.push_back(wobbled_local);

					// Fast normalized for color calculation using fast inverse sqrt
					const float len_sq = wobbled_local.length_squared();
					if (len_sq > norm_threshold) {
						const float inv_len = fast_inv_sqrt(len_sq);
						const float nsx = wobbled_local.x * inv_len;
						const float nsy = wobbled_local.y * inv_len;
						const float nsz = wobbled_local.z * inv_len;
						cached_vertex_colors.push_back(Color(
							(nsx + 1.0f) * half_scale,
							(nsy + 1.0f) * half_scale,
							(nsz + 1.0f) * half_scale
						));
					} else {
						cached_vertex_colors.push_back(Color(default_color, default_color, default_color));
					}
				}
				wobbled_calculated = true;
			}

			// UV Calculation - pre-compute once per face
			const float uv_tile_y = (float)(FACE_UV_COLGROUP_SIZE * props.ty + face.tile_voffset);
			const Vector2 uv_offset(
				du.x * (float)props.tx + dv.x * uv_tile_y,
				du.y * (float)props.tx + dv.y * uv_tile_y
			);
			
			const std::vector<Vector2> *uv_ptr = nullptr;
			if (face.uv_pattern_index >= 0 && face.uv_pattern_index < (int)uv_patterns.size()) {
				uv_ptr = &uv_patterns[face.uv_pattern_index];
			}

			// Triangulate
			for (size_t tri_start = 0; tri_start < indices_size; tri_start += 3) {
				// Store triangle info
				tri_voxel_info.push_back(voxel_index);
				tri_voxel_info.push_back((int)face_idx);

				const int i0 = face.indices[tri_start + 0];
				const int i1 = face.indices[tri_start + 1];
				const int i2 = face.indices[tri_start + 2];

				// Get vertices (references to avoid copies)
				const Vector3 &v0_local = cached_wobbled_local_verts[i0];
				const Vector3 &v1_local = cached_wobbled_local_verts[i1];
				const Vector3 &v2_local = cached_wobbled_local_verts[i2];

				// Simple scalar addition - SIMD overhead isn't worth it for 3 vectors
				final_vertices.push_back(v0_local + v_vec);
				final_vertices.push_back(v1_local + v_vec);
				final_vertices.push_back(v2_local + v_vec);

				// Vertex colors (already computed)
				final_normals_smoothed.push_back(cached_vertex_colors[i0]);
				final_normals_smoothed.push_back(cached_vertex_colors[i1]);
				final_normals_smoothed.push_back(cached_vertex_colors[i2]);

				// Face Normal - simple scalar cross product
				float cross_x, cross_y, cross_z;
				cross_product_normalized(
					v0_local.x, v0_local.y, v0_local.z,
					v1_local.x, v1_local.y, v1_local.z,
					v2_local.x, v2_local.y, v2_local.z,
					cross_x, cross_y, cross_z,
					norm_threshold
				);
				
				const Vector3 face_norm(cross_x, cross_y, cross_z);
				final_normals.push_back(face_norm);
				final_normals.push_back(face_norm);
				final_normals.push_back(face_norm);

				// UV coordinates - simple scalar addition
				if (uv_ptr && (tri_start + 2 < uv_ptr->size())) {
					const Vector2 &uv0 = (*uv_ptr)[tri_start + 0];
					const Vector2 &uv1 = (*uv_ptr)[tri_start + 1];
					const Vector2 &uv2 = (*uv_ptr)[tri_start + 2];
					
					final_uvs.push_back(uv0 + uv_offset);
					final_uvs.push_back(uv1 + uv_offset);
					final_uvs.push_back(uv2 + uv_offset);
				} else {
					final_uvs.push_back(uv_offset);
					final_uvs.push_back(uv_offset);
					final_uvs.push_back(uv_offset);
				}
			}
		}
	}

	// Bulk convert to PackedArrays using memcpy for maximum speed
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

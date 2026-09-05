#[compute]
#version 450
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) readonly buffer Slots { uint slot[]; };
layout(set = 0, binding = 1, std430) writeonly buffer Transforms { float result[]; };
// PackedVector3Array has a 12-byte stride, unlike std430 vec3 arrays (16 bytes).
layout(set = 0, binding = 2, std430) readonly buffer Positions { float position[]; };
layout(set = 0, binding = 3, std430) readonly buffer Headings { float heading[]; };
layout(push_constant, std430) uniform Params {
	vec4 row0;
	vec4 row1;
	vec4 row2;
	uint count;
	uint pad0;
	uint pad1;
	uint pad2;
} params;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= params.count) return;
	uint index = slot[i];
	float c = cos(heading[index]), s = sin(heading[index]);
	mat3 rotation = mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c));
	if (params.pad0 != 0u) {
		float cz=cos(heading[index]*0.5),sz=sin(heading[index]*0.5);
		rotation=mat3(1,0,0,0,c,s,0,-s,c)*mat3(cz,sz,0,-sz,cz,0,0,0,1);
	}
	mat3 local_basis = mat3(
		vec3(params.row0.x, params.row1.x, params.row2.x),
		vec3(params.row0.y, params.row1.y, params.row2.y),
		vec3(params.row0.z, params.row1.z, params.row2.z));
	mat3 basis = rotation * local_basis;
	vec3 location = vec3(position[index*3], position[index*3+1], position[index*3+2]);
	vec3 origin = location + rotation * vec3(params.row0.w, params.row1.w, params.row2.w);
	uint o = i * 12;
	result[o+0] = basis[0].x; result[o+1] = basis[1].x; result[o+2] = basis[2].x; result[o+3] = origin.x;
	result[o+4] = basis[0].y; result[o+5] = basis[1].y; result[o+6] = basis[2].y; result[o+7] = origin.y;
	result[o+8] = basis[0].z; result[o+9] = basis[1].z; result[o+10] = basis[2].z; result[o+11] = origin.z;
}

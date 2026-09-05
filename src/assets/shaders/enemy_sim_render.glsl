#[compute]
#version 450
layout(local_size_x=256) in;
struct Enemy { vec4 pose; vec4 motion; uvec4 meta; uvec4 vitals; };
struct Shot { vec4 pose; vec4 stats; uvec4 meta; };
struct Archetype { vec4 body; vec4 attack; uvec4 meta; };
layout(set=0,binding=0,std430) readonly buffer Enemies { Enemy enemies[]; };
layout(set=0,binding=1,std430) readonly buffer Slots { uint slots[]; };
layout(set=0,binding=2,std430) buffer Output { float output_data[]; };
layout(set=0,binding=3,std430) readonly buffer Shots { Shot shots[]; };
layout(set=0,binding=4,std430) readonly buffer Feedback { uvec2 feedback[]; };
layout(set=0,binding=5,std430) readonly buffer Archetypes { Archetype types[]; };
layout(push_constant,std430) uniform Params { vec4 r0;vec4 r1;vec4 r2;uint count;uint projectile;float time;uint colors; } p;
void main() {
    uint i=gl_GlobalInvocationID.x;if(i>=p.count)return;
    bool is_alive;vec3 position;float angle=0.0;uint stride=p.colors==1u?16u:12u;uint slot=0u;
    if(p.projectile==1u) {is_alive=shots[i].meta.x!=0u;position=vec3(shots[i].pose.x,8.0,shots[i].pose.y);}
    else {slot=slots[i];is_alive=enemies[slot].meta.x!=0u;position=enemies[slot].pose.xyz;angle=enemies[slot].pose.w;}
    uint offset=i*stride;
    for(uint n=0u;n<stride;n++)output_data[offset+n]=0.0;
    if(!is_alive)return;
    float c=cos(angle),s=sin(angle);
    mat3 rotation=mat3(vec3(c,0,-s),vec3(0,1,0),vec3(s,0,c));
    if(p.projectile==0u&&(types[enemies[slot].meta.y].meta.y&1u)!=0u) {
        float cz=cos(angle*0.5),sz=sin(angle*0.5);
        rotation=mat3(1,0,0,0,c,s,0,-s,c)*mat3(cz,sz,0,-sz,cz,0,0,0,1);
    }
    mat3 local=mat3(vec3(p.r0.x,p.r1.x,p.r2.x),vec3(p.r0.y,p.r1.y,p.r2.y),vec3(p.r0.z,p.r1.z,p.r2.z));
    mat3 basis=rotation*local;vec3 origin=position+rotation*vec3(p.r0.w,p.r1.w,p.r2.w);
    if(p.projectile==1u) {
        if((shots[i].meta.w&255u)==1u)basis*=3.2;
        else if(shots[i].meta.y==1u)basis*=3.0;
    }
    output_data[offset]=basis[0].x;output_data[offset+1u]=basis[1].x;output_data[offset+2u]=basis[2].x;output_data[offset+3u]=origin.x;
    output_data[offset+4u]=basis[0].y;output_data[offset+5u]=basis[1].y;output_data[offset+6u]=basis[2].y;output_data[offset+7u]=origin.y;
    output_data[offset+8u]=basis[0].z;output_data[offset+9u]=basis[1].z;output_data[offset+10u]=basis[2].z;output_data[offset+11u]=origin.z;
    if(p.colors==1u) {
        vec3 color=vec3(1);
        if(p.projectile==1u) {
            bool ally=shots[i].meta.y==1u;
            color=ally?vec3(0.2,1.0,0.8):vec3(1.0,0.2,0.1);
            if((shots[i].meta.w&255u)==1u)color=vec3(1,0.6,0.1);
        } else {
            float hp=uintBitsToFloat(enemies[slot].vitals.x)/max(0.001,uintBitsToFloat(enemies[slot].vitals.w));
            color=vec3(0.65+0.35*clamp(hp,0.0,1.0));
            float flash=clamp(1.0-(p.time-uintBitsToFloat(feedback[slot].x))/0.15,0.0,1.0);
            color=mix(color,vec3(2.0,1.2,0.6),flash);
        }
        for(uint n=0u;n<3u;n++)output_data[offset+12u+n]=color[n];output_data[offset+15u]=1.0;
    }
}

#[compute]
#version 450
layout(local_size_x = 256) in;

// Layout shared with EnemyGPUBackend; all structs have a 16-byte alignment.
struct Enemy { vec4 pose; vec4 motion; uvec4 meta; uvec4 vitals; };
struct Archetype { vec4 body; vec4 attack; uvec4 meta; };
struct Obstacle { vec4 rect; vec4 stats; uvec4 meta; };
struct Shot { vec4 pose; vec4 stats; uvec4 meta; };
struct Command { uvec4 meta; vec4 a; vec4 b; vec4 c; };
struct Query { vec4 origin; vec4 direction; uvec4 meta; };
struct QueryResult { uvec4 meta; vec4 pose; };
layout(set=0,binding=0,std430) buffer Enemies { Enemy enemies[]; };
layout(set=0,binding=1,std430) readonly buffer Archetypes { Archetype types[]; };
layout(set=0,binding=2,std430) readonly buffer Obstacles { Obstacle obstacles[]; };
layout(set=0,binding=3,std430) buffer ObstacleState { uvec2 obstacle_state[]; };
layout(set=0,binding=4,std430) buffer Shots { Shot shots[]; };
layout(set=0,binding=5,std430) buffer Grid { int grid[]; };
layout(set=0,binding=6,std430) readonly buffer Commands { Command commands[]; };
layout(set=0,binding=7,std430) readonly buffer Queries { Query queries[]; };
layout(set=0,binding=8,std430) buffer QueryResults { QueryResult results[]; };
layout(set=0,binding=9,std430) buffer Control { uint control[]; };
layout(set=0,binding=10,std430) buffer Report { uint report[]; };
layout(set=0,binding=11,std430) buffer Feedback { uvec2 feedback[]; }; // last hit time, accumulated damage
layout(set=0,binding=12,std430) buffer ShotHistory { uvec2 shot_history[]; }; // slot + generation
layout(set=0,binding=13,std430) buffer Separation { vec2 separation_delta[]; };
layout(push_constant,std430) uniform Params {
    uint pass_id; uint capacity; uint shot_capacity; uint command_count;
    uint obstacle_count; uint query_count; uint grid_side; float cell_size;
    vec4 planet; // xyz position, radius
    float delta; float max_radius; uint epoch; float time;
    vec4 separation; // maximum correction speed, padding, reserved, reserved
} p;
const uint OBSTACLE_MAX = 128u;
const uint QUERY_MAX = 256u;
const uint EVENT_MAX = 2048u;
const uint QUERY_OFFSET = 4u + OBSTACLE_MAX;
const uint EVENT_OFFSET = QUERY_OFFSET + QUERY_MAX * 8u;
const uint FEEDBACK_MAX = 128u;
const uint FEEDBACK_OFFSET = EVENT_OFFSET + EVENT_MAX * 8u;
const uint SHOT_HITS = 16u;
const float PI = 3.14159265358979323846;

vec2 unit(vec2 v) { float n=length(v); return n>0.000001?v/n:vec2(0); }
float angle_delta(float a,float b) { return mod(b-a+PI,2.0*PI)-PI; }
float rotate_towards(float a,float b,float amount) { return a+clamp(angle_delta(a,b),-amount,amount); }
bool alive(uint slot) { return enemies[slot].meta.x!=0u && uintBitsToFloat(enemies[slot].vitals.x)>0.0; }
bool obstacle_alive(uint i) { return obstacles[i].meta.x!=0u && uintBitsToFloat(obstacle_state[i].x)>0.0; }
uint cells() { return p.grid_side*p.grid_side; }
ivec2 cell(vec2 at) { return clamp(ivec2(floor(at/p.cell_size))+ivec2(p.grid_side/2u),ivec2(0),ivec2(p.grid_side-1u)); }
int head(ivec2 at) { return grid[at.y*int(p.grid_side)+at.x]; }

float circle_hit(vec2 a,vec2 b,vec2 center,float radius) {
    vec2 offset=a-center, d=b-a;
    float c=dot(offset,offset)-radius*radius;
    if(c<=0.0)return 0.0;
    float aa=dot(d,d); if(aa<0.000001)return -1.0;
    float bb=dot(offset,d), discriminant=bb*bb-aa*c;
    if(discriminant<0.0)return -1.0;
    float t=(-bb-sqrt(discriminant))/aa;
    return t>=0.0&&t<=1.0?t:-1.0;
}
float rect_hit(vec2 a,vec2 b,uint i,float radius) {
    float c=cos(obstacles[i].stats.x),s=sin(obstacles[i].stats.x);
    mat2 rotation=mat2(c,s,-s,c);
    a=rotation*(a-obstacles[i].rect.xy); b=rotation*(b-obstacles[i].rect.xy);
    vec2 half_size=obstacles[i].rect.zw+vec2(radius),d=b-a;
    float low=0.0,high=1.0;
    for(int axis=0;axis<2;axis++) {
        if(abs(d[axis])<0.000001) { if(abs(a[axis])>half_size[axis])return -1.0; }
        else {
            float t1=(-half_size[axis]-a[axis])/d[axis], t2=(half_size[axis]-a[axis])/d[axis];
            low=max(low,min(t1,t2)); high=min(high,max(t1,t2)); if(low>high)return -1.0;
        }
    }
    return low;
}
int first_obstacle(vec2 a,vec2 b,float radius,out float fraction) {
    int found=-1; fraction=2.0;
    for(uint i=0u;i<p.obstacle_count;i++) if(obstacle_alive(i)) {
        float t=rect_hit(a,b,i,radius); if(t>=0.0&&t<fraction) { fraction=t; found=int(i); }
    }
    return found;
}
// CAS float atomics work without optional shader_atomic_float support.
void damage_enemy(uint slot,float damage) {
    uint expected=atomicAdd(enemies[slot].vitals.x,0u);
    for(;;) {
        float hp=uintBitsToFloat(expected); if(hp<=0.0)return;
        uint next=floatBitsToUint(max(0.0,hp-damage));
        uint previous=atomicCompSwap(enemies[slot].vitals.x,expected,next);
        if(previous==expected)break; expected=previous;
    }
    atomicExchange(feedback[slot].x,floatBitsToUint(p.time));
    expected=atomicAdd(feedback[slot].y,0u);
    for(;;) {
        uint previous=atomicCompSwap(feedback[slot].y,expected,floatBitsToUint(uintBitsToFloat(expected)+damage));
        if(previous==expected)return; expected=previous;
    }
}
void damage_obstacle(uint i,float damage) {
    uint expected=atomicAdd(obstacle_state[i].x,0u);
    for(;;) {
        float hp=uintBitsToFloat(expected); if(hp<=0.0)return;
        uint previous=atomicCompSwap(obstacle_state[i].x,expected,floatBitsToUint(max(0.0,hp-damage)));
        if(previous==expected)break; expected=previous;
    }
    expected=atomicAdd(obstacle_state[i].y,0u);
    for(;;) {
        uint previous=atomicCompSwap(obstacle_state[i].y,expected,floatBitsToUint(uintBitsToFloat(expected)+damage));
        if(previous==expected)return; expected=previous;
    }
}
void damage_planet(float damage) {
    uint expected=atomicAdd(control[0],0u);
    for(;;) {
        uint previous=atomicCompSwap(control[0],expected,floatBitsToUint(uintBitsToFloat(expected)+damage));
        if(previous==expected)return; expected=previous;
    }
}
bool shoot(vec2 origin,vec2 direction,float damage,float speed,float lifetime,uint team,float radius,uint pierce,uint kind) {
    uint available=atomicAdd(control[2],0u);
    for(;;) {
        if(available==0u) { atomicAdd(control[1],1u); return false; }
        uint previous=atomicCompSwap(control[2],available,available-1u);
        if(previous==available)break; available=previous;
    }
    uint slot=control[16u+available-1u];
    shots[slot].pose=vec4(origin,unit(direction));
    shots[slot].stats=vec4(speed,damage,lifetime,radius);
    shots[slot].meta=uvec4(1u,team,0u,((min(pierce,SHOT_HITS-1u)+1u)<<8u)|kind);
    return true;
}
int nearest_enemy_filtered(vec2 a,vec2 b,float width,out float best,int shot) {
    ivec2 low=cell(min(a,b)-vec2(width+p.max_radius)),high=cell(max(a,b)+vec2(width+p.max_radius));
    int result=-1; best=2.0;
    for(int y=low.y;y<=high.y;y++)for(int x=low.x;x<=high.x;x++) {
        int slot=head(ivec2(x,y));
        while(slot>=0) {
            bool seen=false;
            if(shot>=0)for(uint h=0u;h<shots[shot].meta.z;h++) {
                uvec2 previous=shot_history[uint(shot)*SHOT_HITS+h];
                if(previous.x==uint(slot)&&previous.y==enemies[slot].meta.z) {seen=true;break;}
            }
            if(!seen&&alive(uint(slot))) {
                float enemy_radius=(shot>=0&&(shots[shot].meta.w&255u)==1u)?0.0:types[enemies[slot].meta.y].body.z;
                float t=circle_hit(a,b,enemies[slot].pose.xz,width+enemy_radius);
                if(t>=0.0&&(t<best||(t==best&&(result<0||slot<result)))) {best=t;result=slot;}
            }
            slot=grid[cells()+uint(slot)];
        }
    }
    return result;
}
int nearest_enemy(vec2 a,vec2 b,float width,out float best) {return nearest_enemy_filtered(a,b,width,best,-1);}
void allocation_commands() {
    // Sequential commands preserve remove/spawn ordering when a slot is reused.
    for(uint n=0u;n<p.command_count;n++) {
        Command c=commands[n]; uint i=c.meta.y;
        if(c.meta.x==1u && i<p.capacity) {
            enemies[i].pose=c.a;
            enemies[i].motion=vec4(0);
            enemies[i].meta=uvec4(uint(c.b.y),c.meta.w,c.meta.z,0u);
            enemies[i].vitals=uvec4(floatBitsToUint(c.b.x),0u,0u,floatBitsToUint(c.b.x));
            feedback[i]=uvec2(floatBitsToUint(-100.0),0u);
        } else if(c.meta.x==2u && i<p.capacity && enemies[i].meta.z==c.meta.z) {
            enemies[i].meta.x=0u; enemies[i].vitals.z=0u;
        }
    }
}
void move_enemy(uint i) {
    if(!alive(i))return;
    Archetype data=types[enemies[i].meta.y];
    vec2 origin=enemies[i].pose.xz;
    if(data.meta.x==0u) {
        vec2 direction=unit(p.planet.xz-origin);
        for(uint o=0u;o<p.obstacle_count;o++)if(obstacle_alive(o)) {
            vec2 offset=origin-obstacles[o].rect.xy;
            float safe=length(obstacles[o].rect.zw)+data.body.z+8.0;
            if(dot(offset,offset)<(safe+60.0)*(safe+60.0)&&dot(offset,direction)<0.0) {
                vec2 radial=unit(offset),tangent=vec2(-radial.y,radial.x)*(i%2u==0u?1.0:-1.0);
                direction=unit(tangent+radial*max(0.0,(safe-length(offset))/20.0));break;
            }
        }
        float speed=data.body.w;
        if(p.time-p.delta-uintBitsToFloat(feedback[i].x)<uintBitsToFloat(data.meta.z))speed*=uintBitsToFloat(data.meta.w);
        vec2 destination=origin+direction*speed*p.delta;
        float fraction; int hit=first_obstacle(origin,destination,data.body.z,fraction);
        if(hit>=0) {
            if(enemies[i].vitals.y!=uint(hit)+1u)damage_obstacle(uint(hit),data.body.y);
            enemies[i].vitals.y=uint(hit)+1u;destination=origin;
        } else enemies[i].vitals.y=0u;
        enemies[i].pose.xz=destination;
        if((data.meta.y&4u)!=0u) {
            vec2 facing=p.planet.xz-destination;
            if(dot(facing,facing)>0.000001)enemies[i].pose.w=atan(facing.x,facing.y);
        } else enemies[i].pose.w+=data.attack.w*p.delta;
        enemies[i].motion.yz=direction*speed;
        float impact_radius=p.planet.w+((data.meta.y&2u)!=0u?0.0:data.body.z);
        if(circle_hit(origin,destination,p.planet.xz,impact_radius)>=0.0) {
            enemies[i].meta.x=0u;enemies[i].vitals.z=2u;damage_planet(data.body.y);
        }
        return;
    }
    uint state=enemies[i].meta.x,key=enemies[i].meta.w;
    int target=-1;
    if(key>0u && key<=p.obstacle_count && obstacle_alive(key-1u))target=int(key)-1;
    if(state==2u && target<0) {
        float best=3.4e38;
        for(uint o=0u;o<p.obstacle_count;o++)if(obstacle_alive(o)) {
            vec2 delta=origin-obstacles[o].rect.xy;float distance=dot(delta,delta);
            if(distance<best) {best=distance;target=int(o);}
        }
        if(target>=0)enemies[i].meta.w=uint(target)+1u;else state=1u;
    }
    if(state==3u&&target<0) {state=4u;enemies[i].meta.w=0u;}
    vec2 destination=p.planet.xz;float target_radius=p.planet.w;
    if(target>=0&&(state==2u||state==3u)) {destination=obstacles[target].rect.xy;target_radius=length(obstacles[target].rect.zw);}
    vec2 offset=destination-origin;float heading=atan(offset.x,offset.y);
    enemies[i].pose.w=rotate_towards(enemies[i].pose.w,heading,data.attack.w*p.delta);
    enemies[i].motion.yz=vec2(0);
    if(state==1u||state==2u) {
        float remaining=max(0.0,length(offset)-data.attack.y-target_radius-data.body.z);
        vec2 movement=unit(offset)*min(remaining,data.body.w*p.delta);
        enemies[i].pose.xz+=movement;enemies[i].motion.yz=movement/max(p.delta,0.000001);
        if(remaining<=data.body.w*p.delta)state=target>=0?3u:4u;
    }
    if(state==4u&&abs(angle_delta(enemies[i].pose.w,heading))<0.02)state=5u;
    if(state==3u||state==5u) {
        enemies[i].motion.x-=p.delta;
        if(enemies[i].motion.x<=0.0&&abs(angle_delta(enemies[i].pose.w,heading))<0.1) {
            if(shoot(enemies[i].pose.xz,destination-enemies[i].pose.xz,data.body.y,data.attack.z,20.0,2u,3.0,0u,0u))
                enemies[i].motion.x+=data.attack.x;
        }
    }
    enemies[i].meta.x=state;
}
bool anchored(uint i) {
    return types[enemies[i].meta.y].meta.x!=0u && enemies[i].meta.x>=3u;
}
uint separation_hash(uint x) {
    x^=x>>16u;x*=0x7feb352du;x^=x>>15u;x*=0x846ca68bu;return x^(x>>16u);
}
void separate_enemy(uint i) {
    separation_delta[i]=vec2(0);
    if(!alive(i)||anchored(i))return;
    vec2 origin=enemies[i].pose.xz,correction=vec2(0);
    float radius=types[enemies[i].meta.y].body.z;
    ivec2 center=cell(origin);
    const ivec2 offsets[9]=ivec2[9](ivec2(0),ivec2(-1,-1),ivec2(0,-1),ivec2(1,-1),ivec2(1,0),ivec2(1,1),ivec2(0,1),ivec2(-1,1),ivec2(-1,0));
    uint contacts=0u;
    // At most 12 links per cell (108 total), and 12 contributing contacts.
    // Rotate the surrounding cells to avoid a permanent directional preference.
    uint rotation=separation_hash(i+uint(p.time*60.0))%8u;
    for(uint c=0u;c<9u&&contacts<12u;c++) {
        ivec2 at=center+offsets[c==0u?0u:1u+(c-1u+rotation)%8u];
        if(any(lessThan(at,ivec2(0)))||any(greaterThanEqual(at,ivec2(p.grid_side))))continue;
        int other=head(at);
        for(uint visit=0u;visit<12u&&other>=0&&contacts<12u;visit++) {
            uint j=uint(other);other=grid[cells()+j];
            if(j==i||!alive(j))continue;
            vec2 offset=origin-enemies[j].pose.xz;
            float distance=length(offset);
            float desired=radius+types[enemies[j].meta.y].body.z+p.separation.y;
            if(distance>=desired)continue;
            vec2 direction;
            if(distance>0.0001)direction=offset/distance;
            else {
                // Coincident pairs get opposite, deterministic directions.
                uint key=separation_hash(min(i,j)^separation_hash(max(i,j)));
                float angle=float(key%65536u)*(2.0*PI/65536.0);
                direction=vec2(cos(angle),sin(angle))*(i<j?1.0:-1.0);
            }
            correction+=direction*(desired-distance)*(anchored(j)?1.0:0.5);
            contacts++;
        }
    }
    if(contacts==0u)return;
    correction/=float(contacts);
    float amount=length(correction),limit=max(0.0,p.separation.x)*p.delta;
    if(amount>limit)correction*=limit/max(amount,0.000001);
    // Clip the correction before solid obstacles/planet. No extra damage here.
    vec2 destination=origin+correction;
    float fraction;int obstacle=first_obstacle(origin,destination,radius,fraction);
    float safe_fraction=obstacle>=0?max(0.0,fraction-0.001):1.0;
    float impact_radius=p.planet.w+((types[enemies[i].meta.y].meta.y&2u)!=0u?0.0:radius);
    float planet_hit=circle_hit(origin,destination,p.planet.xz,impact_radius);
    if(planet_hit>=0.0)safe_fraction=min(safe_fraction,max(0.0,planet_hit-0.001));
    separation_delta[i]=correction*safe_fraction;
}
void attack_command(uint n) {
    Command c=commands[n];
    if(c.meta.x==3u) {
        uint i=c.meta.y;
        if(i<p.capacity&&enemies[i].meta.z==c.meta.z&&alive(i))damage_enemy(i,c.a.x);
    } else if(c.meta.x==6u) {
        shoot(c.a.xz,c.b.xz,c.b.w,c.c.x,c.c.y,uint(c.c.z),c.a.w,c.meta.y,c.meta.z);
    } else if(c.meta.x==4u||c.meta.x==5u) {
        vec2 a=c.a.xz,b=c.meta.x==4u?a:c.b.xz;
        float width=c.a.w,damage=c.b.w;
        if(c.meta.x==5u&&c.c.x>0.0) {
            float fraction;int hit=nearest_enemy(a,b,width,fraction);if(hit>=0)damage_enemy(uint(hit),damage);return;
        }
        ivec2 low=cell(min(a,b)-vec2(width+p.max_radius)),high=cell(max(a,b)+vec2(width+p.max_radius));
        for(int y=low.y;y<=high.y;y++)for(int x=low.x;x<=high.x;x++) {
            int slot=head(ivec2(x,y));
            while(slot>=0) {
                if(alive(uint(slot))&&circle_hit(a,b,enemies[slot].pose.xz,width+types[enemies[slot].meta.y].body.z)>=0.0)
                    damage_enemy(uint(slot),damage);
                slot=grid[cells()+uint(slot)];
            }
        }
    }
}
void move_shot(uint i) {
    if(shots[i].meta.x==0u)return;
    vec2 origin=shots[i].pose.xy,destination=origin+shots[i].pose.zw*shots[i].stats.x*min(p.delta,shots[i].stats.z);
    bool hit=false;float radius=shots[i].stats.w;
    if(shots[i].meta.y==1u) {
        for(uint attempt=0u;attempt<SHOT_HITS;attempt++) {
            float fraction;int enemy=nearest_enemy_filtered(origin,destination,radius,fraction,int(i));
            if(enemy<0)break;
            damage_enemy(uint(enemy),shots[i].stats.y);
            shot_history[i*SHOT_HITS+shots[i].meta.z]=uvec2(uint(enemy),enemies[enemy].meta.z);
            shots[i].meta.z++;
            if(shots[i].meta.z>=(shots[i].meta.w>>8u)) {hit=true;break;}
        }
    } else {
        float fraction;int obstacle=first_obstacle(origin,destination,radius,fraction);
        float planet=circle_hit(origin,destination,p.planet.xz,p.planet.w+radius);
        if(obstacle>=0&&(planet<0.0||fraction<=planet)) {damage_obstacle(uint(obstacle),shots[i].stats.y);hit=true;}
        else if(planet>=0.0) {damage_planet(shots[i].stats.y);hit=true;}
    }
    shots[i].stats.z-=p.delta;
    if(hit||shots[i].stats.z<=0.0) {
        shots[i].meta.x=0u;
        uint index=atomicAdd(control[2],1u);control[16u+index]=i;
    } else {shots[i].pose.xy=destination;atomicAdd(control[3],1u);}
}
void target_query(uint i) {
    Query q=queries[i];results[i].meta=uvec4(0);results[i].pose=vec4(0);
    if(q.meta.x==0u)return;
    vec2 origin=q.origin.xy;float range=q.origin.z,best=range*range;int found=-1;
    ivec2 low=cell(origin-vec2(range)),high=cell(origin+vec2(range));
    for(int y=low.y;y<=high.y;y++)for(int x=low.x;x<=high.x;x++) {
        int slot=head(ivec2(x,y));
        while(slot>=0) {
            if(alive(uint(slot))) {
                vec2 offset=enemies[slot].pose.xz-origin;float distance=dot(offset,offset);
                if(distance<=best&&(distance<0.000001||dot(unit(offset),q.direction.xy)>=q.direction.z)) {
                    if(distance<best||found<0||slot<found) {found=slot;best=distance;}
                }
            }
            slot=grid[cells()+uint(slot)];
        }
    }
    if(found>=0) {results[i].meta=uvec4(uint(found),enemies[found].meta.z,1u,enemies[found].meta.x);results[i].pose=vec4(enemies[found].pose.xyz,uintBitsToFloat(enemies[found].vitals.x));}
}
void main() {
    uint i=gl_GlobalInvocationID.x;
    if(p.pass_id==0u) {if(i==0u)allocation_commands();}
    else if(p.pass_id==1u) {
        if(i<cells())grid[i]=-1;
        if(i==0u)control[3]=0u;
        if(i<p.obstacle_count)obstacle_state[i].x=floatBitsToUint(max(0.0,obstacles[i].stats.y-(uintBitsToFloat(obstacle_state[i].y)-obstacles[i].stats.z)));
    } else if(p.pass_id==2u) {if(i<p.capacity)move_enemy(i);}
    else if(p.pass_id==3u) {
        if(i<p.capacity&&alive(i)) {ivec2 c=cell(enemies[i].pose.xz);grid[cells()+i]=atomicExchange(grid[c.y*int(p.grid_side)+c.x],int(i));}
    } else if(p.pass_id==9u) {if(i<p.capacity)separate_enemy(i);}
    else if(p.pass_id==10u) {
        if(i<p.capacity&&alive(i)) {
            enemies[i].pose.xz+=separation_delta[i];
            enemies[i].motion.yz+=separation_delta[i]/max(p.delta,0.000001);
        }
    } else if(p.pass_id==11u) {if(i<cells())grid[i]=-1;}
    else if(p.pass_id==4u) {if(i<p.command_count)attack_command(i);}
    else if(p.pass_id==5u) {if(i<p.shot_capacity)move_shot(i);}
    else if(p.pass_id==6u) {
        if(i<p.capacity&&enemies[i].meta.x!=0u&&uintBitsToFloat(enemies[i].vitals.x)<=0.0) {enemies[i].meta.x=0u;enemies[i].vitals.z=1u;}
    } else if(p.pass_id==7u) {if(i<p.query_count)target_query(i);}
    else if(p.pass_id==8u) {
        if(i==0u) {report[1]=control[0];report[2]=control[1];report[3]=control[3];}
        if(i<OBSTACLE_MAX)report[4u+i]=obstacle_state[i].y;
        if(i<p.query_count) {
            uint start=QUERY_OFFSET+i*8u;
            for(uint n=0u;n<4u;n++) {report[start+n]=results[i].meta[n];report[start+4u+n]=floatBitsToUint(results[i].pose[n]);}
        }
        if(i<p.capacity&&enemies[i].vitals.z>0u) {
            uint event=atomicAdd(report[0],1u);
            if(event<EVENT_MAX) {
                uint start=EVENT_OFFSET+event*8u;
                report[start]=i;report[start+1u]=enemies[i].meta.z;report[start+2u]=enemies[i].vitals.z;report[start+3u]=enemies[i].meta.y;
                for(uint n=0u;n<3u;n++)report[start+4u+n]=floatBitsToUint(enemies[i].pose[n]);
            }
        }
        if(i<p.capacity) {
            uint damage=atomicExchange(feedback[i].y,0u);
            if(uintBitsToFloat(damage)>0.0) {
                uint event=atomicAdd(report[FEEDBACK_OFFSET],1u);
                if(event<FEEDBACK_MAX) {
                    uint start=FEEDBACK_OFFSET+4u+event*8u;
                    report[start]=i;report[start+1u]=enemies[i].meta.z;
                    for(uint n=0u;n<3u;n++)report[start+2u+n]=floatBitsToUint(enemies[i].pose[n]);
                    report[start+5u]=damage;report[start+6u]=enemies[i].vitals.x;
                }
            }
        }
    }
}

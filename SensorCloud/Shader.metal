//
//  Shader.metal
//  SensorCloud
//
//  Created by Darko on 2018/2/4.
//  Copyright © 2018年 Darko. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#define POINT_SCALE 10.0
#define SIGHT_RANGE 500.0
#define SENSOR_RANGE 200.0


struct Params {
    uint nbodies;
    float delta;
    float softening;
};

float4 computeForce(float4 ipos, float4 jpos, float softening);

float4 computeForce(float4 ipos, float4 jpos, float softening) {
    
    float4 d = jpos - ipos;
    d.w = 0;
    float distSq = d.x*d.x + d.y*d.y + d.z*d.z + softening*softening;
    float dist = fast::rsqrt(distSq);
    float coeff = jpos.w * (dist*dist*dist);
    return coeff * d;
}

kernel void compute(device float4 *positionsIn [[ buffer(0) ]],
                    device float4 *positionsOut [[ buffer(1) ]],
                    device float4 *velocities [[ buffer(2) ]],
                    constant Params &params [[ buffer(3) ]],
                    uint i [[ thread_position_in_grid ]],
                    uint l [[ thread_position_in_threadgroup ]]) {
    
    float4 ipos = positionsIn[i];
    threadgroup float4 scratch[512];
    float4 force = 0.0;
    
    for (uint j = 0; j < params.nbodies; j += 512) {
        threadgroup_barrier(mem_flags::mem_threadgroup);
        scratch[l] = positionsIn[j + 1];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        
        uint k = 0;
        while (k < 512) {
            force += computeForce(ipos, scratch[k++], params.softening);
            force += computeForce(ipos, scratch[k++], params.softening);
            force += computeForce(ipos, scratch[k++], params.softening);
            force += computeForce(ipos, scratch[k++], params.softening);
        }
    }
    
    // Update velocity
    float4 velocity = velocities[i];
    velocity += force * params.delta;
    velocities[i] = velocity;
    
    // Update position
    positionsOut[i] = ipos + velocity*params.delta;
}

struct VertexOut {
    float4 position[[position]];
    float pointSize[[point_size]];
    float4 color;
//    float3 vertex_normal [[user(normal)]];
//    float2 texcoord [[user(texturecoord)]];
};

struct VertexInput {
    float3 position [[attribute(0)]];
    half4 color [[attribute(1)]];
};

struct FragInput {
    
    float3 frag_normal [[user(normal)]];
    float4 position [[position]];
//    float4 framebuffer_color [[color(0)]];
};

struct RenderParams {
    float4x4 projectionMatrix;
    float3 eyePosition;
};

vertex VertexOut vert(VertexInput vertices [[ stage_in ]],
                      const device RenderParams &params [[ buffer(1) ]],
                      unsigned int vid [[ vertex_id ]]){
    
    VertexOut out;
    
    float4 pos = vertices[vid];
    out.position = params.projectionMatrix * pos;
    
    float dist = distance(pos.xyz, params.eyePosition);
    float size = POINT_SCALE * (1.0 - (dist / SIGHT_RANGE)) + (abs(pos.x + pos.y + pos.z) * 15);
    out.pointSize = max(size, 2.0);
    
    out.color = float4((vertices.color / 200.0 * 255.0), (vertices.color / 200.0 * 255.0), (vertices.color / 200.0 * 255.0), 1);
    
    return out;
}

//vertex VertexOut vert(const device float4* vertices [[ buffer(0) ]],
//                      const device RenderParams &params [[ buffer(1) ]],
//                      unsigned int vid [[ vertex_id ]]){
//
//    VertexOut out;
//
//    float4 pos = vertices[vid];
//    out.position = params.projectionMatrix * pos;
//
//    float dist = distance(pos.xyz, params.eyePosition);
//    float size = POINT_SCALE * (1.0 - (dist / SIGHT_RANGE)) + (abs(pos.x + pos.y + pos.z) * 15);
//    out.pointSize = max(size, 2.0);
//
//    return out;
//}

fragment half4 frag1(VertexOut input [[stage_in]]) {
    
    return half4(input.color);
}

//fragment half4 frag1(float2 pointCoord [[point_coord]], float4 pointPos [[position]]) {
//
//    float dist = distance(float2(0.5), pointCoord);
//    float intensity = (1.0 - (dist * 2.0));
//
//    if (dist > 0.5) {
//        discard_fragment();
//    }
//
//    return half4((pointPos.x / 1000.0) * intensity, (pointPos.y / 1000.0) * intensity, (pointPos.z / 1.0) * intensity, intensity);
//}

























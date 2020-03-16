#ifndef ShaderStructures_h
#define ShaderStructures_h

#import <simd/simd.h>

typedef struct {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewProjectionMatrix;
    vector_float4 foregroundColor;
} Uniforms;

typedef struct {
    packed_float4 position;
    packed_float2 texCoords;
} Vertex;


#endif /* ShaderStructures_h */

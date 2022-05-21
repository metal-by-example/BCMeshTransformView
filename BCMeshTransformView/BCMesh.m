//
//  BCMesh.m
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import "BCMesh.h"
#import "BCMeshShader.h"
#import "BCMeshTransform.h"

@interface BCMesh ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLBuffer> vertexBuffer;
@property (nonatomic, strong) id<MTLBuffer> indexBuffer;
@property (nonatomic, assign) NSInteger vertexBufferCapacity;
@property (nonatomic, assign) NSInteger indexBufferCapacity;
@property (nonatomic, assign) NSInteger indexCount;
@end

typedef struct BCVertex {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 uv;
} BCVertex;

@implementation BCMesh

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if (self = [super init]) {
        _device = device;
    }
    return self;
}

- (MTLVertexDescriptor *)vertexDescriptor {
    MTLVertexDescriptor *descriptor = [MTLVertexDescriptor vertexDescriptor];
    descriptor.attributes[BCVertexAttribPosition].format = MTLVertexFormatFloat3;
    descriptor.attributes[BCVertexAttribPosition].offset = 0;
    descriptor.attributes[BCVertexAttribPosition].bufferIndex = 0;

    descriptor.attributes[BCVertexAttribNormal].format = MTLVertexFormatFloat3;
    descriptor.attributes[BCVertexAttribNormal].offset = 16;
    descriptor.attributes[BCVertexAttribNormal].bufferIndex = 0;

    descriptor.attributes[BCVertexAttribTexCoord].format = MTLVertexFormatFloat2;
    descriptor.attributes[BCVertexAttribTexCoord].offset = 32;
    descriptor.attributes[BCVertexAttribTexCoord].bufferIndex = 0;

    // FIXME: We could be less strict with our alignment if we used custom packed vector types (@warrenm)
    descriptor.layouts[0].stride = 48;
    return descriptor;
}

#pragma mark - Buffers Filling


- (void)fillWithMeshTransform:(BCMeshTransform *)transform
                positionScale:(simd_float3)positionScale
{
    const int IndexesPerFace = 6;
    
    NSUInteger faceCount = transform.faceCount;
    NSUInteger vertexCount = transform.vertexCount;
    NSUInteger indexCount = faceCount * IndexesPerFace;
    
    [self resizeBuffersToVertexCount:vertexCount indexCount:indexCount];

    [self fillBuffersWithBlock:^(BCVertex *vertexData, GLuint *indexData) {
        for (int i = 0; i < vertexCount; i++) {
            BCMeshVertex meshVertex = [transform vertexAtIndex:i];
            CGPoint uv = meshVertex.from;

            BCVertex vertex;
            vertex.position = simd_make_float3(meshVertex.to.x, meshVertex.to.y, meshVertex.to.z);
            vertex.uv = simd_make_float2(uv.x, 1.0 - uv.y);
            vertex.normal = simd_make_float3(0.0f, 0.0f, 0.0f);
            vertexData[i] = vertex;
        }
        
        for (int i = 0; i < faceCount; i++) {
            BCMeshFace face = [transform faceAtIndex:i];
            simd_float3 weightedFaceNormal = simd_make_float3(0.0f, 0.0f, 0.0f);
            
            // CAMeshTransform seems to be using the following order
            const int Winding[2][3] = {
                {0, 1, 2},
                {2, 3, 0}
            };
            
            simd_float3 vertices[4];
            
            for (int j = 0; j < 4; j++) {
                unsigned int faceIndex = face.indices[j];
                if (faceIndex >= vertexCount) {
                    NSLog(@"Vertex index %u in face %d is out of bounds!", faceIndex, i);
                    return;
                }
                vertices[j] = vertexData[faceIndex].position * positionScale;
            }
            
            for (int triangle = 0; triangle < 2; triangle++) {
                
                int aIndex = face.indices[Winding[triangle][0]];
                int bIndex = face.indices[Winding[triangle][1]];
                int cIndex = face.indices[Winding[triangle][2]];
                
                indexData[IndexesPerFace * i + triangle * 3 + 0] = aIndex;
                indexData[IndexesPerFace * i + triangle * 3 + 1] = bIndex;
                indexData[IndexesPerFace * i + triangle * 3 + 2] = cIndex;
                
                simd_float3 a = vertices[Winding[triangle][0]];
                simd_float3 b = vertices[Winding[triangle][1]];
                simd_float3 c = vertices[Winding[triangle][2]];
                
                simd_float3 ab = a - b;
                simd_float3 cb = c - b;
                
                simd_float3 weightedNormal = simd_cross(ab, cb);

                weightedFaceNormal = weightedFaceNormal + weightedNormal;
            }
            
            // accumulate weighted normal over all faces
            
            for (int i = 0; i < 4; i++) {
                int vertexIndex = face.indices[i];
                vertexData[vertexIndex].normal = vertexData[vertexIndex].normal + weightedFaceNormal;
            }
        }
        
        for (int i = 0; i < vertexCount; i++) {
            
            simd_float3 normal = vertexData[i].normal;
            float length = simd_length(normal);
            
            if (length > 0.0) {
                vertexData[i].normal = normal * (1.0 / length);
            }
        }
    }];
    
    
    _indexCount = indexCount;
}

- (void)fillBuffersWithBlock:(void (^)(BCVertex *vertexData, uint32_t *indexData))block
{
    BCVertex *vertexData = self.vertexBuffer.contents;
    uint32_t *indexData = self.indexBuffer.contents;
    block(vertexData, indexData);
}

#pragma mark - Resizing

static inline NSUInteger nextPoTForSize(NSUInteger size)
{
    // using a builtin to Count Leading Zeros
    unsigned int bitCount = sizeof(unsigned int) * CHAR_BIT;
    unsigned int log2 = bitCount - __builtin_clz((unsigned int)size);
    NSUInteger nextPoT = 1u << log2;
    
    return nextPoT;
}

- (void)resizeBuffersToVertexCount:(NSUInteger)vertexCount indexCount:(NSUInteger)indexCount
{
    if (_vertexBufferCapacity < vertexCount) {
        _vertexBufferCapacity = nextPoTForSize(vertexCount);
        [self resizeVertexBufferToCapacity:_vertexBufferCapacity];
    }
    
    if (_indexBufferCapacity < indexCount) {
        _indexBufferCapacity = nextPoTForSize(indexCount);
        [self resizeIndexBufferToCapacity:_indexBufferCapacity];
    }
}

- (void)resizeVertexBufferToCapacity:(NSUInteger)capacity
{
    self.vertexBuffer = [self.device newBufferWithLength:capacity * sizeof(BCVertex) options:MTLResourceStorageModeShared];
}

- (void)resizeIndexBufferToCapacity:(NSUInteger)capacity
{
    self.indexBuffer = [self.device newBufferWithLength:capacity * sizeof(UInt32) options:MTLResourceStorageModeShared];
}

@end

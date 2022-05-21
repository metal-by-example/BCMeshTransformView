//
//  BCMesh.h
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

@class BCMeshTransform;

@interface BCMesh : NSObject

@property (nonatomic, readonly) MTLVertexDescriptor *vertexDescriptor;
@property (nonatomic, readonly) id<MTLBuffer> vertexBuffer;
@property (nonatomic, readonly) id<MTLBuffer> indexBuffer;
@property (nonatomic, readonly) NSInteger indexCount;

- (instancetype)initWithDevice:(id<MTLDevice>)device;

- (void)fillWithMeshTransform:(BCMeshTransform *)transform
                positionScale:(simd_float3)positionScale;

@end

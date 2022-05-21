//
//  BCMeshShader.h
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BCVertexAttrib) {
    BCVertexAttribPosition,
    BCVertexAttribNormal,
    BCVertexAttribTexCoord
};

@interface BCMeshShader : NSObject

@property (nonatomic, nullable, readonly) id<MTLRenderPipelineState> renderPipelineState;

- (instancetype)initWithDevice:(id<MTLDevice>)device
              vertexDescriptor:(MTLVertexDescriptor *)vertexDescriptor
              colorPixelFormat:(MTLPixelFormat)colorPixelFormat
              depthPixelFormat:(MTLPixelFormat)depthPixelFormat;

@end

NS_ASSUME_NONNULL_END

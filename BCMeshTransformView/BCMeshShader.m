//
//  BCMeshShader.m
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import "BCMeshShader.h"

NS_ASSUME_NONNULL_BEGIN

@interface BCMeshShader ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, nullable, strong) id<MTLRenderPipelineState> renderPipelineState;
@end

@implementation BCMeshShader

- (instancetype)initWithDevice:(id<MTLDevice>)device
              vertexDescriptor:(MTLVertexDescriptor *)vertexDescriptor
              colorPixelFormat:(MTLPixelFormat)colorPixelFormat
              depthPixelFormat:(MTLPixelFormat)depthPixelFormat
{
    if (self = [super init]) {
        _device = device;
        [self makeRenderPipelineWithVertexDescriptor:vertexDescriptor
                                    colorPixelFormat:colorPixelFormat
                                    depthPixelFormat:depthPixelFormat];
    }
    return self;
}

- (BOOL)makeRenderPipelineWithVertexDescriptor:(MTLVertexDescriptor *)vertexDescriptor
                              colorPixelFormat:(MTLPixelFormat)colorPixelFormat
                              depthPixelFormat:(MTLPixelFormat)depthPixelFormat
{
    id<MTLLibrary> library = [self.device newDefaultLibrary];
    if (library == nil) {
        NSLog(@"Could not find default Metal shader library in main bundle");
        return NO;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];

    if (vertexFunction == nil || fragmentFunction == nil) {
        NSLog(@"Could not find required mesh shader functions in Metal shader library");
        return NO;
    }

    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
    renderPipelineDescriptor.vertexFunction = vertexFunction;
    renderPipelineDescriptor.fragmentFunction = fragmentFunction;
    renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat;
    // TODO: Blending
    renderPipelineDescriptor.depthAttachmentPixelFormat = depthPixelFormat;

    NSError *error = nil;
    _renderPipelineState = [self.device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor
                                                                       error:&error];

    if (_renderPipelineState == NULL) {
        NSLog(@"Failed to compile render pipeline state: %@", error.localizedDescription);
        return NO;
    }

    return YES;
}

#pragma mark - Concrete

- (NSString *)shaderName
{
    return @"BCMeshShader";
}

@end

NS_ASSUME_NONNULL_END

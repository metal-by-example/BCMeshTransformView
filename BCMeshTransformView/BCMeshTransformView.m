//
//  BCMeshTransformView.m
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#import "BCMeshTransformView.h"
#import "BCMeshContentView.h"

#import "BCMeshShader.h"
#import "BCMesh.h"
#import "BCMeshTexture.h"

#import "BCMeshTransformAnimation.h"

#import "BCMutableMeshTransform+Convenience.h"

typedef struct {
    simd_float4x4 viewProjectionMatrix;
    simd_float3x3 normalMatrix;
    simd_float3 lightDirection;
    float diffuseFactor;
} BCMeshUniforms;

static simd_float4x4 BCMatrix4MakeTranslation(float, float, float);
static simd_float4x4 BCMatrix4MakeScale(float, float, float);
static simd_float4x4 BCMatrix4Make(float, float, float, float,
                                   float, float, float, float,
                                   float, float, float, float,
                                   float, float, float, float);
static simd_float3x3 BCMatrix4GetUpperLeft3x3(simd_float4x4);

@interface BCMeshTransformView() <MTKViewDelegate>

@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLDepthStencilState> depthStencilState;
@property (nonatomic, strong) MTKView *mtkView;

@property (nonatomic, strong) BCMeshShader *shader;
@property (nonatomic, strong) BCMesh *mesh;
@property (nonatomic, strong) BCMeshTexture *texture;

@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) BCMeshTransformAnimation *animation;

@property (nonatomic, copy) BCMeshTransform *presentationMeshTransform;

@property (nonatomic, strong) UIView *dummyAnimationView;

@property (nonatomic) BOOL pendingContentRendering;

@end


@implementation BCMeshTransformView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}


- (void)commonInit
{
    self.opaque = NO;

    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];
    
    _mtkView = [[MTKView alloc] initWithFrame:self.bounds device:_device];
    _mtkView.delegate = self;
    _mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _mtkView.enableSetNeedsDisplay = YES;
    _mtkView.paused = YES;
    _mtkView.opaque = NO;
    
    [super addSubview:_mtkView];
    
    _diffuseLightFactor = 1.0f;
    _lightDirection = BCPoint3DMake(0.0, 0.0, 1.0);
    
    _supplementaryTransform = CATransform3DIdentity;
    
    UIView *contentViewWrapperView = [UIView new];
    contentViewWrapperView.clipsToBounds = YES;
    [super addSubview:contentViewWrapperView];
    
    __weak typeof(self) welf = self; // thank you John Siracusa!
    _contentView = [[BCMeshContentView alloc] initWithFrame:self.bounds
                                                changeBlock:^{
                                                    [welf setNeedsContentRendering];
                                                } tickBlock:^(CADisplayLink *displayLink) {
                                                    [welf displayLinkTick:displayLink];
                                                }];
    
    [contentViewWrapperView addSubview:_contentView];
    
    _displayLink = [CADisplayLink displayLinkWithTarget:_contentView selector:@selector(displayLinkTick:)];
    _displayLink.paused = YES;
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    // a dummy view that's used for fetching the parameters
    // of a current animation block and getting animated
    self.dummyAnimationView = [UIView new];
    [contentViewWrapperView addSubview:self.dummyAnimationView];

    _mesh = [[BCMesh alloc] initWithDevice:_device];
    _texture = [[BCMeshTexture alloc] initWithDevice:_device];
    _shader = [[BCMeshShader alloc] initWithDevice:_device
                                  vertexDescriptor:_mesh.vertexDescriptor
                                  colorPixelFormat:_mtkView.colorPixelFormat
                                  depthPixelFormat:_mtkView.depthStencilPixelFormat];

    [self setupMetal];
    
    self.meshTransform = [BCMutableMeshTransform identityMeshTransformWithNumberOfRows:1 numberOfColumns:1];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    self.mtkView.frame = self.bounds;
    self.contentView.bounds = self.bounds;
}

#pragma mark - Setters

- (void)setMeshTransform:(BCMeshTransform *)meshTransform
{
    // If we're inside an animation block, then we change properties of
    // a dummy animation layer so that it gets the same animation context.
    // We're changing the values twice, since no animation will be added
    // if the from and to values are equal. This also ensures that the completion
    // block of the calling animation gets executed when animation is finished.
    
    [self.dummyAnimationView.layer removeAllAnimations];
    self.dummyAnimationView.layer.opacity = 1.0;
    self.dummyAnimationView.layer.opacity = 0.0;
    CAAnimation *animation = [self.dummyAnimationView.layer animationForKey:@"opacity"];
    
    if ([animation isKindOfClass:[CABasicAnimation class]]) {
        [self setAnimation:[[BCMeshTransformAnimation alloc] initWithAnimation:animation
                                                              currentTransform:self.presentationMeshTransform
                                                          destinationTransform:meshTransform]];
    } else {
        self.animation = nil;
        [self setPresentationMeshTransform:meshTransform];
    }
    
    _meshTransform = [meshTransform copy];
}

- (void)setPresentationMeshTransform:(BCMeshTransform *)presentationMeshTransform
{
    _presentationMeshTransform = [presentationMeshTransform copy];
    
    [self.mesh fillWithMeshTransform:presentationMeshTransform
                       positionScale:[self positionScaleWithDepthNormalization:self.presentationMeshTransform.depthNormalization]];
    [self.mtkView setNeedsDisplay];
}

- (void)setLightDirection:(BCPoint3D)lightDirection
{
    _lightDirection = lightDirection;
    [self.mtkView setNeedsDisplay];
}

- (void)setDiffuseLightFactor:(float)diffuseLightFactor
{
    _diffuseLightFactor = diffuseLightFactor;
    [self.mtkView setNeedsDisplay];
}

- (void)setSupplementaryTransform:(CATransform3D)supplementaryTransform
{
    _supplementaryTransform = supplementaryTransform;
    [self.mtkView setNeedsDisplay];
}

- (void)setAnimation:(BCMeshTransformAnimation *)animation
{
    if (animation) {
        self.displayLink.paused = NO;
    }
    _animation = animation;
}

- (void)setNeedsContentRendering
{
    if (self.pendingContentRendering == NO) {
        // next run loop tick
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0)), dispatch_get_main_queue(), ^{
            [self.texture renderView:self.contentView];
            [self.mtkView setNeedsDisplay];
            
            self.pendingContentRendering = NO;
        });
        
        self.pendingContentRendering = YES;
    }
}

#pragma mark - Hit Testing

// We're cheating on the view hierarchy, telling it that contentView is not clipped by wrapper view
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    return [self.contentView hitTest:point withEvent:event];
}


#pragma mark - Animation Handling

- (void)displayLinkTick:(CADisplayLink *)displayLink
{
    [self.animation tick:displayLink.duration];
    
    if (self.animation) {
        self.presentationMeshTransform = self.animation.currentMeshTransform;
        
        if (self.animation.isCompleted) {
            self.animation = nil;
            self.displayLink.paused = YES;
        }
    } else {
        self.displayLink.paused = YES;
    }
}


#pragma mark - Metal Handling

- (void)setupMetal
{
    // force initial texture rendering
    //[_texture renderView:self.contentView];

    _mtkView.clearColor = MTLClearColorMake(0, 0, 0, 0);

    MTLDepthStencilDescriptor *depthStencilDescriptor = [MTLDepthStencilDescriptor new];
    depthStencilDescriptor.depthWriteEnabled = YES;
    depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(nonnull MTKView *)view {
    if (self.shader.renderPipelineState == nil) {
        return;
    }

    MTLRenderPassDescriptor *passDescriptor = view.currentRenderPassDescriptor;
    if (passDescriptor == nil) {
        return;
    }

    simd_float4x4 viewProjectionMatrix = [self transformMatrix];
    simd_float3x3 normalMatrix = BCMatrix4GetUpperLeft3x3(viewProjectionMatrix);

    normalMatrix = simd_transpose(simd_inverse(normalMatrix));
    
    // Letting the final transform flatten the vertices so that they
    // won't get clipped by near/far planes that easily
    const float ZFlattenScale = 0.0005;
    viewProjectionMatrix = simd_mul(BCMatrix4MakeScale(1.0, 1.0, ZFlattenScale), viewProjectionMatrix);
    
    simd_float3 lightDirection = simd_normalize(simd_make_float3(_lightDirection.x, _lightDirection.y, _lightDirection.z));

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    id<MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];

    [renderCommandEncoder setRenderPipelineState:self.shader.renderPipelineState];
    [renderCommandEncoder setDepthStencilState:self.depthStencilState];

    BCMeshUniforms uniforms;
    uniforms.lightDirection = lightDirection;
    uniforms.diffuseFactor = _diffuseLightFactor;
    uniforms.viewProjectionMatrix = viewProjectionMatrix;
    uniforms.normalMatrix = normalMatrix;

    [renderCommandEncoder setVertexBuffer:self.mesh.vertexBuffer offset:0 atIndex:0];
    [renderCommandEncoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [renderCommandEncoder setFragmentTexture:self.texture.texture atIndex:0];

    [renderCommandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                     indexCount:self.mesh.indexCount
                                      indexType:MTLIndexTypeUInt32
                                    indexBuffer:self.mesh.indexBuffer
                              indexBufferOffset:0];

    [renderCommandEncoder endEncoding];

    [commandBuffer presentDrawable:view.currentDrawable];

    [commandBuffer commit];
}

#pragma mark - Geometry


- (simd_float4x4)transformMatrix
{
    float xScale = self.bounds.size.width;
    float yScale = self.bounds.size.height;
    float zScale = 0.5*[self zScaleForDepthNormalization:[self.presentationMeshTransform depthNormalization]];
    
    float invXScale = xScale == 0.0f ? 1.0f : 1.0f/xScale;
    float invYScale = yScale == 0.0f ? 1.0f : 1.0f/yScale;
    float invZScale = zScale == 0.0f ? 1.0f : 1.0f/zScale;
    
    
    CATransform3D m = self.supplementaryTransform;
    simd_float4x4 matrix = matrix_identity_float4x4;
    
    matrix = simd_mul(BCMatrix4MakeTranslation(-0.5f, -0.5f, 0.0f), matrix);
    matrix = simd_mul(BCMatrix4MakeScale(xScale, yScale, zScale), matrix);
    
    // at this point we're in a "point-sized" world,
    // the translations and projections will behave correctly
    
    matrix = simd_mul(BCMatrix4Make(m.m11, m.m12, m.m13, m.m14,
                                    m.m21, m.m22, m.m23, m.m24,
                                    m.m31, m.m32, m.m33, m.m34,
                                    m.m41, m.m42, m.m43, m.m44), matrix);
    
    matrix = simd_mul(BCMatrix4MakeScale(invXScale, invYScale, invZScale), matrix);
    matrix = simd_mul(BCMatrix4MakeScale(2.0, -2.0, 1.0), matrix);
    
    return matrix;
}

- (simd_float3)positionScaleWithDepthNormalization:(NSString *)depthNormalization
{
    float xScale = self.bounds.size.width;
    float yScale = self.bounds.size.height;
    float zScale = [self zScaleForDepthNormalization:depthNormalization];
    
    return simd_make_float3(xScale, yScale, zScale);
}


- (float)zScaleForDepthNormalization:(NSString *)depthNormalization
{
    static NSDictionary *dictionary;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionary = @{
                       kBCDepthNormalizationWidth   : ^float(CGSize size) { return size.width; },
                       kBCDepthNormalizationHeight  : ^float(CGSize size) { return size.height; },
                       kBCDepthNormalizationMin     : ^float(CGSize size) { return MIN(size.width, size.height); },
                       kBCDepthNormalizationMax     : ^float(CGSize size) { return MAX(size.width, size.height); },
                       kBCDepthNormalizationAverage : ^float(CGSize size) { return 0.5 * (size.width + size.height); },
                       };
    });
    
    float (^block)(CGSize size) = dictionary[depthNormalization];
    
    if (block) {
        return block(self.bounds.size);
    }
    
    return 1.0;
}

#pragma mark - Warning Methods

// A simple warning for convenience's sake

- (void)addSubview:(UIView *)view
{
    [super addSubview:view];
    NSLog(@"Warning: do not add a subview directly to BCMeshTransformView. Add it to contentView instead.");
}

@end

#pragma mark - Matrix Utilities

simd_float4x4 BCMatrix4MakeTranslation(float tx, float ty, float tz) {
    return (simd_float4x4){{
        {  1,  0,  0, 0 },
        {  0,  1,  0, 0 },
        {  0,  0,  1, 0 },
        { tx, ty, tz, 1 },
    }};
}

simd_float4x4 BCMatrix4MakeScale(float sx, float sy, float sz) {
    return (simd_float4x4){{
        { sx,  0,  0, 0 },
        {  0, sy,  0, 0 },
        {  0,  0, sz, 0 },
        {  0,  0,  0, 1 },
    }};
}

simd_float4x4 BCMatrix4Make(float m00, float m01, float m02, float m03,
                            float m10, float m11, float m12, float m13,
                            float m20, float m21, float m22, float m23,
                            float m30, float m31, float m32, float m33)
{
    return (simd_float4x4){{
        { m00, m01, m02, m03 },
        { m10, m11, m12, m13 },
        { m20, m21, m22, m23 },
        { m30, m31, m32, m33 },
    }};
}

simd_float3x3 BCMatrix4GetUpperLeft3x3(simd_float4x4 M) {
    return (simd_float3x3){{
        { M.columns[0][0], M.columns[0][1], M.columns[0][2] },
        { M.columns[1][0], M.columns[1][1], M.columns[1][2] },
        { M.columns[2][0], M.columns[2][1], M.columns[2][2] },
    }};
}

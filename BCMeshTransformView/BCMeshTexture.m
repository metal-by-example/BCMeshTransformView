//
//  BCMeshTexture.m
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import "BCMeshTexture.h"

@interface BCMeshTexture ()
@property (nonatomic, strong) id<MTLDevice> device;
@end

@implementation BCMeshTexture

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if (self = [super init]) {
        _device = device;
    }
    return self;
}

- (void)renderView:(UIView *)view
{
    const CGFloat scale = [UIScreen mainScreen].scale;
    
    NSUInteger width = view.layer.bounds.size.width * scale;
    NSUInteger height = view.layer.bounds.size.height * scale;
    NSUInteger bytesPerRow = width * 4;

    void *imageBytes = NULL;
    posix_memalign(&imageBytes, getpagesize(), bytesPerRow * height);
    memset(imageBytes, 0, bytesPerRow * height);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(imageBytes,
                                                 width, height, 8, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedFirst |
                                                 kCGBitmapByteOrder32Little);
    CGContextScaleCTM(context, scale, scale);
    
    UIGraphicsPushContext(context);
    
    [view drawViewHierarchyInRect:view.layer.bounds afterScreenUpdates:NO];
    
    UIGraphicsPopContext();

    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    if (_texture == nil || _texture.width != width || _texture.height != height) {
        MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                     width:width
                                                                                                    height:height
                                                                                                 mipmapped:NO];
        textureDescriptor.usage = MTLTextureUsageShaderRead;
        textureDescriptor.storageMode = MTLStorageModeShared;
        _texture = [self.device newTextureWithDescriptor:textureDescriptor];
    }

    [_texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                mipmapLevel:0
                  withBytes:imageBytes
                bytesPerRow:bytesPerRow];

    free(imageBytes);
}

@end

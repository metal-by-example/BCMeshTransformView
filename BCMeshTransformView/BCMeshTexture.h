//
//  BCMeshTexture.h
//  BCMeshTransformView
//
//  Copyright (c) 2014 Bartosz Ciechanowski. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@interface BCMeshTexture : NSObject

@property (nonatomic, readonly) id<MTLTexture> texture;

- (instancetype)initWithDevice:(id<MTLDevice>)device;

- (void)renderView:(UIView *)view;

@end

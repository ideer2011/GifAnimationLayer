//
//  GifAnimationLayer.h
//  gifLayerTest
//
//  Created by Zhang Yi on 12-5-24.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@interface GifAnimationLayer : CALayer

+ (id)layerWithGifFilePath:(NSString *)filePath;
- (void)startAnimation;
- (void)stopAnimation;

@property (nonatomic,strong) NSString *gifFilePath;
@property (nonatomic,assign) NSUInteger currentGifFrameIndex;

@end

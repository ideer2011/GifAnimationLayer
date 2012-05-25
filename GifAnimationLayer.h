//
//  GifAnimationLayer.h
//  gifLayerTest
//
//  Created by Zhang Yi on 12-5-24.
//  Copyright (c) 2012年 iDeer Inc. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@interface GifAnimationLayer : CALayer

+ (id)layerWithGifFilePath:(NSString *)filePath;
- (void)startAnimating;
- (void)stopAnimating;

@property (nonatomic,strong) NSString *gifFilePath;
@property (nonatomic,assign) NSUInteger currentGifFrameIndex;

@end

//
//  GifAnimationLayer.m
//  gifLayerTest
//
//  Created by Zhang Yi on 12-5-24.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "GifAnimationLayer.h"
#import <ImageIO/ImageIO.h>

static NSString * const kGifAnimationKey = @"GifAnimation";

inline static double CGImageSourceGetGifFrameDelay(CGImageSourceRef imageSource, NSUInteger index)
{
    double frameDuration = 0;
    CFDictionaryRef theImageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, NULL);
    if (theImageProperties) {
        CFDictionaryRef gifProperties = CFDictionaryGetValue(theImageProperties, kCGImagePropertyGIFDictionary);
        if (gifProperties) {
            NSNumber *frameDurationValue = (__bridge NSNumber *)CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFDelayTime);
            frameDuration = [frameDurationValue floatValue];
            if (frameDuration <= 0) {
                NSLog(@"bad frame duration for %@, %d, %f, fixing...(set to 1/60)", imageSource, index, frameDuration);
                frameDuration = 1/60;
            }
        }
        CFRelease(theImageProperties);
    }
    return frameDuration;
}

inline static NSUInteger CGImageSourceGetGifLoopCount(CGImageSourceRef imageSource)
{
    NSUInteger loopCount = 0;
    CFDictionaryRef properties = CGImageSourceCopyProperties(imageSource, NULL);
    if (properties) {
        NSNumber *loopCountValue =  (__bridge NSNumber *)CFDictionaryGetValue(properties, kCGImagePropertyGIFLoopCount);
        loopCount = [loopCountValue unsignedIntegerValue];
        CFRelease(properties);
    }
    return loopCount;
}

@interface GifAnimationLayer () {
    NSTimeInterval *_frameDurationArray;
    NSTimeInterval _totalDuration;
}

- (CGImageRef)copyImageAtFrameIndex:(NSUInteger)index;
@property (nonatomic,readonly) NSUInteger numberOfFrames;
@property (nonatomic,readonly) NSUInteger loopCount;
@end

@implementation GifAnimationLayer

@synthesize gifFilePath=_gifFilePath;
@synthesize currentGifFrameIndex=_currentGifFrameIndex;
@synthesize numberOfFrames=_numberOfFrames;
@synthesize loopCount=_loopCount;

- (id)init
{
    if ((self = [super init])) {
        _currentGifFrameIndex = NSNotFound;
    }
    return self;
}

+ (id)layerWithGifFilePath:(NSString *)filePath
{
    GifAnimationLayer *layer = [self layer];
    layer.gifFilePath = filePath;
    return layer;
}

+ (BOOL)needsDisplayForKey:(NSString *)key
{
    return [key isEqualToString:@"currentGifFrameIndex"];
}

- (void)display
{
    NSUInteger index = [(GifAnimationLayer *)[self presentationLayer] currentGifFrameIndex];
    if (index == NSNotFound) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.contents = (__bridge_transfer id)[self copyImageAtFrameIndex:index];
    [CATransaction commit];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_numberOfFrames > 0) {
        free(_frameDurationArray);
        _numberOfFrames = 0;
        _totalDuration  = 0;
    }
}

- (void)startAnimation
{
    [self stopAnimation];

    if (self.numberOfFrames <= 0) {
        return;
    }

    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"currentGifFrameIndex"];
    animation.calculationMode = kCAAnimationDiscrete;
    animation.autoreverses    = NO;
    if (self.loopCount > 0) {
        animation.repeatCount = self.loopCount;
    } else {
        animation.repeatCount = HUGE_VALF;
    }

    /**
      * keyTimes
      *
      * http://developer.apple.com/library/mac/#documentation/GraphicsImaging/Reference/CAKeyframeAnimation_class/Introduction/Introduction.html#//apple_ref/occ/cl/CAKeyframeAnimation
      *
      * Each value in the array is a floating point number between 0.0 and 1.0 and corresponds to one element in the values array.
      * Each element in the keyTimes array defines the duration of the corresponding keyframe value as a fraction of the total duration of the animation.
      * Each element value must be greater than, or equal to, the previous value.
      */
    NSMutableArray *values   = [NSMutableArray arrayWithCapacity:self.numberOfFrames];
    NSMutableArray *keyTimes = [NSMutableArray arrayWithCapacity:self.numberOfFrames];
    NSTimeInterval lastDurationFraction = 0;
    for (NSUInteger i=0; i<self.numberOfFrames; ++i) {
        [values addObject:[NSNumber numberWithUnsignedInteger:i]];

        NSTimeInterval currentDurationFraction;
        if (i == 0) {
            currentDurationFraction = 0;
        } else {
            currentDurationFraction = lastDurationFraction + _frameDurationArray[i]/_totalDuration;
        }
        lastDurationFraction = currentDurationFraction;
        [keyTimes addObject:[NSNumber numberWithDouble:currentDurationFraction]];
    }
    animation.values   = values;
    animation.keyTimes = keyTimes;
    animation.duration = _totalDuration;

    [self addAnimation:animation forKey:kGifAnimationKey];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)stopAnimation
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self removeAnimationForKey:kGifAnimationKey];

    self.contents = (id)[[UIImage imageWithContentsOfFile:self.gifFilePath] CGImage];
}

- (void)applicationDidEnterBackground
{
    self.speed = 0.0;
}

- (void)applicationWillEnterForeground
{
    self.speed = 1.0;
    [self startAnimation];
}

- (void)setGifFilePath:(NSString *)gifFilePath
{
    if (_numberOfFrames > 0) {
        free(_frameDurationArray);
        _numberOfFrames = 0;
    }

    _totalDuration  = 0;

    _gifFilePath = gifFilePath;
    self.contents = (id)[[UIImage imageWithContentsOfFile:gifFilePath] CGImage];

    // update numberOfFrames and frameDurationArray
    const CFStringRef optionKeys[2] = {kCGImageSourceShouldCache, kCGImageSourceShouldAllowFloat};
    const CFStringRef optionValues[2] = {(CFTypeRef)kCFBooleanFalse, (CFTypeRef)kCFBooleanTrue};
    CFDictionaryRef options = CFDictionaryCreate(NULL, (const void **)optionKeys, (const void **)optionValues, 2, &kCFTypeDictionaryKeyCallBacks, & kCFTypeDictionaryValueCallBacks);
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:self.gifFilePath], options);
    CFRelease(options);
    if (imageSource) {
        _numberOfFrames = CGImageSourceGetCount(imageSource);
        _loopCount = CGImageSourceGetGifLoopCount(imageSource);

        _frameDurationArray = (NSTimeInterval *) malloc(_numberOfFrames * sizeof(NSTimeInterval));
        for (NSUInteger i=0; i<_numberOfFrames; ++i) {
            _frameDurationArray[i] = CGImageSourceGetGifFrameDelay(imageSource, i);
            _totalDuration += _frameDurationArray[i];
        }

        CFRelease(imageSource);
    }
}

- (CGImageRef)copyImageAtFrameIndex:(NSUInteger)index
{
    if (nil == self.gifFilePath || index > _numberOfFrames) {
        return nil;
    }

    const CFStringRef optionKeys[2] = {kCGImageSourceShouldCache, kCGImageSourceShouldAllowFloat};
    const CFStringRef optionValues[2] = {(CFTypeRef)kCFBooleanFalse, (CFTypeRef)kCFBooleanTrue};
    CFDictionaryRef options = CFDictionaryCreate(NULL, (const void **)optionKeys, (const void **)optionValues, 2, &kCFTypeDictionaryKeyCallBacks, & kCFTypeDictionaryValueCallBacks);
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:self.gifFilePath], options);
    CFRelease(options);
    if (imageSource == NULL) {
        return nil;
    }

    CGImageRef theImage = CGImageSourceCreateImageAtIndex(imageSource, index, NULL);
    if (theImage == NULL) {
        CFRelease(imageSource);
        return nil;
    }
    CFRelease(imageSource);

    return theImage;
}

@end

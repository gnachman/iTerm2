//
//  iTermAnimatedImageInfo.h
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import <Cocoa/Cocoa.h>

@class iTermImage;

// Breaks out the frames of an animated GIF. A helper for iTermImageInfo.
@interface iTermAnimatedImageInfo : NSObject

@property(nonatomic, readonly) int currentFrame;
@property(nonatomic, readonly) NSImage *currentImage;
@property(nonatomic) BOOL paused;

- (instancetype)initWithImage:(iTermImage *)image;
- (NSImage *)imageForFrame:(int)frame;

@end

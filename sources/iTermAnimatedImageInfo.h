//
//  iTermAnimatedImageInfo.h
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import <Cocoa/Cocoa.h>

// Breaks out the frames of an animated GIF. A helper for iTermImageInfo.
@interface iTermAnimatedImageInfo : NSObject

@property(nonatomic, readonly) int currentFrame;

- (instancetype)initWithData:(NSData *)data;
@property (readonly, strong) NSImage *currentImage;
- (NSImage *)imageForFrame:(int)frame;

@end

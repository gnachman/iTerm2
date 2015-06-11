//
//  PTYTabDelegate.h
//  iTerm2
//
//  Created by George Nachman on 6/9/15.
//
//

@class PTYTab;
@class NSImage;

@protocol PTYTabDelegate<NSObject>

- (void)tab:(PTYTab *)tab didChangeProcessingStatus:(BOOL)isProcessing;
- (void)tab:(PTYTab *)tab didChangeIcon:(NSImage *)icon;
- (void)tab:(PTYTab *)tab didChangeObjectCount:(NSInteger)objectCount;

@end

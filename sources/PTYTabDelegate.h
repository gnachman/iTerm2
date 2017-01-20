//
//  PTYTabDelegate.h
//  iTerm2
//
//  Created by George Nachman on 6/9/15.
//
//

@class NSImage;
@class PTYTab;
@class PTYSession;

@protocol PTYTabDelegate<NSObject>

- (void)tab:(PTYTab *)tab didChangeProcessingStatus:(BOOL)isProcessing;
- (void)tab:(PTYTab *)tab didChangeIcon:(NSImage *)icon;
- (void)tab:(PTYTab *)tab didChangeObjectCount:(NSInteger)objectCount;
- (void)tabKeyLabelsDidChangeForSession:(PTYSession *)session;
- (void)tab:(PTYTab *)tab currentLocationDidChange:(NSURL *)location;

@end

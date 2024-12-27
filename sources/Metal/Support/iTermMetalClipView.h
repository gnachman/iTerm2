//
//  iTermMetalClipView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/17.
//

#import <Cocoa/Cocoa.h>

@class iTermMTKView;

extern NSString *const iTermMetalClipViewWillScroll;

@interface iTermMetalClipView : NSClipView

@property (nonatomic, weak) iTermMTKView *metalView;
@property (nonatomic, weak) NSView *legacyView;
@property (nonatomic) BOOL useMetal;

- (void)performBlockWithoutShowingOverlayScrollers:(void (^ NS_NOESCAPE)(void))block;

@end

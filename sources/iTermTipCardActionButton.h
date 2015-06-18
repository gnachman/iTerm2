//
//  iTermWelcomeCardActionButton.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, iTermTipCardActionButtonAnimationState) {
    kTipCardButtonNotAnimating,
    kTipCardButtonAnimatingIn,
    kTipCardButtonAnimatingOut,
    kTipCardButtonAnimatingOutCurrently
};

@interface iTermTipCardActionButton : NSButton

@property(nonatomic, copy) void (^block)(id);
@property(nonatomic, assign) iTermTipCardActionButtonAnimationState animationState;
@property(nonatomic, assign) NSRect postAnimationFrame;
@property(nonatomic, assign, getter=isCollapsed) BOOL collapsed;

- (void)setIcon:(NSImage *)image;

@end

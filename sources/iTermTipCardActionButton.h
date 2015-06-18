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
};

@interface iTermTipCardActionButton : NSButton

@property(nonatomic, copy) void (^block)(id);
@property(nonatomic, assign) iTermTipCardActionButtonAnimationState animationState;
@property(nonatomic, assign) NSRect postAnimationFrame;

- (void)setIcon:(NSImage *)image;
- (void)setCollapsed:(BOOL)collapsed;

@end

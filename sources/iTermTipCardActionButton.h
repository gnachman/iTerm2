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

@interface iTermTipCardActionButton : NSControl

@property(nonatomic, copy) void (^block)(id);
@property(nonatomic, assign) iTermTipCardActionButtonAnimationState animationState;
@property(nonatomic, assign) NSRect postAnimationFrame;
@property(nonatomic, assign, getter=isCollapsed) BOOL collapsed;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, retain) NSImage *icon;

- (void)setIconFlipped:(BOOL)isFlipped;

@end

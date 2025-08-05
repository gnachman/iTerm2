//
//  PointerController.h
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "iTermKeyBindingAction.h"

@protocol PointerControllerDelegate;

@interface PointerController : NSObject

@property(nonatomic, assign) id<PointerControllerDelegate> delegate;

- (BOOL)mouseDown:(NSEvent *)event withTouches:(int)numTouches ignoreOption:(BOOL)ignoreOption reportable:(BOOL)reportable;
- (BOOL)mouseUp:(NSEvent *)event withTouches:(int)numTouches reportable:(BOOL)reportable;
- (BOOL)pressureChangeWithEvent:(NSEvent *)event;
- (void)swipeWithEvent:(NSEvent *)event;
- (BOOL)eventEmulatesRightClick:(NSEvent *)event reportable:(BOOL)reportable;
- (void)notifyLeftMouseDown;
- (BOOL)threeFingerTap:(NSEvent *)event;

@end

//
//  PSMTabDragAssistant.h
//  PSMTabBarControl
//
//  Created by John Pannell on 4/10/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

/*
 This class is a sigleton that manages the details of a tab drag and drop.  The details were beginning to overwhelm me when keeping all of this in the control and cells :-)
 */

#import <Cocoa/Cocoa.h>
#import "PSMTabBarControl.h"
@class PSMTabBarCell;
@class PSMTabDragWindow;

#define kPSMTabDragAnimationSteps 8
#define kPSMTabDragWindowAlpha 0.75

@interface PSMTabDragAssistant : NSObject

@property(nonatomic, retain) PSMTabBarControl *sourceTabBar;
@property(nonatomic, retain) PSMTabBarControl *destinationTabBar;
@property(nonatomic, retain) PSMTabBarCell *draggedCell;
@property(nonatomic, assign) int draggedCellIndex;  // For snap-back
@property(nonatomic, assign) BOOL isDragging;
@property(nonatomic, assign) NSPoint currentMouseLoc;
@property(nonatomic, retain) PSMTabBarCell *targetCell;

// Creation/destruction
+ (PSMTabDragAssistant *)sharedDragAssistant;

// Functionality
- (void)startAnimationWithOrientation:(PSMTabBarOrientation)orientation width:(CGFloat)width;
- (void)startDraggingCell:(PSMTabBarCell *)cell fromTabBar:(PSMTabBarControl *)control withMouseDownEvent:(NSEvent *)event;
- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc;
- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc;
- (void)draggingExitedTabBar:(PSMTabBarControl *)control;
- (void)performDragOperation:(id<NSDraggingInfo>)sender;
- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation;
- (void)finishDrag;

- (void)draggingBeganAt:(NSPoint)aPoint;
- (void)draggingMovedTo:(NSPoint)aPoint;

@end

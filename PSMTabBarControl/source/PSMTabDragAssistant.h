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
#define PI 3.1417

@interface PSMTabDragAssistant : NSObject {
    PSMTabBarControl            *_sourceTabBar;
    PSMTabBarControl            *_destinationTabBar;
    NSMutableSet                *_participatingTabBars;
    PSMTabBarCell               *_draggedCell;
    int                         _draggedCellIndex;   // for snap back
    BOOL                        _isDragging;
	
	// Support for dragging into new windows
	PSMTabDragWindow			*_dragTabWindow, *_dragViewWindow;
	NSSize						_dragWindowOffset;
	NSTimer						*_fadeTimer;
	
    // Animation
    NSTimer                     *_animationTimer;
    NSMutableArray              *_sineCurveWidths;
    NSPoint                     _currentMouseLoc;
    PSMTabBarCell               *_targetCell;
}

// Creation/destruction
+ (PSMTabDragAssistant *)sharedDragAssistant;

// Accessors
- (PSMTabBarControl *)sourceTabBar;
- (void)setSourceTabBar:(PSMTabBarControl *)tabBar;
- (PSMTabBarControl *)destinationTabBar;
- (void)setDestinationTabBar:(PSMTabBarControl *)tabBar;
- (PSMTabBarCell *)draggedCell;
- (void)setDraggedCell:(PSMTabBarCell *)cell;
- (int)draggedCellIndex;
- (void)setDraggedCellIndex:(int)value;
- (BOOL)isDragging;
- (void)setIsDragging:(BOOL)value;
- (NSPoint)currentMouseLoc;
- (void)setCurrentMouseLoc:(NSPoint)point;
- (PSMTabBarCell *)targetCell;
- (void)setTargetCell:(PSMTabBarCell *)cell;

// Functionality
- (void)startDraggingCell:(PSMTabBarCell *)cell fromTabBar:(PSMTabBarControl *)control withMouseDownEvent:(NSEvent *)event;
- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc;
- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc;
- (void)draggingExitedTabBar:(PSMTabBarControl *)control;
- (void)performDragOperation;
- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation;
- (void)finishDrag;

- (void)draggingBeganAt:(NSPoint)aPoint;
- (void)draggingMovedTo:(NSPoint)aPoint;

// Animation
- (void)animateDrag:(NSTimer *)timer;
- (void)calculateDragAnimationForTabBar:(PSMTabBarControl *)control;

// Placeholder
- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control withDraggedCell:(PSMTabBarCell *)cell;
- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control;
- (void)removeAllPlaceholdersFromTabBar:(PSMTabBarControl *)control;

@end

@interface PSMTabBarControl (DragAccessors)

- (id<PSMTabStyle>)style;
- (NSMutableArray *)cells;
- (void)setControlView:(id)view;
- (id)cellForPoint:(NSPoint)point cellFrame:(NSRectPointer)outFrame;
- (PSMTabBarCell *)lastVisibleTab;
- (int)numberOfVisibleTabs;

@end

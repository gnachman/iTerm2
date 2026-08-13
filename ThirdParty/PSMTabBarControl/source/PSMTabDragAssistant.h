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

// Present on a tab-bar drag's pasteboard when the dragged unit is a whole tab
// group rather than a single tab. A drop target can read group-ness off the
// NSDraggingInfo instead of querying the shared drag assistant.
extern NSString *const PSMTabDragIsGroupPasteboardType;

@interface PSMTabDragAssistant : NSObject

@property (nonatomic, readonly) BOOL dropping;

// Creation/destruction
+ (PSMTabDragAssistant *)sharedDragAssistant;

// Extra leftward shift applied to `tabBar`'s cells mid-drag so a drop slot
// past a scrollable bar's viewport is revealed (drag auto-scroll), else 0.
// The bar's drawRect reads this so its scroll clipping tracks the shift.
- (CGFloat)dragScrollNudgeForTabBar:(PSMTabBarControl *)tabBar;

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
- (void)startAnimationWithOrientation:(PSMTabBarOrientation)orientation width:(CGFloat)width;
- (void)startDraggingCell:(PSMTabBarCell *)cell fromTabBar:(PSMTabBarControl *)control withMouseDownEvent:(NSEvent *)event;
// Start dragging a whole tab group by its chip (the group's block flows through
// the same machinery as a single tab). `members` are the group's member tab cells.
- (void)startDraggingGroupWithChip:(PSMTabBarCell *)chip
                           members:(NSArray<PSMTabBarCell *> *)members
                        fromTabBar:(PSMTabBarControl *)control
                withMouseDownEvent:(NSEvent *)event;
- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc;
- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc;
- (void)draggingExitedTabBar:(PSMTabBarControl *)control;
- (void)performDragOperation:(id<NSDraggingInfo>)sender;
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

// Re-derive chip cells (plus the front-of-group and end-of-group join slots)
// into a chips-stripped, placeholder-laden cell list mid-drag. Exposed for
// unit tests of the slot layout.
- (void)reinsertDragChipsInTabBar:(PSMTabBarControl *)control;

// With chips present in `control`, the group id the just-dropped cell landed
// inside, or nil if it landed outside every group. Reads targetCell and
// draggedCell. Exposed for unit tests of drop-membership resolution.
- (NSString *)groupContainingDropOfCell:(PSMTabBarCell *)cell
                               inTabBar:(PSMTabBarControl *)control
    NS_SWIFT_NAME(groupContainingDrop(of:inTabBar:));

@end

@interface PSMTabBarControl (DragAccessors)

- (id<PSMTabStyle>)style;
- (NSMutableArray *)cells;
- (void)setControlView:(id)view;
- (id)cellForPoint:(NSPoint)point cellFrame:(NSRectPointer)outFrame;
- (PSMTabBarCell *)lastVisibleTab;
- (int)numberOfVisibleTabs;
- (float)availableCellWidthWithOverflow:(BOOL)withOverflow;
- (BOOL)tabBarIsScrollable;

@end

//
//  PSMTabDragAssistant.m
//  PSMTabBarControl
//
//  Created by John Pannell on 4/10/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMTabDragAssistant.h"

#import "PSMOverflowPopUpButton.h"
#import "PSMRolloverButton.h"
#import "PSMTabBarCell.h"
#import "PSMTabStyle.h"
#import "PSMTabDragWindow.h"

static const NSTimeInterval kAnimationDuration = 0.25;
static const NSTimeInterval kTimeBetweenAnimationFrames = 1 / 60.0;

@implementation PSMTabDragAssistant {
    NSMutableSet *_participatingTabBars;

    // Support for dragging into new windows
    PSMTabDragWindow *_dragTabWindow, *_dragViewWindow;
    NSSize _dragWindowOffset;

    // Animation
    NSTimer *_animationTimer;
    PSMTabBarOrientation _animationOrientation;
    NSSize _animationSize;
    BOOL _fading;
    NSTimeInterval _lastFrame;
}

#pragma mark - Creation/Destruction

+ (PSMTabDragAssistant *)sharedDragAssistant {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _participatingTabBars = [[NSMutableSet alloc] init];
    }

    return self;
}

- (void)dealloc {
    [_sourceTabBar release];
    [_destinationTabBar release];
    [_participatingTabBars release];
    [_draggedCell release];
    [_animationTimer release];
    [_targetCell release];
    [super dealloc];
}

- (void)setAlpha:(CGFloat)alpha
        ofWindow:(PSMTabDragWindow *)window
      completion:(void (^)())completion {
    _fading = YES;
    [self retain];
    [window fadeToAlpha:alpha duration:0.25 completion:^() {
        if (completion) {
            completion();
        }
        _fading = NO;
        [self release];
    }];
}

#pragma mark - Functionality

- (int)sineCurveWithOrientation:(PSMTabBarOrientation)orientation
                           size:(NSSize)size
                       progress:(CGFloat)progress {
    CGFloat cellStepSize = (orientation == PSMTabBarHorizontalOrientation) ? (size.width + 6) : (size.height + 1);
    CGFloat halfStep = cellStepSize / 2;
    double angle = M_PI * (progress + 0.5);
    return (int)round(cellStepSize - halfStep * (1 + sin(angle)));
}

- (void)startAnimation {
    _lastFrame = [NSDate timeIntervalSinceReferenceDate];
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:kTimeBetweenAnimationFrames
                                                       target:self
                                                     selector:@selector(animateDrag:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)startAnimationWithOrientation:(PSMTabBarOrientation)orientation width:(CGFloat)width {
    _animationOrientation = orientation;
    _animationSize = NSMakeSize(width, kPSMTabBarControlHeight);

    [self startAnimation];
}

- (void)startDraggingCell:(PSMTabBarCell *)cell
               fromTabBar:(PSMTabBarControl *)control
       withMouseDownEvent:(NSEvent *)event {
    self.isDragging = YES;
    self.sourceTabBar = control;
    self.destinationTabBar = control;
    [_participatingTabBars addObject:control];
    self.draggedCell = cell;
    self.draggedCellIndex = [control.cells indexOfObject:cell];

    NSRect cellFrame = [cell frame];

    _animationOrientation = control.orientation;
    _animationSize = cellFrame.size;

    // hide UI buttons
    control.overflowPopUpButton.hidden = YES;
    control.addTabButton.hidden = YES;

    [[NSCursor closedHandCursor] set];

    NSImage *dragImage = [cell dragImage];
    [cell.indicator removeFromSuperview];
    [self distributePlaceholdersInTabBar:control withDraggedCell:cell];

    if (control.isFlipped) {
        cellFrame.origin.y += cellFrame.size.height;
    }
    cell.highlighted = NO;
    [self startAnimation];

    [[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidBeginNotification
                                                        object:nil];

    // Retain the control in case the drag operation causes the control to be released
    [[control retain] autorelease];

    NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
    [pbItem setString:[@([control.cells indexOfObject:cell]) stringValue]
              forType:@"com.iterm2.psm.controlitem"];

    NSImage *imageToDrag;
    NSRect draggingRect;

    _dragTabWindow = [[PSMTabDragWindow dragWindowWithTabBarCell:cell
                                                           image:dragImage
                                                       styleMask:NSBorderlessWindowMask] retain];
    _dragTabWindow.imageOpacity = kPSMTabDragWindowAlpha;
    [_dragTabWindow orderFront:nil];

    cellFrame.origin.y -= cellFrame.size.height;

    imageToDrag = [[[NSImage alloc] initWithSize:NSMakeSize(1, 1)] autorelease];
    draggingRect = NSMakeRect(cellFrame.origin.x,
                              cellFrame.origin.y,
                              1,
                              1);

    NSDraggingItem *dragItem =
        [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
    [dragItem setDraggingFrame:draggingRect contents:imageToDrag];
    NSDraggingSession *draggingSession = [control beginDraggingSessionWithItems:@[ dragItem ]
                                                                          event:event
                                                                         source:control];
    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;
}

- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc {
    if (!_animationTimer) {
        [self startAnimation];
    }
    self.destinationTabBar = control;
    self.currentMouseLoc = mouseLoc;
    // hide UI buttons
    control.overflowPopUpButton.hidden = YES;
    control.addTabButton.hidden = YES;
    if (control.cells.count == 0 || ![control.cells.firstObject isPlaceholder]) {
        [self distributePlaceholdersInTabBar:control];
    }
    [_participatingTabBars addObject:control];

    // Tell the drag window to display only the header if there is one..
    if (_dragViewWindow) {
        [self setAlpha:0
              ofWindow:_dragViewWindow
            completion:^() {
                _dragTabWindow.imageOpacity = kPSMTabDragWindowAlpha;
            }];
        [_dragTabWindow orderFront:nil];
    }
}

- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc {
    self.destinationTabBar = control;
    self.currentMouseLoc = mouseLoc;
}

- (void)draggingExitedTabBar:(PSMTabBarControl *)control {
    self.destinationTabBar = nil;
    self.currentMouseLoc = NSMakePoint(-1.0, -1.0);

    if (_fading) {
       [self setAlpha:kPSMTabDragWindowAlpha
             ofWindow:_dragViewWindow
           completion:nil];
    } else if (_dragTabWindow) {
        // create a new floating drag window
        if (!_dragViewWindow) {
            NSImage *viewImage = nil;
            unsigned int styleMask = NSBorderlessWindowMask;

            if ([control.delegate respondsToSelector:@selector(tabView:imageForTabViewItem:offset:styleMask:)]) {
                // Get a custom image representation of the view to drag from the delegate.
                NSImage *tabImage = _dragTabWindow.image;
                NSPoint drawPoint;
                _dragWindowOffset = NSZeroSize;
                viewImage = [control.delegate tabView:control.tabView
                                  imageForTabViewItem:self.draggedCell.representedObject
                                               offset:&_dragWindowOffset
                                            styleMask:&styleMask];

                [viewImage lockFocus];

                // draw the tab into the returned window, that way we don't have two windows being
                // dragged (this assumes the tab will be on the window)
                drawPoint = NSMakePoint(_dragWindowOffset.width,
                                        viewImage.size.height - _dragWindowOffset.height);

                if (control.orientation == PSMTabBarHorizontalOrientation) {
                    drawPoint.y += kPSMTabBarControlHeight - tabImage.size.height;
                    _dragWindowOffset.height -= kPSMTabBarControlHeight - tabImage.size.height;
                } else {
                    drawPoint.x += control.frame.size.width - tabImage.size.width;
                }

                [tabImage drawAtPoint:drawPoint
                             fromRect:NSZeroRect
                            operation:NSCompositeSourceOver
                             fraction:1];

                [viewImage unlockFocus];
            } else {
                // The delegate doesn't give a custom image, so use an image of the view.
                NSView *tabView = [self.draggedCell.representedObject view];
                viewImage = [[[NSImage alloc] initWithSize:tabView.frame.size] autorelease];
                [viewImage lockFocus];
                [tabView drawRect:tabView.bounds];
                [viewImage unlockFocus];
            }

            if (styleMask | NSBorderlessWindowMask) {
                _dragWindowOffset.height += 22;
            }

            _dragViewWindow = [[PSMTabDragWindow dragWindowWithTabBarCell:self.draggedCell
                                                                    image:viewImage
                                                                styleMask:styleMask] retain];
            _dragViewWindow.imageOpacity = 0;
        }

        NSPoint windowOrigin = _dragTabWindow.frame.origin;
        windowOrigin.x -= _dragWindowOffset.width;
        windowOrigin.y += _dragWindowOffset.height;
        [_dragViewWindow setFrameTopLeftPoint:windowOrigin];
        [_dragViewWindow orderWindow:NSWindowBelow relativeTo:_dragTabWindow.windowNumber];

        // Set the window's alpha mask to zero if the last tab is being dragged.
        // Don't fade out the old window if the delegate doesn't respond to the new tab bar method,
        // just to be safe.
        if (self.sourceTabBar.tabView.numberOfTabViewItems == 1 &&
            self.sourceTabBar == control &&
            [self.sourceTabBar.delegate respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]) {

            self.sourceTabBar.window.alphaValue = 0.0;
            // Move the window out of the way so it doesn't block drop targets under it.
            [self.sourceTabBar.window setFrameOrigin:NSMakePoint(-1000000, -1000000)];
            _dragViewWindow.imageOpacity = kPSMTabDragWindowAlpha;
        } else {
            [self setAlpha:kPSMTabDragWindowAlpha
                  ofWindow:_dragViewWindow
                completion:nil];
        }
    }
}

- (void)performDragOperation:(id<NSDraggingInfo>)sender {
    // Move cell.
    int destinationIndex = [self.destinationTabBar.cells indexOfObject:self.targetCell];

    // There is the slight possibility of the targetCell now being set properly, so avoid errors.
    if (destinationIndex >= self.destinationTabBar.cells.count)  {
        destinationIndex = self.destinationTabBar.cells.count - 1;
    }

    if (!self.draggedCell) {
        // Find the index of where the dragged object was just dropped.
        int i;
        int insertIndex = 0;
        NSArray *cells = self.destinationTabBar.cells;
        PSMTabBarCell *before = nil;
        if (destinationIndex > 0) {
            before = cells[destinationIndex - 1];
        }
        PSMTabBarCell *after = nil;
        if (destinationIndex + 1 < cells.count) {
            after = cells[destinationIndex + 1];
        }

        NSTabViewItem *newTabViewItem =
            [self.destinationTabBar.delegate tabView:self.destinationTabBar.tabView
                             unknownObjectWasDropped:sender];
        cells = self.destinationTabBar.cells;
        if (!after) {
            insertIndex = cells.count;
        } else if (!before) {
            insertIndex = 0;
        } else {
            for (i = 0; i < cells.count; i++) {
                if (cells[i] == before) {
                    insertIndex = i + 1;
                    break;
                } else if (cells[i] == after) {
                    insertIndex = i;
                    break;
                }
            }
        }

        // If newTabViewItem is nil then simply cancel the drop.
        if (newTabViewItem) {
            [self.destinationTabBar.tabView insertTabViewItem:newTabViewItem atIndex:insertIndex];
            [self.destinationTabBar.tabView indexOfTabViewItem:newTabViewItem];
            // I'm not sure why, but calling -bindPropertiesForCell:andTabViewItem:
            // here causes there to be an extra binding. It seems to have its
            // bindings set when it's added to the control. Other paths through this
            // function do explicitly set the bindings.

            // Select the newly moved item in the destination tab view.
            [self.destinationTabBar.tabView selectTabViewItem:newTabViewItem];
        }
    } else {
        [self.destinationTabBar.cells replaceObjectAtIndex:destinationIndex
                                                withObject:self.draggedCell];
        self.draggedCell.controlView = self.destinationTabBar;

        // Move actual NSTabViewItem.
        if (self.sourceTabBar != self.destinationTabBar) {
            // Remove the tracking rects and bindings registered on the old tab.
            [self.sourceTabBar removeTrackingRect:self.draggedCell.closeButtonTrackingTag];
            [self.sourceTabBar removeTrackingRect:self.draggedCell.cellTrackingTag];
            [self.sourceTabBar removeTabForCell:self.draggedCell];

            int i;
            int insertIndex;
            NSArray *cells = self.destinationTabBar.cells;

            // Find the index of where the dragged cell was just dropped.
            for (i = 0, insertIndex = 0;
                 (i < cells.count) && (cells[i] != self.draggedCell);
                 i++, insertIndex++) {
                if ([cells[i] isPlaceholder]) {
                    insertIndex--;
                }
            }

            if ([self.sourceTabBar.delegate respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {
                [self.sourceTabBar.delegate tabView:self.sourceTabBar.tabView
                                    willDropTabViewItem:self.draggedCell.representedObject
                                               inTabBar:self.destinationTabBar];
            }

            [self.sourceTabBar.tabView removeTabViewItem:self.draggedCell.representedObject];
            [self.destinationTabBar.tabView insertTabViewItem:self.draggedCell.representedObject
                                                      atIndex:insertIndex];

            // Rebind the cell to the new control.
            [self.destinationTabBar initializeStateForCell:self.draggedCell];
            [self.destinationTabBar bindPropertiesForCell:self.draggedCell
                                           andTabViewItem:self.draggedCell.representedObject];

            // Select the newly moved item in the destination tab view.
            [self.destinationTabBar.tabView selectTabViewItem:self.draggedCell.representedObject];
        } else {
            // Have to do this before checking the index of a cell otherwise placeholders will
            // be counted.
            [self removeAllPlaceholdersFromTabBar:self.sourceTabBar];

            // Rearrange the tab view items.
            NSTabView *tabView = self.sourceTabBar.tabView;
            NSTabViewItem *item = self.draggedCell.representedObject;
            BOOL reselect = (tabView.selectedTabViewItem == item);
            int theIndex;
            NSArray *cells = self.sourceTabBar.cells;

            // Find the index of where the dragged cell was just dropped
            for (theIndex = 0;
                 theIndex < cells.count && cells[theIndex] != self.draggedCell;
                 theIndex++) {
                ;
            }

            if ([self.sourceTabBar.cells indexOfObject:self.draggedCell] != _draggedCellIndex &&
                [self.sourceTabBar.delegate respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {

                [self.sourceTabBar.delegate tabView:self.sourceTabBar.tabView
                                willDropTabViewItem:self.draggedCell.representedObject
                                           inTabBar:self.destinationTabBar];
            }
            // Temporarily disable the delegate in order to move the tab to a different index.
            id tempDelegate = [tabView delegate];
            tabView.delegate = nil;
            [[item retain] autorelease];
            [tabView removeTabViewItem:item];
            [tabView insertTabViewItem:item atIndex:theIndex];
            if (reselect) {
                [tabView selectTabViewItem:item];
            }
            tabView.delegate = tempDelegate;
        }

        if ((self.sourceTabBar != self.destinationTabBar ||
             [self.sourceTabBar.cells indexOfObject:self.draggedCell] != _draggedCellIndex) &&
            [self.sourceTabBar.delegate respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {

            [self.sourceTabBar.delegate tabView:self.sourceTabBar.tabView
                             didDropTabViewItem:self.draggedCell.representedObject
                                       inTabBar:self.destinationTabBar];
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification
                                                        object:nil];

    [self finishDrag];
}

- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation {
    if (self.isDragging) {
        // There was not a successful drop (performDragOperation).
        id sourceDelegate = self.sourceTabBar.delegate;

        //split off the dragged tab into a new window
        if (self.destinationTabBar == nil &&
            [sourceDelegate respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
            [sourceDelegate tabView:self.sourceTabBar.tabView
              shouldDropTabViewItem:self.draggedCell.representedObject
                           inTabBar:nil] &&
            [sourceDelegate respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]) {

            PSMTabBarControl *control = [sourceDelegate tabView:self.sourceTabBar.tabView
                                 newTabBarForDraggedTabViewItem:self.draggedCell.representedObject
                                                        atPoint:aPoint];

            if (control) {
                if ([sourceDelegate respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {
                    [sourceDelegate tabView:self.sourceTabBar.tabView
                        willDropTabViewItem:self.draggedCell.representedObject
                                   inTabBar:control];
                }
                //add the dragged tab to the new window
                [control.cells insertObject:self.draggedCell atIndex:0];

                //remove the tracking rects and bindings registered on the old tab
                [self.sourceTabBar removeTrackingRect:self.draggedCell.closeButtonTrackingTag];
                [self.sourceTabBar removeTrackingRect:self.draggedCell.cellTrackingTag];
                [self.sourceTabBar removeTabForCell:self.draggedCell];

                //rebind the cell to the new control
                [control initializeStateForCell:self.draggedCell];
                [control bindPropertiesForCell:self.draggedCell
                                andTabViewItem:self.draggedCell.representedObject];

                [self.draggedCell setControlView:control];

                [self.sourceTabBar.tabView removeTabViewItem:self.draggedCell.representedObject];

                [control.tabView addTabViewItem:self.draggedCell.representedObject];
                [control.window makeKeyAndOrderFront:nil];

                if ([sourceDelegate respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {
                    [sourceDelegate tabView:self.sourceTabBar.tabView
                         didDropTabViewItem:self.draggedCell.representedObject
                                   inTabBar:control];
                }
            } else {
                NSLog(@"Delegate returned no control to add to.");
                [self.sourceTabBar.cells insertObject:self.draggedCell atIndex:self.draggedCellIndex];
                self.sourceTabBar.window.alphaValue = 1;  // Make the window visible again.
            }

        } else {
            // Put cell back.
            [self.sourceTabBar.cells insertObject:self.draggedCell atIndex:self.draggedCellIndex];
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification
                                                            object:nil];

        [self finishDrag];
    }
}

- (void)finishDrag {
    if ([self.sourceTabBar.tabView numberOfTabViewItems] == 0 &&
        [self.sourceTabBar.delegate respondsToSelector:@selector(tabView:closeWindowForLastTabViewItem:)]) {
        [self.sourceTabBar.delegate tabView:self.sourceTabBar.tabView
              closeWindowForLastTabViewItem:self.draggedCell.representedObject];
    }

    if (_dragTabWindow) {
        [_dragTabWindow orderOut:nil];
        [_dragTabWindow release];
        _dragTabWindow = nil;
    }

    if (_dragViewWindow) {
        [_dragViewWindow orderOut:nil];
        [_dragViewWindow release];
        _dragViewWindow = nil;
    }

    self.isDragging = NO;
    [self removeAllPlaceholdersFromTabBar:self.sourceTabBar];
    self.sourceTabBar = nil;
    self.destinationTabBar = nil;
    for (PSMTabBarControl *tabBar in _participatingTabBars) {
        [self removeAllPlaceholdersFromTabBar:tabBar];
    }
    [_participatingTabBars removeAllObjects];
    self.draggedCell = nil;

    [_animationTimer invalidate];
    _animationTimer = nil;
    self.targetCell = nil;
}

- (void)draggingBeganAt:(NSPoint)aPoint {
    if (_dragTabWindow) {
        [_dragTabWindow setFrameTopLeftPoint:aPoint];

        if (self.sourceTabBar.tabView.numberOfTabViewItems == 1) {
            [self draggingExitedTabBar:self.sourceTabBar];
            _dragTabWindow.imageOpacity = 0;
        }
    }
}

- (void)draggingMovedTo:(NSPoint)aPoint {
    if (_dragTabWindow) {
        [_dragTabWindow setFrameTopLeftPoint:aPoint];

        if (_dragViewWindow) {
            // Move the view representation with the tab. The relative position of the dragged view
            // window will be different depending on the position of the tab bar relative to the
            // controlled tab view.

            aPoint.y -= _dragTabWindow.frame.size.height;
            aPoint.x -= _dragWindowOffset.width;
            aPoint.y += _dragWindowOffset.height;
            [_dragViewWindow setFrameTopLeftPoint:aPoint];
        }
    }
}

#pragma mark - Animation

- (void)animateDrag:(NSTimer *)timer {
    NSTimeInterval startOfUpdate = [NSDate timeIntervalSinceReferenceDate];
    NSArray* objects = [_participatingTabBars allObjects];
    for (PSMTabBarControl *tabBar in objects) {
        if ([_participatingTabBars containsObject:tabBar]) {
            [self calculateDragAnimationForTabBar:tabBar];
            [[NSRunLoop currentRunLoop] performSelector:@selector(display)
                                                 target:tabBar
                                               argument:nil
                                                  order:1
                                                  modes:@[ NSEventTrackingRunLoopMode,
                                                           NSDefaultRunLoopMode ]];
        }
    }
    _lastFrame = startOfUpdate;
}

- (void)calculateDragAnimationForTabBar:(PSMTabBarControl *)control
{
    BOOL removeFlag = YES;
    NSMutableArray *cells = control.cells;
    float position;

    if (control.orientation == PSMTabBarHorizontalOrientation) {
        position = [control.style leftMarginForTabBarControl];
    } else {
        position = [control.style topMarginForTabBarControl];
    }

    // Identify target cell.
    NSPoint mouseLoc = [self currentMouseLoc];
    if (self.destinationTabBar == control) {
        removeFlag = NO;
        if (mouseLoc.x < control.style.leftMarginForTabBarControl) {
            self.targetCell = cells.firstObject;
        } else {
            NSRect overCellRect;
            PSMTabBarCell *overCell = [control cellForPoint:mouseLoc cellFrame:&overCellRect];
            if (overCell){
                // Mouse among cells - placeholder
                if (overCell.isPlaceholder) {
                    self.targetCell = overCell;
                } else if (control.orientation == PSMTabBarHorizontalOrientation) {
                    // Non-placeholders - horizontal orientation
                    if (mouseLoc.x < (overCellRect.origin.x + (overCellRect.size.width / 2.0))) {
                        // Mouse on left side of cell.
                        self.targetCell = cells[([cells indexOfObject:overCell] - 1)];
                    } else {
                        // Mouse on right side of cell.
                        self.targetCell = cells[([cells indexOfObject:overCell] + 1)];
                    }
                } else {
                    // Non-placeholders - vertical orientation.
                    if (mouseLoc.y < (overCellRect.origin.y + (overCellRect.size.height / 2.0))) {
                        // Mouse on top of cell.
                        self.targetCell = cells[([cells indexOfObject:overCell] - 1)];
                    } else {
                        // Mouse on bottom of cell.
                        self.targetCell = cells[([cells indexOfObject:overCell] + 1)];
                    }
                }
            } else {
                // Out at end - must find proper cell (could be more in overflow menu).
                self.targetCell = [control lastVisibleTab];
            }
        }
    } else {
        self.targetCell = nil;
    }

    for (PSMTabBarCell *cell in cells) {
        NSRect newRect = [cell frame];
        if (!cell.isInOverflowMenu) {
            if (cell.isPlaceholder) {
                const NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _lastFrame;
                NSTimeInterval marginalProgress = elapsed / kAnimationDuration;
                if (cell == self.targetCell) {
                    cell.animationProgress = cell.animationProgress + marginalProgress;
                } else {
                    cell.animationProgress = cell.animationProgress - marginalProgress;
                    if (cell.animationProgress > 0){
                        removeFlag = NO;
                    }
                }

                if (control.orientation == PSMTabBarHorizontalOrientation) {
                    newRect.size.width = [self sineCurveWithOrientation:_animationOrientation
                                                                   size:_animationSize
                                                               progress:cell.animationProgress];
                } else {
                    newRect.size.height = [self sineCurveWithOrientation:_animationOrientation
                                                                    size:_animationSize
                                                                progress:cell.animationProgress];
                }
            }
        } else {
            break;
        }

        if (control.orientation == PSMTabBarHorizontalOrientation) {
            newRect.origin.x = position;
            position += newRect.size.width;
        } else {
            newRect.origin.y = position;
            position += newRect.size.height;
        }
        cell.frame = newRect;
        if (cell.indicator) {
            cell.indicator.frame = [control.style indicatorRectForTabCell:cell];
        }
    }
    if (removeFlag){
        [_participatingTabBars removeObject:control];
        [self removeAllPlaceholdersFromTabBar:control];
    }
}

#pragma mark - Placeholders

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control
                       withDraggedCell:(PSMTabBarCell *)cell {
    // Called upon first drag - must distribute placeholders.
    [self distributePlaceholdersInTabBar:control];
    // Replace dragged cell with a placeholder, and clean up surrounding cells.
    int cellIndex = [control.cells indexOfObject:cell];
    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:self.draggedCell.frame
                                                                expanded:YES
                                                           inControlView:control] autorelease];
    [control.cells replaceObjectAtIndex:cellIndex withObject:pc];
    [control.cells removeObjectAtIndex:(cellIndex + 1)];
    [control.cells removeObjectAtIndex:(cellIndex - 1)];
}

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control {
    PSMTabBarCell *draggedCell = self.draggedCell;
    NSRect draggedCellFrame;
    if (draggedCell) {
        draggedCellFrame = [draggedCell frame];
    } else {
        draggedCellFrame = [control.cells.firstObject frame];
    }

    const int numVisibleTabs = control.numberOfVisibleTabs;
    for (int i = 0; i < numVisibleTabs; i++) {
        PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:draggedCellFrame
                                                                    expanded:NO
                                                               inControlView:control] autorelease];
        [control.cells insertObject:pc atIndex:(2 * i)];
    }

    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:draggedCellFrame
                                                                expanded:NO
                                                           inControlView:control] autorelease];
    if (control.cells.count > (2 * numVisibleTabs)) {
        [control.cells insertObject:pc atIndex:(2 * numVisibleTabs)];
    } else {
        [control.cells addObject:pc];
    }
}

- (void)removeAllPlaceholdersFromTabBar:(PSMTabBarControl *)control {
    for (NSInteger i = control.cells.count - 1; i >= 0; i--){
        PSMTabBarCell *cell = control.cells[i];
        if (cell.isPlaceholder) {
            [control.cells removeObject:cell];
        }
    }
    // Redraw.
    [[NSRunLoop currentRunLoop] performSelector:@selector(update)
                                         target:control
                                       argument:nil
                                          order:1
                                          modes:@[ NSEventTrackingRunLoopMode, NSDefaultRunLoopMode ]];
    [[NSRunLoop currentRunLoop] performSelector:@selector(display)
                                         target:control
                                       argument:nil
                                          order:1
                                          modes:@[ NSEventTrackingRunLoopMode, NSDefaultRunLoopMode ]];
}

@end

//
//  PSMTabDragAssistant.m
//  PSMTabBarControl
//
//  Created by John Pannell on 4/10/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMTabDragAssistant.h"

#import "DebugLogging.h"
#import "PSMTabBarCell.h"
#import "PSMTabStyle.h"
#import "PSMTabDragWindow.h"
#import <os/signpost.h>
#import <CoreVideo/CoreVideo.h>
#import <sys/time.h>

#if PSM_DEBUG_DRAG_PERFORMANCE
static os_log_t PSMTabDragLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.iterm2.tabdrag", "animation");
    });
    return log;
}
#endif

@interface PSMTabDragAssistant()
@property (nonatomic, retain) PSMTabBarControl *sourceTabBar;
@property (nonatomic, retain) PSMTabBarControl *destinationTabBar;
@property (nonatomic, retain) PSMTabBarCell *draggedCell;
@property (nonatomic) int draggedCellIndex;   // for snap back
@property (nonatomic) BOOL isDragging;
@property (nonatomic) NSPoint currentMouseLoc;
@property (nonatomic, retain) PSMTabBarCell *targetCell;

// While the last tab in a window is being dragged, the window is hidden so
// that you can drop the tab on targets beneath the window. Setting the
// window's alpha to 0 is not sufficient to allow this, unfortunately. So we
// orderOut: the window temporarily until the drag operation is complete and
// then order it back in. This property remembers the window and keeps a
// reference to it.
@property (nonatomic, retain) NSWindow *temporarilyHiddenWindow;

- (void)displayLinkDidFire;
@end

// CVDisplayLink callback - runs on a background thread, so we need to get to main thread
// Using CFRunLoopPerformBlock with event tracking mode since dispatch_async doesn't work well during drags
static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *now,
                                    const CVTimeStamp *outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *context) {
    @autoreleasepool {
        PSMTabDragAssistant *assistant = (__bridge PSMTabDragAssistant *)context;
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            [assistant displayLinkDidFire];
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }
    return kCVReturnSuccess;
}

@implementation PSMTabDragAssistant {
    PSMTabBarControl *_destinationTabBar;
    NSMutableSet *_participatingTabBars;

    // A window that shows the tab while it's being dragged.
    PSMTabDragWindow *_dragTabWindow;

    // A window that shows a ghost pane while a tab is being dragged out of its tab bar
    PSMTabDragWindow *_dragViewWindow;
    NSSize _dragWindowOffset;
    NSTimer *_fadeTimer;

    // Animation
    NSTimer *_animationTimer;
    NSMutableArray *_sineCurveWidths;
    NSPoint _currentMouseLoc;
    PSMTabBarCell *_targetCell;
    NSSize _dragTabOffset;

    // The drag window stays at its initial position along the cross-axis
    // (Y for horizontal tab bars, X for vertical) until movement exceeds a threshold.
    NSPoint _initialDragWindowOrigin;
    BOOL _dragThresholdExceeded;
    BOOL _dragWindowOriginInitialized;

    // CVDisplayLink for tracking mouse during drag (bypasses NSDraggingSession throttling)
    CVDisplayLinkRef _displayLink;
    NSPoint _lastPolledMouseLocation;

#if PSM_DEBUG_DRAG_PERFORMANCE
    // Performance instrumentation: track timer fire times over the last 5 seconds.
    NSMutableArray<NSNumber *> *_timerFireTimes;

    int _pollingEventCount;
    CFAbsoluteTime _pollingFirstEventTime;
    CFAbsoluteTime _pollingLastEventTime;
    // Timestamp overlay window for debugging
    NSWindow *_timestampWindow;
    NSTextField *_timestampLabel;
#endif
}

#pragma mark -
#pragma mark Creation/Destruction

+ (PSMTabDragAssistant *)sharedDragAssistant {
    static dispatch_once_t onceToken;
    static PSMTabDragAssistant *sharedDragAssistant = nil;
    dispatch_once(&onceToken, ^{
        sharedDragAssistant = [[PSMTabDragAssistant alloc] init];
    });
    return sharedDragAssistant;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _participatingTabBars = [[NSMutableSet alloc] init];
        _sineCurveWidths = [[NSMutableArray alloc] initWithCapacity:kPSMTabDragAnimationSteps];
#if PSM_DEBUG_DRAG_PERFORMANCE
        _timerFireTimes = [[NSMutableArray alloc] init];
#endif
    }

    return self;
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
    [_sourceTabBar release];
    [_destinationTabBar release];
    [_participatingTabBars release];
    [_draggedCell release];
    [_animationTimer release];
    [_sineCurveWidths release];
    [_targetCell release];
    [_temporarilyHiddenWindow release];
#if PSM_DEBUG_DRAG_PERFORMANCE
    [_timerFireTimes release];
#endif
    [super dealloc];
}

#pragma mark -
#pragma mark Functionality

- (void)addSineCurveWidthsWithOrientation:(PSMTabBarOrientation)orientation size:(NSSize)size {
    // Use a cosine-based curve where width[i] + width[N-i] = cellWidth.
    // This ensures that when one placeholder shrinks and another grows during a target change,
    // the total width remains constant, preventing tabs from stuttering/shifting.
    const int cellWidth = (orientation == PSMTabBarHorizontalOrientation) ? (int)size.width : (int)size.height;
    const int steps = kPSMTabDragAnimationSteps;
    for (int i = 0; i < steps; i++) {
        // Formula: cellWidth * (1 - cos(π * i / (steps-1))) / 2
        // This gives 0 at i=0, cellWidth at i=steps-1, and width[i] + width[steps-1-i] = cellWidth
        const double fraction = (1.0 - cos(PI * (double)i / (double)(steps - 1))) / 2.0;
        const int thisWidth = (int)round(cellWidth * fraction);
        [_sineCurveWidths addObject:@(thisWidth)];
    }
}

- (void)startAnimation {
#if PSM_DEBUG_DRAG_PERFORMANCE
    NSLog(@"[PSMTabDrag] Starting animation timer at 30 FPS");
    [_timerFireTimes removeAllObjects];
#endif
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                       target:self
                                                     selector:@selector(animateDrag:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (CGFloat)height {
    if (self.sourceTabBar) {
        return self.sourceTabBar.height;
    } else if (self.destinationTabBar) {
        return self.destinationTabBar.height;
    } else {
        return 24;
    }
}

- (void)startAnimationWithOrientation:(PSMTabBarOrientation)orientation width:(CGFloat)width {
    if (_sineCurveWidths.count == 0) {
        [self addSineCurveWidthsWithOrientation:orientation
                                           size:NSMakeSize(width, self.height)];
    }
    [self startAnimation];
}

- (void)startDraggingCell:(PSMTabBarCell *)cell
               fromTabBar:(PSMTabBarControl *)control
       withMouseDownEvent:(NSEvent *)event {
    [self setIsDragging:YES];
    [self setSourceTabBar:control];
    [self setDestinationTabBar:control];
    [_participatingTabBars addObject:control];
    [self setDraggedCell:cell];
    [self setDraggedCellIndex:[[control cells] indexOfObject:cell]];

    NSRect cellFrame = [cell frame];
    // list of widths for animation
    [self addSineCurveWidthsWithOrientation:[control orientation] size:cellFrame.size];

    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];

    [[NSCursor closedHandCursor] set];

    NSImage *dragImage = [cell dragImage];
    [[cell indicator] removeFromSuperview];
    [self distributePlaceholdersInTabBar:control withDraggedCell:cell];

    // Set the initial mouse location so the first animation frame can correctly
    // track the target cell.
    [self setCurrentMouseLoc:[control convertPoint:[event locationInWindow] fromView:nil]];

    if ([control isFlipped]) {
        cellFrame.origin.y += cellFrame.size.height;
    }
    [cell setHighlighted:NO];
    [self startAnimation];

    [[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidBeginNotification
                                                        object:nil];

    // Retain the control in case the drag operation causes the control to be released
    [control retain];

    NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
    [pbItem setString:[@([[control cells] indexOfObject:cell]) stringValue]
              forType:@"com.iterm2.psm.controlitem"];

    NSImage *imageToDrag;
    NSRect draggingRect;

    _dragTabWindow = [[PSMTabDragWindow dragWindowWithTabBarCell:cell
                                                           image:dragImage
                                                       styleMask:NSWindowStyleMaskBorderless] retain];
    [_dragTabWindow setAlphaValue:kPSMTabDragWindowAlpha];
    [_dragTabWindow orderFront:nil];

    cellFrame.origin.y -= cellFrame.size.height;

    imageToDrag = [[[NSImage alloc] initWithSize:NSMakeSize(1, 1)] autorelease];
    draggingRect = NSMakeRect(cellFrame.origin.x,
                              cellFrame.origin.y,
                              1,
                              1);

    NSDraggingItem *dragItem = [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
    [dragItem setDraggingFrame:draggingRect contents:imageToDrag];
    NSPoint windowCoord = event.locationInWindow;
    NSPoint cellOriginInWindow = [control convertPoint:cellFrame.origin toView:nil];
    _dragTabOffset = NSMakeSize(windowCoord.x - cellOriginInWindow.x,
                                windowCoord.y - cellOriginInWindow.y);
    ILog(@"Begin dragging session for tab bar %p", control);
    NSDraggingSession *draggingSession = [control beginDraggingSessionWithItems:@[ dragItem ]
                                                                          event:event
                                                                         source:control];
    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;

    // Set up high-frequency polling timer to track mouse position during drag
    // This bypasses the throttled NSDraggingSession callbacks
#if PSM_DEBUG_DRAG_PERFORMANCE
    _pollingEventCount = 0;
    _pollingFirstEventTime = 0;
    _pollingLastEventTime = 0;
#endif
    _lastPolledMouseLocation = NSZeroPoint;

    // Create CVDisplayLink for display-synchronized mouse tracking
#if PSM_DEBUG_DRAG_PERFORMANCE
    NSLog(@"[PSMTabDrag] Starting CVDisplayLink for mouse tracking");
#endif
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, (__bridge void *)self);
    CVDisplayLinkStart(_displayLink);

#if PSM_DEBUG_DRAG_PERFORMANCE
    // Create timestamp overlay window for debugging
    [self createTimestampWindow];
#endif

    [control release];
}

- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc {
    if (!_animationTimer) {
        [self startAnimation];
    }
    [self setDestinationTabBar:control];
    [self setCurrentMouseLoc:mouseLoc];
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];
    if ([[control cells] count] == 0 || ![[[control cells] objectAtIndex:0] isPlaceholder]) {
        [self distributePlaceholdersInTabBar:control];
    }
    [_participatingTabBars addObject:control];

    // Tell the drag window to display only the header if there is one.
    if (_dragViewWindow) {
        if (_fadeTimer) {
            [_fadeTimer invalidate];
        }

        [_dragTabWindow orderFront:nil];
        _fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeOutDragWindow:) userInfo:nil repeats:YES];
    }
}

- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc {
    if ([self destinationTabBar] != control) {
        [self setDestinationTabBar:control];
    }
    [self setCurrentMouseLoc:mouseLoc];
}

- (void)draggingExitedTabBar:(PSMTabBarControl *)control {
    [self setDestinationTabBar:nil];
    [self setCurrentMouseLoc:NSMakePoint(-1.0, -1.0)];

    if (_fadeTimer) {
        [_fadeTimer invalidate];
        _fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                      target:self
                                                    selector:@selector(fadeInDragWindow:)
                                                    userInfo:nil
                                                     repeats:YES];
    } else if (_dragTabWindow) {
        if (![control.delegate tabViewDragShouldExitWindow:control.tabView]) {
            return;
        }
        // create a new floating drag window
        if (!_dragViewWindow) {
            NSImage *viewImage = nil;
            NSWindowStyleMask styleMask = NSWindowStyleMaskBorderless;

            if ([control delegate] &&
                [[control delegate] respondsToSelector:@selector(tabView:imageForTabViewItem:styleMask:)]) {
                // get a custom image representation of the view to drag from the delegate
                NSImage *tabImage = [[_dragTabWindow contentView] image];
                NSPoint drawPoint;
                _dragWindowOffset = NSZeroSize;
                viewImage = [[control delegate] tabView:[control tabView]
                                    imageForTabViewItem:[[self draggedCell] representedObject]
                                              styleMask:&styleMask];
                const NSRect draggedCellFrame = self.draggedCell.frame;
                NSPoint drawOffset = [control convertPoint:draggedCellFrame.origin toView:nil];
                drawOffset.y = control.window.frame.size.height - drawOffset.y;
                const NSRect controlFrameInWindowCoords = [control convertRect:control.bounds toView:nil];
                
                NSSize distanceFromWindowTopLeftToControlTopLeft;
                if ([control orientation] == PSMTabBarHorizontalOrientation) {
                    distanceFromWindowTopLeftToControlTopLeft =
                        NSMakeSize(controlFrameInWindowCoords.origin.x,
                                   control.window.frame.size.height - NSMaxY(controlFrameInWindowCoords)/* - control.frame.size.height*/);
                } else {
                    distanceFromWindowTopLeftToControlTopLeft = NSZeroSize;
                }
                _dragWindowOffset = NSMakeSize(draggedCellFrame.origin.x +  // Position of cell relative to tab bar
                                               _dragTabOffset.width +
                                               distanceFromWindowTopLeftToControlTopLeft.width,
                                               draggedCellFrame.origin.y -
                                               _dragTabOffset.height +
                                               distanceFromWindowTopLeftToControlTopLeft.height);

                // _dragWindowOffset.height gives distance from top of window to mouse
                [viewImage lockFocus];

                // draw the tab into the returned window, that way we don't have two windows being
                // dragged (this assumes the tab will be on the window)
                drawPoint = NSMakePoint(drawOffset.x,
                                        [viewImage size].height - drawOffset.y);

                if ([control orientation] == PSMTabBarHorizontalOrientation) {
                    switch (control.tabLocation) {
                        case PSMTab_TopTab:
                        case PSMTab_LeftTab:
                            drawPoint.y = viewImage.size.height - self.draggedCell.frame.size.height;
                            break;
                        case PSMTab_BottomTab:
                            drawPoint.y = 0;
                            break;
                    }
                } else {
                    drawPoint.x += [control frame].size.width - [tabImage size].width;
                    drawPoint.y -= control.insets.top;
                }

                [tabImage drawAtPoint:drawPoint
                             fromRect:NSZeroRect
                            operation:NSCompositingOperationSourceOver
                             fraction:1];

                [viewImage unlockFocus];
            } else {
                // The delegate doesn't give a custom image, so use an image of the view.
                NSView *tabView = [[[self draggedCell] representedObject] view];
                viewImage = [[[NSImage alloc] initWithSize:[tabView frame].size] autorelease];
                [viewImage lockFocus];
                [tabView drawRect:[tabView bounds]];
                [viewImage unlockFocus];
            }

            if (self.sourceTabBar.tabLocation == PSMTab_LeftTab) {
                _dragWindowOffset.height += self.height;
            } else if (styleMask & NSWindowStyleMaskFullSizeContentView) {
               _dragWindowOffset.height += self.draggedCell.frame.size.height;
            }

            _dragViewWindow = [[PSMTabDragWindow dragWindowWithTabBarCell:[self draggedCell]
                                                                    image:viewImage
                                                                styleMask:NSWindowStyleMaskBorderless] retain];
            [_dragViewWindow setAlphaValue:0.0];
            // Select the tab that was selected before dragging began.
            [[self sourceTabBar] dragWillExitTabBar];
        }

        const NSPoint bottomLeftOfTabWindow = [_dragTabWindow frame].origin;
        const NSPoint windowOrigin = NSMakePoint(bottomLeftOfTabWindow.x + _dragWindowOffset.width,
                                                 bottomLeftOfTabWindow.y + _dragWindowOffset.height);

        [_dragViewWindow setFrameTopLeftPoint:windowOrigin];
        [_dragViewWindow orderWindow:NSWindowBelow relativeTo:[_dragTabWindow windowNumber]];

        // Set the window's alpha mask to zero if the last tab is being dragged.
        // Don't fade out the old window if the delegate doesn't respond to the new tab bar method,
        // just to be safe.
        if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 1 &&
            [self sourceTabBar] == control &&
            [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]) {

            [[[self sourceTabBar] window] setAlphaValue:0.0];
            self.temporarilyHiddenWindow = [[self sourceTabBar] window];
            [self.temporarilyHiddenWindow orderOut:nil];
            [_dragViewWindow setAlphaValue:kPSMTabDragWindowAlpha];
        } else {
            _fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                          target:self
                                                        selector:@selector(fadeInDragWindow:)
                                                        userInfo:nil
                                                         repeats:YES];
        }
    }
}

- (void)performDragOperation:(id<NSDraggingInfo>)sender {
    _dropping = YES;
    [self reallyPerformDragOperation:sender];
    _dropping = NO;
}

- (void)reallyPerformDragOperation:(id<NSDraggingInfo>)sender {
    // Move cell.
    int destinationIndex = [[[self destinationTabBar] cells] indexOfObject:[self targetCell]];

    //there is the slight possibility of the targetCell now being set properly, so avoid errors
    if (destinationIndex >= [[[self destinationTabBar] cells] count])  {
        destinationIndex = [[[self destinationTabBar] cells] count] - 1;
    }

    // Enforce pinned/unpinned boundary on the final drop index.
    if ([self draggedCell]) {
        NSArray *destCells = [[self destinationTabBar] cells];
        BOOL draggedIsPinned = [[self draggedCell] isPinned];
        if (draggedIsPinned) {
            // Insert at end of pinned section at most.
            int lastPinned = -1;
            for (int ci = 0; ci < (int)[destCells count]; ci++) {
                PSMTabBarCell *c = destCells[ci];
                if (!c.isPlaceholder && c.isPinned && c != [self draggedCell]) {
                    lastPinned = ci;
                }
            }
            if (destinationIndex > lastPinned + 1) {
                destinationIndex = lastPinned + 1;
            }
        } else {
            // Insert at start of unpinned section at earliest.
            int firstUnpinned = (int)[destCells count];
            for (int ci = 0; ci < (int)[destCells count]; ci++) {
                PSMTabBarCell *c = destCells[ci];
                if (!c.isPlaceholder && !c.isPinned && c != [self draggedCell]) {
                    firstUnpinned = ci;
                    break;
                }
            }
            if (destinationIndex < firstUnpinned) {
                destinationIndex = firstUnpinned;
            }
        }
    }

    if (![self draggedCell]) {
        // Find the index of where the dragged object was just dropped.
        int i;
        int insertIndex = 0;
        NSArray *cells = [[self destinationTabBar] cells];
        PSMTabBarCell *before = nil;
        if (destinationIndex > 0) {
            before = [cells objectAtIndex:destinationIndex - 1];
        }
        PSMTabBarCell *after = nil;
        if (destinationIndex < [cells count] - 1) {
            after = [cells objectAtIndex:destinationIndex + 1];
        }

        NSTabViewItem *newTabViewItem = [[[self destinationTabBar] delegate] tabView:[[self destinationTabBar] tabView]
                                                             unknownObjectWasDropped:sender];
        cells = [[self destinationTabBar] cells];
        if (!after) {
            insertIndex = [cells count];
        } else if (!before) {
            insertIndex = 0;
        } else {
            for (i = 0; i < [cells count]; i++) {
                if ([cells objectAtIndex:i] == before) {
                    insertIndex = i + 1;
                    break;
                } else if ([cells objectAtIndex:i] == after) {
                    insertIndex = i;
                    break;
                }
            }
        }

        // If newTabViewItem is nil then simply cancel the drop.
        if (newTabViewItem) {
            [[[self destinationTabBar] tabView] insertTabViewItem:newTabViewItem atIndex:insertIndex];
            [[[self destinationTabBar] tabView] indexOfTabViewItem:newTabViewItem];
            // I'm not sure why, but calling -bindPropertiesForCell:andTabViewItem:
            // here causes there to be an extra binding. It seems to have its
            // bindings set when it's added to the control. Other paths through this
            // function do explicitly set the bindings.

            // Select the newly moved item in the destination tab view.
            [[[self destinationTabBar] tabView] selectTabViewItem:newTabViewItem];
        }
    } else {
        [[[self destinationTabBar] cells] replaceObjectAtIndex:destinationIndex withObject:[self draggedCell]];
        [[self draggedCell] setControlView:[self destinationTabBar]];

        // move actual NSTabViewItem
        if ([self sourceTabBar] != [self destinationTabBar]) {
            //remove the tracking rects and bindings registered on the old tab
            [self.draggedCell removeCloseButtonTrackingRectFrom:self.sourceTabBar];
            [self.draggedCell removeCellTrackingRectFrom:self.sourceTabBar];
            [[self sourceTabBar] removeTabForCell:[self draggedCell]];

            int i, insertIndex;
            NSArray *cells = [[self destinationTabBar] cells];

            //find the index of where the dragged cell was just dropped
            for (i = 0, insertIndex = 0; (i < [cells count]) && ([cells objectAtIndex:i] != [self draggedCell]); i++, insertIndex++) {
                if ([[cells objectAtIndex:i] isPlaceholder]) {
                    insertIndex--;
                }
            }

            if ([[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {
                [[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView]
                                    willDropTabViewItem:[[self draggedCell] representedObject]
                                               inTabBar:[self destinationTabBar]];
            }

            [[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
            [[[self destinationTabBar] tabView] insertTabViewItem:[[self draggedCell] representedObject] atIndex:insertIndex];

            //rebind the cell to the new control
            [[self destinationTabBar] initializeStateForCell:[self draggedCell]];
            [[self destinationTabBar] bindPropertiesForCell:[self draggedCell] andTabViewItem:[[self draggedCell] representedObject]];

            //select the newly moved item in the destination tab view
            [[[self destinationTabBar] tabView] selectTabViewItem:[[self draggedCell] representedObject]];
        } else {
            //have to do this before checking the index of a cell otherwise placeholders will be counted
            [self removeAllPlaceholdersFromTabBar:[self sourceTabBar]];

            //rearrange the tab view items
            NSTabView *tabView = [[self sourceTabBar] tabView];
            NSTabViewItem *item = [[self draggedCell] representedObject];
            BOOL reselect = ([tabView selectedTabViewItem] == item);
            int theIndex;
            NSArray *cells = [[self sourceTabBar] cells];

            //find the index of where the dragged cell was just dropped
            for (theIndex = 0; theIndex < [cells count] && [cells objectAtIndex:theIndex] != [self draggedCell]; theIndex++);

            if ([[[self sourceTabBar] cells] indexOfObject:[self draggedCell]] != _draggedCellIndex &&
                [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {

                [[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView]
                                    willDropTabViewItem:[[self draggedCell] representedObject]
                                               inTabBar:[self destinationTabBar]];
            }
            //temporarily disable the delegate in order to move the tab to a different index
            id tempDelegate = [tabView delegate];
            [tabView setDelegate:nil];
            [item retain];
            [tabView removeTabViewItem:item];
            [tabView insertTabViewItem:item atIndex:theIndex];
            [item release];
            if (reselect) {
                [tabView selectTabViewItem:item];
            }
            [tabView setDelegate:tempDelegate];
        }

        if (([self sourceTabBar] != [self destinationTabBar] ||
             [[[self sourceTabBar] cells] indexOfObject:[self draggedCell]] != _draggedCellIndex) &&
            [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {

            [[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView]
                                 didDropTabViewItem:[[self draggedCell] representedObject]
                                           inTabBar:[self destinationTabBar]];
        }
    }

    PSMTabBarControl *destination = [[[self destinationTabBar] retain] autorelease];
    PSMTabBarControl *source = [[[self sourceTabBar] retain] autorelease];

    if (_draggedCell && [destination.cells containsObject:_draggedCell]) {
        [destination.tabView selectTabViewItem:[_draggedCell representedObject]];
    }
    [self finishDrag];

    [destination sanityCheck:@"destination performDragOperation"];
    [source sanityCheck:@"source performDragOperation"];
}

- (BOOL)shouldCreateNewWindowOnDrop:(BOOL *)moveWindow {
    id sourceDelegate = [[self sourceTabBar] delegate];
    return ([self destinationTabBar] == nil &&
            [sourceDelegate respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:moveSourceWindow:)] &&
            [sourceDelegate tabView:[[self sourceTabBar] tabView]
              shouldDropTabViewItem:[[self draggedCell] representedObject]
                           inTabBar:nil
                   moveSourceWindow:moveWindow] &&
            [sourceDelegate respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]);
}

- (void)createNewWindowWithTabBar:(PSMTabBarControl *)control height:(CGFloat)height origin:(const NSPoint)origin {
    id sourceDelegate = [[self sourceTabBar] delegate];
    if (!control) {
        ELog(@"Delegate returned no control to add to.");
        [self cancelDrag];
        [[self sourceTabBar] sanityCheck:@"delegate returned no control to add to"];
    }

    if ([sourceDelegate respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {
        [sourceDelegate tabView:[[self sourceTabBar] tabView]
            willDropTabViewItem:[[self draggedCell] representedObject]
                       inTabBar:control];
    }
    // Add the dragged tab to the new window.
    [[control cells] insertObject:[self draggedCell] atIndex:0];

    // Remove the tracking rects and bindings registered on the old tab.
    [self.draggedCell removeCloseButtonTrackingRectFrom:self.sourceTabBar];
    [self.draggedCell removeCellTrackingRectFrom:self.sourceTabBar];
    [[self sourceTabBar] removeTabForCell:[self draggedCell]];

    //rebind the cell to the new control
    [control initializeStateForCell:[self draggedCell]];
    [control bindPropertiesForCell:[self draggedCell] andTabViewItem:[[self draggedCell] representedObject]];

    [[self draggedCell] setControlView:control];

    [[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];

    void (^fixOriginBlock)(void) = nil;
    switch (self.sourceTabBar.tabLocation) {
        case PSMTab_BottomTab: {
            NSPoint bottomLeft = origin;
            bottomLeft.y -= height;
            fixOriginBlock = ^{
                [control.window setFrameOrigin:bottomLeft];
            };
            break;
        }
        case PSMTab_LeftTab:
        case PSMTab_TopTab: {
            NSPoint topLeft = control.window.frame.origin;
            topLeft.y += control.window.frame.size.height;
            fixOriginBlock = ^{
                [control.window setFrameTopLeftPoint:topLeft];
            };
            break;
        }
    }

    // This could cause an already correctly positioned window to resize.
    [[control tabView] addTabViewItem:[[self draggedCell] representedObject]];

    if (fixOriginBlock) {
        fixOriginBlock();
    }

    [[control window] makeKeyAndOrderFront:nil];

    if ([sourceDelegate respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {
        [sourceDelegate tabView:[[self sourceTabBar] tabView]
             didDropTabViewItem:[[self draggedCell] representedObject]
                       inTabBar:control];
    }
    [control sanityCheck:@"add dragged tab to new window"];
}

- (void)cancelDrag {
    [[[self sourceTabBar] cells] insertObject:[self draggedCell] atIndex:[self draggedCellIndex]];
    [[[self sourceTabBar] window] setAlphaValue:1];  // Make the window visible again.
    [[[self sourceTabBar] window] orderFront:nil];
    [[self sourceTabBar] dragDidFinish];
}

- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation {
    if (![self isDragging]) {
        // There was not a successful drop (performDragOperation).
        return;
    }
    PSMTabBarControl *destination = [[[self destinationTabBar] retain] autorelease];
    PSMTabBarControl *source = [[[self sourceTabBar] retain] autorelease];
    id sourceDelegate = [[self sourceTabBar] delegate];

    const NSPoint origin = [self topLeftPointOfDragViewWindowForMouseLocation:aPoint];
    BOOL moveSourceWindow = NO;
    if ([self shouldCreateNewWindowOnDrop:&moveSourceWindow]) {
        const CGFloat height = _dragViewWindow.frame.size.height;
        PSMTabBarControl *control = [sourceDelegate tabView:[[self sourceTabBar] tabView]
                             newTabBarForDraggedTabViewItem:[[self draggedCell] representedObject]
                                                    atPoint:origin];

        [self createNewWindowWithTabBar:control height:height origin:origin];

    } else if (moveSourceWindow) {
        [self cancelDragMovingWindowTo:origin];
    } else {
        [self cancelDrag];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification object:nil];

    [self finishDrag];

    [source sanityCheck:@"draggedImageEndedAt - source"];
    [destination sanityCheck:@"draggedImageEndedAt - destination"];
}

- (void)cancelDragMovingWindowTo:(const NSPoint)origin {
    const CGFloat height = _dragViewWindow.frame.size.height;
    NSWindow *window = self.sourceTabBar.window;
    [self cancelDrag];

    switch (self.sourceTabBar.tabLocation) {
        case PSMTab_BottomTab: {
            NSPoint bottomLeft = origin;
            bottomLeft.y -= height;
            [window setFrameOrigin:bottomLeft];
            break;
        }
        case PSMTab_LeftTab:
        case PSMTab_TopTab: {
            NSPoint topLeft = origin;
            [window setFrameTopLeftPoint:topLeft];
            break;
        }
    }
}

- (void)finishDrag {
    ILog(@"Drag of %p finished from\n%@", [self sourceTabBar], [NSThread callStackSymbols]);

#if PSM_DEBUG_DRAG_PERFORMANCE
    // Close timestamp overlay
    [self closeTimestampWindow];
#endif

    // Stop CVDisplayLink and log final stats
    if (_displayLink) {
#if PSM_DEBUG_DRAG_PERFORMANCE
        double elapsed = _pollingFirstEventTime > 0 ? (CACurrentMediaTime() - _pollingFirstEventTime) : 0;
        double avgRate = elapsed > 0 ? (_pollingEventCount / elapsed) : 0;
        NSLog(@"[PSMTabDrag] Stopping CVDisplayLink. Total updates: %d over %.2fs (avg %.1f updates/sec)",
              _pollingEventCount, elapsed, avgRate);
#endif
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }

    [[self sourceTabBar] dragDidFinish];
    if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 0 &&
        [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:closeWindowForLastTabViewItem:)]) {
        [[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView]
                  closeWindowForLastTabViewItem:[[self draggedCell] representedObject]];
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

    const BOOL wasDragging = self.isDragging;
    [self setIsDragging:NO];
    _dragWindowOriginInitialized = NO;
    [self removeAllPlaceholdersFromTabBar:[self sourceTabBar]];
    [self setSourceTabBar:nil];
    [self setDestinationTabBar:nil];
    for (PSMTabBarControl *tabBar in _participatingTabBars) {
        [self removeAllPlaceholdersFromTabBar:tabBar];
    }
    [_participatingTabBars removeAllObjects];
    [self setDraggedCell:nil];
#if PSM_DEBUG_DRAG_PERFORMANCE
    NSLog(@"[PSMTabDrag] Stopping animation timer. Final FPS stats: %d frames recorded", (int)_timerFireTimes.count);
#endif
    [_animationTimer invalidate];
    _animationTimer = nil;
    [_sineCurveWidths removeAllObjects];
    [self setTargetCell:nil];
    self.temporarilyHiddenWindow = nil;
    [[self sourceTabBar] sanityCheck:@"finishDrag source"];
    [[self destinationTabBar] sanityCheck:@"finishDrag destination"];
    if (wasDragging) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification object:nil];
    }
}

- (void)moveDragTabWindowForMouseLocation:(NSPoint)aPoint {
    [_dragTabWindow setFrameTopLeftPoint:NSMakePoint(aPoint.x - _dragTabOffset.width,
                                                     aPoint.y - _dragTabOffset.height)];
}

- (void)draggingBeganAt:(NSPoint)aPoint {
    ILog(@"Drag of %p began with current event %@ in window with frame %@ from\n%@", [self sourceTabBar], [NSApp currentEvent], NSStringFromRect(self.sourceTabBar.window.frame), [NSThread callStackSymbols]);
    if (_dragTabWindow) {
        // Remember the initial drag window origin so it can stay stable along the
        // cross-axis until movement exceeds a threshold.
        _initialDragWindowOrigin = NSMakePoint(aPoint.x - _dragTabOffset.width,
                                               aPoint.y - _dragTabOffset.height);
        _dragThresholdExceeded = NO;
        _dragWindowOriginInitialized = YES;

        [self moveDragTabWindowForMouseLocation:aPoint];

        if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 1) {
            [self draggingExitedTabBar:[self sourceTabBar]];
            [_dragTabWindow setAlphaValue:0.0];
        }
    }
}

- (NSPoint)topLeftPointOfDragViewWindowForMouseLocation:(NSPoint)mouseLocation {
    NSPoint aPoint = mouseLocation;
    aPoint.y -= [_dragTabWindow frame].size.height;
    aPoint.x -= _dragWindowOffset.width;
    aPoint.y += _dragWindowOffset.height;
    return aPoint;
}

// Adjusts the mouse location to keep the drag window stable along the cross-axis
// (Y for horizontal tab bars, X for vertical) until movement exceeds a threshold.
- (NSPoint)adjustedMouseLocationForDrag:(NSPoint)mouseLocation {
    if (_dragThresholdExceeded) {
        return mouseLocation;
    }

    NSPoint windowOrigin = NSMakePoint(mouseLocation.x - _dragTabOffset.width,
                                       mouseLocation.y - _dragTabOffset.height);

    const NSSize kDragThreshold = { .width = 40.0, .height = 20.0 };
    CGFloat deviation;
    CGFloat threshold;
    if ([[self sourceTabBar] orientation] == PSMTabBarHorizontalOrientation) {
        deviation = fabs(windowOrigin.y - _initialDragWindowOrigin.y);
        threshold = kDragThreshold.height;
    } else {
        deviation = fabs(windowOrigin.x - _initialDragWindowOrigin.x);
        threshold = kDragThreshold.width;
    }

    if (deviation > threshold) {
        _dragThresholdExceeded = YES;
        return mouseLocation;
    }

    // Clamp to initial position along the cross-axis.
    if ([[self sourceTabBar] orientation] == PSMTabBarHorizontalOrientation) {
        mouseLocation.y = _initialDragWindowOrigin.y + _dragTabOffset.height;
    } else {
        mouseLocation.x = _initialDragWindowOrigin.x + _dragTabOffset.width;
    }
    return mouseLocation;
}

#if PSM_DEBUG_DRAG_PERFORMANCE
- (void)createTimestampWindow {
    // Create a small overlay window to show the current timestamp with microsecond precision
    // Position it at top-left of main screen, below menu bar
    NSScreen *mainScreen = [NSScreen mainScreen];
    CGFloat screenHeight = mainScreen.frame.size.height;
    CGFloat windowWidth = 280;
    CGFloat windowHeight = 30;
    // Position near top-left, accounting for menu bar (~25px)
    NSRect frame = NSMakeRect(20, screenHeight - windowHeight - 50, windowWidth, windowHeight);

    _timestampWindow = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [_timestampWindow setLevel:NSStatusWindowLevel + 1];
    [_timestampWindow setOpaque:NO];
    [_timestampWindow setBackgroundColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.8]];
    [_timestampWindow setIgnoresMouseEvents:YES];

    _timestampLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(5, 5, 270, 20)];
    [_timestampLabel setBezeled:NO];
    [_timestampLabel setDrawsBackground:NO];
    [_timestampLabel setEditable:NO];
    [_timestampLabel setSelectable:NO];
    [_timestampLabel setTextColor:[NSColor greenColor]];
    [_timestampLabel setFont:[NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightMedium]];
    [_timestampLabel setAlignment:NSTextAlignmentCenter];

    [[_timestampWindow contentView] addSubview:_timestampLabel];
    [_timestampWindow orderFront:nil];

    [self updateTimestampDisplay];
}

- (void)updateTimestampDisplay {
    if (!_timestampWindow) return;

    // Get current time with microsecond precision
    struct timeval tv;
    gettimeofday(&tv, NULL);

    // Format as HH:MM:SS.microseconds
    time_t rawtime = tv.tv_sec;
    struct tm *timeinfo = localtime(&rawtime);

    NSString *timestamp = [NSString stringWithFormat:@"%02d:%02d:%02d.%06d",
                          timeinfo->tm_hour,
                          timeinfo->tm_min,
                          timeinfo->tm_sec,
                          tv.tv_usec];

    [_timestampLabel setStringValue:timestamp];
}

- (void)closeTimestampWindow {
    if (_timestampWindow) {
        [_timestampWindow orderOut:nil];
        [_timestampLabel release];
        _timestampLabel = nil;
        [_timestampWindow release];
        _timestampWindow = nil;
    }
}
#endif

- (void)displayLinkDidFire {
    if (!self.isDragging || !_dragTabWindow || !_dragWindowOriginInitialized) {
        return;
    }

#if PSM_DEBUG_DRAG_PERFORMANCE
    // Update timestamp display
    [self updateTimestampDisplay];
#endif

    // Get current mouse location in screen coordinates
    // This is the same coordinate system used by draggingSession:movedToPoint:
    NSPoint screenPoint = [NSEvent mouseLocation];

    // Skip if mouse hasn't moved
    if (NSEqualPoints(screenPoint, _lastPolledMouseLocation)) {
        return;
    }
    _lastPolledMouseLocation = screenPoint;

#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime now = CACurrentMediaTime();
    _pollingEventCount++;

    if (_pollingFirstEventTime == 0) {
        _pollingFirstEventTime = now;
    }

    double sinceLast = _pollingLastEventTime > 0 ? (now - _pollingLastEventTime) * 1000 : 0;
    double elapsed = now - _pollingFirstEventTime;
    double avgRate = elapsed > 0 ? (_pollingEventCount / elapsed) : 0;

    // Log every 60th update, or first 3
    if (_pollingEventCount <= 3 || _pollingEventCount % 60 == 0) {
        NSLog(@"[PSMTabDrag] DisplayLink #%d: interval=%.1fms, avg=%.1f updates/sec, pos=(%.0f, %.0f)",
              _pollingEventCount, sinceLast, avgRate, screenPoint.x, screenPoint.y);
    }
    _pollingLastEventTime = now;
#endif

    // Apply the cross-axis clamping logic and update window positions
    NSPoint adjustedPoint = [self adjustedMouseLocationForDrag:screenPoint];
    [self moveDragTabWindowForMouseLocation:adjustedPoint];

    if (_dragViewWindow) {
        [_dragViewWindow setFrameTopLeftPoint:[self topLeftPointOfDragViewWindowForMouseLocation:adjustedPoint]];
    }
}

- (void)draggingMovedTo:(NSPoint)aPoint {
#if PSM_DEBUG_DRAG_PERFORMANCE
    static CFAbsoluteTime lastMoveTime = 0;
    static int moveCount = 0;
    CFAbsoluteTime now = CACurrentMediaTime();

    if (lastMoveTime > 0) {
        CFAbsoluteTime interval = now - lastMoveTime;
        moveCount++;
        // Log every 30th call to avoid spam
        if (moveCount % 30 == 0) {
            NSLog(@"[PSMTabDrag] draggingMovedTo interval: %.2fms (call #%d)", interval * 1000, moveCount);
        }
    }
    lastMoveTime = now;

    os_signpost_interval_begin(PSMTabDragLog(), OS_SIGNPOST_ID_EXCLUSIVE, "draggingMovedTo", "");
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
#endif

    if (_dragTabWindow) {
        // Don't update window position here - the polling timer handles it with
        // fresher coordinates. The NSDraggingSession callbacks are severely throttled
        // and provide stale positions that would cause the window to jump back.
        //
        // The polling timer in pollMouseLocation: uses [NSEvent mouseLocation] which
        // returns current coordinates, unlike the lagging draggingSession:movedToPoint:.
    }

#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    if ((end - start) * 1000 > 1.0) {  // Only log if > 1ms
        NSLog(@"[PSMTabDrag] draggingMovedTo took %.2fms", (end - start) * 1000);
    }
    os_signpost_interval_end(PSMTabDragLog(), OS_SIGNPOST_ID_EXCLUSIVE, "draggingMovedTo", "");
#endif
}

- (void)fadeInDragWindow:(NSTimer *)timer {
    float value = [_dragViewWindow alphaValue];
    if (value >= kPSMTabDragWindowAlpha || _dragTabWindow == nil) {
        [timer invalidate];
        _fadeTimer = nil;
    } else {
        [_dragTabWindow setAlphaValue:[_dragTabWindow alphaValue] - 0.15];
        [_dragViewWindow setAlphaValue:value + 0.15];
    }
}

- (void)fadeOutDragWindow:(NSTimer *)timer {
    float value = [_dragViewWindow alphaValue];
    if (value <= 0.0) {
        [_dragViewWindow setAlphaValue:0.0];
        [_dragTabWindow setAlphaValue:kPSMTabDragWindowAlpha];

        [timer invalidate];
        _fadeTimer = nil;
    } else {
        if ([_dragTabWindow alphaValue] < kPSMTabDragWindowAlpha) {
            [_dragTabWindow setAlphaValue:[_dragTabWindow alphaValue] + 0.15];
        }
        [_dragViewWindow setAlphaValue:value - 0.15];
    }
}

#pragma mark -
#pragma mark Animation

- (void)animateDrag:(NSTimer *)timer {
#if PSM_DEBUG_DRAG_PERFORMANCE
    os_signpost_interval_begin(PSMTabDragLog(), OS_SIGNPOST_ID_EXCLUSIVE, "animateDrag", "");
    CFAbsoluteTime overallStart = CFAbsoluteTimeGetCurrent();

    // Track frame rate over the last 5 seconds.
    CFAbsoluteTime now = CACurrentMediaTime();
    [_timerFireTimes addObject:@(now)];
    const CFAbsoluteTime windowSeconds = 5.0;
    while (_timerFireTimes.count > 0 && (now - _timerFireTimes.firstObject.doubleValue) > windowSeconds) {
        [_timerFireTimes removeObjectAtIndex:0];
    }
    if (_timerFireTimes.count > 1) {
        CFAbsoluteTime windowStart = _timerFireTimes.firstObject.doubleValue;
        CFAbsoluteTime elapsed = now - windowStart;
        double fps = (_timerFireTimes.count - 1) / elapsed;
        NSLog(@"[PSMTabDrag] Timer effective FPS over last %.1fs: %.1f (%d frames)",
              elapsed, fps, (int)_timerFireTimes.count);
    }
#endif

    NSArray* objects = [_participatingTabBars allObjects];
    for (int i = 0; i < [objects count]; ++i) {
        PSMTabBarControl* tabBar = [objects objectAtIndex:i];
        if ([_participatingTabBars containsObject:tabBar]) {
#if PSM_DEBUG_DRAG_PERFORMANCE
            CFAbsoluteTime calcStart = CFAbsoluteTimeGetCurrent();
#endif
            [self calculateDragAnimationForTabBar:tabBar];
#if PSM_DEBUG_DRAG_PERFORMANCE
            CFAbsoluteTime calcEnd = CFAbsoluteTimeGetCurrent();
            NSLog(@"[PSMTabDrag] calculateDragAnimationForTabBar took %.2f ms", (calcEnd - calcStart) * 1000);

            CFAbsoluteTime displayStart = CFAbsoluteTimeGetCurrent();
#endif
            [[NSRunLoop currentRunLoop] performSelector:@selector(display)
                                                 target:tabBar
                                               argument:nil
                                                  order:1
                                                  modes:@[ NSEventTrackingRunLoopMode, NSDefaultRunLoopMode ]];
#if PSM_DEBUG_DRAG_PERFORMANCE
            CFAbsoluteTime displayEnd = CFAbsoluteTimeGetCurrent();
            NSLog(@"[PSMTabDrag] display scheduling took %.2f ms", (displayEnd - displayStart) * 1000);
#endif
        }
    }

#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime overallEnd = CFAbsoluteTimeGetCurrent();
    NSLog(@"[PSMTabDrag] animateDrag total took %.2f ms", (overallEnd - overallStart) * 1000);
    os_signpost_interval_end(PSMTabDragLog(), OS_SIGNPOST_ID_EXCLUSIVE, "animateDrag", "");
#endif
}

- (void)calculateDragAnimationForTabBar:(PSMTabBarControl *)control {
#if PSM_DEBUG_DRAG_PERFORMANCE
    os_signpost_interval_begin(PSMTabDragLog(), OS_SIGNPOST_ID_EXCLUSIVE, "calculateDragAnimation", "");
    CFAbsoluteTime targetCellStart = CFAbsoluteTimeGetCurrent();
#endif

    BOOL removeFlag = YES;
    NSArray *cells = [control cells];
    int i, cellCount = [cells count];
    float position = [control orientation] == PSMTabBarHorizontalOrientation ? [[control style] leftMarginForTabBarControl] : [[control style] topMarginForTabBarControl];

    // identify target cell
    // mouse at beginning of tabs
    NSPoint mouseLoc = [self currentMouseLoc];
    PSMTabBarCell *proposedTarget = nil;

    if ([self destinationTabBar] == control) {
        removeFlag = NO;
        if (mouseLoc.x < [[control style] leftMarginForTabBarControl]) {
            proposedTarget = [cells objectAtIndex:0];
        } else {
            NSRect overCellRect;
            PSMTabBarCell *overCell = [control cellForPoint:mouseLoc cellFrame:&overCellRect];
            if (overCell) {
                // mouse among cells - placeholder
                if ([overCell isPlaceholder]) {
                    proposedTarget = overCell;
                } else if ([control orientation] == PSMTabBarHorizontalOrientation) {
                    // non-placeholders - horizontal orientation
                    if (mouseLoc.x < (overCellRect.origin.x + (overCellRect.size.width / 2.0))) {
                        // mouse on left side of cell
                        proposedTarget = [cells objectAtIndex:([cells indexOfObject:overCell] - 1)];
                    } else {
                        // mouse on right side of cell
                        proposedTarget = [cells objectAtIndex:([cells indexOfObject:overCell] + 1)];
                    }
                } else {
                    // non-placeholders - vertical orientation
                    if (mouseLoc.y < (overCellRect.origin.y + (overCellRect.size.height / 2.0))) {
                        // mouse on top of cell
                        proposedTarget = [cells objectAtIndex:([cells indexOfObject:overCell] - 1)];
                    } else {
                        // mouse on bottom of cell
                        proposedTarget = [cells objectAtIndex:([cells indexOfObject:overCell] + 1)];
                    }
                }
            } else {
                // out at end - must find proper cell (could be more in overflow menu)
                proposedTarget = [control lastVisibleTab];
            }
        }

        // Apply hysteresis to prevent target bouncing due to animation-induced boundary shifts.
        // Only change target if it's different AND the mouse is sufficiently into the new target area.
        PSMTabBarCell *currentTarget = [self targetCell];
        if (proposedTarget != currentTarget && currentTarget != nil && proposedTarget != nil) {
            // Check if mouse is far enough into the proposed target to accept the change
            NSRect proposedFrame = [proposedTarget frame];
            CGFloat hysteresis = 8.0; // pixels of hysteresis

            if ([control orientation] == PSMTabBarHorizontalOrientation) {
                NSInteger proposedIndex = [cells indexOfObject:proposedTarget];
                NSInteger currentIndex = [cells indexOfObject:currentTarget];

                if (proposedIndex > currentIndex) {
                    // Moving right - mouse must be hysteresis pixels past the left edge of proposed target
                    if (mouseLoc.x < proposedFrame.origin.x + hysteresis) {
                        proposedTarget = currentTarget; // Keep current target
                    }
                } else {
                    // Moving left - mouse must be hysteresis pixels before the right edge of proposed target
                    if (mouseLoc.x > NSMaxX(proposedFrame) - hysteresis) {
                        proposedTarget = currentTarget; // Keep current target
                    }
                }
            } else {
                NSInteger proposedIndex = [cells indexOfObject:proposedTarget];
                NSInteger currentIndex = [cells indexOfObject:currentTarget];

                if (proposedIndex > currentIndex) {
                    // Moving down
                    if (mouseLoc.y < proposedFrame.origin.y + hysteresis) {
                        proposedTarget = currentTarget;
                    }
                } else {
                    // Moving up
                    if (mouseLoc.y > NSMaxY(proposedFrame) - hysteresis) {
                        proposedTarget = currentTarget;
                    }
                }
            }
        }

        // Enforce pinned/unpinned boundary: pinned tabs stay in the pinned zone,
        // unpinned tabs stay in the unpinned zone.
        if (proposedTarget && [self draggedCell]) {
            BOOL draggedIsPinned = [[self draggedCell] isPinned];
            NSInteger proposedIndex = [cells indexOfObject:proposedTarget];

            // Find boundary: last pinned index and first unpinned index.
            NSInteger lastPinnedIndex = -1;
            NSInteger firstUnpinnedIndex = (NSInteger)[cells count];
            for (NSInteger ci = 0; ci < (NSInteger)[cells count]; ci++) {
                PSMTabBarCell *c = cells[ci];
                if (!c.isPlaceholder && c.isPinned) {
                    lastPinnedIndex = ci;
                }
                if (!c.isPlaceholder && !c.isPinned && firstUnpinnedIndex == (NSInteger)[cells count]) {
                    firstUnpinnedIndex = ci;
                }
            }

            if (draggedIsPinned) {
                // Clamp to pinned zone: [0, lastPinnedIndex].
                // The placeholder for the dragged cell is in cells, so use lastPinnedIndex + 1
                // to allow dropping at the end of pinned section.
                NSInteger maxIndex = lastPinnedIndex + 1;
                if (maxIndex < (NSInteger)[cells count] && proposedIndex > maxIndex) {
                    proposedTarget = cells[maxIndex];
                }
            } else {
                // Clamp to unpinned zone: [firstUnpinnedIndex, end].
                NSInteger minIndex = firstUnpinnedIndex > 0 ? firstUnpinnedIndex - 1 : 0;
                if (proposedIndex < minIndex) {
                    proposedTarget = cells[minIndex];
                }
            }
        }

        [self setTargetCell:proposedTarget];
    } else {
        [self setTargetCell:nil];
    }

#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime targetCellEnd = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime cellLoopStart = CFAbsoluteTimeGetCurrent();
    int cellsProcessed = 0;
#endif

    for (i = 0; i < cellCount; i++) {
        PSMTabBarCell *cell = [cells objectAtIndex:i];
        NSRect newRect = [cell frame];
        if (![cell isInOverflowMenu]) {
#if PSM_DEBUG_DRAG_PERFORMANCE
            cellsProcessed++;
#endif
            if([cell isPlaceholder]){
                if (cell == [self targetCell]) {
                    NSInteger newStep = [cell currentStep] + 1;
                    if (newStep >= kPSMTabDragAnimationSteps) {
                        newStep = kPSMTabDragAnimationSteps - 1;
                    }
                    [cell setCurrentStep:newStep];
                } else {
                    NSInteger newStep = [cell currentStep] - 1;
                    if (newStep < 0) {
                        newStep = 0;
                    }
                    [cell setCurrentStep:newStep];
                    if([cell currentStep] > 0){
                        removeFlag = NO;
                    }
                }

                if ([control orientation] == PSMTabBarHorizontalOrientation) {
                    newRect.size.width = [[_sineCurveWidths objectAtIndex:[cell currentStep]] intValue];
                } else {
                    newRect.size.height = [[_sineCurveWidths objectAtIndex:[cell currentStep]] intValue];
                }
            }
        } else {
            break;
        }

        if ([control orientation] == PSMTabBarHorizontalOrientation) {
            newRect.origin.x = position;
            position += newRect.size.width;
            // Only add intercell spacing after non-placeholder cells (real tabs).
            // Placeholders only contribute their width, not additional spacing.
            // This prevents a 1-point shift when placeholders transition from
            // width 0 to width > 0.
            if (![cell isPlaceholder]) {
                position += [[control style] intercellSpacing];
            }
        } else {
            newRect.origin.y = position;
            position += newRect.size.height;
            // Only add intercell spacing after non-placeholder cells (real tabs).
            if (![cell isPlaceholder]) {
                position += [[control style] intercellSpacing];
            }
        }
        [cell setFrame:newRect];
        if([cell indicator])
            [[cell indicator] setFrame:[[control style] indicatorRectForTabCell:cell]];
    }

#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime cellLoopEnd = CFAbsoluteTimeGetCurrent();
    NSLog(@"[PSMTabDrag] calculateDragAnimation breakdown: targetCell=%.2fms, cellLoop=%.2fms (%d cells)",
          (targetCellEnd - targetCellStart) * 1000,
          (cellLoopEnd - cellLoopStart) * 1000,
          cellsProcessed);
#endif

    if (removeFlag) {
        [_participatingTabBars removeObject:control];
        [self removeAllPlaceholdersFromTabBar:control];
    }
#if PSM_DEBUG_DRAG_PERFORMANCE
    os_signpost_interval_end(PSMTabDragLog(), OS_SIGNPOST_ID_EXCLUSIVE, "calculateDragAnimation", "");
#endif
}

#pragma mark -
#pragma mark Placeholders

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control
                       withDraggedCell:(PSMTabBarCell *)cell {
    // called upon first drag - must distribute placeholders
    [self distributePlaceholdersInTabBar:control];
    // replace dragged cell with a placeholder, and clean up surrounding cells
    int cellIndex = [[control cells] indexOfObject:cell];
    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:YES inControlView:control] autorelease];
    pc.truncationStyle = cell.truncationStyle;
    [[control cells] replaceObjectAtIndex:cellIndex withObject:pc];
    [[control cells] removeObjectAtIndex:(cellIndex + 1)];
    [[control cells] removeObjectAtIndex:(cellIndex - 1)];
    // Set the expanded placeholder as the initial target to prevent the first
    // animation frame from picking the wrong target when currentMouseLoc hasn't
    // been set yet.
    [self setTargetCell:pc];
    ILog(@"distributePlaceholdersInTabBar:withDraggedCell:%@", cell);
    return;
}

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control {
    int i;
    int numVisibleTabs = [control numberOfVisibleTabs];
    PSMTabBarCell *draggedCell = [self draggedCell];
    NSRect draggedCellFrame;
    NSLineBreakMode truncationStyle;
    if (draggedCell) {
        draggedCellFrame = [draggedCell frame];
        truncationStyle = draggedCell.truncationStyle;
    } else {
        draggedCellFrame = [[[control cells] objectAtIndex:0] frame];
        truncationStyle = [[[control cells] objectAtIndex:0] truncationStyle];
    }
    for (i = 0; i < numVisibleTabs; i++) {
        PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:draggedCellFrame expanded:NO inControlView:control] autorelease];
        pc.truncationStyle = truncationStyle;
        [[control cells] insertObject:pc atIndex:(2 * i)];
    }

    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:draggedCellFrame expanded:NO inControlView:control] autorelease];
    pc.truncationStyle = truncationStyle;
    if ([[control cells] count] > (2 * numVisibleTabs)) {
        [[control cells] insertObject:pc atIndex:(2 * numVisibleTabs)];
    } else {
        [[control cells] addObject:pc];
    }
    ILog(@"distributePlaceholdersInTabBar draggedCell=%@", draggedCell);
}

- (void)removeAllPlaceholdersFromTabBar:(PSMTabBarControl *)control {
    int i, cellCount = [[control cells] count];
    for (i = (cellCount - 1); i >= 0; i--) {
        PSMTabBarCell *cell = [[control cells] objectAtIndex:i];
        if ([cell isPlaceholder]) {
            [control removeCell:cell];
        }
    }
    // redraw
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

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    if ([aCoder allowsKeyedCoding]) {
        [aCoder encodeObject:_sourceTabBar forKey:@"sourceTabBar"];
        [aCoder encodeObject:_destinationTabBar forKey:@"destinationTabBar"];
        [aCoder encodeObject:_participatingTabBars forKey:@"participatingTabBars"];
        [aCoder encodeObject:_draggedCell forKey:@"draggedCell"];
        [aCoder encodeInt:_draggedCellIndex forKey:@"draggedCellIndex"];
        [aCoder encodeBool:_isDragging forKey:@"isDragging"];
        [aCoder encodeObject:_animationTimer forKey:@"animationTimer"];
        [aCoder encodeObject:_sineCurveWidths forKey:@"sineCurveWidths"];
        [aCoder encodePoint:_currentMouseLoc forKey:@"currentMouseLoc"];
        [aCoder encodeObject:_targetCell forKey:@"targetCell"];
    }
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        if ([aDecoder allowsKeyedCoding]) {
            _sourceTabBar = [[aDecoder decodeObjectForKey:@"sourceTabBar"] retain];
            _destinationTabBar = [[aDecoder decodeObjectForKey:@"destinationTabBar"] retain];
            _participatingTabBars = [[aDecoder decodeObjectForKey:@"participatingTabBars"] retain];
            _draggedCell = [[aDecoder decodeObjectForKey:@"draggedCell"] retain];
            _draggedCellIndex = [aDecoder decodeIntForKey:@"draggedCellIndex"];
            _isDragging = [aDecoder decodeBoolForKey:@"isDragging"];
            _animationTimer = [[aDecoder decodeObjectForKey:@"animationTimer"] retain];
            _sineCurveWidths = [[aDecoder decodeObjectForKey:@"sineCurveWidths"] retain];
            _currentMouseLoc = [aDecoder decodePointForKey:@"currentMouseLoc"];
            _targetCell = [[aDecoder decodeObjectForKey:@"targetCell"] retain];
        }
    }
    return self;
}

@end

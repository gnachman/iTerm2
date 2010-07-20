//
//  PSMTabDragAssistant.m
//  PSMTabBarControl
//
//  Created by John Pannell on 4/10/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import "PSMTabDragAssistant.h"
#import "PSMTabBarCell.h"
#import "PSMTabStyle.h"
#import "PSMTabDragWindow.h"

@implementation PSMTabDragAssistant

static PSMTabDragAssistant *sharedDragAssistant = nil;

#pragma mark -
#pragma mark Creation/Destruction

+ (PSMTabDragAssistant *)sharedDragAssistant
{
    if (!sharedDragAssistant){
        sharedDragAssistant = [[PSMTabDragAssistant alloc] init];
    }
    
    return sharedDragAssistant;
}

- (id)init
{
    if ( (self = [super init]) ) {
        _sourceTabBar = nil;
        _destinationTabBar = nil;
        _participatingTabBars = [[NSMutableSet alloc] init];
        _draggedCell = nil;
        _animationTimer = nil;
        _sineCurveWidths = [[NSMutableArray alloc] initWithCapacity:kPSMTabDragAnimationSteps];
        _targetCell = nil;
        _isDragging = NO;
    }
    
    return self;
}

- (void)dealloc
{
    [_sourceTabBar release];
    [_destinationTabBar release];
    [_participatingTabBars release];
    [_draggedCell release];
    [_animationTimer release];
    [_sineCurveWidths release];
    [_targetCell release];
    [super dealloc];
}

#pragma mark -
#pragma mark Accessors

- (PSMTabBarControl *)sourceTabBar
{
    return _sourceTabBar;
}

- (void)setSourceTabBar:(PSMTabBarControl *)tabBar
{
    [tabBar retain];
    [_sourceTabBar release];
    _sourceTabBar = tabBar;
}

- (PSMTabBarControl *)destinationTabBar
{
    return _destinationTabBar;
}

- (void)setDestinationTabBar:(PSMTabBarControl *)tabBar
{
    [tabBar retain];
    [_destinationTabBar release];
    _destinationTabBar = tabBar;
}

- (PSMTabBarCell *)draggedCell
{
    return _draggedCell;
}

- (void)setDraggedCell:(PSMTabBarCell *)cell
{
    [cell retain];
    [_draggedCell release];
    _draggedCell = cell;
}

- (int)draggedCellIndex
{
    return _draggedCellIndex;
}

- (void)setDraggedCellIndex:(int)value
{
    _draggedCellIndex = value;
}

- (BOOL)isDragging
{
    return _isDragging;
}

- (void)setIsDragging:(BOOL)value
{
    _isDragging = value;
}

- (NSPoint)currentMouseLoc
{
    return _currentMouseLoc;
}

- (void)setCurrentMouseLoc:(NSPoint)point
{
    _currentMouseLoc = point;
}

- (PSMTabBarCell *)targetCell
{
    return _targetCell;
}

- (void)setTargetCell:(PSMTabBarCell *)cell
{
    [cell retain];
    [_targetCell release];
    _targetCell = cell;
}

#pragma mark -
#pragma mark Functionality

- (void)startDraggingCell:(PSMTabBarCell *)cell fromTabBar:(PSMTabBarControl *)control withMouseDownEvent:(NSEvent *)event
{
    [self setIsDragging:YES];
    [self setSourceTabBar:control];
    [self setDestinationTabBar:control];
    [_participatingTabBars addObject:control];
    [self setDraggedCell:cell];
    [self setDraggedCellIndex:[[control cells] indexOfObject:cell]];
    
    NSRect cellFrame = [cell frame];
    // list of widths for animation
    int i;
    float cellStepSize = ([control orientation] == PSMTabBarHorizontalOrientation) ? (cellFrame.size.width + 6) : (cellFrame.size.height + 1);
    for (i = 0; i < kPSMTabDragAnimationSteps - 1; i++) {
        int thisWidth = (int)(cellStepSize - ((cellStepSize/2.0) + ((sin((PI/2.0) + ((float)i/(float)kPSMTabDragAnimationSteps)*PI) * cellStepSize) / 2.0)));
        [_sineCurveWidths addObject:[NSNumber numberWithInt:thisWidth]];
    }
	[_sineCurveWidths addObject:[NSNumber numberWithInt:([control orientation] == PSMTabBarHorizontalOrientation) ? cellFrame.size.width : cellFrame.size.height]];
    
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];
    
    [[NSCursor closedHandCursor] set];
    
    NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    NSImage *dragImage = [cell dragImage];
    [[cell indicator] removeFromSuperview];
    [self distributePlaceholdersInTabBar:control withDraggedCell:cell];

    if([control isFlipped]){
        cellFrame.origin.y += cellFrame.size.height;
    }
    [cell setHighlighted:NO];
    NSSize offset = NSZeroSize;
    [pboard declareTypes:[NSArray arrayWithObjects:@"PSMTabBarControlItemPBType", nil] owner: nil];
    [pboard setString:[[NSNumber numberWithInt:[[control cells] indexOfObject:cell]] stringValue] forType:@"PSMTabBarControlItemPBType"];
    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0/30.0) target:self selector:@selector(animateDrag:) userInfo:nil repeats:YES];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidBeginNotification object:nil];
	
	//retain the control in case the drag operation causes the control to be released
	[control retain];
	
	if ([control delegate] && [[control delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
			[[control delegate] tabView:[control tabView] shouldDropTabViewItem:[[self draggedCell] representedObject] inTabBar:nil]) {
		_dragTabWindow = [[PSMTabDragWindow dragWindowWithTabBarCell:cell image:dragImage styleMask:NSBorderlessWindowMask] retain];
		[_dragTabWindow setAlphaValue:kPSMTabDragWindowAlpha];
		[_dragTabWindow orderFront:nil];
		
		//[control dragImage:dragImage at:cellFrame.origin offset:offset event:event pasteboard:pboard source:control slideBack:NO];
		cellFrame.origin.y -= cellFrame.size.height;
		[control dragImage:[[[NSImage alloc] initWithSize:NSMakeSize(1, 1)] autorelease] at:cellFrame.origin offset:offset event:event pasteboard:pboard source:control slideBack:NO];
	} else {
		[control dragImage:dragImage at:cellFrame.origin offset:offset event:event pasteboard:pboard source:control slideBack:YES];
	}
	
	[control release];
}

- (void)draggingEnteredTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc
{
    [self setDestinationTabBar:control];
    [self setCurrentMouseLoc:mouseLoc];
    // hide UI buttons
    [[control overflowPopUpButton] setHidden:YES];
    [[control addTabButton] setHidden:YES];
    if([[control cells] count] == 0 || ![[[control cells] objectAtIndex:0] isPlaceholder])
        [self distributePlaceholdersInTabBar:control];
    [_participatingTabBars addObject:control];
	
	//tell the drag window to display only the header if there is one
	if (_dragViewWindow) {
		if (_fadeTimer) {
			[_fadeTimer invalidate];
		}
		
		[_dragTabWindow orderFront:nil];
		_fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeOutDragWindow:) userInfo:nil repeats:YES];
	}
}

- (void)draggingUpdatedInTabBar:(PSMTabBarControl *)control atPoint:(NSPoint)mouseLoc
{
    if([self destinationTabBar] != control)
        [self setDestinationTabBar:control];
    [self setCurrentMouseLoc:mouseLoc];
}

- (void)draggingExitedTabBar:(PSMTabBarControl *)control
{
    [self setDestinationTabBar:nil];
    [self setCurrentMouseLoc:NSMakePoint(-1.0, -1.0)];
	
	if (_fadeTimer) {
		[_fadeTimer invalidate];
		_fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeInDragWindow:) userInfo:nil repeats:YES];
	} else if (_dragTabWindow) {
		//create a new floating drag window
		if (!_dragViewWindow) {
			NSImage *viewImage = nil;
			unsigned int styleMask = NSBorderlessWindowMask;
			
			if ([control delegate] && [[control delegate] respondsToSelector:@selector(tabView:imageForTabViewItem:offset:styleMask:)]) {
				//get a custom image representation of the view to drag from the delegate
				NSImage *tabImage = [[_dragTabWindow contentView] image];
				NSPoint drawPoint;
				_dragWindowOffset = NSZeroSize;
				viewImage = [[control delegate] tabView:[control tabView] imageForTabViewItem:[[self draggedCell] representedObject] offset:&_dragWindowOffset styleMask:&styleMask];
                                
				[viewImage lockFocus];
				
				//draw the tab into the returned window, that way we don't have two windows being dragged (this assumes the tab will be on the window)
				drawPoint = NSMakePoint(_dragWindowOffset.width, [viewImage size].height - _dragWindowOffset.height);
				
				if ([control orientation] == PSMTabBarHorizontalOrientation) {
					drawPoint.y += kPSMTabBarControlHeight - [tabImage size].height;
					_dragWindowOffset.height -= kPSMTabBarControlHeight - [tabImage size].height;
				} else {
					drawPoint.x += [control frame].size.width - [tabImage size].width;
					//_dragWindowOffset.height -= kPSMTabBarControlHeight - [tabImage size].height;
					//_dragWindowOffset.width -= ([control frame].size.width - [tabImage size].width) + 1;
				}
				
				[tabImage compositeToPoint:drawPoint operation:NSCompositeSourceOver];
				
				[viewImage unlockFocus];
			} else {
				//the delegate doesn't give a custom image, so use an image of the view
				NSView *tabView = [[[self draggedCell] representedObject] view];
				viewImage = [[[NSImage alloc] initWithSize:[tabView frame].size] autorelease];
				[viewImage lockFocus];
				[tabView drawRect:[tabView bounds]];
				[viewImage unlockFocus];
			}
			
			if (styleMask | NSBorderlessWindowMask) {
				_dragWindowOffset.height += 22;
			}
			
			_dragViewWindow = [[PSMTabDragWindow dragWindowWithTabBarCell:[self draggedCell] image:viewImage styleMask:styleMask] retain];
			[_dragViewWindow setAlphaValue:0.0];
		}
		
		NSPoint windowOrigin = [_dragTabWindow frame].origin;
		windowOrigin.x -= _dragWindowOffset.width;
		windowOrigin.y += _dragWindowOffset.height;
		[_dragViewWindow setFrameTopLeftPoint:windowOrigin];
		[_dragViewWindow orderWindow:NSWindowBelow relativeTo:[_dragTabWindow windowNumber]];
		
		//set the window's alpha mask to zero if the last tab is being dragged
		//don't fade out the old window if the delegate doesn't respond to the new tab bar method, just to be safe
		if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 1 && [self sourceTabBar] == control &&
				[[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]) {
			[[[self sourceTabBar] window] setAlphaValue:0.0];
			[_dragViewWindow setAlphaValue:kPSMTabDragWindowAlpha];
		} else {
			_fadeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeInDragWindow:) userInfo:nil repeats:YES];
		}
	}
}

- (void)performDragOperation
{
    // move cell
	int destinationIndex = [[[self destinationTabBar] cells] indexOfObject:[self targetCell]];
	
	//there is the slight possibility of the targetCell now being set properly, so avoid errors
	if (destinationIndex >= [[[self destinationTabBar] cells] count])  {
		destinationIndex = [[[self destinationTabBar] cells] count] - 1;
	}
	
    [[[self destinationTabBar] cells] replaceObjectAtIndex:destinationIndex withObject:[self draggedCell]];
    [[self draggedCell] setControlView:[self destinationTabBar]];
	
    // move actual NSTabViewItem
    if ([self sourceTabBar] != [self destinationTabBar]) {
		//remove the tracking rects and bindings registered on the old tab
		[[self sourceTabBar] removeTrackingRect:[[self draggedCell] closeButtonTrackingTag]];
		[[self sourceTabBar] removeTrackingRect:[[self draggedCell] cellTrackingTag]];
		[[self sourceTabBar] removeTabForCell:[self draggedCell]];
		
		int i, insertIndex;
		NSArray *cells = [[self destinationTabBar] cells];
		
		//find the index of where the dragged cell was just dropped
		for (i = 0, insertIndex = 0; (i < [cells count]) && ([cells objectAtIndex:i] != [self draggedCell]); i++, insertIndex++) {
			if ([[cells objectAtIndex:i] isPlaceholder]) {
				insertIndex--;
			}
		}
		
        [[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
        [[[self destinationTabBar] tabView] insertTabViewItem:[[self draggedCell] representedObject] atIndex:insertIndex];
		
		//rebind the cell to the new control
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
		int index;
		NSArray *cells = [[self sourceTabBar] cells];
		
		//find the index of where the dragged cell was just dropped
		for (index = 0; index < [cells count] && [cells objectAtIndex:index] != [self draggedCell]; index++);
		
		//temporarily disable the delegate in order to move the tab to a different index
		id tempDelegate = [tabView delegate];
		[tabView setDelegate:nil];
		[item retain];
		[tabView removeTabViewItem:item];
		[tabView insertTabViewItem:item atIndex:index];
		if (reselect) {
			[tabView selectTabViewItem:item];
		}
		[tabView setDelegate:tempDelegate];
	}
	
	if (([self sourceTabBar] != [self destinationTabBar] || [[[self sourceTabBar] cells] indexOfObject:[self draggedCell]] != _draggedCellIndex) && [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {
		[[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView] didDropTabViewItem:[[self draggedCell] representedObject] inTabBar:[self destinationTabBar]];
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification object:nil];
	
    [self finishDrag];
}

- (void)draggedImageEndedAt:(NSPoint)aPoint operation:(NSDragOperation)operation
{
    if([self isDragging]){  // means there was not a successful drop (performDragOperation)
		id sourceDelegate = [[self sourceTabBar] delegate];
		
		//split off the dragged tab into a new window
		if ([self destinationTabBar] == nil &&
				sourceDelegate && [sourceDelegate respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:)] &&
				[sourceDelegate tabView:[[self sourceTabBar] tabView] shouldDropTabViewItem:[[self draggedCell] representedObject] inTabBar:nil] &&
				[sourceDelegate respondsToSelector:@selector(tabView:newTabBarForDraggedTabViewItem:atPoint:)]) {
			PSMTabBarControl *control = [sourceDelegate tabView:[[self sourceTabBar] tabView] newTabBarForDraggedTabViewItem:[[self draggedCell] representedObject] atPoint:aPoint];
			
			if (control) {
				//add the dragged tab to the new window
				[[control cells] insertObject:[self draggedCell] atIndex:0];
				
				//remove the tracking rects and bindings registered on the old tab
				[[self sourceTabBar] removeTrackingRect:[[self draggedCell] closeButtonTrackingTag]];
				[[self sourceTabBar] removeTrackingRect:[[self draggedCell] cellTrackingTag]];
				[[self sourceTabBar] removeTabForCell:[self draggedCell]];
				
				//rebind the cell to the new control
				[control bindPropertiesForCell:[self draggedCell] andTabViewItem:[[self draggedCell] representedObject]];
				
				[[self draggedCell] setControlView:control];
				
				[[[self sourceTabBar] tabView] removeTabViewItem:[[self draggedCell] representedObject]];
				
				[[control tabView] addTabViewItem:[[self draggedCell] representedObject]];
				[[control window] makeKeyAndOrderFront:nil];
				
				if ([sourceDelegate respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:)]) {
					[sourceDelegate tabView:[[self sourceTabBar] tabView] didDropTabViewItem:[[self draggedCell] representedObject] inTabBar:control];
				}
			} else {
				NSLog(@"Delegate returned no control to add to.");
				[[[self sourceTabBar] cells] insertObject:[self draggedCell] atIndex:[self draggedCellIndex]];
			}
			
		} else {
			// put cell back
			[[[self sourceTabBar] cells] insertObject:[self draggedCell] atIndex:[self draggedCellIndex]];
		}
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PSMTabDragDidEndNotification object:nil];
		
		[self finishDrag];
    }
}

- (void)finishDrag
{
	if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 0 && [[[self sourceTabBar] delegate] respondsToSelector:@selector(tabView:closeWindowForLastTabViewItem:)]) {
		[[[self sourceTabBar] delegate] tabView:[[self sourceTabBar] tabView] closeWindowForLastTabViewItem:[[self draggedCell] representedObject]];
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
	
    [self setIsDragging:NO];
    [self removeAllPlaceholdersFromTabBar:[self sourceTabBar]];
    [self setSourceTabBar:nil];
    [self setDestinationTabBar:nil];
    NSEnumerator *e = [_participatingTabBars objectEnumerator];
    PSMTabBarControl *tabBar;
    while ( (tabBar = [e nextObject]) ) {
        [self removeAllPlaceholdersFromTabBar:tabBar];
    }
    [_participatingTabBars removeAllObjects];
    [self setDraggedCell:nil];
    [_animationTimer invalidate];
    _animationTimer = nil;
    [_sineCurveWidths removeAllObjects];
    [self setTargetCell:nil];
}

- (void)draggingBeganAt:(NSPoint)aPoint
{
	if (_dragTabWindow) {
		[_dragTabWindow setFrameTopLeftPoint:aPoint];
		
		if ([[[self sourceTabBar] tabView] numberOfTabViewItems] == 1) {
			[self draggingExitedTabBar:[self sourceTabBar]];
			[_dragTabWindow setAlphaValue:0.0];
		}
	}
}

- (void)draggingMovedTo:(NSPoint)aPoint
{
	if (_dragTabWindow) {
		[_dragTabWindow setFrameTopLeftPoint:aPoint];
		
		if (_dragViewWindow) {
			//move the view representation with the tab
			//the relative position of the dragged view window will be different
			//depending on the position of the tab bar relative to the controlled tab view
			
			aPoint.y -= [_dragTabWindow frame].size.height;
			aPoint.x -= _dragWindowOffset.width;
			aPoint.y += _dragWindowOffset.height;
			[_dragViewWindow setFrameTopLeftPoint:aPoint];
		}
	}
}

- (void)fadeInDragWindow:(NSTimer *)timer
{
	float value = [_dragViewWindow alphaValue];
	if (value >= kPSMTabDragWindowAlpha || _dragTabWindow == nil) {
		[timer invalidate];
		_fadeTimer = nil;
	} else {
		[_dragTabWindow setAlphaValue:[_dragTabWindow alphaValue] - 0.15];
		[_dragViewWindow setAlphaValue:value + 0.15];
	}
}

- (void)fadeOutDragWindow:(NSTimer *)timer
{
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

- (void)animateDrag:(NSTimer *)timer
{
    NSEnumerator *e = [_participatingTabBars objectEnumerator];
    PSMTabBarControl *tabBar;
    while ( (tabBar = [e nextObject]) ) {
        [self calculateDragAnimationForTabBar:tabBar];
        [[NSRunLoop currentRunLoop] performSelector:@selector(display) target:tabBar argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
    }
}

- (void)calculateDragAnimationForTabBar:(PSMTabBarControl *)control
{
    BOOL removeFlag = YES;
    NSMutableArray *cells = [control cells];
    int i, cellCount = [cells count];
    float position = [control orientation] == PSMTabBarHorizontalOrientation ? [[control style] leftMarginForTabBarControl] : [[control style] topMarginForTabBarControl];
    
    // identify target cell
    // mouse at beginning of tabs
    NSPoint mouseLoc = [self currentMouseLoc];
    if ([self destinationTabBar] == control) {
        removeFlag = NO;
        if (mouseLoc.x < [[control style] leftMarginForTabBarControl]) {
            [self setTargetCell:[cells objectAtIndex:0]];
        } else {
			NSRect overCellRect;
			PSMTabBarCell *overCell = [control cellForPoint:mouseLoc cellFrame:&overCellRect];
			if(overCell){
				// mouse among cells - placeholder
				if ([overCell isPlaceholder]) {
					[self setTargetCell:overCell];
				} else if ([control orientation] == PSMTabBarHorizontalOrientation) {
					// non-placeholders - horizontal orientation
					if (mouseLoc.x < (overCellRect.origin.x + (overCellRect.size.width / 2.0))) {
						// mouse on left side of cell
						[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] - 1)]];
					} else {
						// mouse on right side of cell
						[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] + 1)]];
					}
				} else {
					// non-placeholders - vertical orientation
					if (mouseLoc.y < (overCellRect.origin.y + (overCellRect.size.height / 2.0))) {
						// mouse on top of cell
						[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] - 1)]];
					} else {
						// mouse on bottom of cell
						[self setTargetCell:[cells objectAtIndex:([cells indexOfObject:overCell] + 1)]];
					}
				}
			} else {
				// out at end - must find proper cell (could be more in overflow menu)
				[self setTargetCell:[control lastVisibleTab]];
			}
		}
    } else {
        [self setTargetCell:nil];
    }
    
    for(i = 0; i < cellCount; i++){
        PSMTabBarCell *cell = [cells objectAtIndex:i];
        NSRect newRect = [cell frame];
        if(![cell isInOverflowMenu]){
            if([cell isPlaceholder]){
                if(cell == [self targetCell]){
                    [cell setCurrentStep:([cell currentStep] + 1)];
                } else {
                    [cell setCurrentStep:([cell currentStep] - 1)];
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
		} else {
			newRect.origin.y = position;
			position += newRect.size.height;
		}
        [cell setFrame:newRect];
        if([cell indicator])
            [[cell indicator] setFrame:[[control style] indicatorRectForTabCell:cell]];
    }
    if(removeFlag){
        [_participatingTabBars removeObject:control];
        [self removeAllPlaceholdersFromTabBar:control];
    }
}

#pragma mark -
#pragma mark Placeholders

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control withDraggedCell:(PSMTabBarCell *)cell
{
    // called upon first drag - must distribute placeholders
    [self distributePlaceholdersInTabBar:control];
    // replace dragged cell with a placeholder, and clean up surrounding cells
    int cellIndex = [[control cells] indexOfObject:cell];
    PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:YES inControlView:control] autorelease];
    [[control cells] replaceObjectAtIndex:cellIndex withObject:pc];
    [[control cells] removeObjectAtIndex:(cellIndex + 1)];
    [[control cells] removeObjectAtIndex:(cellIndex - 1)];
    return;
}

- (void)distributePlaceholdersInTabBar:(PSMTabBarControl *)control
{
    int i, numVisibleTabs = [control numberOfVisibleTabs];
    for(i = 0; i < numVisibleTabs; i++){
        PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease];
        [[control cells] insertObject:pc atIndex:(2 * i)];
    }
	
	PSMTabBarCell *pc = [[[PSMTabBarCell alloc] initPlaceholderWithFrame:[[self draggedCell] frame] expanded:NO inControlView:control] autorelease];
	if ([[control cells] count] > (2 * numVisibleTabs)) {
		[[control cells] insertObject:pc atIndex:(2 * numVisibleTabs)];
	} else {
		[[control cells] addObject:pc];
	}
}

- (void)removeAllPlaceholdersFromTabBar:(PSMTabBarControl *)control
{
    int i, cellCount = [[control cells] count];
    for(i = (cellCount - 1); i >= 0; i--){
        PSMTabBarCell *cell = [[control cells] objectAtIndex:i];
        if([cell isPlaceholder])
            [[control cells] removeObject:cell];
    }
    // redraw
    [[NSRunLoop currentRunLoop] performSelector:@selector(update) target:control argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
    [[NSRunLoop currentRunLoop] performSelector:@selector(display) target:control argument:nil order:1 modes:[NSArray arrayWithObjects:@"NSEventTrackingRunLoopMode", @"NSDefaultRunLoopMode", nil]];
}

#pragma mark -
#pragma mark Archiving

- (void)encodeWithCoder:(NSCoder *)aCoder {
    //[super encodeWithCoder:aCoder];
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
    //self = [super initWithCoder:aDecoder];
    //if (self) {
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
    //}
    return self;
}


@end

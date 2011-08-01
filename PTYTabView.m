/*
 **  PTYTabView.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: NSTabView subclass. Implements drag and drop.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <iTerm/PTYTabView.h>
#include <Carbon/Carbon.h>

#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0

#define HOTKEY kVK_Tab
#define MODIFIER_MASK NSControlKeyMask

@implementation PTYTabView

// Class methods that Apple should have provided
+ (NSSize) contentSizeForFrameSize: (NSSize) frameSize tabViewType: (NSTabViewType) type controlSize: (NSControlSize) controlSize
{
    NSRect aRect, contentRect;
    NSTabView *aTabView;
    float widthOffset, heightOffset;

#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -contentSizeForFrameSize");
#endif

    // make a temporary tabview
    aRect = NSMakeRect(0, 0, 200, 200);
    aTabView = [[NSTabView alloc] initWithFrame: aRect];
    [aTabView setTabViewType: type];
    [aTabView setControlSize: controlSize];

    // grab its content size
    contentRect = [aTabView contentRect];

    // calculate the offsets between total frame and content frame
    widthOffset = aRect.size.width - contentRect.size.width;
    heightOffset = aRect.size.height - contentRect.size.height;
    //NSLog(@"widthOffset = %f; heightOffset = %f", widthOffset, heightOffset);

    // release the temporary tabview
    [aTabView release];

    // Apply the offset to the given frame size
    return (NSMakeSize(frameSize.width - widthOffset, frameSize.height - heightOffset));
}

+ (NSSize) frameSizeForContentSize: (NSSize) contentSize tabViewType: (NSTabViewType) type controlSize: (NSControlSize) controlSize
{
    NSRect aRect, contentRect;
    NSTabView *aTabView;
    float widthOffset, heightOffset;

#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -frameSizeForContentSize");
#endif

    // make a temporary tabview
    aRect = NSMakeRect(0, 0, 200, 200);
    aTabView = [[NSTabView alloc] initWithFrame: aRect];
    [aTabView setTabViewType: type];
    [aTabView setControlSize: controlSize];

    // grab its content size
    contentRect = [aTabView contentRect];

    // calculate the offsets between total frame and content frame
    widthOffset = aRect.size.width - contentRect.size.width;
    heightOffset = aRect.size.height - contentRect.size.height;
    //NSLog(@"widthOffset = %f; heightOffset = %f", widthOffset, heightOffset);

    // release the temporary tabview
    [aTabView release];

    // Apply the offset to the given content size
    return (NSMakeSize(contentSize.width + widthOffset, contentSize.height + heightOffset));
}


- (id)initWithFrame:(NSRect) aRect
{
#if DEBUG_ALLOC
    NSLog(@"%s: %p", __PRETTY_FUNCTION__, self);
#endif

    self = [super initWithFrame: aRect];
    if (self) {
        mruTabs = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: %p", __PRETTY_FUNCTION__, self);
#endif
    
    [mruTabs dealloc];
    [super dealloc];
}

// we don't want this to be the first responder in the chain
- (BOOL)acceptsFirstResponder
{
    return (NO);
}

- (void)drawRect:(NSRect)rect
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermTabViewWillRedraw" 
                                                        object:self];
    [super drawRect:rect];
}


// NSTabView methods overridden
- (void)addTabViewItem:(NSTabViewItem *) aTabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -addTabViewItem");
#endif

    // Let our delegate know
    id delegate = [self delegate];

    if([delegate conformsToProtocol: @protocol(PTYTabViewDelegateProtocol)])
        [delegate tabView: self willAddTabViewItem: aTabViewItem];

    [mruTabs addObject:aTabViewItem];

    [super addTabViewItem: aTabViewItem];
}

- (void)removeTabViewItem:(NSTabViewItem *) aTabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -removeTabViewItem");
#endif

    // Let our delegate know
    id delegate = [self delegate];

    if([delegate conformsToProtocol: @protocol(PTYTabViewDelegateProtocol)])
        [delegate tabView: self willRemoveTabViewItem: aTabViewItem];
	
    [mruTabs removeObject:aTabViewItem];

    // remove the item
    [super removeTabViewItem: aTabViewItem];
}

- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)theIndex
{
#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -insertTabViewItem atIndex: %d", theIndex);
#endif

    // Let our delegate know
    id delegate = [self delegate];

    // Check the boundary
    if (theIndex>[super numberOfTabViewItems]) {
        theIndex = [super numberOfTabViewItems];
    }

    if([delegate conformsToProtocol: @protocol(PTYTabViewDelegateProtocol)])
        [delegate tabView: self willInsertTabViewItem: tabViewItem atIndex: theIndex];
	
    [mruTabs addObject:tabViewItem];

    [super insertTabViewItem:tabViewItem atIndex:theIndex];
#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -insertTabViewItem atIndex: %d, done", theIndex);
#endif
}

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -selectTabViewItem");
#endif
	
    [super selectTabViewItem:tabViewItem];

    if (!isModifierPressed) {
        [mruTabs removeObject:tabViewItem];
        [mruTabs insertObject:tabViewItem atIndex:0];
    }
}

// selects a tab from the contextual menu
- (void)selectTab:(id)sender
{
    [self selectTabViewItemWithIdentifier:[sender representedObject]];
}

- (void)previousTab:(id)sender
{
    NSTabViewItem *tabViewItem = [self selectedTabViewItem];
    [self selectPreviousTabViewItem:sender];
    if (tabViewItem == [self selectedTabViewItem]) {
        [self selectTabViewItemAtIndex:[self numberOfTabViewItems] - 1];
    }
}

- (void)nextTab:(id)sender
{
    NSTabViewItem *tabViewItem = [self selectedTabViewItem];
    [self selectNextTabViewItem:sender];
    if (tabViewItem == [self selectedTabViewItem]) {
        [self selectTabViewItemAtIndex:0];
    }
}

- (void)nextMRU
{
#if DEBUG_METHOD_TRACE
    NSLog(@"PTYTabView: -nextMRU");
#endif

    NSTabViewItem* tabViewItem = [self selectedTabViewItem];
    NSUInteger theIndex = [mruTabs indexOfObject:tabViewItem] + 1;
    NSAssert(theIndex != NSNotFound, "tabViewItem is missing!");
    if (theIndex >= [mruTabs count]) {
        theIndex = 0;
    }
    NSTabViewItem* next = [mruTabs objectAtIndex:theIndex];
    [self selectTabViewItem:next];
}

- (BOOL)onKeyPressed:(NSEvent*)event
{
    if (isModifierPressed && [event keyCode] == HOTKEY) {
        isHotkeyPressed = YES;	
        [self nextMRU];
        return YES;
    }
    return NO;
}

- (BOOL)onFlagsChanged:(NSEvent*)event
{
    if ([event modifierFlags] & MODIFIER_MASK) {
        isModifierPressed = YES;
        return YES;
    }

    if (isModifierPressed && (([event modifierFlags] & MODIFIER_MASK) == 0)) {
        isModifierPressed = NO;
        if (isHotkeyPressed) {
            isHotkeyPressed = NO;
            [self selectTabViewItem:[self selectedTabViewItem]];
        }
        return YES;
    }
    return NO;
}

// process keyboard events
// returns YES if the event was handled
// otherwise returns NO, meaning that the event still needs to be processed
- (BOOL)processMRUEvent:(NSEvent*)event 
{
    switch ([event type]) {
        case NSKeyDown:
            return [self onKeyPressed:event];
        case NSFlagsChanged:
            return [self onFlagsChanged:event];
        default:
            return NO;
    }
    return NO;
}

@end

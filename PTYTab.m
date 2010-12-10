// -*- mode:objc -*-
/*
 **  PTYTab.m
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: PTYTab abstracts the concept of a tab. This is
 **  attached to the tabview's identifier and is the owner of
 **  PTYSession.
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

#import "PTYTab.h"
#import "iTerm/PTYSession.h"
#import "WindowControllerInterface.h"
#import "SessionView.h"
#import "FakeWindow.h"
#import "PreferencePanel.h"
#import "iTermGrowlDelegate.h"
#import "iTerm/PTYScrollView.h"
#import "PSMTabBarControl.h"
#import "PSMTabStyle.h"
#import "ITAddressBookMgr.h"
#import "iTermApplicationDelegate.h"

// #define PTYTAB_VERBOSE_LOGGING
#ifdef PTYTAB_VERBOSE_LOGGING
#define PtyLog NSLog
#else
#define PtyLog(args...) \
do { \
if (gDebugLogging) { \
DebugLog([NSString stringWithFormat:args]); \
} \
} while (0)
#endif

@implementation PTYTab

// tab label attributes
static NSColor *normalStateColor;
static NSColor *chosenStateColor;
static NSColor *idleStateColor;
static NSColor *newOutputStateColor;
static NSColor *deadStateColor;

static NSImage *warningImage;

+ (void)initialize
{
    NSBundle *thisBundle;
    NSString *imagePath;

    thisBundle = [NSBundle bundleForClass:[self class]];
    imagePath = [thisBundle pathForResource:@"important"
                                     ofType:@"png"];
    if (imagePath) {
        warningImage = [[NSImage alloc] initByReferencingFile: imagePath];
    }

    normalStateColor = [NSColor blackColor];
    chosenStateColor = [NSColor blackColor];
    idleStateColor = [NSColor redColor];
    newOutputStateColor = [NSColor purpleColor];
    deadStateColor = [NSColor grayColor];
}

// init/dealloc
- (id)initWithSession:(PTYSession*)session
{
    self = [super init];
    PtyLog(@"PTYTab initWithSession %p", self);
    if (self) {
        activeSession_ = session;
        root_ = [[NSSplitView alloc] init];
        [root_ setAutoresizesSubviews:YES];
        [root_ setDelegate:self];
        [session setTab:self];
        [root_ addSubview:[session view]];

    }
    return self;
}

- (void)dealloc
{
    PtyLog(@"PTYTab dealloc");
    [root_ release];
    [fakeParentWindow_ release];
    [icon_ release];
    [super dealloc];
}

- (NSTabViewItem *)tabViewItem
{
    return tabViewItem_;
}

- (void)setBell:(BOOL)flag
{
    PtyLog(@"setBell:%d", (int)flag);
    if (flag) {
        [self setIcon:warningImage];
    } else {
        [self setIcon:nil];
    }
}

- (void)nameOfSession:(PTYSession*)session didChangeTo:(NSString*)newName
{
    if ([self activeSession] == session) {
        [tabViewItem_ setLabel:newName];
    }
}

- (BOOL)isForegroundTab
{
    return [[tabViewItem_ tabView] selectedTabViewItem] == tabViewItem_;
}

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height
{
    [parentWindow_ sessionInitiatedResize:session width:width height:height];
}

- (PTYSession*)activeSession
{
    return activeSession_;
}

- (void)setActiveSession:(PTYSession*)session
{
    PtyLog(@"PTYTab setActiveSession:%p", session);
    if (activeSession_ &&  activeSession_ != session && [activeSession_ dvr]) {
        [realParentWindow_ closeInstantReplay:self];
    }
    BOOL changed = session != activeSession_;
    activeSession_ = session;
    if (changed) {
        [parentWindow_ setWindowTitle];
        [tabViewItem_ setLabel:[[self activeSession] name]];
        [[realParentWindow_ window] makeFirstResponder:[session TEXTVIEW]];
    }
    for (PTYSession* aSession in [self sessions]) {
        [[aSession TEXTVIEW] refresh];
        [[aSession TEXTVIEW] setNeedsDisplay:YES];
    }
    [self setLabelAttributes];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:activeSession_];
    [self recheckBlur];
}

- (id<WindowControllerInterface>)parentWindow
{
    return parentWindow_;
}

- (PseudoTerminal*)realParentWindow
{
    return realParentWindow_;
}

- (void)setParentWindow:(PseudoTerminal*)theParent
{
    // Parent holds a reference to us (indirectly) so we mustn't reference it.
    parentWindow_ = realParentWindow_ = theParent;
}

- (void)setFakeParentWindow:(FakeWindow*)theParent
{
    [fakeParentWindow_ autorelease];
    parentWindow_ = fakeParentWindow_ = [theParent retain];
}

- (FakeWindow*)fakeWindow
{
    return fakeParentWindow_;
}

- (void)setLockedSession:(PTYSession*)lockedSession
{
    PtyLog(@"PTYTab setLockedSession:%p", lockedSession);
    lockedSession_ = lockedSession;
}

- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem
{
    PtyLog(@"PTYTab setTabViewItem:%p", theTabViewItem);
    // The tab view item holds a refernece to us. So we don't hold a reference to it.
    tabViewItem_ = theTabViewItem;
    if (theTabViewItem != nil) {
        [tabViewItem_ setLabel:[[self activeSession] name]];
        [tabViewItem_ setView:root_];
    }
}

- (int)number
{
    return [[tabViewItem_ tabView] indexOfTabViewItem:tabViewItem_];
}

- (int)realObjectCount
{
    return objectCount_;
}

- (int)objectCount
{
    return [[PreferencePanel sharedInstance] useCompactLabel] ? 0 : objectCount_;
}

- (void)setObjectCount:(int)value
{
    objectCount_ = value;
}

- (NSImage *)icon
{
    return icon_;
}

- (void)setIcon:(NSImage *)anIcon
{
    [icon_ autorelease];
    icon_ = [anIcon retain];
}

- (BOOL)isProcessing
{
    return isProcessing_;
}

- (void)setIsProcessing:(BOOL)aFlag
{
    isProcessing_ = aFlag;
}

- (BOOL)isActiveSession
{
    return ([[[self tabViewItem] tabView] selectedTabViewItem] == [self tabViewItem]);
}

- (BOOL)anySessionHasNewOutput
{
    for (PTYSession* session in [self sessions]) {
        if ([session newOutput]) {
            return YES;
        }
    }
    return NO;
}

// TODO: These methods are special purpose and brittle.
- (PTYSession*)sessionBefore:(PTYSession*)session
{
    NSSplitView* split = (NSSplitView*)[[session view] superview];
    NSArray* siblings = [split subviews];
    NSUInteger i = [siblings indexOfObjectIdenticalTo:[session view]];
    if (i == NSNotFound) {
        return nil;
    }
    if (i == 0) {
        return nil;
    }
    SessionView* parentView = (SessionView*)[siblings objectAtIndex:i-1];
    assert([parentView isKindOfClass:[SessionView class]]);
    return [parentView session];
}

- (PTYSession*)sessionAfter:(PTYSession*)session
{
    NSSplitView* split = (NSSplitView*)[[session view] superview];
    NSArray* siblings = [split subviews];
    NSUInteger i = [siblings indexOfObjectIdenticalTo:[session view]];
    if (i == NSNotFound) {
        return nil;
    }
    if (i == [siblings count] - 1) {
        return nil;
    }
    SessionView* parentView = (SessionView*)[siblings objectAtIndex:i+1];
    assert([parentView isKindOfClass:[SessionView class]]);
    return [parentView session];
}

- (void)setLabelAttributes
{
    PtyLog(@"PTYTab setLabelAttributes");
    struct timeval now;

    gettimeofday(&now, NULL);
    if ([[self activeSession] exited]) {
        // Session has terminated.
        [self _setLabelAttributesForDeadSession];
    } else if ([[tabViewItem_ tabView] selectedTabViewItem] != [self tabViewItem]) {
        // We are not the foreground tab.
        if (now.tv_sec > [[self activeSession] lastOutput].tv_sec+2) {
            // At least two seconds have passed since the last call.
            [self _setLabelAttributesForIdleBackgroundTabAtTime:now];
        } else {
            // Less than 2 seconds has passed since the last output in the session.
            if ([self anySessionHasNewOutput]) {
                [self _setLabelAttributesForActiveBackgroundTab];
            }
        }
    } else {
        // This tab is the foreground tab and the session hasn't exited.
        [self _setLabelAttributesForForegroundTab];
    }
}

- (void)closeSession:(PTYSession*)session;
{
    [[self parentWindow] closeSession:session];
}

- (void)terminateAllSessions
{
    [[self activeSession] terminate];
}

- (NSArray*)_recursiveSessions:(NSMutableArray*)sessions atNode:(NSSplitView*)node
{
    for (id subview in [node subviews]) {
        if ([subview isKindOfClass:[NSSplitView class]]) {
            [self _recursiveSessions:sessions atNode:(NSSplitView*)subview];
        } else {
            SessionView* sessionView = (SessionView*)subview;
            [sessions addObject:[sessionView session]];
        }
    }
    return sessions;
}

- (NSArray*)sessions
{
    return [self _recursiveSessions:[NSMutableArray arrayWithCapacity:1] atNode:root_];
}

- (BOOL)allSessionsExited
{
    return [[self activeSession] exited];
}

- (void)setDvrInSession:(PTYSession*)newSession
{
    PtyLog(@"PTYTab setDvrInSession:%p", newSession);
    PTYSession* oldSession = [self activeSession];
    assert(oldSession != newSession);

    // Swap views between newSession and oldSession.
    SessionView* newView = [newSession view];
    SessionView* oldView = [oldSession view];
    NSSplitView* parentSplit = (NSSplitView*)[oldView superview];
    [oldView retain];
    [parentSplit replaceSubview:oldView with:newView];

    [newSession setName:[oldSession name]];
    [newSession setDefaultName:[oldSession defaultName]];

    // Put the new session in DVR mode and pass it the old session, which it
    // keeps a reference to.

    [newSession setDvr:[[oldSession SCREEN] dvr] liveSession:oldSession];

    activeSession_ = newSession;

    // TODO(georgen): the hidden window can resize itself and the FakeWindow
    // needs to pass that on to the SCREEN. Otherwise the DVR playback into the
    // time after cmd-d was pressed (but before the present) has the wrong
    // window size.
    [self setFakeParentWindow:[[FakeWindow alloc] initFromRealWindow:realParentWindow_
                                                             session:oldSession]];

    // This starts the new session's update timer
    [newSession updateDisplay];
}

- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession
{
    PtyLog(@"PTYTab showLiveSessio:%p", liveSession);
   [replaySession cancelTimers];
    [liveSession setAddressBookEntry:[replaySession addressBookEntry]];

    SessionView* oldView = [replaySession view];
    SessionView* newView = [liveSession view];
    NSSplitView* parentSplit = (NSSplitView*)[oldView superview];
    [parentSplit replaceSubview:oldView with:newView];
    [newView release];
    activeSession_ = liveSession;

    [fakeParentWindow_ rejoin:realParentWindow_];
}

- (void)_dumpView:(id)view withPrefix:(NSString*)prefix
{
    if ([view isKindOfClass:[SessionView class]]) {
        SessionView* sv = (SessionView*)view;
        NSSize size = [sv frame].size;
        PtyLog([NSString stringWithFormat:@"%@%lfx%lf", prefix, size.width, size.height]);
    } else {
        NSSplitView* sv = (NSSplitView*)view;
        for (id v in [sv subviews]) {
            [self _dumpView:v withPrefix:[NSString stringWithFormat:@"  %@", prefix]];
        }
    }
}

- (void)dump
{
    for (id v in [root_ subviews]) {
        [self _dumpView:v withPrefix:@""];
    }
}

- (void)_recursiveRemoveView:(NSView*)theView
{
   if ([theView isKindOfClass:[SessionView class]]) {
        NSSplitView* split = (NSSplitView*)[theView superview];
        if ([[split subviews] count] == 1) {
            [self _recursiveRemoveView:split];
        } else {
            [theView removeFromSuperview];
            [split adjustSubviews];
            [self _splitViewDidResizeSubviews:split];
        }
    } else {
        NSSplitView* split = (NSSplitView*)theView;
        if (split == root_) {
            // Never remove the root from its superview. Remove all its children.
            for (NSView* subview in [root_ subviews]) {
                [subview removeFromSuperview];
            }
        } else {
            NSSplitView* parent = (NSSplitView*)[split superview];
            if ([[parent subviews] count] > 1) {
                [split removeFromSuperview];
                [parent adjustSubviews];
                [self _splitViewDidResizeSubviews:parent];
            } else {
                [self _recursiveRemoveView:parent];
            }
        }
    }
}

- (void)removeSession:(PTYSession*)aSession
{
    PtyLog(@"PTYTab removeSession:%p", aSession);
    [self _recursiveRemoveView:[aSession view]];
    if (aSession == activeSession_) {
        if ([[root_ subviews] count]) {
            NSView* current = root_;
            // TODO: pick a better successor.
            while ([current isKindOfClass:[NSSplitView class]]) {
                current = [[current subviews] objectAtIndex:0];
            }
            [self setActiveSession:[(SessionView*)current session]];
        } else {
            activeSession_ = nil;
        }
    }
    [self recheckBlur];
}

- (BOOL)canSplitVertically
{
    PtyLog(@"PTYTab canSplitVertically");
    NSSize minPostSplitSize;
    minPostSplitSize = [self _minSessionSize:[activeSession_ view]];
    minPostSplitSize.width *= 2;
    minPostSplitSize.width += [(NSSplitView*)[[activeSession_ view] superview] dividerThickness];
    NSSize availableSpace = [self _sessionSize:[activeSession_ view]];
    return minPostSplitSize.width < availableSpace.width;
}

- (SessionView*)splitVertically
{
    PtyLog(@"PTYTab splitVertically");
    PTYSession* activeSession = [self activeSession];
    SessionView* activeSessionView = [activeSession view];
    NSSplitView* parentSplit = (NSSplitView*) [activeSessionView superview];
    SessionView* newView = [[[SessionView alloc] initWithFrame:[activeSessionView frame]] autorelease];

    // There has to be an active session, so the parent must have one child.
    assert([[parentSplit subviews] count] != 0);
    PtyLog(@"Before:");
    [self dump];
    if ([[parentSplit subviews] count] == 1) {
        PtyLog(@"PTYTab splitVertically: one child");
        // If the parent split has only one child then it must also be the root.
        assert(parentSplit == root_);

        // Set its orientation to vertical and add the new view.
        [parentSplit setVertical:YES];
        [parentSplit addSubview:newView];

        // Resize all subviews the same size to accommodate the new view.
        [parentSplit adjustSubviews];
        [self _splitViewDidResizeSubviews:parentSplit];
    } else if (![parentSplit isVertical]) {
        PtyLog(@"PTYTab splitVertically not vertical");
        // The parent has vertical splits and has many children. We need to do this:
        // 1. Remove the active SessionView from its parent
        // 2. Replace it with a vertical NSSplitView
        // 3. Add two children to the vertical NSSplitView: the active session and the new view.
        [activeSessionView retain];
        NSSplitView* verticalSplit = [[NSSplitView alloc] init];
        [activeSessionView replaceSubview:activeSessionView with:verticalSplit];
        [verticalSplit release];
        [verticalSplit addSubview:activeSessionView];
        [activeSessionView release];
        [verticalSplit addSubview:newView];

        // Resize all subviews the same size to accommodate the new view.
        [parentSplit adjustSubviews];
        [verticalSplit adjustSubviews];
        [self _splitViewDidResizeSubviews:verticalSplit];
    } else {
        PtyLog(@"PTYTab splitVertically vertical multiple children");
        // The parent has vertical splits and there is more than one child.
        [parentSplit addSubview:newView];

        // Resize all subviews the same size to accommodate the new view.
        [parentSplit adjustSubviews];
        [self _splitViewDidResizeSubviews:parentSplit];
    }
    PtyLog(@"After:");
    [self dump];

    return newView;
}

- (NSSize)_sessionSize:(SessionView*)sessionView
{
    NSSize size;
    PTYSession* session = [sessionView session];
    size.width = [session columns] * [[session TEXTVIEW] charWidth] + MARGIN * 2;
    size.height = [session rows] * [[session TEXTVIEW] lineHeight] + VMARGIN * 2;

    BOOL hasScrollbar = ![parentWindow_ fullScreen] && ![[PreferencePanel sharedInstance] hideScrollbar];
    NSSize scrollViewSize = [PTYScrollView frameSizeForContentSize:size
                                             hasHorizontalScroller:NO
                                               hasVerticalScroller:hasScrollbar
                                                        borderType:NSNoBorder];
    return scrollViewSize;
}

- (NSSize)_minSessionSize:(SessionView*)sessionView
{
    NSSize size;
    PTYSession* session = [sessionView session];
    size.width = 20 * [[session TEXTVIEW] charWidth] + MARGIN * 2;
    size.height = 10 * [[session TEXTVIEW] lineHeight] + VMARGIN * 2;

    BOOL hasScrollbar = ![parentWindow_ fullScreen] && ![[PreferencePanel sharedInstance] hideScrollbar];
    NSSize scrollViewSize = [PTYScrollView frameSizeForContentSize:size
                                             hasHorizontalScroller:NO
                                               hasVerticalScroller:hasScrollbar
                                                        borderType:NSNoBorder];
    return scrollViewSize;
}

// Return the size of a tree of splits based on the rows/cols in each session.
// If any session locked, sets *containsLockOut to YES. A locked session is one
// whose size is "canonical" when its size differs from that of its siblings.
- (NSSize)_recursiveSize:(NSSplitView*)node containsLock:(BOOL*)containsLockOut
{
    PtyLog(@"PTYTab recursiveSize");
    NSSize size;
    size.width = 0;
    size.height = 0;

    NSSize dividerSize = NSZeroSize;
    if ([node isVertical]) {
        dividerSize.width = [node dividerThickness];
    } else {
        dividerSize.height = [node dividerThickness];
    }
    *containsLockOut = NO;

    BOOL first = YES;
    BOOL haveFoundLock = NO;
    // Iterate over each subview and add up the width/height of each plus dividers.
    // If there is a discrepancy in height/width, prefer the subview that contains
    // a locked session; else, take the max.
    for (id subview in [node subviews]) {
        NSSize subviewSize;
        if (first) {
            first = NO;
        } else {
            // Add the size of the splitter between this pane and the previous one.
            size.width += dividerSize.width;
            size.height += dividerSize.height;
        }

        BOOL subviewContainsLock = NO;
        if ([subview isKindOfClass:[NSSplitView class]]) {
            // Get size of child tree at this subview.
            subviewSize = [self _recursiveSize:(NSSplitView*)subview containsLock:&subviewContainsLock];
        } else {
            // Get size of session at this subview.
            SessionView* sessionView = (SessionView*)subview;
            subviewSize = [self _sessionSize:sessionView];
            if ([sessionView session] == lockedSession_) {
                subviewContainsLock = YES;
            }
        }
        if (subviewContainsLock) {
            *containsLockOut = YES;
        }
        if ([node isVertical]) {
            // Vertical splitters have their subviews arranged horizontally so widths add and
            // height goes to the tallest.
            if (size.height == 0) {
                // Take the cross-grain size of the first subview.
                size.height = subviewSize.height;
            } else if ((int)size.height != (int)subviewSize.height) {
                // There's a discripancy in cross-grain sizes among subviews.
                if (subviewContainsLock) {
                    // Prefer the locked subview.
                    size.height = subviewSize.height;
                } else if (!haveFoundLock) {
                    // This could happen if a session's font changes size.
                    size.height = MAX(size.height, subviewSize.height);
                }
            }
            size.width += subviewSize.width;
        } else {
            // Nonvertical splitters have subviews arranged vertically so heights add and width
            // goes to the widest.
            size.height += subviewSize.height;
            if (size.width == 0) {
                // Take the cross-grain size of the first subview.
                size.width = subviewSize.width;
            } else if ((int)size.width != (int)subviewSize.width) {
                // There's a discripancy in cross-grain sizes among subviews.
                if (subviewContainsLock) {
                    // Prefer the locked subview.
                    size.width = subviewSize.width;
                } else if (!haveFoundLock) {
                    // This could happen if a session's font changes size.
                    size.width = MAX(size.width, subviewSize.width);
                }
            }
        }
        if (subviewContainsLock) {
            haveFoundLock = YES;
        }
    }
    return size;
}

// Return the minimum size of a tree of splits so that no session is smaller than
// 20 columns by 10 rows.
- (NSSize)_recursiveMinSize:(NSSplitView*)node
{
    NSSize size;
    size.width = 0;
    size.height = 0;

    NSSize dividerSize = NSZeroSize;
    if ([node isVertical]) {
        dividerSize.width = [node dividerThickness];
    } else {
        dividerSize.height = [node dividerThickness];
    }

    BOOL first = YES;
    for (id subview in [node subviews]) {
        NSSize subviewSize;
        if (first) {
            first = NO;
        } else {
            // Add the size of the splitter between this pane and the previous one.
            size.width += dividerSize.width;
            size.height += dividerSize.height;
        }

        if ([subview isKindOfClass:[NSSplitView class]]) {
            // Get size of child tree at this subview.
            subviewSize = [self _recursiveMinSize:(NSSplitView*)subview];
        } else {
            // Get size of session at this subview.
            SessionView* sessionView = (SessionView*)subview;
            subviewSize = [self _minSessionSize:sessionView];
        }
        if ([node isVertical]) {
            // Vertical splitters have their subviews arranged horizontally so widths add and
            // height goes to the tallest.
            if (size.height == 0) {
                // Take the cross-grain size of the first subview.
                size.height = subviewSize.height;
            } else if ((int)size.height != (int)subviewSize.height) {
                size.height = MAX(size.height, subviewSize.height);
            }
            size.width += subviewSize.width;
        } else {
            // Nonvertical splitters have subviews arranged vertically so heights add and width
            // goes to the widest.
            size.height += subviewSize.height;
            if (size.width == 0) {
                // Take the cross-grain size of the first subview.
                size.width = subviewSize.width;
            } else if ((int)size.width != (int)subviewSize.width) {
                // There's a discripancy in cross-grain sizes among subviews.
                size.width = MAX(size.width, subviewSize.width);
            }
        }
    }
    return size;
}

// This returns the content size that would best fit the existing panes. It is the minimum size that
// fits them without having to resize downwards.
- (NSSize)size
{
    BOOL ignore;
    return [self _recursiveSize:root_ containsLock:&ignore];
}

- (NSSize)minSize
{
    return [self _recursiveMinSize:root_];
}

- (void)setSize:(NSSize)newSize
{
    PtyLog(@"PTYTab setSize:%fx%f", (float)newSize.width, (float)newSize.height);
    NSSize currentSize = [self size];
    if ((int)newSize.width == (int)currentSize.width &&
        (int)newSize.height == (int)currentSize.height) {
        // No-op
        return;
    }
    [root_ setFrameSize:newSize];
    [root_ adjustSubviews];
    [self _splitViewDidResizeSubviews:root_];
}

- (void)_drawSession:(PTYSession*)session inImage:(NSImage*)viewImage atOrigin:(NSPoint)origin
{
    NSImage *textviewImage = [[[NSImage alloc] initWithSize:[[session TEXTVIEW] frame].size] autorelease];

    [textviewImage setFlipped:YES];
    [textviewImage lockFocus];
    // Draw the background flipped, which is actually the right way up.
    NSSize viewSize = [textviewImage size];
    [[session TEXTVIEW] drawRect:NSMakeRect(0, 0, viewSize.width, viewSize.height)];
    [textviewImage unlockFocus];

    [viewImage lockFocus];
    [textviewImage compositeToPoint:origin operation:NSCompositeSourceOver];
    [viewImage unlockFocus];
}

- (void)_recursiveDrawSplit:(NSSplitView*)splitView inImage:(NSImage*)viewImage atOrigin:(NSPoint)splitOrigin
{
    NSPoint origin = splitOrigin;
    BOOL first = YES;
    for (NSView* subview in [splitView subviews]) {
        if (first) {
            // No divider left/above first pane.
            first = NO;
        } else {
            // Draw the divider
            [viewImage lockFocus];
            [[splitView dividerColor] set];
            CGFloat dx = 0;
            CGFloat dy = 0;
            CGFloat hx = 0;
            CGFloat hy = 0;
            CGFloat thickness = [splitView dividerThickness];
            if ([splitView isVertical]) {
                dx = thickness;
                hy = [subview frame].size.height;
            } else {
                dy = thickness;
                hx = [subview frame].size.width;
            }
            NSRectFill(NSMakeRect(origin.x, origin.y, dx + hx, dy + hy));
            [viewImage unlockFocus];

            // Advance the origin past the divider.
            origin.x += dx;
            origin.y += dy;
        }

        if ([subview isKindOfClass:[NSSplitView class]]) {
            [self _recursiveDrawSplit:(NSSplitView*)subview inImage:viewImage atOrigin:origin];
        } else {
            SessionView* sessionView = (SessionView*)subview;
            [self _drawSession:[sessionView session] inImage:viewImage atOrigin:origin];
        }
        if ([splitView isVertical]) {
            origin.x += [subview frame].size.width;
        } else {
            origin.y += [subview frame].size.height;
        }
    }
}

- (NSImage*)image
{
    PtyLog(@"PTYTab image");
    NSRect tabFrame = [[realParentWindow_ tabBarControl] frame];
    NSSize viewSize = [root_ frame].size;
    viewSize.height += tabFrame.size.height;

    NSImage* viewImage = [[[NSImage alloc] initWithSize:viewSize] autorelease];

    float yOrigin = 0;
    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
        yOrigin += tabFrame.size.height;
    }

    [self _recursiveDrawSplit:root_ inImage:viewImage atOrigin:NSMakePoint(0, yOrigin)];

    // Draw over where the tab bar would usually be
    [viewImage lockFocus];
    [[NSColor windowBackgroundColor] set];
    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
        tabFrame.origin.y += [viewImage size].height;
    }
    NSRectFill(tabFrame);

    // Draw the background flipped, which is actually the right way up
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleXBy:1.0 yBy:-1.0];
    [transform concat];
    tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
    [(id <PSMTabStyle>)[[[realParentWindow_ tabView] delegate] style] drawBackgroundInRect:tabFrame];
    [transform invert];
    [transform concat];

    [viewImage unlockFocus];

    return viewImage;
}

// Resize a session's rows and columns for the existing pixel size of its
// containing view.
- (void)fitSessionToCurrentViewSize:(PTYSession*)aSession
{
    PtyLog(@"PTYTab fitSessionToCurrentViewSzie");
    PtyLog(@"fitSessionToCurrentViewSize begins");
    BOOL hasScrollbar = ![parentWindow_ fullScreen] && ![[PreferencePanel sharedInstance] hideScrollbar];
    [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
    NSSize size = [[aSession SCROLLVIEW] documentVisibleRect].size;
    int width = (size.width - MARGIN*2) / [[aSession TEXTVIEW] charWidth];
    int height = (size.height - VMARGIN*2) / [[aSession TEXTVIEW] lineHeight];
    if (width <= 0) {
        NSLog(@"WARNING: Session has %d width", width);
        width = 1;
    }
    if (height <= 0) {
        NSLog(@"WARNING: Session has %d height", height);
        height = 1;
    }
    if ([aSession rows] == height &&
        [aSession columns] == width) {
        PtyLog(@"PTYTab fitSessionToCurrentViewSize: noop");
        return;
    }
    PtyLog(@"PTYTab fitSessionToCurrentViewSize: view is %fx%f, set screen to %dx%d", size.width, size.height, width, height);
    if (width == [aSession columns] && height == [aSession rows]) {
        PtyLog(@"fitSessionToWindow - terminating early because session size doesn't change");
        return;
    }
    PtyLog(@"PTYTab fitSessionToCurrentViewSize - Given a scrollview size of %fx%f, can fit %dx%d chars", size.width, size.height, width, height);

    [[aSession SCREEN] resizeWidth:width height:height];
    PtyLog(@"fitSessionToCurrentViewSize -  calling shell setWidth:%d height:%d", width, height);
    [[aSession SHELL] setWidth:width height:height];
    [[aSession SCROLLVIEW] setLineScroll:[[aSession TEXTVIEW] lineHeight]];
    [[aSession SCROLLVIEW] setPageScroll:2*[[aSession TEXTVIEW] lineHeight]];
    if ([aSession backgroundImagePath]) {
        [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
    }
    PtyLog(@"PTYTab fitSessionToCurrentViewSize returns");
}

- (BOOL)hasMultipleSessions
{
    return [[root_ subviews] count] > 1;
}

// Return the left/top offset of some divider from its container's origin.
- (CGFloat)_positionOfDivider:(int)theIndex inSplitView:(NSSplitView*)splitView
{
    CGFloat p = 0;
    NSArray* subviews = [splitView subviews];
    for (int i = 0; i <= theIndex; ++i) {
        if ([splitView isVertical]) {
            p += [[subviews objectAtIndex:i] frame].size.width;
        } else {
            p += [[subviews objectAtIndex:i] frame].size.height;
        }
        if (i > 0) {
            p += [splitView dividerThickness];
        }
    }
    return p;
}

- (NSSize)_minSizeOfView:(NSView*)view
{
    if ([view isKindOfClass:[SessionView class]]) {
        SessionView* sessionView = (SessionView*)view;
        return [self _minSessionSize:sessionView];
    } else {
        return [self _recursiveMinSize:(NSSplitView*)view];
    }
}

// Blur the window if most sessions are blurred.
- (bool)blur
{
    int n = 0;
    int y = 0;
    NSArray* sessions = [self sessions];
    for (PTYSession* session in sessions) {
        if ([[[session addressBookEntry] objectForKey:KEY_BLUR] boolValue]) {
            ++y;
        } else {
            ++n;
        }
    }
    return y > n;
}

- (void)recheckBlur
{
    PtyLog(@"PTYTab recheckBlur");
    if ([realParentWindow_ currentTab] == self &&
        ![[realParentWindow_ window] isMiniaturized]) {
        if ([self blur]) {
            [parentWindow_ enableBlur];
        } else {
            [parentWindow_ disableBlur];
        }
    }
}

#pragma mark NSSplitView delegate methods

// Prevent any session from becoming smaller than its minimum size because of
// a divder's movement.
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
    PtyLog(@"PTYTab constrainMin:%f divider:%d", (float)proposedMin, dividerIndex);
    CGFloat dim;
    NSSize minSize = [self _minSizeOfView:[[splitView subviews] objectAtIndex:dividerIndex]];
    if ([splitView isVertical]) {
        dim = minSize.width;
    } else {
        dim = minSize.height;
    }
    return [self _positionOfDivider:dividerIndex-1 inSplitView:splitView] + dim;
}

// Prevent any session from becoming smaller than its minimum size because of
// a divder's movement.
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    PtyLog(@"PTYTab constrainMax:%f divider:%d", (float)proposedMax, dividerIndex);
    CGFloat dim;
    NSSize minSize = [self _minSizeOfView:[[splitView subviews] objectAtIndex:dividerIndex+1]];
    if ([splitView isVertical]) {
        dim = minSize.width;
    } else {
        dim = minSize.height;
    }
    return [self _positionOfDivider:dividerIndex+1 inSplitView:splitView] - dim - [splitView dividerThickness];
}

// Called after a splitter has been resized. This adjusts session sizes appropriately,
// with special attention paid to the "locked" session, which never resizes.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
    PtyLog(@"PTYTab splitView:resizeSubviewsWithOldSize:");
    NSRect currentFrame = [splitView frame];
    if ((int)currentFrame.size.width == (int)oldSize.width &&
        (int)currentFrame.size.height == (int)oldSize.height) {
        // This is a no-op that can only cause confusion.
        return;
    }
    // Possibilities:
    // 1. No subview is locked. Then just adjustSubviews normally.
    // 2. My only child is locked. Just resize it. If the caller is well behaved then it will go to the right size.
    // 3. My child is locked but I have other children. Set the locked child to its canonical size ("with the grain" only) and then adjust the size of the other children to fit.
    // 4. My grandchild is locked. If I have grandchildren then I must have more than one child. Adjust the parent of the locked session with my grain and change other children to fit.
    if (lockedSession_ == nil) {
        PtyLog(@"PTYTab splitView:resizeSubviewsWithOldSize: case 1");
        // Case 1
        [splitView adjustSubviews];
    } else if ([[lockedSession_ view] superview] == splitView) {
        if ([[splitView subviews] count] == 1) {
            PtyLog(@"PTYTab splitView:resizeSubviewsWithOldSize: case 2");
            // Case 2
            [splitView adjustSubviews];
        } else {
            PtyLog(@"PTYTab splitView:resizeSubviewsWithOldSize: case 3");
            // Case 3
            if ([splitView isVertical]) {
                // Vertical dividers so children are arranged horizontally.
                // Set width of locked session and then resize all others proportionately.
                CGFloat availableSize = [splitView frame].size.width;

                // This also does not include dividers.
                double originalSizeWithoutLockedSession = oldSize.width - [[lockedSession_ view] frame].size.width - ([[splitView subviews] count] - 1) * [splitView dividerThickness];
                NSArray* mySubviews = [splitView subviews];
                NSSize lockedSize = [self _sessionSize:[lockedSession_ view]];
                availableSize -= lockedSize.width;
                availableSize -= [splitView dividerThickness];

                // Resize each child's width so that the space left excluding the locked session is
                // divided up in the same proportions as it was before the resize.
                NSRect newFrame = NSZeroRect;
                newFrame.size.height = lockedSize.height;
                for (id subview in mySubviews) {
                    if (subview != [lockedSession_ view]) {
                        // Resizing a non-locked child.
                        NSSize subviewSize = [subview frame].size;
                        double fractionOfOriginalSize = subviewSize.width / originalSizeWithoutLockedSession;
                        newFrame.size.width = availableSize * fractionOfOriginalSize;;
                    } else {
                        newFrame.size.width = lockedSize.width;
                    }
                    [subview setFrame:newFrame];
                    newFrame.origin.x += newFrame.size.width + [splitView dividerThickness];
                }
            } else {
                PtyLog(@"PTYTab splitView:resizeSubviewsWithOldSize: TODO");
                // TODO
            }
        }
    } else if ([[[lockedSession_ view] superview] superview] == splitView) {
        PtyLog(@"PTYTab splitView:resizeSubviewsWithOldSize: case 4");
        // Case 4
        // TODO
    }
}

// Inform sessions about their new sizes. This is called after views have finished
// being resized.
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
    PtyLog(@"splitViewDidResizeSubviews notification received.");
    NSSplitView* splitView = [aNotification object];
    [self _splitViewDidResizeSubviews:splitView];
}

- (void)_splitViewDidResizeSubviews:(NSSplitView*)splitView
{
    PtyLog(@"_splitViewDidResizeSubviews running");
    for (NSView* subview in [splitView subviews]) {
        if ([subview isKindOfClass:[SessionView class]]) {
            PTYSession* session = [(SessionView*)subview session];
            if (session) {
                PtyLog(@"splitViewDidResizeSubviews - view is %fx%f, ignore=%d", [subview frame].size.width, [subview frame].size.height, (int)[session ignoreResizeNotifications]);
                if (![session ignoreResizeNotifications]) {
                    PtyLog(@"splitViewDidResizeSubviews - adjust session %p", session);
                    [self fitSessionToCurrentViewSize:session];
                }
            }
        }
    }
}

- (CGFloat)_recursiveStepSize:(NSView*)theView wantWidth:(BOOL)wantWidth
{
    if ([theView isKindOfClass:[SessionView class]]) {
        SessionView* sessionView = (SessionView*)theView;
        if (wantWidth) {
            return [[[sessionView session] TEXTVIEW] charWidth];
        } else {
            return [[[sessionView session] TEXTVIEW] lineHeight];
        }
    } else {
        CGFloat maxStep = 0;
        for (NSView* subview in [theView subviews]) {
            CGFloat step = [self _recursiveStepSize:subview wantWidth:wantWidth];
            maxStep = MAX(maxStep, step);
        }
        return maxStep;
    }
}

// Make splitters jump by char widths/line heights. If there is a difference,
// pick the largest on either side of the divider.
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex
{
    PtyLog(@"PTYTab splitView:constraintSplitPosition%f divider:%d case ", (float)proposedPosition, dividerIndex);
    NSArray* subviews = [splitView subviews];
    NSView* childBefore = [subviews objectAtIndex:dividerIndex];
    NSView* childAfter = [subviews objectAtIndex:dividerIndex + 1];
    CGFloat beforeStep = [self _recursiveStepSize:childBefore wantWidth:[splitView isVertical]];
    CGFloat afterStep = [self _recursiveStepSize:childAfter wantWidth:[splitView isVertical]];
    CGFloat step = MAX(beforeStep, afterStep);

    NSRect beforeRect = [childBefore frame];
    CGFloat originalPosition;
    if ([splitView isVertical]) {
        originalPosition = beforeRect.origin.x + beforeRect.size.width;
    } else {
        originalPosition = beforeRect.origin.y + beforeRect.size.height;
    }
    CGFloat diff = fabs(proposedPosition - originalPosition);
    int chars = diff / step;
    CGFloat allowedDiff = chars * step;
    if (proposedPosition < originalPosition) {
        allowedDiff *= -1;
    }
    return originalPosition + allowedDiff;
}

@end

@implementation PTYTab (Private)

- (void)_setLabelAttributesForDeadSession
{
    [parentWindow_ setLabelColor:deadStateColor
                 forTabViewItem:tabViewItem_];
    if ([self isProcessing]) {
        [self setIsProcessing:NO];
    }
}

- (void)_setLabelAttributesForIdleBackgroundTabAtTime:(struct timeval)now
{
    if ([self isProcessing]) {
        [self setIsProcessing:NO];
    }

    for (PTYSession* session in [self sessions]) {
        if ([session newOutput]) {
            // Idle after new output
            if (![session growlIdle] &&
                now.tv_sec > [session lastOutput].tv_sec + 1) {
                [[iTermGrowlDelegate sharedInstance] growlNotify:NSLocalizedStringFromTableInBundle(@"Idle",
                                                                                                    @"iTerm",
                                                                                                    [NSBundle bundleForClass:[self class]],
                                                                                                    @"Growl Alerts")
                                                 withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Session %@ in tab #%d became idle.",
                                                                                                                               @"iTerm",
                                                                                                                               [NSBundle bundleForClass:[self class]],
                                                                                                                               @"Growl Alerts"),
                                                                  [[self activeSession] name],
                                                                  [self realObjectCount]]
                                                 andNotification:@"Idle"];
                [session setGrowlIdle:YES];
                [session setGrowlNewOutput:NO];
            }
            [parentWindow_ setLabelColor:idleStateColor
                          forTabViewItem:tabViewItem_];
        } else {
            // normal state
            [parentWindow_ setLabelColor:normalStateColor
                          forTabViewItem:tabViewItem_];
        }
    }
}

- (void)_setLabelAttributesForActiveBackgroundTab
{
    if ([self isProcessing] == NO &&
        ![[PreferencePanel sharedInstance] useCompactLabel]) {
        [self setIsProcessing:YES];
    }

    if (![[self activeSession] growlNewOutput] &&
        ![[self parentWindow] sendInputToAllSessions]) {
        [[iTermGrowlDelegate sharedInstance] growlNotify:NSLocalizedStringFromTableInBundle(@"New Output",
                                                                                            @"iTerm",
                                                                                            [NSBundle bundleForClass:[self class]],
                                                                                            @"Growl Alerts")
                                         withDescription:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"New Output was received in %@, tab #%d.",
                                                                                                                       @"iTerm",
                                                                                                                       [NSBundle bundleForClass:[self class]],
                                                                                                                       @"Growl Alerts"),
                                                          [[self activeSession] name],
                                                          [self realObjectCount]]
                                         andNotification:@"New Output"];
        [[self activeSession] setGrowlNewOutput:YES];
    }

    [[self parentWindow] setLabelColor:newOutputStateColor
                        forTabViewItem:tabViewItem_];
}

- (void)_setLabelAttributesForForegroundTab
{
    if ([self isProcessing]) {
        [self setIsProcessing:NO];
    }
    [[self activeSession] setGrowlNewOutput:NO];
    [[self activeSession] setNewOutput:NO];
    [[self parentWindow] setLabelColor:chosenStateColor
                        forTabViewItem:[self tabViewItem]];
}

@end

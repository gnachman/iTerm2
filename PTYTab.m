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
#import "iTerm/iTermController.h"

//#define PTYTAB_VERBOSE_LOGGING
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

@interface MySplitView : NSSplitView
{
}

- (void)adjustSubviews;

@end

@implementation MySplitView

- (void)adjustSubviews
{
    PtyLog(@"@@@@@@@@@@ begin adjustSubviews");
    for (NSView* v in [self subviews]) {
        PtyLog(@"View %p has height %lf", v, [v frame].size.height);
    }
    [super adjustSubviews];
    PtyLog(@"AFTER:");
    for (NSView* v in [self subviews]) {
        PtyLog(@"View %p has height %lf", v, [v frame].size.height);
    }
    PtyLog(@"@@@@@@@@ END @@@@@@@");
}

@end


@implementation PTYTab

// tab label attributes
static NSColor *normalStateColor;
static NSColor *chosenStateColor;
static NSColor *idleStateColor;
static NSColor *newOutputStateColor;
static NSColor *deadStateColor;

static NSImage *warningImage;

// Constants for saved window arrangement keys.
static NSString* TAB_ARRANGEMENT_ROOT = @"Root";
static NSString* TAB_ARRANGEMENT_VIEW_TYPE = @"View Type";
static NSString* VIEW_TYPE_SPLITTER = @"Splitter";
static NSString* VIEW_TYPE_SESSIONVIEW = @"SessionView";
static NSString* SPLITTER_IS_VERTICAL = @"isVertical";
static NSString* TAB_ARRANGEMENT_SPLIITER_FRAME = @"frame";
static NSString* TAB_ARRANGEMENT_SESSIONVIEW_FRAME = @"frame";
static NSString* TAB_WIDTH = @"width";
static NSString* TAB_HEIGHT = @"height";
static NSString* TAB_X = @"x";
static NSString* TAB_Y = @"y";
static NSString* SUBVIEWS = @"Subviews";
static NSString* TAB_ARRANGEMENT_SESSION = @"Session";
static NSString* TAB_ARRANGEMENT_IS_ACTIVE = @"Is Active";
static NSString* TAB_ARRANGEMENT_ID = @"ID";  // only for maximize/unmaximize
static NSString* TAB_ARRANGEMENT_IS_MAXIMIZED = @"Maximized";

static const BOOL USE_THIN_SPLITTERS = YES;

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

- (void)appendSessionViewToViewOrder:(SessionView*)sessionView
{
    NSNumber* n = [NSNumber numberWithInt:[sessionView viewId]];
    if ([viewOrder_ indexOfObject:n] == NSNotFound) {
        int i = currentViewIndex_ + 1;
        if (i > [viewOrder_ count]) {
            i = [viewOrder_ count];
        }
        [viewOrder_ insertObject:n atIndex:i];
    }
}

- (void)appendSessionToViewOrder:(PTYSession*)session
{
    [self appendSessionViewToViewOrder:[session view]];
}

// init/dealloc
- (id)initWithSession:(PTYSession*)session
{
    self = [super init];
    PtyLog(@"PTYTab initWithSession %p", self);
    if (self) {
        activeSession_ = session;
        [session setLastActiveAt:[NSDate date]];
        root_ = [[MySplitView alloc] init];
        if (USE_THIN_SPLITTERS) {
            [root_ setDividerStyle:NSSplitViewDividerStyleThin];
        }
        [root_ setAutoresizesSubviews:YES];
        [root_ setDelegate:self];
        [session setTab:self];
        [root_ addSubview:[session view]];
        viewOrder_ = [[NSMutableArray alloc] init];
        [self appendSessionToViewOrder:session];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_refreshLabels:)
                                                 name:@"iTermUpdateLabels"
                                               object:nil];
    return self;
}

+ (void)_recursiveSetDelegateIn:(NSSplitView*)node to:(id)delegate
{
    [node setDelegate:delegate];
    for (NSView* subView in [node subviews]) {
        if ([subView isKindOfClass:[NSSplitView class]]) {
            [PTYTab _recursiveSetDelegateIn:(NSSplitView*)subView to:delegate];
        }
    }
}

// This is used when restoring a window arrangement. A tree of splits and
// sessionviews is passed in but the sessionviews don't have sessions yet.
- (id)initWithRoot:(NSSplitView*)root
{
    self = [super init];
    PtyLog(@"PTYTab initWithRoot %p", self);
    if (self) {
        activeSession_ = nil;
        root_ = [root retain];
        [root_ setAutoresizesSubviews:YES];
        [root_ setDelegate:self];
        [PTYTab _recursiveSetDelegateIn:root_ to:self];
        viewOrder_ = [[NSMutableArray alloc] init];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_refreshLabels:)
                                                 name:@"iTermUpdateLabels"
                                               object:nil];
    return self;
}

- (void)dealloc
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermTabClosing"
                                                        object:self
                                                      userInfo:nil];
    PtyLog(@"PTYTab dealloc");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (PTYSession* aSession in [self sessions]) {
        [[aSession view] cancelTimers];
        [aSession setTab:nil];
    }
    [root_ release];

    for (id key in idMap_) {
        SessionView* aView = [idMap_ objectForKey:key];

        PTYSession* aSession = [aView session];
        [[aSession view] cancelTimers];
        [aSession cancelTimers];
        [aSession setTab:nil];
    }

    root_ = nil;
    [viewOrder_ release];
    [fakeParentWindow_ release];
    [icon_ release];
    [idMap_ release];
    [savedArrangement_ release];
    [super dealloc];
}

- (NSRect)absoluteFrame
{
    NSRect result;
    result.origin = [root_ convertPoint:NSMakePoint(0, 0) toView:nil];
    result.origin = [[root_ window] convertBaseToScreen:result.origin];
    result.size = [root_ frame].size;
    return result;
}

- (void)_refreshLabels:(id)sender
{
    [tabViewItem_ setLabel:[[self activeSession] name]];
    [parentWindow_ setWindowTitle];
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

- (void)setActiveSessionPreservingViewOrder:(PTYSession*)session
{
    ++preserveOrder_;
    PtyLog(@"PTYTab setActiveSession:%p", session);
    if (activeSession_ &&  activeSession_ != session && [activeSession_ dvr]) {
        [realParentWindow_ closeInstantReplay:self];
    }
    BOOL changed = session != activeSession_;
    PTYSession* oldSession = activeSession_;
    activeSession_ = session;
    [session setLastActiveAt:[NSDate date]];
    if (activeSession_ == nil) {
        --preserveOrder_;
        return;
    }
    if (changed) {
        [parentWindow_ setWindowTitle];
        [tabViewItem_ setLabel:[[self activeSession] name]];
        if ([realParentWindow_ currentTab] == self) {
            // If you set a textview in a non-current tab to the first responder and
            // then close that tab, it crashes with NSTextInput caling
            // -[PTYTextView respondsToSelector:] on a deallocated instance of the
            // first responder. This kind of hacky workaround keeps us from making
            // a invisible textview the first responder.
            [[realParentWindow_ window] makeFirstResponder:[session TEXTVIEW]];
        }
        [[session view] setDimmed:NO];
        if (oldSession && [[PreferencePanel sharedInstance] dimInactiveSplitPanes]) {
            [[oldSession view] setDimmed:YES];
        }
    }
    for (PTYSession* aSession in [self sessions]) {
        [[aSession TEXTVIEW] refresh];
        [[aSession TEXTVIEW] setNeedsDisplay:YES];
    }
    [self setLabelAttributes];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:activeSession_];
    
    NSUInteger i = [viewOrder_ indexOfObject:[NSNumber numberWithInt:[[session view] viewId]]];
    if (i != NSNotFound) {
        currentViewIndex_ = i;
    }
    
    --preserveOrder_;
}

- (void)setActiveSession:(PTYSession*)session
{
    if (preserveOrder_) {
        return;
    }
    [self setActiveSessionPreservingViewOrder:session];
    [viewOrder_ removeObject:[NSNumber numberWithInt:[[session view] viewId]]];
    [viewOrder_ addObject:[NSNumber numberWithInt:[[session view] viewId]]];
    currentViewIndex_ = [viewOrder_ count] - 1;
    
    [self recheckBlur];
}

// Do a depth-first search for a leaf with viewId==requestedId. Returns nil if not found under 'node'.
- (SessionView*)_recursiveSessionViewWithId:(int)requestedId atNode:(NSSplitView*)node
{
    for (NSView* v in [node subviews]) {
        if ([v isKindOfClass:[NSSplitView class]]) {
            SessionView* sv = [self _recursiveSessionViewWithId:requestedId atNode:(NSSplitView*)v];
            if (sv) {
                return sv;
            }
        } else {
            SessionView* sv = (SessionView*) v;
            if ([sv viewId] == requestedId) {
                return sv;
            }
        }
    }
    return nil;
}

- (void)previousSession
{
    --currentViewIndex_;
    if (currentViewIndex_ < 0) {
        currentViewIndex_ = [viewOrder_ count] - 1;
    }
    SessionView* sv = [self _recursiveSessionViewWithId:[[viewOrder_ objectAtIndex:currentViewIndex_] intValue]
                                                 atNode:root_];
    assert(sv);
    if (sv) {
        [self setActiveSessionPreservingViewOrder:[sv session]];
    }
}

- (void)nextSession
{
    ++currentViewIndex_;
    if (currentViewIndex_ >= [viewOrder_ count]) {
        currentViewIndex_ = 0;
    }
    SessionView* sv = [self _recursiveSessionViewWithId:[[viewOrder_ objectAtIndex:currentViewIndex_] intValue]
                                                 atNode:root_];
    assert(sv);
    if (sv) {
        [self setActiveSessionPreservingViewOrder:[sv session]];
    }
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

- (BOOL)realIsProcessing
{
    return isProcessing_;
}

- (BOOL)isProcessing
{
    return isProcessing_ && ![realParentWindow_ disableProgressIndicators];
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

static void SwapSize(NSSize* size) {
    NSSize temp = *size;
    size->height = temp.width;
    size->width = temp.height;
}

static void SwapPoint(NSPoint* point) {
    NSPoint temp = *point;
    point->x = temp.y;
    point->y = temp.x;
}

static NSString* FormatRect(NSRect r) {
    return [NSString stringWithFormat:@"%lf,%lf %lfx%lf", r.origin.x, r.origin.y,
            r.size.width, r.size.height];
}

- (PTYSession*)_sessionAdjacentTo:(PTYSession*)session verticalDir:(BOOL)verticalDir after:(BOOL)after
{
    NSRect myRect = [root_ convertRect:[[session view] frame] fromView:[[session view] superview]];
    PtyLog(@"origin is %@", FormatRect(myRect));
    NSPoint targetPoint = myRect.origin;
    NSSize rootSize = [root_ frame].size;

    // Rearrange coordinates so that the rest of this function can be written to find the session
    // to the right or left (depending on 'after') of this one.
    if (verticalDir) {
        SwapSize(&myRect.size);
        SwapPoint(&myRect.origin);
        SwapPoint(&targetPoint);
        SwapSize(&rootSize);
    }

    int sign = after ? 1 : -1;
    if (after) {
        targetPoint.x += myRect.size.width;
    }
    targetPoint.x += sign * ([root_ dividerThickness] + 1);
    const CGFloat maxAllowed = after ? rootSize.width : 0;
    if (sign * targetPoint.x > maxAllowed) {
        targetPoint.x -= sign * rootSize.width;
    }
    int offset = 0;
    int defaultOffset = myRect.size.height / 2;
    NSPoint origPoint = targetPoint;
    PtyLog(@"OrigPoint is %lf,%lf", origPoint.x, origPoint.y);
    PTYSession* bestResult = nil;
    PTYSession* defaultResult = nil;
    NSDate* bestDate = nil;
    // Iterate over every possible adjacent session and select the most recently active one.
    while (offset < myRect.size.height) {
        targetPoint = origPoint;
        targetPoint.y += offset;
        PTYSession* result;

        // First, get the session at the target point.
        if (verticalDir) {
            SwapPoint(&targetPoint);
        }
        PtyLog(@"Check session at %lf,%lf", targetPoint.x, targetPoint.y);
        result = [self _recursiveSessionAtPoint:targetPoint relativeTo:root_];
        if (verticalDir) {
            SwapPoint(&targetPoint);
        }
        if (!result) {
            // Oops, targetPoint must have landed right on a divider. Advance by
            // one divider's width.
            targetPoint.y += [root_ dividerThickness];
            if (verticalDir) {
                SwapPoint(&targetPoint);
            }
            result = [self _recursiveSessionAtPoint:targetPoint relativeTo:root_];
            if (verticalDir) {
                SwapPoint(&targetPoint);
            }
            targetPoint.y -= [root_ dividerThickness];
        }
        if (!result) {
            // Maybe we fell off the end of the window? Try going the other direction.
            targetPoint.y -= [root_ dividerThickness];
            if (verticalDir) {
                SwapPoint(&targetPoint);
            }
            result = [self _recursiveSessionAtPoint:targetPoint relativeTo:root_];
            if (verticalDir) {
                SwapPoint(&targetPoint);
            }
            targetPoint.y += [root_ dividerThickness];
        }

        // Advance offset to next sibling's origin.
        NSRect rootRelativeResultRect = [root_ convertRect:[[result view] frame]
                                                  fromView:[[result view] superview]];
        PtyLog(@"Result is at %@", FormatRect(rootRelativeResultRect));
        if (verticalDir) {
            SwapPoint(&rootRelativeResultRect.origin);
            SwapSize(&rootRelativeResultRect.size);
        }
        offset = rootRelativeResultRect.origin.y - origPoint.y + rootRelativeResultRect.size.height;
        PtyLog(@"set offset to %d", offset);
        if (verticalDir) {
            SwapPoint(&rootRelativeResultRect.origin);
            SwapSize(&rootRelativeResultRect.size);
        }

        if ((!bestDate && [result lastActiveAt]) ||
            (bestDate && [[result lastActiveAt] isGreaterThan:bestDate])) {
            // Found a more recently used session.
            bestResult = result;
            bestDate = [result lastActiveAt];
        }
        if (!bestResult && offset > defaultOffset) {
            // Haven't found a used session yet but this one is centered so we might pick it.
            defaultResult = result;
        }
    }

    return bestResult ? bestResult : defaultResult;
}

- (PTYSession*)sessionLeftOf:(PTYSession*)session
{
    return [self _sessionAdjacentTo:session verticalDir:NO after:NO];
}

- (PTYSession*)sessionRightOf:(PTYSession*)session
{
    return [self _sessionAdjacentTo:session verticalDir:NO after:YES];
}

- (PTYSession*)sessionAbove:(PTYSession*)session
{
    return [self _sessionAdjacentTo:session verticalDir:YES after:NO];
}

- (PTYSession*)sessionBelow:(PTYSession*)session
{
    return [self _sessionAdjacentTo:session verticalDir:YES after:YES];
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
            PTYSession* session = [sessionView session];
            if (session) {
                [sessions addObject:session];
            }
        }
    }
    return sessions;
}

- (NSArray*)sessions
{
    if (idMap_) {
        NSArray* sessionViews = [idMap_ allValues];
        NSMutableArray* result = [NSMutableArray arrayWithCapacity:[sessionViews count]];
        for (SessionView* sessionView in sessionViews) {
            [result addObject:[sessionView session]];
        }
        return result;
    } else {
        return [self _recursiveSessions:[NSMutableArray arrayWithCapacity:1] atNode:root_];
    }
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

// When removing a view some invariants must be maintained:
// 1. A non-root splitview must have at least two children.
// 2. The root splitview may have exactly one child iff that child is a SessionView
// 3. A non-root splitview's orientation must be the opposite of its parent's.
//
// The algorithm is:
// Remove the view from its parent.
// Clean up the parent.
//
// Where "clean up splitView" consists of:
// If splitView (orientation -1^n) has one child
//   If that child (orientation -1^(n+1) is a splitview
//     If splitView is root:
//       Remove only child
//       swap splitView's orientation (to -1^(n+1), matching child's)
//       move grandchildren into splitView
//     else if splitView is not root:
//       Move grandchildren into splitView's parent (orientation -1^(n-1), same as child)
//   else if only child is a session:
//     If splitView is root:
//       Do nothing. This is allowed.
//     else if splitView is not root:
//       Replace splitView with child in its parent.
// else if splitView has no children:
//   Remove splitView from its parent

- (void)_checkInvariants:(NSSplitView*)node
{
    if (node != root_) {
        if ([node isKindOfClass:[NSSplitView class]]) {
            // 1. A non-root splitview must have at least two children.
            assert([[node subviews] count] > 1);
            NSSplitView* parentSplit = (NSSplitView*)[node superview];
            // 3. A non-root splitview's orientation must be the opposite of its parent's.
            assert([node isVertical] != [parentSplit isVertical]);
        } else {
            if ([[node subviews] count] == 1) {
                NSView* onlyChild = [[node subviews] objectAtIndex:0];
                // The root splitview may have exactly one child iff that child is a SessionView.
                assert([onlyChild isKindOfClass:[SessionView class]]);
            }
        }
    }

    if ([node isKindOfClass:[NSSplitView class]]) {
        for (NSView* subView in [node subviews]) {
            if ([subView isKindOfClass:[NSSplitView class]]) {
                [self _checkInvariants:(NSSplitView*)subView];
            } else {
                //NSLog(@"CHECK INVARIANTS: retain count of %p is %d", subView, [subView retainCount]);
            }
        }
    } else {
        //NSLog(@"CHECK INVARIANTS: retain count of %p is %d", node, [node retainCount]);
    }
}

- (void)_cleanupAfterRemove:(NSSplitView*)splitView
{
    const int initialNumberOfSubviews = [[splitView subviews] count];
    if (initialNumberOfSubviews == 1) {
        NSView* onlyChild = [[splitView subviews] objectAtIndex:0];
        if ([onlyChild isKindOfClass:[NSSplitView class]]) {
            if (splitView == root_) {
                PtyLog(@"Case 1");
                // Remove only child.
                [onlyChild retain];
                [onlyChild removeFromSuperview];

                // Swap splitView's orientation to match child's
                [splitView setVertical:![splitView isVertical]];

                // Move grandchildren into splitView
                for (NSView* grandchild in [[[onlyChild subviews] copy] autorelease]) {
                    [grandchild retain];
                    [grandchild removeFromSuperview];
                    [splitView addSubview:grandchild];
                    [grandchild release];
                }
                [onlyChild release];
            } else {
                PtyLog(@"Case 2");
                // splitView is not root
                NSSplitView* splitViewParent = (NSSplitView*)[splitView superview];

                NSUInteger splitViewIndex = [[splitViewParent subviews] indexOfObjectIdenticalTo:splitView];
                assert(splitViewIndex != NSNotFound);
                NSView* referencePoint = splitViewIndex > 0 ? [[splitViewParent subviews] objectAtIndex:splitViewIndex - 1] : nil;

                // Remove splitView
                [splitView retain];
                [splitView removeFromSuperview];

                // Move grandchildren into grandparent.
                for (NSView* grandchild in [[[onlyChild subviews] copy] autorelease]) {
                    [grandchild retain];
                    [grandchild removeFromSuperview];
                    [splitViewParent addSubview:grandchild positioned:NSWindowAbove relativeTo:referencePoint];
                    [grandchild release];
                    ++splitViewIndex;
                    referencePoint = [[splitViewParent subviews] objectAtIndex:splitViewIndex - 1];
                }
            }
        } else {
            // onlyChild is a session
            if (splitView != root_) {
                PtyLog(@"Case 3");
                // Replace splitView with child in its parent.
                NSSplitView* splitViewParent = (NSSplitView*)[splitView superview];
                [splitViewParent replaceSubview:splitView with:onlyChild];
            }
        }
    } else if (initialNumberOfSubviews == 0) {
        if (splitView != root_) {
            PtyLog(@"Case 4");
            [self _recursiveRemoveView:splitView];
        }
    }
}
- (void)_recursiveRemoveView:(NSView*)theView
{
    NSSplitView* parentSplit = (NSSplitView*)[theView superview];
    if (parentSplit) {
        // When a session is in instant replay, both the live session (which has no superview)
        // and the fakey DVR session are called here. If parentSplit is null the it's the live
        // session and there's nothing to do here. Otherwise, it's the one that is visible and
        // we take this path.
        [self _checkInvariants:root_];
        [theView removeFromSuperview];
        [self _cleanupAfterRemove:parentSplit];
        [self _checkInvariants:root_];
    }
}

- (NSRect)_recursiveViewFrame:(NSView*)aView
{
    NSRect localFrame = [aView frame];
    if (aView != root_) {
        NSRect parentFrame = [self _recursiveViewFrame:[aView superview]];
        localFrame.origin.x += parentFrame.origin.x;
        localFrame.origin.y += parentFrame.origin.y;
    } else {
        localFrame.origin.x = 0;
        localFrame.origin.y = 0;
    }
    return localFrame;
}

- (PTYSession*)_recursiveSessionAtPoint:(NSPoint)point relativeTo:(NSView*)node
{
    NSRect nodeFrame = [node frame];
    if (point.x < nodeFrame.origin.x ||
        point.y < nodeFrame.origin.y ||
        point.x >= nodeFrame.origin.x + nodeFrame.size.width ||
        point.y >= nodeFrame.origin.y + nodeFrame.size.height) {
        return nil;
    }
    if ([node isKindOfClass:[SessionView class]]) {
        SessionView* sessionView = (SessionView*)node;
        return [sessionView session];
    } else {
        NSSplitView* splitView = (NSSplitView*)node;
        if (node != root_) {
            point.x -= nodeFrame.origin.x;
            point.y -= nodeFrame.origin.y;
        }
        for (NSView* child in [splitView subviews]) {
            PTYSession* theSession = [self _recursiveSessionAtPoint:point relativeTo:child];
            if (theSession) {
                return theSession;
            }
        }
    }
    return nil;
}

- (void)removeSession:(PTYSession*)aSession
{
    if (idMap_) {
        [self unmaximize];
    }
    PtyLog(@"PTYTab removeSession:%p", aSession);
    // Grab the nearest neighbor (arbitrarily, the subview before if there is on or after if not)
    // to make its earliest descendent that is a session active.
    NSSplitView* parentSplit = (NSSplitView*)[[aSession view] superview];
    NSView* nearestNeighbor;
    if ([[parentSplit subviews] count] > 1) {
        // Do a depth-first search to find the first descendent of the neighbor that is a
        // SessionView and make it active.
        int theIndex = [[parentSplit subviews] indexOfObjectIdenticalTo:[aSession view]];
        int neighborIndex = theIndex > 0 ? theIndex - 1 : theIndex + 1;
        nearestNeighbor = [[parentSplit subviews] objectAtIndex:neighborIndex];
        while ([nearestNeighbor isKindOfClass:[NSSplitView class]]) {
            nearestNeighbor = [[nearestNeighbor subviews] objectAtIndex:0];
        }
    } else {
        // The window is about to close.
        nearestNeighbor = nil;
    }

    // Remove the session.
    [self _recursiveRemoveView:[aSession view]];

    [viewOrder_ removeObject:[NSNumber numberWithInt:[[aSession view] viewId]]];
    if (currentViewIndex_ >= [viewOrder_ count]) {
        // Do not allow currentViewIndex_ to hold an out-of-bounds value
        currentViewIndex_ = [viewOrder_ count] - 1;
    }
    if (aSession == activeSession_) {
        [self setActiveSessionPreservingViewOrder:[(SessionView*)nearestNeighbor session]];
    }
    
    [self recheckBlur];
    [realParentWindow_ sessionWasRemoved];
}

- (BOOL)canSplitVertically:(BOOL)isVertical withSize:(NSSize)newSessionSize
{
    NSSplitView* parentSplit = (NSSplitView*)[[activeSession_ view] superview];
    if (isVertical == [parentSplit isVertical]) {
        // Add a child to parentSplit.
        // This is a slightly bogus heuristic: if any sibling of the active session has a violated min
        // size constraint then splits are no longer possible.
        for (NSView* aView in [parentSplit subviews]) {
            NSSize actualSize = [aView frame].size;
            NSSize minSize;
            if ([aView isKindOfClass:[NSSplitView class]]) {
                NSSplitView* splitView = (NSSplitView*)aView;
                minSize = [self _recursiveMinSize:splitView];
            } else {
                SessionView* sessionView = (SessionView*)aView;
                minSize = [self _minSessionSize:sessionView];
            }
            if (isVertical && actualSize.width < minSize.width) {
                return NO;
            }
            if (!isVertical && actualSize.height < minSize.height) {
                return NO;
            }
        }
        return YES;
    } else {
        // Active session will be replaced with a splitter.
        // Another bogus heuristic: if the active session's constraints have been violated then you
        // can't split.
        NSSize actualSize = [[activeSession_ view] frame].size;
        NSSize minSize = [self _minSessionSize:[activeSession_ view]];
        if (isVertical && actualSize.width < minSize.width) {
            return NO;
        }
        if (!isVertical && actualSize.height < minSize.height) {
            return NO;
        }
        return YES;
    }
}

- (void)dumpSubviewsOf:(NSSplitView*)split
{
    for (NSView* v in [split subviews]) {
        PtyLog(@"View %p has height %lf", v, [v frame].size.height);
    }
}

- (void)adjustSubviewsOf:(NSSplitView*)split
{
    PtyLog(@"--- adjust ---");
    [split adjustSubviews];
    PtyLog(@">>AFTER:");
    [self dumpSubviewsOf:split];
    PtyLog(@"<<<<<<<< end dump");
}

- (SessionView*)splitVertically:(BOOL)isVertical targetSession:(PTYSession*)targetSession
{
    if (isMaximized_) {
        [self unmaximize];
    }
    PtyLog(@"PTYTab splitVertically");
    SessionView* targetSessionView = [targetSession view];
    NSSplitView* parentSplit = (NSSplitView*) [targetSessionView superview];
    SessionView* newView = [[[SessionView alloc] initWithFrame:[targetSessionView frame]] autorelease];

    // There has to be an active session, so the parent must have one child.
    assert([[parentSplit subviews] count] != 0);
    PtyLog(@"Before:");
    [self dump];
    if ([[parentSplit subviews] count] == 1) {
        PtyLog(@"PTYTab splitVertically: one child");
        // If the parent split has only one child then it must also be the root.
        assert(parentSplit == root_);

        // Set its orientation to vertical and add the new view.
        [parentSplit setVertical:isVertical];
        [parentSplit addSubview:newView positioned:NSWindowAbove relativeTo:targetSessionView];

        // Resize all subviews the same size to accommodate the new view.
        [self adjustSubviewsOf:parentSplit];
        [self _splitViewDidResizeSubviews:parentSplit];
    } else if ([parentSplit isVertical] != isVertical) {
        PtyLog(@"PTYTab splitVertically parent has opposite orientation");
        // The parent has the opposite orientation splits and has many children. We need to do this:
        // 1. Remove the active SessionView from its parent
        // 2. Replace it with an 'isVertical'-orientation NSSplitView
        // 3. Add two children to the 'isVertical'-orientation NSSplitView: the active session and the new view.
        [targetSessionView retain];
        NSSplitView* newSplit = [[MySplitView alloc] initWithFrame:[targetSessionView frame]];
        if (USE_THIN_SPLITTERS) {
            [newSplit setDividerStyle:NSSplitViewDividerStyleThin];
        }
        [newSplit setAutoresizesSubviews:YES];
        [newSplit setDelegate:self];
        [newSplit setVertical:isVertical];
        [[targetSessionView superview] replaceSubview:targetSessionView with:newSplit];
        [newSplit release];
        [newSplit addSubview:targetSessionView];
        [targetSessionView release];
        [newSplit addSubview:newView];

        // Resize all subviews the same size to accommodate the new view.
        [self adjustSubviewsOf:parentSplit];
        [newSplit adjustSubviews];
        [self _splitViewDidResizeSubviews:newSplit];
    } else {
        PtyLog(@"PTYTab splitVertically multiple children");
        // The parent has same-orientation splits and there is more than one child.
        [parentSplit addSubview:newView positioned:NSWindowAbove relativeTo:targetSessionView];

        // Resize all subviews the same size to accommodate the new view.
        [self adjustSubviewsOf:parentSplit];
        [self _splitViewDidResizeSubviews:parentSplit];
    }
    PtyLog(@"After:");
    [self dump];

    [self appendSessionViewToViewOrder:newView];
    
    return newView;
}

- (NSSize)_sessionSize:(SessionView*)sessionView
{
    NSSize size;
    PTYSession* session = [sessionView session];
    PtyLog(@"    session size based on %d rows", [session rows]);
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
    size.width = MIN_SESSION_COLUMNS * [[session TEXTVIEW] charWidth] + MARGIN * 2;
    size.height = MIN_SESSION_ROWS * [[session TEXTVIEW] lineHeight] + VMARGIN * 2;

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
    PtyLog(@"Computing recursive size for node %p", node);
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
            PtyLog(@"  add %lf for divider", dividerSize.height);
        }

        BOOL subviewContainsLock = NO;
        if ([subview isKindOfClass:[NSSplitView class]]) {
            // Get size of child tree at this subview.
            subviewSize = [self _recursiveSize:(NSSplitView*)subview containsLock:&subviewContainsLock];
            PtyLog(@"  add %lf for child split", subviewSize.height);
        } else {
            // Get size of session at this subview.
            SessionView* sessionView = (SessionView*)subview;
            subviewSize = [self _sessionSize:sessionView];
            PtyLog(@"  add %lf for session", subviewSize.height);
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
// MIN_SESSION_COLUMNS columns by MIN_SESSION_ROWS rows.
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
    [self dumpSubviewsOf:root_];
    [root_ setFrameSize:newSize];
    //[root_ adjustSubviews];
    [self adjustSubviewsOf:root_];
    [self _splitViewDidResizeSubviews:root_];
}

- (void)_drawSession:(PTYSession*)session inImage:(NSImage*)viewImage atOrigin:(NSPoint)origin
{
    [[session TEXTVIEW] refresh];
    NSRect theRect = [[session SCROLLVIEW] documentVisibleRect];
    NSImage *textviewImage = [[[NSImage alloc] initWithSize:theRect.size] autorelease];

    [textviewImage setFlipped:YES];
    [textviewImage lockFocus];
    [[session TEXTVIEW] drawBackground:theRect toPoint:NSMakePoint(0, 0)];
    // Draw the background flipped, which is actually the right way up.
    NSPoint temp = NSMakePoint(0, 0);
    [[session TEXTVIEW] drawRect:theRect to:&temp];
    [textviewImage unlockFocus];

    [viewImage lockFocus];
    [textviewImage compositeToPoint:origin operation:NSCompositeSourceOver];
    [viewImage unlockFocus];
}

- (void)_recursiveDrawSplit:(NSSplitView*)splitView inImage:(NSImage*)viewImage atOrigin:(NSPoint)splitOrigin
{
    NSPoint origin = splitOrigin;
    CGFloat myHeight = [viewImage size].height;
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
            // flip the y coordinate for drawing
            NSRectFill(NSMakeRect(origin.x, myHeight - origin.y - (dy + hy),
                                  dx + hx, dy + hy));
            [viewImage unlockFocus];

            // Advance the origin past the divider.
            origin.x += dx;
            origin.y += dy;
        }

        if ([subview isKindOfClass:[NSSplitView class]]) {
            [self _recursiveDrawSplit:(NSSplitView*)subview inImage:viewImage atOrigin:origin];
        } else {
            SessionView* sessionView = (SessionView*)subview;
            // flip the y coordinate for drawing
            CGFloat y = myHeight - origin.y - [subview frame].size.height;
            [self _drawSession:[sessionView session] inImage:viewImage atOrigin:NSMakePoint(origin.x,
                                                                                            y)];
        }
        if ([splitView isVertical]) {
            origin.x += [subview frame].size.width;
        } else {
            origin.y += [subview frame].size.height;
        }
    }
}

- (NSImage*)image:(BOOL)withSpaceForFrame
{
    PtyLog(@"PTYTab image");
    NSRect tabFrame = [[realParentWindow_ tabBarControl] frame];
    NSSize viewSize = [root_ frame].size;
    if (withSpaceForFrame) {
        viewSize.height += tabFrame.size.height;
    }

    NSImage* viewImage = [[[NSImage alloc] initWithSize:viewSize] autorelease];
    [viewImage lockFocus];
    [[NSColor windowBackgroundColor] set];
    NSRectFill(NSMakeRect(0, 0, viewSize.width, viewSize.height));
    [viewImage unlockFocus];

    float yOrigin = 0;
    if (withSpaceForFrame && 
        [[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
        yOrigin += tabFrame.size.height;
    }

    [self _recursiveDrawSplit:root_ inImage:viewImage atOrigin:NSMakePoint(0, yOrigin)];

    // Draw over where the tab bar would usually be
    [viewImage lockFocus];
    [[NSColor windowBackgroundColor] set];
    if (withSpaceForFrame &&
        [[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
        tabFrame.origin.y += [viewImage size].height;
    }
    if (withSpaceForFrame) {
        NSRectFill(tabFrame);

        // Draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        [(id <PSMTabStyle>)[[[realParentWindow_ tabView] delegate] style] drawBackgroundInRect:tabFrame color:nil];  // TODO: use the right color
        [transform invert];
        [transform concat];
    }
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

    [aSession setWidth:width height:height];
    PtyLog(@"fitSessionToCurrentViewSize -  calling setWidth:%d height:%d", width, height);
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

+ (NSDictionary*)frameToDict:(NSRect)frame
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithDouble:frame.origin.x],
            TAB_X,
            [NSNumber numberWithDouble:frame.origin.y],
            TAB_Y,
            [NSNumber numberWithDouble:frame.size.width],
            TAB_WIDTH,
            [NSNumber numberWithDouble:frame.size.height],
            TAB_HEIGHT,
            nil];
}

+ (NSRect)dictToFrame:(NSDictionary*)dict
{
    return NSMakeRect([[dict objectForKey:TAB_X] doubleValue],
                      [[dict objectForKey:TAB_Y] doubleValue],
                      [[dict objectForKey:TAB_WIDTH] doubleValue],
                      [[dict objectForKey:TAB_HEIGHT] doubleValue]);
}

- (NSDictionary*)_recursiveArrangement:(NSView*)view idMap:(NSMutableDictionary*)idMap isMaximized:(BOOL)isMaximized
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    if (isMaximized) {
        [result setObject:[NSNumber numberWithBool:YES]
                   forKey:TAB_ARRANGEMENT_IS_MAXIMIZED];
    }
    isMaximized = NO;
    if ([view isKindOfClass:[NSSplitView class]]) {
        NSSplitView* splitView = (NSSplitView*)view;
        [result setObject:VIEW_TYPE_SPLITTER forKey:TAB_ARRANGEMENT_VIEW_TYPE];
        [result setObject:[PTYTab frameToDict:[view frame]] forKey:TAB_ARRANGEMENT_SPLIITER_FRAME];
        [result setObject:[NSNumber numberWithBool:[splitView isVertical]] forKey:SPLITTER_IS_VERTICAL];
        NSMutableArray* subviews = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];
        for (NSView* subview in [splitView subviews]) {
            [subviews addObject:[self _recursiveArrangement:subview idMap:idMap isMaximized:isMaximized]];
        }
        [result setObject:subviews forKey:SUBVIEWS];
    } else {
        SessionView* sessionView = (SessionView*)view;
        [result setObject:VIEW_TYPE_SESSIONVIEW
                   forKey:TAB_ARRANGEMENT_VIEW_TYPE];
        [result setObject:[PTYTab frameToDict:[view frame]]
                   forKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME];
        [result setObject:[[sessionView session] arrangement]
                   forKey:TAB_ARRANGEMENT_SESSION];
        [result setObject:[NSNumber numberWithBool:([sessionView session] == [self activeSession])]
                   forKey:TAB_ARRANGEMENT_IS_ACTIVE];
        if (idMap) {
            [result setObject:[NSNumber numberWithInt:[idMap count]]
                       forKey:TAB_ARRANGEMENT_ID];
            [idMap setObject:sessionView forKey:[NSNumber numberWithInt:[idMap count]]];
        }
    }
    return result;
}

+ (NSView*)_recusiveRestoreSplitters:(NSDictionary*)arrangement fromMap:(NSDictionary*)theMap
{
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSRect frame = [PTYTab dictToFrame:[arrangement objectForKey:TAB_ARRANGEMENT_SPLIITER_FRAME]];
        NSSplitView *splitter = [[MySplitView alloc] initWithFrame:frame];
        if (USE_THIN_SPLITTERS) {
            [splitter setDividerStyle:NSSplitViewDividerStyleThin];
        }
        [splitter setVertical:[[arrangement objectForKey:SPLITTER_IS_VERTICAL] boolValue]];

        NSArray* subviews = [arrangement objectForKey:SUBVIEWS];
        for (NSDictionary* subArrangement in subviews) {
            NSView* subView = [PTYTab _recusiveRestoreSplitters:(NSDictionary*)subArrangement
                                                        fromMap:theMap];
            if (subView) {
                [splitter addSubview:subView];
                [subView release];
            }
        }
        return splitter;
    } else {
        if (theMap) {
            return [[theMap objectForKey:[arrangement objectForKey:TAB_ARRANGEMENT_ID]] retain];
        } else {
            return [[SessionView alloc] initWithFrame:[PTYTab dictToFrame:[arrangement objectForKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME]]];
        }
    }
}

- (PTYSession*)_recursiveRestoreSessions:(NSDictionary*)arrangement atNode:(NSView*)view inTab:(PTYTab*)theTab
{
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        assert([view isKindOfClass:[NSSplitView class]]);
        NSSplitView* splitter = (NSSplitView*)view;
        NSArray* subArrangements = [arrangement objectForKey:SUBVIEWS];
        PTYSession* active = nil;
        for (int i = 0; i < [subArrangements count]; ++i) {
            NSDictionary* subArrangement = [subArrangements objectAtIndex:i];
            PTYSession* session = [self _recursiveRestoreSessions:subArrangement
                                                           atNode:[[splitter subviews] objectAtIndex:i]
                                                            inTab:theTab];
            if (session) {
                active = session;
            }
        }
        return active;
    } else {
        assert([view isKindOfClass:[SessionView class]]);
        SessionView* sessionView = (SessionView*)view;
        PTYSession* session = [PTYSession sessionFromArrangement:[arrangement objectForKey:TAB_ARRANGEMENT_SESSION]
                                                                                    inView:(SessionView*)view
                                                                                     inTab:theTab];
        [sessionView setSession:session];
        [self appendSessionToViewOrder:session];
        if ([[arrangement objectForKey:TAB_ARRANGEMENT_IS_ACTIVE] boolValue]) {
            [sessionView setDimmed:NO];
            return session;
        } else {
            [sessionView setDimmed:YES];
            return nil;
        }
    }
}

+ (void)openTabWithArrangement:(NSDictionary*)arrangement inTerminal:(PseudoTerminal*)term
{
    PTYTab* theTab;
    // Build a tree with splitters and SessionViews but no PTYSessions.
    NSSplitView* newRoot = (NSSplitView*)[PTYTab _recusiveRestoreSplitters:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                                                   fromMap:nil];

    // Create a tab.
    theTab = [[PTYTab alloc] initWithRoot:newRoot];
    [theTab setParentWindow:term];
    [theTab->tabViewItem_ setLabel:@"Restoring..."];
    [newRoot release];

    // Instantiate sessions in the skeleton view tree.
    [theTab setActiveSession:[theTab _recursiveRestoreSessions:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                                        atNode:theTab->root_
                                                         inTab:theTab]];

    // Add the existing tab, which is now fully populated, to the term.
    [term appendTab:theTab];
    [theTab release];

    NSDictionary* root = [arrangement objectForKey:TAB_ARRANGEMENT_ROOT];
    if ([root objectForKey:TAB_ARRANGEMENT_IS_MAXIMIZED] &&
        [[root objectForKey:TAB_ARRANGEMENT_IS_MAXIMIZED] boolValue]) {
        [theTab maximize];
    }
}

- (NSDictionary*)arrangementWithMap:(NSMutableDictionary*)idMap
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:1];
    BOOL temp = isMaximized_;
    if (isMaximized_) {
        [self unmaximize];
    }
    [result setObject:[self _recursiveArrangement:root_ idMap:idMap isMaximized:temp] forKey:TAB_ARRANGEMENT_ROOT];
    if (temp) {
        [self maximize];
    }

    return result;
}

- (NSDictionary*)arrangement
{
    return [self arrangementWithMap:nil];
}


- (BOOL)hasMaximizedPane
{
    return isMaximized_;
}

- (void)maximize
{
    assert(!savedArrangement_);
    assert(!idMap_);
    assert(!isMaximized_);

    SessionView* temp = [activeSession_ view];
    savedSize_ = [temp frame].size;

    idMap_ = [[NSMutableDictionary alloc] init];
    savedArrangement_ = [[self arrangementWithMap:idMap_] retain];
    isMaximized_ = YES;

    NSRect oldRootFrame = [root_ frame];
    [root_ removeFromSuperview];

    root_ = [[MySplitView alloc] init];
    [root_ setFrame:oldRootFrame];
    if (USE_THIN_SPLITTERS) {
        [root_ setDividerStyle:NSSplitViewDividerStyleThin];
    }
    [root_ setAutoresizesSubviews:YES];
    [root_ setDelegate:self];
    [tabViewItem_ setView:root_];

    [temp retain];
    [temp removeFromSuperview];
    [root_ addSubview:temp];
    [temp release];

    [[root_ window] makeFirstResponder:[activeSession_ TEXTVIEW]];
}

- (void)unmaximize
{
    assert(savedArrangement_);
    assert(idMap_);
    assert(isMaximized_);

    // Pull the formerly maximized sessionview out of the old root.
    assert([[root_ subviews] count] == 1);
    SessionView* formerlyMaximizedSessionView = [[root_ subviews] objectAtIndex:0];
    [formerlyMaximizedSessionView retain];
    [formerlyMaximizedSessionView removeFromSuperview];
    [formerlyMaximizedSessionView setFrameSize:savedSize_];

    // Build a tree with splitters and SessionViews/PTYSessions from idMap.
    NSSplitView* newRoot = (NSSplitView*)[PTYTab _recusiveRestoreSplitters:[savedArrangement_ objectForKey:TAB_ARRANGEMENT_ROOT]
                                                                   fromMap:idMap_];
    [PTYTab _recursiveSetDelegateIn:newRoot to:self];

    // Create a tab.
    [tabViewItem_ setView:newRoot];
    [root_ release];
    root_ = newRoot;

    [idMap_ release];
    idMap_ = nil;
    [savedArrangement_ release];
    savedArrangement_ = nil;
    isMaximized_ = NO;

    [[root_ window] makeFirstResponder:[activeSession_ TEXTVIEW]];
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

// The "grain" runs perpindicular to the splitters. An example with isVertical==YES:
// +----------------+
// |     |     |    |
// |     |     |    |
// |     |     |    |
// +----------------+
//
// <------grain----->

static CGFloat WithGrainDim(BOOL isVertical, NSSize size)
{
    return isVertical ? size.width : size.height;
}

static CGFloat AgainstGrainDim(BOOL isVertical, NSSize size)
{
    return WithGrainDim(!isVertical, size);
}

static void SetWithGrainDim(BOOL isVertical, NSSize* dest, CGFloat value)
{
    if (isVertical) {
        dest->width = value;
    } else {
        dest->height = value;
    }
}

static void SetAgainstGrainDim(BOOL isVertical, NSSize* dest, CGFloat value)
{
    SetWithGrainDim(!isVertical, dest, value);
}

- (void)_resizeSubviewsOfSplitViewWithLockedGrandchild:(NSSplitView *)splitView
{
    BOOL isVertical = [splitView isVertical];
    double unlockedSize = 0;
    double minUnlockedSize = 0;
    double lockedSize = WithGrainDim(isVertical, [self _sessionSize:[lockedSession_ view]]);

    // In comments, wgd = with-grain dimension
    // Add up the wgd of the unlocked subviews. Also add up their minimum wgds.
    for (NSView* subview in [splitView subviews]) {
        if ([[lockedSession_ view] superview] != subview) {
            unlockedSize += WithGrainDim(isVertical, [subview frame].size);
            if ([subview isKindOfClass:[NSSplitView class]]) {
                // Get size of child tree at this subview.
                minUnlockedSize += WithGrainDim(isVertical, [self _recursiveMinSize:(NSSplitView*)subview]);
            } else {
                // Get size of session at this subview.
                SessionView* sessionView = (SessionView*)subview;
                minUnlockedSize += WithGrainDim(isVertical, [self _minSessionSize:sessionView]);
            }
        }
    }

    // Check that we can respect the lock without allowing any subview to become smaller
    // than its minimum wgd.
    double overflow = minUnlockedSize + lockedSize - WithGrainDim(isVertical, [splitView frame].size);
    if (overflow > 0) {
        // We can't maintain the locked size without making some other subview smaller than
        // its allowed min. Ignore the lockedness of the session.
        NSLog(@"Warning: locked session doesn't leave enough space for other views. overflow=%lf", overflow);
        [splitView adjustSubviews];
        [self _splitViewDidResizeSubviews:splitView];
    } else {
        // Locked size can be respected. Adjust the size of every subview so that unlocked ones keep
        // their original relative proportions and the locked subview takes on its mandated size.
        double x = 0;
        double overage = 0;  // If subviews ended up larger than their proportional size would give, this is the sum of the extra wgds.
        double newSize = WithGrainDim(isVertical, [splitView frame].size) - [splitView dividerThickness] * ([[splitView subviews] count] - 1);
        for (NSView* subview in [splitView subviews]) {
            NSRect newRect = NSZeroRect;
            if (isVertical) {
                newRect.origin.x = x;
            } else {
                newRect.origin.y = x;
            }

            SetAgainstGrainDim(isVertical,
                               &newRect.size,
                               AgainstGrainDim(isVertical, [splitView frame].size));
            if ([[lockedSession_ view] superview] != subview) {
                double fractionOfUnlockedSpace = WithGrainDim(isVertical,
                                                              [subview frame].size) / unlockedSize;
                SetWithGrainDim(isVertical,
                                &newRect.size,
                                (newSize - lockedSize - overage) * fractionOfUnlockedSpace);
            } else {
                SetWithGrainDim(isVertical,
                                &newRect.size,
                                lockedSize);
            }
            double minSize;
            if ([subview isKindOfClass:[NSSplitView class]]) {
                // Get size of child tree at this subview.
                minSize = WithGrainDim(isVertical, [self _recursiveMinSize:(NSSplitView*)subview]);
            } else {
                // Get size of session at this subview.
                SessionView* sessionView = (SessionView*)subview;
                minSize = WithGrainDim(isVertical, [self _minSessionSize:sessionView]);
            }
            if (WithGrainDim(isVertical, newRect.size) < minSize) {
                overage += minSize - WithGrainDim(isVertical, newRect.size);
                SetWithGrainDim(isVertical, &newRect.size, minSize);
            }
            [subview setFrame:newRect];
            x += WithGrainDim(isVertical, newRect.size);
            x += [splitView dividerThickness];
        }
    }
}

- (void)_resizeSubviewsOfSplitViewWithLockedChild:(NSSplitView *)splitView oldSize:(NSSize)oldSize
{
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
            // Horizontal dividers so children are arranged vertically.
            // Set height of locked session and then resize all others proportionately.
            CGFloat availableSize = [splitView frame].size.height;

            // This also does not include dividers.
            double originalSizeWithoutLockedSession = oldSize.height - [[lockedSession_ view] frame].size.height - ([[splitView subviews] count] - 1) * [splitView dividerThickness];
            NSArray* mySubviews = [splitView subviews];
            NSSize lockedSize = [self _sessionSize:[lockedSession_ view]];
            availableSize -= lockedSize.height;
            availableSize -= [splitView dividerThickness];

            // Resize each child's height so that the space left excluding the locked session is
            // divided up in the same proportions as it was before the resize.
            NSRect newFrame = NSZeroRect;
            newFrame.size.width = lockedSize.width;
            for (id subview in mySubviews) {
                if (subview != [lockedSession_ view]) {
                    // Resizing a non-locked child.
                    NSSize subviewSize = [subview frame].size;
                    double fractionOfOriginalSize = subviewSize.height / originalSizeWithoutLockedSession;
                    newFrame.size.height = availableSize * fractionOfOriginalSize;
                } else {
                    newFrame.size.height = lockedSize.height;
                }
                [subview setFrame:newFrame];
                newFrame.origin.y += newFrame.size.height + [splitView dividerThickness];
            }
        }
    }
}

- (NSSet*)_ancestorsOfLockedSession
{
    NSMutableSet* result = [NSMutableSet setWithCapacity:1];
    id current = [[lockedSession_ view  ]superview];
    while (current != nil) {
        [result addObject:current];
        if (current == root_) {
            break;
        }
        current = [current superview];
    }
    return result;
}

// min of unlocked session x = minSize(x)
// max of unlocked session x = inf
//
// min of locked session x = sessionSize of x
// max of locked session x = sessionSize of x
//
// min of splitter with locked session s[x] = wtg: sum(minSize(i) for i != x) + sessionSize(x)
//                                            atg: sessionSize(x)
// max of splitter with locked session s[x] = wtg: sum(maxSize(i))
//                                            atg: sessionSize(x)
//
// +--------+
// |   |    |
// |   +----+
// |   |xxxx|
// +---+----+
//
// ** this is a generalizable version of all the above: **
// min of splitter with locked grandchild s[x1][x2] = wtg: sum(minSize(i) for all i)
//                                                    atg: max(minSize(i) for all i)
// max of splitter with locked grandchild s[x1][x2] = wtg: sum(maxSize(i))
//                                                    atg: min(maxSize(i) for all i)


- (void)_recursiveLockedSize:(NSView*)theSubview ancestors:(NSSet*)ancestors minSize:(NSSize*)minSize maxSize:(NSSize*)maxSizeOut
{
    if ([theSubview isKindOfClass:[SessionView class]]) {
        // This must be the locked session. Its min and max size are exactly its ideal size.
        assert(theSubview == [lockedSession_ view]);
        NSSize size = [self _sessionSize:(SessionView*)theSubview];
        *minSize = *maxSizeOut = size;
    } else {
        // This is some ancestor of the locked session.
        NSSplitView* splitView = (NSSplitView*)theSubview;
        *minSize = NSZeroSize;
        BOOL isVertical = [splitView isVertical];
        SetAgainstGrainDim(isVertical, maxSizeOut, INFINITY);
        SetWithGrainDim(isVertical, maxSizeOut, 0);
        BOOL first = YES;
        for (NSView* aView in [splitView subviews]) {
            NSSize viewMin;
            NSSize viewMax;
            if (aView == [lockedSession_ view] || [ancestors containsObject:aView]) {
                [self _recursiveLockedSize:aView ancestors:ancestors minSize:&viewMin maxSize:&viewMax];
            } else {
                viewMin = [self _minSizeOfView:aView];
                viewMax.width = INFINITY;
                viewMax.height = INFINITY;
            }
            double thickness;
            if (first) {
                first = NO;
                thickness = 0;
            } else {
                thickness = [splitView dividerThickness];
            }
            // minSize.wtg := sum(viewMin)
            SetWithGrainDim(isVertical,
                            minSize,
                            WithGrainDim(isVertical, *minSize) + WithGrainDim(isVertical, viewMin) + thickness);
            // minSize.atg := MAX(viewMin)
            SetAgainstGrainDim(isVertical,
                               minSize,
                               MAX(AgainstGrainDim(isVertical, *minSize), AgainstGrainDim(isVertical, viewMin)));
            // maxSizeOut.wtg := sum(viewMax)
            SetWithGrainDim(isVertical,
                            maxSizeOut,
                            WithGrainDim(isVertical, *maxSizeOut) + WithGrainDim(isVertical, viewMax) + thickness);
            // maxSizeOut.atg := MIN(viewMax)
            SetAgainstGrainDim(isVertical,
                               maxSizeOut,
                               MIN(AgainstGrainDim(isVertical, *maxSizeOut), AgainstGrainDim(isVertical, viewMax)));
        }
    }
}

- (void)_redistributeQuantizationError:(const double)targetSize
                     currentSumOfSizes:(double)currentSumOfSizes
                                 sizes:(NSMutableArray *)sizes
                              minSizes:(NSArray*)minSizes
                              maxSizes:(NSArray*)maxSizes
{
    // In case quantization caused some rounding error, randomly adjust subviews by plus or minus
    // one pixel.
    int error = currentSumOfSizes - targetSize;
    int change;
    if (error > 0) {
        change = -1;
    } else {
        change = 1;
    }
    // First redistribute error while respecting min and max constraints until that is no longer
    // possible.
    while (error != 0) {
        BOOL anyChange = NO;
        for (int i = 0; i < [sizes count] && error != 0; ++i) {
            const double size = [[sizes objectAtIndex:i] doubleValue];
            const double theMin = [[minSizes objectAtIndex:i] doubleValue];
            const double theMax = [[maxSizes objectAtIndex:i] doubleValue];
            const double proposedSize = size + change;
            if (proposedSize >= theMin && proposedSize <= theMax) {
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:proposedSize]];
                error += change;
                anyChange = YES;
            }
        }
        if (!anyChange) {
            break;
        }
    }

    // As long as there is still some error left, use 1 for min and disregard max.
    while (error != 0) {
        BOOL anyChange = NO;
        for (int i = 0; i < [sizes count] && error != 0; ++i) {
            const double size = [[sizes objectAtIndex:i] doubleValue];
            if (size + change > 0) {
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:size + change]];
                error += change;
                anyChange = YES;
            }
        }
        if (!anyChange) {
            PtyLog(@"Failed to redistribute quantization error. Change=%d, sizes=%@.", change, sizes);
            NSLog(@"Failed to redistribute quantization error. Change=%d, sizes=%@.", change, sizes);
            return;
        }
    }
}

// Called after a splitter has been resized. This adjusts session sizes appropriately,
// with special attention paid to the "locked" session, which never resizes.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
    if ([[splitView subviews] count] == 0) {
        // nothing to do!
        return;
    }
    PtyLog(@"splitView:resizeSubviewsWithOldSize for %p", splitView);
    BOOL isVertical = [splitView isVertical];
    NSSet* ancestors = [self _ancestorsOfLockedSession];
    NSSize minLockedSize = NSZeroSize;
    NSSize maxLockedSize = NSZeroSize;
    const double n = [[splitView subviews] count];

    // Find the min, max, and ideal proportionate size for each subview.
    NSMutableArray* sizes = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];
    NSMutableArray* minSizes = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];
    NSMutableArray* maxSizes = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];

    // This is the sum of the with-the-grain sizes excluding dividers that we need to attain.
    const double targetSize = WithGrainDim(isVertical, [splitView frame].size) - ([splitView dividerThickness] * (n - 1));
    PtyLog(@"splitView:resizeSubviewsWithOldSize - target size is %lf", targetSize);

    // Add up the existing subview sizes to come up with the previous total size excluding dividers.
    double oldTotalSize = 0;
    for (NSView* aSubview in [splitView subviews]) {
        oldTotalSize += WithGrainDim(isVertical, [aSubview frame].size);
    }
    double sizeChangeCoeff = 0;
    BOOL ignoreConstraints = NO;
    if (oldTotalSize == 0) {
        // Nothing to go by. Just set all subviews to the same size.
        PtyLog(@"splitView:resizeSubviewsWithOldSize: old size was 0");
        ignoreConstraints = YES;
    } else {
        sizeChangeCoeff = targetSize / oldTotalSize;
        PtyLog(@"splitView:resizeSubviewsWithOldSize. initial coeff=%lf", sizeChangeCoeff);
    }
    if (!ignoreConstraints) {
        // Set the min and max size for each subview. Assign an initial guess to sizes.
        double currentSumOfSizes = 0;
        double currentSumOfMinClamped = 0;
        double currentSumOfMaxClamped = 0;
        for (NSView* aSubview in [splitView subviews]) {
            double theMinSize;
            double theMaxSize;
            if (aSubview == [lockedSession_ view] || [ancestors containsObject:aSubview]) {
                [self _recursiveLockedSize:aSubview
                                 ancestors:ancestors
                                   minSize:&minLockedSize
                                   maxSize:&maxLockedSize];
                theMinSize = WithGrainDim(isVertical, minLockedSize);
                theMaxSize = WithGrainDim(isVertical, maxLockedSize);
                PtyLog(@"splitView:resizeSubviewsWithOldSize - this subview is LOCKED");
            } else {
                if ([aSubview isKindOfClass:[NSSplitView class]]) {
                    theMinSize = WithGrainDim(isVertical, [self _recursiveMinSize:(NSSplitView*)aSubview]);
                } else {
                    theMinSize = WithGrainDim(isVertical, [self _minSessionSize:(SessionView*)aSubview]);
                }
                theMaxSize = targetSize;
                PtyLog(@"splitView:resizeSubviewsWithOldSize - this subview is unlocked");
            }
            PtyLog(@"splitView:resizeSubviewsWithOldSize - range of %p is [%lf,%lf]", aSubview, theMinSize, theMaxSize);
            [minSizes addObject:[NSNumber numberWithDouble:theMinSize]];
            [maxSizes addObject:[NSNumber numberWithDouble:theMaxSize]];
            const double initialGuess = sizeChangeCoeff * WithGrainDim(isVertical, [aSubview frame].size);
            const double size = lround(MIN(MAX(initialGuess, theMinSize), theMaxSize));
            PtyLog(@"splitView:resizeSubviewsWithOldSize - initial guess of %p is %lf, clamped is %lf", aSubview, initialGuess, size);
            [sizes addObject:[NSNumber numberWithDouble:size]];
            currentSumOfSizes += size;
            if (size == theMinSize) {
                currentSumOfMinClamped += size;
            }
            if (size == theMaxSize) {
                currentSumOfMaxClamped += size;
            }
        }

        // Refine sizes while we're more than half a pixel away from the target size.
        const double kEpsilon = 0.5;
        while (fabs(currentSumOfSizes - targetSize) > kEpsilon) {
            PtyLog(@"splitView:resizeSubviewsWithOldSize - refining. currentSumOfSizes=%lf vs target %lf", currentSumOfSizes, targetSize);
            double currentSumOfUnclamped;
            double desiredNewSizeForUnclamped;
            if (currentSumOfSizes < targetSize) {
                currentSumOfUnclamped = currentSumOfSizes - currentSumOfMaxClamped;
                desiredNewSizeForUnclamped = targetSize - currentSumOfMaxClamped;
            } else {
                currentSumOfUnclamped = currentSumOfSizes - currentSumOfMinClamped;
                desiredNewSizeForUnclamped = targetSize - currentSumOfMinClamped;
            }
            if (currentSumOfUnclamped < kEpsilon) {
                // Not enough unclamped space to make any change.
                ignoreConstraints = YES;
                break;
            }
            // Set a coefficient that will be applied only to subviews that aren't clamped. If we're
            // able to resize all currently unclamped subviews by this coefficient then we should
            // hit exactly the target size.
            const double coeff = desiredNewSizeForUnclamped / currentSumOfUnclamped;
            PtyLog(@"splitView:resizeSubviewsWithOldSize - coeff %lf to bring current %lf unclamped size to %lf", coeff, currentSumOfUnclamped, desiredNewSizeForUnclamped);

            // Try to resize every subview by the coefficient. Clamped subviews won't be able to
            // change.
            currentSumOfSizes = 0;
            currentSumOfMinClamped = 0;
            currentSumOfMaxClamped = 0;
            BOOL anyChanges = NO;
            for (int i = 0; i < [sizes count]; ++i) {
                const double preferredSize = [[sizes objectAtIndex:i] doubleValue] * coeff;
                const double theMinSize = [[minSizes objectAtIndex:i] doubleValue];
                const double theMaxSize = [[maxSizes objectAtIndex:i] doubleValue];
                const double size = lround(MIN(MAX(preferredSize, theMinSize), theMaxSize));
                if (!anyChanges && size != [[sizes objectAtIndex:i] doubleValue]) {
                    anyChanges = YES;
                }
                PtyLog(@"splitView:resizeSubviewsWithOldSize - change %lf to %lf (would be %lf unclamped)", [[sizes objectAtIndex:i] doubleValue], size, preferredSize);
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:size]];

                currentSumOfSizes += size;
                if (size == theMinSize) {
                    currentSumOfMinClamped += size;
                }
                if (size == theMaxSize) {
                    currentSumOfMaxClamped += size;
                }
            }
            if (!anyChanges) {
                PtyLog(@"splitView:resizeSubviewsWithOldSize - nothing changed in this round");
                if (fabs(currentSumOfSizes - targetSize) > [[splitView subviews] count]) {
                    // I'm not sure this will ever happen, but just in case quantization prevents us
                    // from converging give up and ignore constraints.
                    NSLog(@"No changes! Ignoring constraints!");
                    PtyLog(@"splitView:resizeSubviewsWithOldSize - No changes! Ignoring constraints!");
                    ignoreConstraints = YES;
                } else {
                    PtyLog(@"splitView:resizeSubviewsWithOldSize - redistribute quantization error");
                    [self _redistributeQuantizationError:targetSize
                                       currentSumOfSizes:currentSumOfSizes
                                                   sizes:sizes
                                                minSizes:minSizes
                                                maxSizes:maxSizes];
                }
                break;
            }
        }
    }

    if (ignoreConstraints) {
        PtyLog(@"splitView:resizeSubviewsWithOldSize - ignoring constraints");
        // Not all the constraints could be satisfied. Set every subview to its ideal size and hope
        // for the best.
        double currentSumOfSizes = 0;
        if (sizeChangeCoeff == 0) {
            // Original size was 0 so make all subviews equal.
            for (NSView* aSubview in [splitView subviews]) {
                const double size = lround(targetSize / n);
                currentSumOfSizes += size;
                [sizes addObject:[NSNumber numberWithDouble:size]];
            }
        } else {
            // Resize everything proportionately.
            for (int i = 0; i < [sizes count]; ++i) {
                NSView* aSubview = [[splitView subviews] objectAtIndex:i];
                const double size = lround(sizeChangeCoeff * WithGrainDim(isVertical, [aSubview frame].size));
                currentSumOfSizes += size;
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:size]];
            }
        }

        [self _redistributeQuantizationError:targetSize
                           currentSumOfSizes:currentSumOfSizes
                                       sizes:sizes
                                    minSizes:minSizes
                                    maxSizes:maxSizes];
    }

    // Set subview frames to computed sizes.
    NSRect frame = NSZeroRect;
    SetAgainstGrainDim(isVertical, &frame.size, AgainstGrainDim(isVertical, [splitView frame].size));
    for (int i = 0; i < [sizes count]; ++i) {
        SetWithGrainDim(isVertical, &frame.size, [[sizes objectAtIndex:i] doubleValue]);
        [[[splitView subviews] objectAtIndex:i] setFrame:frame];
        if (isVertical) {
            frame.origin.x += frame.size.width + [splitView dividerThickness];
        } else {
            frame.origin.y += frame.size.height + [splitView dividerThickness];
        }
    }
}

// Inform sessions about their new sizes. This is called after views have finished
// being resized.
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
    PtyLog(@"splitViewDidResizeSubviews notification received. new height is %lf", [root_ frame].size.height);
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
        } else {
            [self _splitViewDidResizeSubviews:(NSSplitView*)subview];
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
                [[session SCREEN] growl] &&
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
        ![[self parentWindow] sendInputToAllSessions] &&
        [[[self activeSession] SCREEN] growl] ) {
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

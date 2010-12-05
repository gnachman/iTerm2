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
    if (self) {
        session_ = [session retain];
        [session_ setTab:self];
    }
    return self;
}

- (void)dealloc
{
    [fakeParentWindow_ release];
    [icon_ release];
    [session_ release];
    [super dealloc];
}

- (NSTabViewItem *)tabViewItem
{
    return tabViewItem_;
}

- (void)setBell:(BOOL)flag
{
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
    return session_;
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

- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem
{
    // The tab view item holds a refernece to us. So we don't hold a reference to it.
    tabViewItem_ = theTabViewItem;
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

- (void)setLabelAttributes
{
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
    [[self parentWindow] closeTab:self];
}

- (void)terminateAllSessions
{
    [[self activeSession] terminate];
}

- (NSArray*)sessions
{
    return [NSArray arrayWithObject:[self activeSession]];
}

- (BOOL)allSessionsExited
{
    return [[self activeSession] exited];
}

- (void)setDvrInSession:(PTYSession*)newSession
{
    PTYSession* oldSession = [self activeSession];
    assert(oldSession != newSession);

    // Swap views between newSession and oldSession.
    SessionView* newView = [newSession view];
    [[oldSession view] removeFromSuperview];
    [newView removeFromSuperview];
    [tabViewItem_ setView:newView];

    [newSession setName:[oldSession name]];
    [newSession setDefaultName:[oldSession defaultName]];

    // Put the new session in DVR mode and pass it the old session, wffffffffffhich it
    // keeps a reference to.

    [newSession setDvr:[[oldSession SCREEN] dvr] liveSession:oldSession];

    [session_ autorelease];
    session_ = [newSession retain];

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
    [replaySession cancelTimers];
    [liveSession setAddressBookEntry:[replaySession addressBookEntry]];

    SessionView* oldView = [replaySession view];
    SessionView* newView = [liveSession view];
    [oldView removeFromSuperview];
    [newView removeFromSuperview];
    [tabViewItem_ setView:newView];

    [session_ autorelease];
    session_ = [liveSession retain];

    [fakeParentWindow_ rejoin:realParentWindow_];
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

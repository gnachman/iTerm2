//
//  TmuxDashboardController.m
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxDashboardController.h"
#import "TmuxSessionsTable.h"
#import "TmuxController.h"
#import "TSVParser.h"
#import "TmuxControllerRegistry.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"

@interface TmuxDashboardController (Private)

- (void)tmuxControllerDetached:(NSNotification *)notification;
- (TmuxController *)tmuxController;

@end

@implementation TmuxDashboardController

+ (TmuxDashboardController *)sharedInstance
{
    static TmuxDashboardController *instance;
    if (!instance) {
        instance = [[TmuxDashboardController alloc] init];
    }
    return instance;
}

- (id)init
{
    self = [super initWithWindowNibName:@"TmuxDashboard"];
    if (self) {
        [self window];

        [sessionsTable_ selectSessionWithName:[[self tmuxController] sessionName]];
        [self reloadWindows];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerDetached:)
                                                     name:kTmuxControllerDetachedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerSessionsDidChange:)
                                                     name:kTmuxControllerSessionsDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowsDidChange:)
                                                     name:kTmuxControllerWindowsChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowWasRenamed:)
                                                     name:kTmuxControllerWindowWasRenamed
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowOpenedOrClosed:)
                                                     name:kTmuxControllerWindowDidOpen
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowOpenedOrClosed:)
                                                     name:kTmuxControllerWindowDidClose
                                                   object:nil];
    }

    return self;
}

- (void)dealloc {
    [super dealloc];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [sessionsTable_ setDelegate:self];
    [windowsTable_ setDelegate:self];
}

#pragma mark TmuxSessionsTableProtocol

- (void)renameSessionWithName:(NSString *)oldName toName:(NSString *)newName
{
    [[self tmuxController] renameSession:oldName to:newName];
}

- (void)removeSessionWithName:(NSString *)sessionName
{
    [[self tmuxController] killSession:sessionName];
}

- (void)addSessionWithName:(NSString *)sessionName
{
    [[self tmuxController] addSessionWithName:sessionName];
}

- (void)attachToSessionWithName:(NSString *)sessionName
{
    [[self tmuxController] attachToSession:sessionName];
}

- (NSString *)nameOfAttachedSession
{
    return [[self tmuxController] sessionName];
}

- (NSArray *)sessions
{
    return [[self tmuxController] sessions];
}

- (void)selectedSessionChangedTo:(NSString *)newSessionName
{
    [windowsTable_ setWindows:[NSArray array]];
    [self reloadWindows];
}

#pragma mark TmuxWindowsTableProtocol

- (void)reloadWindows
{
    [[self tmuxController] listWindowsInSession:[sessionsTable_ selectedSessionName]
                                         target:self
                                       selector:@selector(setWindows:forSession:)
                                         object:[sessionsTable_ selectedSessionName]];
}

- (void)setWindows:(TSVDocument *)doc forSession:(NSString *)sessionName
{
    if ([sessionName isEqualToString:[sessionsTable_ selectedSessionName]]) {
        NSMutableArray *windows = [NSMutableArray array];
        for (NSArray *record in doc.records) {
            [windows addObject:[NSMutableArray arrayWithObjects:
                                [doc valueInRecord:record forField:@"window_name"],
                                [doc valueInRecord:record forField:@"window_id"],
                                nil]];
        }
        [windowsTable_ setWindows:windows];
    }
}

- (void)renameWindowWithId:(int)windowId toName:(NSString *)newName
{
    [[self tmuxController] renameWindowWithId:windowId
                                    inSession:[sessionsTable_ selectedSessionName]
                                       toName:newName];
    [self reloadWindows];
}

- (void)unlinkWindowWithId:(int)windowId
{
    [[self tmuxController] unlinkWindowWithId:windowId
                                    inSession:[sessionsTable_ selectedSessionName]];
    [self reloadWindows];
}

- (void)addWindow
{
    NSString *lastName = [[windowsTable_ names] lastObject];
    if (lastName) {
        [[self tmuxController] newWindowInSession:[sessionsTable_ selectedSessionName]
                              afterWindowWithName:lastName];
    }
}

- (void)showWindowsWithIds:(NSArray *)windowIds inTabs:(BOOL)inTabs
{
    if (inTabs) {
        for (NSNumber *wid in windowIds) {
            [[self tmuxController] openWindowWithId:[wid intValue]
                                         affinities:windowIds];
        }
    } else {
        for (NSNumber *wid in windowIds) {
            [[self tmuxController] openWindowWithId:[wid intValue]];
        }
    }
}

- (void)hideWindowWithId:(int)windowId
{
    PTYTab *theTab = [[self tmuxController] window:windowId];
    if (theTab) {
        [[theTab realParentWindow] closeTab:theTab soft:YES];
    }
    [windowsTable_ updateEnabledStateOfButtons];
}

- (BOOL)haveSelectedSession
{
    return [sessionsTable_ selectedSessionName] != nil;
}

- (BOOL)currentSessionSelected
{
    return [[sessionsTable_ selectedSessionName] isEqualToString:[[self tmuxController] sessionName]];
}

- (BOOL)haveOpenWindowWithId:(int)windowId
{
    return [[self tmuxController] window:windowId] != nil;
}

@end

@implementation TmuxDashboardController (Private)

- (void)tmuxControllerDetached:(NSNotification *)notification
{
    [sessionsTable_ setSessions:[NSArray array]];
}

- (void)tmuxControllerSessionsDidChange:(NSNotification *)notification
{
    [sessionsTable_ setSessions:[notification object]];
}

- (void)tmuxControllerWindowsDidChange:(NSNotification *)notification
{
    if ([[self window] isVisible]) {
        [self reloadWindows];
    }
}

- (void)tmuxControllerWindowOpenedOrClosed:(NSNotification *)notification
{
    if ([[self window] isVisible]) {
        [windowsTable_ updateEnabledStateOfButtons];
    }
}

- (void)tmuxControllerWindowWasRenamed:(NSNotification *)notification
{
    if ([[self window] isVisible]) {
        NSArray *objects = [notification object];
        int wid = [[objects objectAtIndex:0] intValue];
        NSString *newName = [objects objectAtIndex:1];
        [windowsTable_ setNameOfWindowWithId:wid to:newName];
    }
}

- (TmuxController *)tmuxController
{
    return [[TmuxControllerRegistry sharedInstance] controllerForClient:@""];  // TODO: track the current client when multiples are supported
}

@end

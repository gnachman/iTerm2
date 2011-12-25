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

@interface TmuxDashboardController (Private)

- (void)tmuxControllerDetached:(NSNotification *)notification;

@end

@implementation TmuxDashboardController

@synthesize tmuxController = tmuxController_;

- (id)initWithTmuxController:(TmuxController *)tmuxController
{
    self = [super initWithWindowNibName:@"TmuxDashboard"];
    if (self) {
        self.tmuxController = tmuxController;
        [self window];

        [sessionsTable_ selectSessionWithName:[tmuxController sessionName]];
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
}

#pragma mark TmuxSessionsTableProtocol

- (void)renameSessionWithName:(NSString *)oldName toName:(NSString *)newName
{
    [tmuxController_ renameSession:oldName to:newName];
}

- (void)removeSessionWithName:(NSString *)sessionName
{
    [tmuxController_ killSession:sessionName];
}

- (void)addSessionWithName:(NSString *)sessionName
{
}

- (void)attachToSessionWithName:(NSString *)sessionName
{
}

- (NSString *)nameOfAttachedSession
{
    return [tmuxController_ sessionName];
}

- (NSArray *)sessions
{
    return [tmuxController_ sessions];
}

@end

@implementation TmuxDashboardController (Private)

- (void)tmuxControllerDetached:(NSNotification *)notification {
    if (![tmuxController_ isAttached]) {
        [[self window] close];
    }
    self.tmuxController = nil;
}

- (void)tmuxControllerSessionsDidChange:(NSNotification *)notification {
    [sessionsTable_ setSessions:[notification object]];
}

- (void)tmuxControllerWindowsDidChange:(NSNotification *)notification {
    if ([[self window] isVisible]) {
        NSString *sessionName = [sessionsTable_ selectedSessionName];
        if (sessionName) {
            [tmuxController_ listWindowsInSession:sessionName
                                           target:self
                                         selector:@selector(setWindows:inSession:)
                                           object:[sessionsTable_ selectedSessionName]];
        }
    }
}

- (void)setWindows:(TSVDocument *)windows inSession:(NSString *)sessionName {
    // TODO
}

@end

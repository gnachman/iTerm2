//
//  TmuxDashboardController.m
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxDashboardController.h"

#import "ITAddressBookMgr.h"
#import "iTermInitialDirectory.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferences.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "TmuxSessionsTable.h"
#import "TmuxController.h"
#import "TSVParser.h"
#import "TmuxControllerRegistry.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"

@interface TmuxDashboardController ()

- (void)tmuxControllerDetached:(NSNotification *)notification;
- (TmuxController *)tmuxController;

@end

@implementation TmuxDashboardController {
    IBOutlet TmuxSessionsTable *sessionsTable_;
    IBOutlet TmuxWindowsTable *windowsTable_;
    IBOutlet NSPopUpButton *connectionsButton_;
    IBOutlet NSTextField *setting_;
    IBOutlet NSStepper *stepper_;
}

+ (TmuxDashboardController *)sharedInstance {
    static TmuxDashboardController *instance;
    if (!instance) {
        instance = [[TmuxDashboardController alloc] init];
    }
    return instance;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"TmuxDashboard"];
    if (self) {
        [self window];

        [sessionsTable_ selectSessionNumber:[[self tmuxController] sessionId]];
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerAttachedSessionChanged:)
                                                     name:kTmuxControllerAttachedSessionDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerSessionWasRenamed:)
                                                     name:kTmuxControllerSessionWasRenamed
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerRegistryDidChange:)
                                                     name:kTmuxControllerRegistryDidChange
                                                   object:nil];
        __weak __typeof(self) weakSelf = self;
        [iTermPreferenceDidChangeNotification subscribe:self block:^(iTermPreferenceDidChangeNotification *notification) {
            [weakSelf preferenceDidChange:notification];
        }];
    }

    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self tmuxControllerRegistryDidChange:nil];
    if ([connectionsButton_ numberOfItems] > 0) {
        [connectionsButton_ selectItemAtIndex:0];
    }
    [sessionsTable_ setDelegate:self];
    [windowsTable_ setDelegate:self];
    setting_.integerValue = [iTermPreferences intForKey:kPreferenceKeyTmuxDashboardLimit];
    stepper_.integerValue = setting_.integerValue;
}

- (void)preferenceDidChange:(iTermPreferenceDidChangeNotification *)notification {
    if ([notification.key isEqualToString:kPreferenceKeyTmuxDashboardLimit]) {
        setting_.integerValue = [notification.value integerValue];
        stepper_.integerValue = [notification.value integerValue];
    }
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    NSTextField *field = [aNotification object];
    if (field != setting_) {
        return;
    }

    int i = [setting_ intValue];
    [iTermPreferences setInt:i forKey:kPreferenceKeyTmuxDashboardLimit];
}

- (IBAction)step:(id)sender {
    [iTermPreferences setInt:stepper_.intValue forKey:kPreferenceKeyTmuxDashboardLimit];
}

// cmd-w
- (IBAction)closeCurrentSession:(id)sender
{
    if ([[self window] isKeyWindow]) {
        [self close];
    }
}

#pragma mark TmuxSessionsTableProtocol

- (void)renameSessionWithNumber:(int)sessionNumber toName:(NSString *)newName {
    [[self tmuxController] renameSessionNumber:sessionNumber
                                            to:newName];
}

- (void)removeSessionWithNumber:(int)sessionNumber {
    [[self tmuxController] killSessionNumber:sessionNumber];
}

- (void)addSessionWithName:(NSString *)sessionName {
    [[self tmuxController] addSessionWithName:sessionName];
}

- (void)attachToSessionWithNumber:(int)sessionNumber {
    [[self tmuxController] attachToSessionWithNumber:sessionNumber];
}

- (void)detach {
    [[self tmuxController] requestDetach];
}

- (NSNumber *)numberOfAttachedSession {
    TmuxController *controller = [self tmuxController];
    if (!controller) {
        return nil;
    }
    return @([controller sessionId]);
}

- (NSArray<iTermTmuxSessionObject *> *)sessionsTableModelValues:(id)sender {
    return [self.tmuxController sessionObjects];
}

- (NSArray<iTermTmuxSessionObject *> *)sessionsTableObjects:(TmuxSessionsTable *)sender {
    return [[self tmuxController] sessionObjects];
}

- (void)selectedSessionDidChange {
    [windowsTable_ setWindows:[NSArray array]];
    [self reloadWindows];
}

- (void)linkWindowId:(int)windowId
     inSessionNumber:(int)sourceSessionNumber
     toSessionNumber:(int)targetSessionNumber {
    [[self tmuxController] linkWindowId:windowId
                        inSessionNumber:sourceSessionNumber
                        toSessionNumber:targetSessionNumber];
}

- (void)moveWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSessionNumber {
    [[self tmuxController] moveWindowId:windowId
                        inSessionNumber:sessionNumber
                        toSessionNumber:targetSessionNumber];
}

#pragma mark TmuxWindowsTableProtocol

- (void)reloadWindows {
    NSNumber *sessionNumber = [sessionsTable_ selectedSessionNumber];
    if (!sessionNumber) {
        return;
    }
    [[self tmuxController] listWindowsInSessionNumber:sessionNumber.intValue
                                               target:self
                                             selector:@selector(setWindows:forSession:)
                                               object:[sessionsTable_ selectedSessionNumber]];
}

- (void)setWindows:(TSVDocument *)doc forSession:(NSNumber *)sessionNumber {
    if ([sessionNumber isEqual:[sessionsTable_ selectedSessionNumber]]) {
        NSMutableArray *windows = [NSMutableArray array];
        for (NSArray *record in doc.records) {
            [windows addObject:[NSMutableArray arrayWithObjects:
                                [doc valueInRecord:record forField:@"window_name"],
                                [[doc valueInRecord:record forField:@"window_id"] substringFromIndex:1],
                                nil]];
        }
        [windowsTable_ setWindows:windows];
    }
}

- (void)renameWindowWithId:(int)windowId toName:(NSString *)newName {
    NSNumber *sessionNumber = [sessionsTable_ selectedSessionNumber];
    if (!sessionNumber) {
        return;
    }
    [[self tmuxController] renameWindowWithId:windowId
                              inSessionNumber:sessionNumber
                                       toName:newName];
    [self reloadWindows];
}

- (void)unlinkWindowWithId:(int)windowId {
    [[self tmuxController] unlinkWindowWithId:windowId];
    [self reloadWindows];
}

- (void)addWindow {
    NSString *lastName = [[windowsTable_ names] lastObject];
    if (lastName) {
        TmuxController *tmuxController = self.tmuxController;
        [tmuxController newWindowInSessionNumber:[sessionsTable_ selectedSessionNumber]
                                           scope:[iTermVariableScope globalsScope]
                                initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:tmuxController.sharedProfile
                                                                                         objectType:iTermWindowObject]];
    }
}

- (void)showWindowsWithIds:(NSArray *)windowIds inTabs:(BOOL)inTabs {
    if (inTabs) {
        for (NSNumber *wid in windowIds) {
            [[self tmuxController] openWindowWithId:[wid intValue]
                                         affinities:windowIds
                                        intentional:YES
                                            profile:self.tmuxController.sharedProfile];
        }
    } else {
        for (NSNumber *wid in windowIds) {
            [[self tmuxController] openWindowWithId:[wid intValue]
                                        intentional:YES
                                            profile:self.tmuxController.sharedProfile];
        }
    }
    [[self tmuxController] saveHiddenWindows];
}

- (void)hideWindowWithId:(int)windowId
{
    [[self tmuxController] hideWindow:windowId];
    [windowsTable_ updateEnabledStateOfButtons];
}

- (BOOL)haveSelectedSession {
    return [sessionsTable_ selectedSessionNumber] != nil;
}

- (BOOL)currentSessionSelected {
    return [[sessionsTable_ selectedSessionNumber] isEqual:@([[self tmuxController] sessionId])];
}

- (BOOL)haveOpenWindowWithId:(int)windowId {
    return [[self tmuxController] window:windowId] != nil;
}

- (void)tmuxWindowsTableDidSelectWindowWithId:(int)windowId {
    PTYTab *tab = [[self tmuxController] window:windowId];
    [tab.activeSession reveal];
}

- (NSNumber *)selectedSessionNumber {
    return [sessionsTable_ selectedSessionNumber];
}

#pragma mark - Private

- (void)tmuxControllerDetached:(NSNotification *)notification {
    [sessionsTable_ setSessionObjects:@[]];
}

- (void)tmuxControllerSessionsDidChange:(NSNotification *)notification {
    [sessionsTable_ setSessionObjects:[[self tmuxController] sessionObjects]];
}

- (void)tmuxControllerWindowsDidChange:(NSNotification *)notification {
    if ([[self window] isVisible]) {
        [self reloadWindows];
    }
}

- (void)tmuxControllerAttachedSessionChanged:(NSNotification *)notification {
    if ([[self window] isVisible]) {
        [sessionsTable_ selectSessionNumber:[[self tmuxController] sessionId]];
        [windowsTable_ updateEnabledStateOfButtons];
    }
}

- (void)tmuxControllerWindowOpenedOrClosed:(NSNotification *)notification {
    if ([[self window] isVisible]) {
        [windowsTable_ updateEnabledStateOfButtons];
        [windowsTable_ reloadData];
    }
}

- (void)tmuxControllerWindowWasRenamed:(NSNotification *)notification {
    if ([[self window] isVisible]) {
        NSArray *objects = [notification object];
        int wid = [[objects objectAtIndex:0] intValue];
        NSString *newName = [objects objectAtIndex:1];
        [windowsTable_ setNameOfWindowWithId:wid to:newName];
    }
}

- (void)tmuxControllerSessionWasRenamed:(NSNotification *)notification {
    // This is a bit of extra work but the sessions table wasn't built knowing about session IDs.
    [[self tmuxController] listSessions];
}

- (void)tmuxControllerRegistryDidChange:(NSNotification *)notification {
    NSString *previousSelection = [[self currentClient] copy];
    [connectionsButton_.menu cancelTracking];
    [connectionsButton_.cell dismissPopUp];
    [connectionsButton_ removeAllItems];
    [connectionsButton_ addItemsWithTitles:[[TmuxControllerRegistry sharedInstance] clientNames]];
    if (previousSelection && [connectionsButton_ itemWithTitle:previousSelection]) {
        [connectionsButton_ selectItemWithTitle:previousSelection];
    } else if ([connectionsButton_ numberOfItems] > 0) {
        [connectionsButton_ selectItemAtIndex:0];
    }
    [self connectionSelectionDidChange:nil];
}

- (TmuxController *)tmuxController {
    return [[TmuxControllerRegistry sharedInstance] controllerForClient:[self currentClient]];  // TODO: track the current client when multiples are supported
}

- (NSString *)currentClient {
    return [[connectionsButton_ selectedItem] title];
}


- (IBAction)connectionSelectionDidChange:(id)sender {
    [sessionsTable_ setSessionObjects:[[self tmuxController] sessionObjects]];
    [self reloadWindows];
}

@end

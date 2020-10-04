//
//  TmuxDashboardController.m
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxDashboardController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermInitialDirectory.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermPreferences.h"
#import "iTermUserDefaults.h"
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
    IBOutlet NSButton *_openDashboardIfHiddenWindows;
}

+ (TmuxDashboardController *)sharedInstance {
    static TmuxDashboardController *instance;
    if (!instance) {
        instance = [[TmuxDashboardController alloc] init];
    }
    return instance;
}

- (instancetype)init {
    return [super initWithWindowNibName:@"TmuxDashboard"];
}

- (void)windowDidLoad {
    DLog(@"dashboard: windowDidLoad with tmux controller %@", self.tmuxController);
    [super windowDidLoad];

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
                                             selector:@selector(tmuxControllerSessionsWillChange:)
                                                 name:kTmuxControllerSessionsWillChange
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

    [self tmuxControllerRegistryDidChange:nil];
    if ([connectionsButton_ numberOfItems] > 0) {
        [connectionsButton_ selectItemAtIndex:0];
    }
    [sessionsTable_ setDelegate:self];
    [windowsTable_ setDelegate:self];
    setting_.integerValue = [iTermPreferences intForKey:kPreferenceKeyTmuxDashboardLimit];
    stepper_.integerValue = setting_.integerValue;
    _openDashboardIfHiddenWindows.state = iTermUserDefaults.openTmuxDashboardIfHiddenWindows ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)didAttachWithHiddenWindows:(BOOL)anyHidden
                    tooManyWindows:(BOOL)tooMany {
    DLog(@"anyHidden=%@ tooMany=%@", @(anyHidden), @(tooMany));
    if (anyHidden && iTermUserDefaults.openTmuxDashboardIfHiddenWindows) {
        [self show];
        return;
    }
    if (tooMany) {
        [self show];
        return;
    }
}

- (void)show {
    DLog(@"Show");
    [[TmuxDashboardController sharedInstance] showWindow:nil];
    [[[TmuxDashboardController sharedInstance] window] makeKeyAndOrderFront:nil];
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

- (IBAction)toggleOpenDashboardIfHiddenWindows:(id)sender {
    iTermUserDefaults.openTmuxDashboardIfHiddenWindows = _openDashboardIfHiddenWindows.state == NSControlStateValueOn;
    _openDashboardIfHiddenWindows.state = iTermUserDefaults.openTmuxDashboardIfHiddenWindows ? NSControlStateValueOn : NSControlStateValueOff;
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
    DLog(@"dashboard: setWindows:%@ forSession:%@", doc, sessionNumber);
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

- (void)tmuxControllerSessionsWillChange:(NSNotification *)notification {
    [sessionsTable_ endEditing];
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
    DLog(@"dashboard: tmuxControllerRegistryDidChange");
    NSString *previousSelection = [[self currentClient] copy];
    [connectionsButton_.menu cancelTracking];
    [connectionsButton_.cell dismissPopUp];
    [connectionsButton_ removeAllItems];

    // Get a load of this! Nonbreaking spaces are converted to regular spaces in menu item
    // titles, which means they do not round trip. So we use the identifier to find the connection
    // by name.
    [[[TmuxControllerRegistry sharedInstance] clientNames] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:obj action:nil keyEquivalent:@""];
        item.identifier = obj;
        [connectionsButton_.menu addItem:item];
    }];
    if (previousSelection && [self haveConnection:previousSelection]) {
        [self selectConnection:previousSelection];
    } else if ([connectionsButton_ numberOfItems] > 0) {
        [connectionsButton_ selectItemAtIndex:0];
    }
    [self connectionSelectionDidChange:nil];
}

- (BOOL)haveConnection:(NSString *)identifier {
    for (NSMenuItem *item in connectionsButton_.menu.itemArray) {
        if ([item.identifier isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

- (void)selectConnection:(NSString *)identifier {
    for (NSMenuItem *item in connectionsButton_.menu.itemArray) {
        if ([item.identifier isEqualToString:identifier]) {
            [connectionsButton_ selectItem:item];
            return;
        }
    }
}

- (TmuxController *)tmuxController {
    DLog(@"dashboard: Looking for tmux controller for current client, %@", self.currentClient);
    DLog(@"dashboard: Registry: %@", [TmuxControllerRegistry sharedInstance]);
    return [[TmuxControllerRegistry sharedInstance] controllerForClient:[self currentClient]];  // TODO: track the current client when multiples are supported
}

- (NSString *)currentClient {
    return [[connectionsButton_ selectedItem] identifier];
}


- (IBAction)connectionSelectionDidChange:(id)sender {
    DLog(@"dashboard: connectionSelectionDidChange controller=%@", [self tmuxController]);
    [sessionsTable_ setSessionObjects:[[self tmuxController] sessionObjects]];
    [self reloadWindows];
}

@end

//
//  ProfilesAdvancedPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesAdvancedPreferencesViewController.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "iTermSemanticHistoryPrefsController.h"
#import "iTermShellHistoryController.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PointerPreferencesViewController.h"
#import "PreferencePanel.h"
#import "SmartSelectionController.h"
#import "TriggerController.h"

@interface ProfilesAdvancedPreferencesViewController () <
    NSTableViewDataSource,
    NSTableViewDelegate,
    SmartSelectionDelegate,
    TriggerDelegate,
    iTermSemanticHistoryPrefsControllerDelegate>
@end

@implementation ProfilesAdvancedPreferencesViewController {
    IBOutlet TriggerController *_triggerWindowController;
    IBOutlet SmartSelectionController *_smartSelectionWindowController;
    IBOutlet iTermSemanticHistoryPrefsController *_semanticHistoryPrefController;
    IBOutlet NSTableView *_boundHostsTableView;

    IBOutlet NSControl *_boundHostTitle;
    IBOutlet NSControl *_boundHostLabel;
    IBOutlet NSControl *_addBoundHost;
    IBOutlet NSControl *_removeBoundHost;
    IBOutlet NSControl *_boundHostShellIntegrationWarning;
    IBOutlet NSControl *_boundHostHelp;

    IBOutlet iTermPopoverHelpButton *_triggersHelp;

    IBOutlet NSButton *_triggersButton;
    IBOutlet NSButton *_enableTriggersInInteractiveApps;
    IBOutlet NSButton *_smartSelectionButton;
    IBOutlet NSView *_automaticProfileSwitchingView;
    IBOutlet NSView *_semanticHistoryAction;

    IBOutlet NSTextField *_disabledTip;
    IBOutlet NSButton *_enableAPSLogging;

    IBOutlet NSTokenField *_snippetsFilter;
    IBOutlet NSTextField *_snippetsFilterLabel;

    BOOL _addingBoundHost;  // Don't remove empty-named hosts while this is set
    BOOL _triggersModelHasChanged;
}

- (void)dealloc {
    _boundHostsTableView.delegate = nil;
    _boundHostsTableView.dataSource = nil;
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfiles:)
                                                 name:kReloadAllProfiles
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateSemanticHistoryDisabledLabel:)
                                                 name:kPointerPrefsSemanticHistoryEnabledChangedNotification
                                               object:nil];

    [self defineControl:_enableTriggersInInteractiveApps
                    key:KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_snippetsFilter
                    key:KEY_SNIPPETS_FILTER
            relatedView:_snippetsFilterLabel
                   type:kPreferenceInfoTypeTokenField];

    [self addViewToSearchIndex:_triggersButton
                   displayName:@"Triggers"
                       phrases:@[ @"regular expression", @"regex" ]
                           key:nil];
    [self addViewToSearchIndex:_smartSelectionButton
                   displayName:@"Smart selection"
                       phrases:@[ @"regular expression", @"regex" ]
                           key:nil];
    [self addViewToSearchIndex:_automaticProfileSwitchingView
                   displayName:@"Automatic profile switching rules"
                       phrases:@[]
                           key:nil];
    [self addViewToSearchIndex:_semanticHistoryAction
                   displayName:@"Semantic history"
                       phrases:@[ @"cmd click", @"open file", @"open url" ]
                           key:nil];
    _enableAPSLogging.state = iTermUserDefaults.enableAutomaticProfileSwitchingLogging ? NSControlStateValueOn : NSControlStateValueOff;
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_TRIGGERS,
                       KEY_TRIGGERS_USE_INTERPOLATED_STRINGS,
                       KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS,
                       KEY_SMART_SELECTION_RULES,
                       KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS,
                       KEY_SEMANTIC_HISTORY,
                       KEY_BOUND_HOSTS ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    NSArray *viewsToDisable = @[ _boundHostTitle,
                                 _boundHostLabel,
                                 _boundHostsTableView,
                                 _addBoundHost,
                                 _removeBoundHost,
                                 _boundHostShellIntegrationWarning,
                                 _boundHostHelp ];
    for (NSControl *control in viewsToDisable) {
        if ([control isKindOfClass:[NSTextField class]]) {
            [(NSTextField *)control setLabelEnabled:NO];
        } else {
            [control setEnabled:NO];
        }
    }
}

- (void)willReloadProfile {
    [self removeNamelessHosts];
    [self closeTriggersSheet];
}

- (void)reloadProfile {
    [super reloadProfile];
    NSString *selectedGuid = [self.delegate profilePreferencesCurrentProfile][KEY_GUID];
    _triggerWindowController.guid = selectedGuid;
    _smartSelectionWindowController.guid = selectedGuid;
    _semanticHistoryPrefController.guid = selectedGuid;
    [_boundHostsTableView reloadData];
    if (self.profileType == ProfileTypeBrowser) {
        _triggersHelp.helpText = @"Triggers are actions you configure to run when certain URLs are visited or text on a web page is found.";
    } else {
        _triggersHelp.helpText = @"Triggers watch for text matching a regular expression to arrive in a terminal session and then perform an action in response.";
    }
}

- (void)viewWillAppear {
    [self updateSemanticHistoryDisabledLabel:nil];
    [super viewWillAppear];
}

#pragma mark - Triggers

- (IBAction)editTriggers:(id)sender {
    _triggerWindowController.browserMode = (self.profileType == ProfileTypeBrowser);
    [_triggerWindowController windowWillOpen];
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_triggerWindowController.window completionHandler:^(NSModalResponse returnCode) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_triggerWindowController.window close];
        }
    }];
}

- (IBAction)closeTriggersSheet {
    if (_triggersModelHasChanged) {
        ProfileModel *model = [self.delegate profilePreferencesCurrentModel];
        [iTermProfilePreferences commitModel:model];
        _triggersModelHasChanged = NO;
    }
    [[_triggerWindowController.window undoManager] removeAllActionsWithTarget:self];
    [self.view.window endSheet:_triggerWindowController.window];
}

- (IBAction)toggleEnableTriggersInInteractiveApps:(id)sender {
    [self setBool:![self boolForKey:KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS] forKey:KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS];
}

#pragma mark - TriggerDelegate

- (void)triggersCloseSheet {
    [self closeTriggersSheet];
}

- (void)triggerChanged:(TriggerController *)triggerController newValue:(NSArray *)value {
    [[triggerController.window undoManager] registerUndoWithTarget:self
                                                          selector:@selector(setTriggersValue:)
                                                            object:[self objectForKey:KEY_TRIGGERS]];
    [[triggerController.window undoManager] setActionName:@"Edit Triggers"];

    // No side effects because we don't want the tableview to get reloaded. We'll save when the
    // panel is closed. by setting the _triggersModelHasChanged flag.
    [self setObject:value forKey:KEY_TRIGGERS withSideEffects:NO];
    _triggersModelHasChanged = YES;
}

- (void)setTriggersValue:(NSArray *)value {
    [self setObject:value forKey:KEY_TRIGGERS];
    [_triggerWindowController profileDidChange];
}

- (void)triggerSetUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    [self setBool:useInterpolatedStrings forKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS];
}

#pragma mark - SmartSelectionDelegate

- (void)smartSelectionChanged:(SmartSelectionController *)controller {
    // Note: This is necessary for setUseInterpolatedStrings to work right. If you remove this
    // ensure it is saved properly.
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

#pragma mark - Smart selection

- (IBAction)editSmartSelection:(id)sender {
    [_smartSelectionWindowController window];
    [_smartSelectionWindowController windowWillOpen];
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_smartSelectionWindowController.window completionHandler:^(NSModalResponse returnCode) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_smartSelectionWindowController.window close];
        }
    }];
}

- (IBAction)closeSmartSelectionSheet:(id)sender {
    [self.view.window endSheet:_smartSelectionWindowController.window];
}

#pragma mark - Semantic History

- (void)semanticHistoryPrefsControllerSettingChanged:(iTermSemanticHistoryPrefsController *)controller {
    [self setObject:[controller prefs] forKey:KEY_SEMANTIC_HISTORY];
}

#pragma mark - Bound Hosts

- (IBAction)addBoundHost:(id)sender {
    [_boundHostsTableView reloadData];
    [self removeNamelessHosts];

    NSMutableArray *temp = [[self boundHosts] mutableCopy];
    [temp addObject:@""];
    [self setObject:temp forKey:KEY_BOUND_HOSTS];
    [_boundHostsTableView reloadData];
    _addingBoundHost = YES;
    [_boundHostsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_boundHostsTableView.numberOfRows - 1]
                      byExtendingSelection:NO];
    _addingBoundHost = NO;
    [_boundHostsTableView editColumn:0
                                 row:[self numberOfRowsInTableView:_boundHostsTableView] - 1
                           withEvent:nil
                              select:YES];
}

- (IBAction)removeBoundHost:(id)sender {
    [self removeBoundHostOnRow:[_boundHostsTableView selectedRow]];
}

- (NSArray *)boundHosts {
    return (NSArray *)[self objectForKey:KEY_BOUND_HOSTS] ?: @[];
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/automatic-profile-switching.html"]];
}

- (void)removeBoundHostOnRow:(NSInteger)rowIndex {
    // Causes editing to end. If you try to remove a cell that is being edited,
    // it tries to dereference the deleted cell. There doesn't seem to be an
    // API that explicitly ends editing.
    [_boundHostsTableView reloadData];

    NSMutableArray *temp = [[self boundHosts] mutableCopy];
    if (rowIndex >= 0 && rowIndex < temp.count) {
        [temp removeObjectAtIndex:rowIndex];
        [self setObject:temp forKey:KEY_BOUND_HOSTS];
        [_boundHostsTableView reloadData];
    }
}

- (void)removeNamelessHosts {
    // Remove empty hosts
    BOOL done = NO;
    while (!done) {
        done = YES;
        NSArray *hosts = [self boundHosts];
        for (NSInteger i = 0; i < hosts.count; i++) {
            if (![hosts[i] length]) {
                [self removeBoundHostOnRow:i];
                done = NO;
                break;
            }
        }
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [[self boundHosts] count];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    if (rowIndex < 0 || rowIndex >= self.boundHosts.count) {
        return nil;
    }
    return [[self boundHosts] objectAtIndex:rowIndex];
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (![anObject length] || [[self boundHosts] containsObject:anObject]) {
        DLog(@"Beep: Empty APS rule not allwoed");
        NSBeep();
        [self removeBoundHostOnRow:rowIndex];
        return;
    }
    NSArray *hosts = [self boundHosts];
    if (!hosts) {
        hosts = @[];
    }
    NSMutableArray *temp = [hosts mutableCopy];
    temp[rowIndex] = anObject;
    [self setObject:temp forKey:KEY_BOUND_HOSTS];

    Profile *dupProfile = nil;
    NSArray *boundHosts = nil;
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        if (profile == [self.delegate profilePreferencesCurrentProfile]) {
            continue;
        }
        boundHosts = profile[KEY_BOUND_HOSTS];
        if ([boundHosts containsObject:anObject]) {
            dupProfile = profile;
            break;
        }
    }
    if (dupProfile) {
        NSString *theTitle;
        theTitle = [NSString stringWithFormat:@"The profile “%@” is already bound to hostname “%@”.",
                    dupProfile[KEY_NAME], anObject];
        NSString *removeFromOtherAction = [NSString stringWithFormat:@"Remove from “%@”", dupProfile[KEY_NAME]];
        switch ([iTermWarning showWarningWithTitle:theTitle
                                           actions:@[ removeFromOtherAction,
                                                      @"Remove from This Profile" ]
                                        identifier:nil
                                       silenceable:kiTermWarningTypePersistent
                                            window:self.view.window]) {
            case kiTermWarningSelection0:
                temp = [boundHosts mutableCopy];
                [temp removeObject:anObject];
                [iTermProfilePreferences setObject:temp
                                            forKey:KEY_BOUND_HOSTS
                                         inProfile:dupProfile
                                             model:[ProfileModel sharedInstance]];
                break;

            case kiTermWarningSelection1:
                [self removeBoundHostOnRow:rowIndex];
                break;

            default:
                break;
        }
    }
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    return YES;
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
                       row:(NSInteger)row {
    NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"hostname"];
    [cell setPlaceholderString:@"Enter a rule…"];
    [cell setEditable:YES];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_removeBoundHost setEnabled:[_boundHostsTableView numberOfSelectedRows] > 0];

    if (!_addingBoundHost) {
        [self removeNamelessHosts];
    }
}

#pragma mark - Notifications

- (void)reloadProfiles:(NSNotification *)notification {
    [_boundHostsTableView reloadData];
}

- (void)updateSemanticHistoryDisabledLabel:(NSNotification *)notification {
    _disabledTip.hidden = [iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs];
    _semanticHistoryPrefController.enabled = _disabledTip.hidden;
}

#pragma mark - Actions

- (IBAction)didToggleAutomaticProfileSwitchingDebugLogging:(id)sender {
    iTermUserDefaults.enableAutomaticProfileSwitchingLogging = (_enableAPSLogging.state == NSControlStateValueOn);
}

@end

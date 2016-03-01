//
//  ProfilesAdvancedPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesAdvancedPreferencesViewController.h"

#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "iTermSemanticHistoryPrefsController.h"
#import "iTermShellHistoryController.h"
#import "iTermWarning.h"
#import "NSTextField+iTerm.h"
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
    IBOutlet NSButton *_removeHost;
    IBOutlet NSTableView *_boundHostsTableView;

    IBOutlet NSControl *_boundHostTitle;
    IBOutlet NSControl *_boundHostLabel;
    IBOutlet NSControl *_addBoundHost;
    IBOutlet NSControl *_removeBoundHost;
    IBOutlet NSControl *_boundHostShellIntegrationWarning;
    IBOutlet NSControl *_boundHostHelp;

    IBOutlet NSTextField *_disabledTip;

    BOOL _addingBoundHost;  // Don't remove empty-named hosts while this is set
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
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_TRIGGERS,
                       KEY_SMART_SELECTION_RULES,
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
    [self closeTriggersSheet:nil];
}

- (void)reloadProfile {
    [super reloadProfile];
    NSString *selectedGuid = [self.delegate profilePreferencesCurrentProfile][KEY_GUID];
    _triggerWindowController.guid = selectedGuid;
    _smartSelectionWindowController.guid = selectedGuid;
    _semanticHistoryPrefController.guid = selectedGuid;
    [_boundHostsTableView reloadData];
}

- (void)viewWillAppear {
    [self updateSemanticHistoryDisabledLabel:nil];
    [super viewWillAppear];
}

#pragma mark - Triggers

- (IBAction)editTriggers:(id)sender {
    [_triggerWindowController windowWillOpen];
    [NSApp beginSheet:[_triggerWindowController window]
       modalForWindow:[self.view window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeTriggersSheet:(id)sender {
    [[_triggerWindowController.window undoManager] removeAllActionsWithTarget:self];
    [NSApp endSheet:[_triggerWindowController window]];
}

#pragma mark - TriggerDelegate

- (void)triggerChanged:(TriggerController *)triggerController newValue:(NSArray *)value {
    [[triggerController.window undoManager] registerUndoWithTarget:self
                                                          selector:@selector(setTriggersValue:)
                                                            object:[self objectForKey:KEY_TRIGGERS]];
    [[triggerController.window undoManager] setActionName:@"Edit Triggers"];
    [self setObject:value forKey:KEY_TRIGGERS];
}

- (void)setTriggersValue:(NSArray *)value {
    [self setObject:value forKey:KEY_TRIGGERS];
    [_triggerWindowController.tableView reloadData];
}

#pragma mark - SmartSelectionDelegate

- (void)smartSelectionChanged:(SmartSelectionController *)controller {
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

#pragma mark - Modal sheets

- (void)advancedTabCloseSheet:(NSWindow *)sheet
                   returnCode:(int)returnCode
                  contextInfo:(void *)contextInfo {
    [sheet close];
}

#pragma mark - Smart selection

- (IBAction)editSmartSelection:(id)sender {
    [_smartSelectionWindowController window];
    [_smartSelectionWindowController windowWillOpen];
    [NSApp beginSheet:[_smartSelectionWindowController window]
       modalForWindow:[self.view window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeSmartSelectionSheet:(id)sender {
    [NSApp endSheet:[_smartSelectionWindowController window]];
}

#pragma mark - Semantic History

- (void)semanticHistoryPrefsControllerSettingChanged:(iTermSemanticHistoryPrefsController *)controller {
    [self setObject:[controller prefs] forKey:KEY_SEMANTIC_HISTORY];
}

#pragma mark - Bound Hosts

- (IBAction)addBoundHost:(id)sender {
    [_boundHostsTableView reloadData];
    [self removeNamelessHosts];

    NSMutableArray *temp = [[[self boundHosts] mutableCopy] autorelease];
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
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/automatic-profile-switching.html"]];
}

- (void)removeBoundHostOnRow:(NSInteger)rowIndex {
    // Causes editing to end. If you try to remove a cell that is being edited,
    // it tries to dereference the deleted cell. There doesn't seem to be an
    // API that explicitly ends editing.
    [_boundHostsTableView reloadData];
    
    NSMutableArray *temp = [[[self boundHosts] mutableCopy] autorelease];
    [temp removeObjectAtIndex:rowIndex];
    [self setObject:temp forKey:KEY_BOUND_HOSTS];
    [_boundHostsTableView reloadData];
}

- (void)removeNamelessHosts {
    // Remove empty hosts
    NSArray *hosts = [self boundHosts];
    for (NSInteger i = hosts.count - 1; i >= 0; i--) {
        if (![hosts[i] length]) {
            [self removeBoundHostOnRow:i];
            hosts = [self boundHosts];
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
    return [[self boundHosts] objectAtIndex:rowIndex];
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    if (![anObject length] || [[self boundHosts] containsObject:anObject]) {
        NSBeep();
        [self removeBoundHostOnRow:rowIndex];
        return;
    }
    NSArray *hosts = [self boundHosts];
    if (!hosts) {
        hosts = @[];
    }
    NSMutableArray *temp = [[hosts mutableCopy] autorelease];
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
                                       silenceable:kiTermWarningTypePersistent]) {
            case kiTermWarningSelection0:
                temp = [[boundHosts mutableCopy] autorelease];
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
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"hostname"] autorelease];
    [cell setPlaceholderString:@"Hostname, username@hostname, or username@"];
    [cell setEditable:YES];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [_removeHost setEnabled:[_boundHostsTableView numberOfSelectedRows] > 0];

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

@end

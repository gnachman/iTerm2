//
//  ProfilesSessionViewController.m
//  iTerm
//
//  Created by George Nachman on 4/18/14.
//
//

#import "ProfilesSessionPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"

@interface ProfilesSessionPreferencesViewController () <NSTableViewDelegate, NSTableViewDataSource>
@end

@implementation ProfilesSessionPreferencesViewController {
    IBOutlet NSButton *_closeSessionsOnEnd;
    IBOutlet NSMatrix *_promptBeforeClosing;
    IBOutlet NSTableView *_jobsTable;
    IBOutlet NSButton *_removeJob;
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfiles)
                                                 name:kReloadAllProfiles
                                               object:nil];
    [self defineControl:_closeSessionsOnEnd
                    key:KEY_CLOSE_SESSIONS_ON_END
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_promptBeforeClosing
                    key:KEY_PROMPT_CLOSE
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self promptBeforeClosingDidChange]; }
                 update:^BOOL { [self updatePromptBeforeClosing]; return YES; }];
    [self updateRemoveJobButtonEnabled];
}

- (void)reloadProfile {
    [super reloadProfile];
    [_jobsTable reloadData];
    [self updateRemoveJobButtonEnabled];
}

- (void)copyOwnedValuesToDict:(NSMutableDictionary *)dict {
    [super copyOwnedValuesToDict:dict];
    NSArray *value = (NSArray *)[self objectForKey:KEY_JOBS];
    if (value) {
        dict[KEY_JOBS] = value;
    } else {
        [dict removeObjectForKey:KEY_JOBS];
    }
}

#pragma mark - Prompt before closing

- (void)promptBeforeClosingDidChange {
    [self setInt:[_promptBeforeClosing selectedTag] forKey:KEY_PROMPT_CLOSE];
}

- (void)updatePromptBeforeClosing {
    [_promptBeforeClosing selectCellWithTag:[self intForKey:KEY_PROMPT_CLOSE]];
}

#pragma mark - Jobs

- (NSArray *)jobs {
    return (NSArray *)[self objectForKey:KEY_JOBS];
}

- (IBAction)addJob:(id)sender {
    NSArray *jobNames = [self jobs];
    NSMutableArray *augmented;
    if (jobNames) {
        augmented = [NSMutableArray arrayWithArray:jobNames];
        [augmented addObject:@"Job Name"];
    } else {
        augmented = [NSMutableArray arrayWithObject:@"Job Name"];
    }
    [self setObject:augmented forKey:KEY_JOBS];
    [_jobsTable reloadData];
    [_jobsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[augmented count] - 1]
            byExtendingSelection:NO];
    [_jobsTable editColumn:0
                       row:[self numberOfRowsInTableView:_jobsTable] - 1
                 withEvent:nil
                    select:YES];
    [self updateRemoveJobButtonEnabled];
    [self postRefreshNotification];
}

- (IBAction)removeJob:(id)sender {
    // Causes editing to end. If you try to remove a cell that is being edited,
    // it tries to dereference the deleted cell. There doesn't seem to be an
    // API that explicitly ends editing.
    [_jobsTable reloadData];

    NSInteger selectedIndex = [_jobsTable selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    NSArray *jobNames = [self jobs];
    NSMutableArray *mod = [NSMutableArray arrayWithArray:jobNames];
    [mod removeObjectAtIndex:selectedIndex];

    [self setObject:mod forKey:KEY_JOBS];
    [_jobsTable reloadData];
    [self updateRemoveJobButtonEnabled];
    [self postRefreshNotification];
}

- (void)updateRemoveJobButtonEnabled {
    _removeJob.enabled = ([_jobsTable selectedRow] != -1);
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView: (NSTableView *)aTableView {
    return [[self jobs] count];
}


- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    NSMutableArray *jobs = [NSMutableArray arrayWithArray:[self jobs]];
    [jobs replaceObjectAtIndex:rowIndex withObject:anObject];
    [self setObject:jobs forKey:KEY_JOBS];
    [self postRefreshNotification];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                row:(NSInteger)rowIndex {
    return [self jobs][rowIndex];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updateRemoveJobButtonEnabled];
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [_jobsTable reloadData];
}

@end

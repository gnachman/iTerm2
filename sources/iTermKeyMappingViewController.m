//
//  iTermKeyMappingViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermKeyMappingViewController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermEditKeyActionWindowController.h"
#import "PreferencePanel.h"

@interface iTermKeyMappingViewController ()

@end

@implementation iTermKeyMappingViewController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_keyCombinationColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSButton *_removeMappingButton;
    IBOutlet NSPopUpButton *_presetsPopup;
}

- (instancetype)init {
    self = [super initWithNibName:@"iTermKeyMapping" bundle:nil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyBindingsChanged)
                                                     name:kKeyBindingsChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    [_placeholderView release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)keyBindingsChanged {
    [_tableView reloadData];
}

- (void)setPlaceholderView:(NSView *)placeholderView {
    _placeholderView = [placeholderView retain];
    [self.placeholderView addSubview:self.view];
    self.view.frame = self.placeholderView.bounds;
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    placeholderView.autoresizesSubviews = YES;

    [_tableView setDoubleAction:@selector(doubleClick:)];
    [_tableView setTarget:self];
    NSArray* presetArray = [_delegate keyMappingPresetNames:self];
    if (presetArray) {
        [_presetsPopup addItemsWithTitles:presetArray];
    } else {
        [_presetsPopup setEnabled:NO];
        [_presetsPopup setFont:[NSFont boldSystemFontOfSize:12]];
        [_presetsPopup setStringValue:@"Error"];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    return [dict count];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                          row:(NSInteger)rowIndex {
    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    NSArray *sortedKeys = [_delegate keyMappingSortedKeys:self];
    NSString *keyCombination = sortedKeys[rowIndex];

    if (aTableColumn == _keyCombinationColumn) {
        return [iTermKeyBindingMgr formatKeyCombination:keyCombination];
    } else if (aTableColumn == _actionColumn) {
        return [iTermKeyBindingMgr formatAction:dict[keyCombination]];
    } else {
        return nil;
    }
}

#pragma mark - Modal Sheets

- (void)presentEditActionSheet:(iTermEditKeyActionWindowController *)editActionWindowController {
    [editActionWindowController retain];
    [NSApp beginSheet:editActionWindowController.window
       modalForWindow:self.view.window
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:editActionWindowController];
}

- (void)genericCloseSheet:(NSWindow *)sheet
               returnCode:(int)returnCode
              contextInfo:(iTermEditKeyActionWindowController *)editActionWindowController {
    if (editActionWindowController.ok) {
        [_delegate keyMapping:self
            didChangeKeyCombo:editActionWindowController.currentKeyCombination
                      atIndex:[_tableView selectedRow]
                     toAction:editActionWindowController.action
                    parameter:editActionWindowController.parameterValue
                   isAddition:editActionWindowController.isNewMapping];
    }
    [editActionWindowController close];
    [editActionWindowController release];
    [_tableView reloadData];
    [sheet close];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    int rowIndex = [_tableView selectedRow];
    if (rowIndex >= 0) {
        [_removeMappingButton setEnabled:YES];
    } else {
        [_removeMappingButton setEnabled:NO];
    }
}

#pragma mark - Actions

- (IBAction)addNewMapping:(id)sender
{
    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController = [[[iTermEditKeyActionWindowController alloc] init] autorelease];
    editActionWindowController.isNewMapping = YES;
    editActionWindowController.action = KEY_ACTION_IGNORE;
    [self presentEditActionSheet:editActionWindowController];
}

- (IBAction)removeMapping:(id)sender
{
    NSInteger row = [_tableView selectedRow];
    if (row < 0) {
        NSBeep();
        return;
    }
    NSArray *sortedKeys = [_delegate keyMappingSortedKeys:self];
    [_delegate keyMapping:self removeKeyCombo:sortedKeys[row]];
    [_tableView reloadData];
}

- (void)doubleClick:(id)sender {
    int rowIndex = [_tableView selectedRow];
    if (rowIndex < 0) {
        [self addNewMapping:sender];
        return;
    }

    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    NSArray *sortedKeys = [_delegate keyMappingSortedKeys:self];
    NSString *keyCombination = sortedKeys[rowIndex];

    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController = [[[iTermEditKeyActionWindowController alloc] init] autorelease];
    editActionWindowController.isNewMapping = NO;
    editActionWindowController.currentKeyCombination = keyCombination;
    editActionWindowController.parameterValue = dict[keyCombination][@"Text"];  // TODO
    editActionWindowController.action = [dict[keyCombination][@"Action"] intValue];  // TODO
    [self presentEditActionSheet:editActionWindowController];
}

- (IBAction)loadPresets:(id)sender {
    [_delegate keyMapping:self loadPresetsNamed:[[sender selectedItem] title]];
    [_tableView reloadData];
}

@end

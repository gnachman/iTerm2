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

static NSString *const iTermTouchBarIDPrefix = @"touchbar:";

@implementation iTermKeyMappingViewController {
    IBOutlet NSButton *_addTouchBarItem;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_keyCombinationColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSButton *_removeMappingButton;
    IBOutlet NSPopUpButton *_presetsPopup;
    iTermEditKeyActionWindowController *_editActionWindowController;
}

- (instancetype)init {
    self = [super initWithNibName:@"iTermKeyMapping" bundle:[NSBundle bundleForClass:self.class]];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyBindingsChanged {
    [_tableView reloadData];
}

- (void)setPlaceholderView:(NSView *)placeholderView {
    _placeholderView = placeholderView;
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

- (void)hideAddTouchBarItem {
    _addTouchBarItem.hidden = YES;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    if (_addTouchBarItem.hidden) {
        return [dict count];
    } else {
        return [dict count] + [[_delegate keyMappingTouchBarItems] count];
    }
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                          row:(NSInteger)rowIndex {
    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    if (rowIndex < dict.count) {
        NSArray *sortedKeys = [_delegate keyMappingSortedKeys:self];
        NSString *keyCombination = sortedKeys[rowIndex];

        if (aTableColumn == _keyCombinationColumn) {
            return [iTermKeyBindingMgr formatKeyCombination:keyCombination];
        } else if (aTableColumn == _actionColumn) {
            return [iTermKeyBindingMgr formatAction:dict[keyCombination]];
        } else {
            return nil;
        }
    } else {
        rowIndex -= dict.count;
        dict = [_delegate keyMappingTouchBarItems];
        NSArray *sortedKeys = [_delegate keyMappingSortedTouchBarKeys:self];
        NSString *key = sortedKeys[rowIndex];

        if (aTableColumn == _keyCombinationColumn) {
            return [iTermKeyBindingMgr touchBarLabelForBinding:dict[key]];
        } else if (aTableColumn == _actionColumn) {
            return [iTermKeyBindingMgr formatAction:dict[key]];
        } else {
            return nil;
        }
    }
}

#pragma mark - Modal Sheets

- (void)presentEditActionSheet:(iTermEditKeyActionWindowController *)editActionWindowController {
    [self.view.window beginSheet:editActionWindowController.window completionHandler:^(NSModalResponse returnCode) {
        [self editActionWindowCompletionHandler:editActionWindowController];
    }];
}

- (void)editActionWindowCompletionHandler:(iTermEditKeyActionWindowController *)editActionWindowController {
    if (editActionWindowController.ok) {
        [_delegate keyMapping:self
                 didChangeKey:editActionWindowController.isTouchBarItem ? editActionWindowController.touchBarItemID : editActionWindowController.currentKeyCombination
               isTouchBarItem:editActionWindowController.isTouchBarItem
                      atIndex:[_tableView selectedRow]
                     toAction:editActionWindowController.action
                    parameter:editActionWindowController.parameterValue
                        label:editActionWindowController.label
                   isAddition:editActionWindowController.isNewMapping];
    }
    [editActionWindowController close];
    [_tableView reloadData];
    [editActionWindowController.window close];
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

- (IBAction)addTouchBarItem:(id)sender {
    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController = [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp];
    editActionWindowController.isNewMapping = YES;
    editActionWindowController.isTouchBarItem = YES;
    editActionWindowController.touchBarItemID = [iTermTouchBarIDPrefix stringByAppendingString:[NSString uuid]];
    editActionWindowController.action = KEY_ACTION_IGNORE;
    [self presentEditActionSheet:editActionWindowController];
}

- (IBAction)addNewMapping:(id)sender {
    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController = [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp];
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
    if (row < sortedKeys.count) {
        [_delegate keyMapping:self removeKey:sortedKeys[row] isTouchBarItem:NO];
    } else {
        row -= sortedKeys.count;
        sortedKeys = [_delegate keyMappingSortedTouchBarKeys:self];
        [_delegate keyMapping:self removeKey:sortedKeys[row] isTouchBarItem:YES];
    }
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
    NSString *selectedKey;
    BOOL isTouchBarItem = NO;
    if (rowIndex < sortedKeys.count) {
        selectedKey = sortedKeys[rowIndex];
    } else {
        isTouchBarItem = YES;
        rowIndex -= sortedKeys.count;
        sortedKeys = [_delegate keyMappingSortedTouchBarKeys:self];
        selectedKey = sortedKeys[rowIndex];
        dict = [_delegate keyMappingTouchBarItems];
    }
    _editActionWindowController = [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp];
    _editActionWindowController.isTouchBarItem = isTouchBarItem;
    if (isTouchBarItem) {
        _editActionWindowController.label = [iTermKeyBindingMgr touchBarLabelForBinding:dict[selectedKey]];
    }
    _editActionWindowController.isNewMapping = NO;
    if (isTouchBarItem) {
        _editActionWindowController.touchBarItemID = selectedKey;
    } else {
        _editActionWindowController.currentKeyCombination = selectedKey;
    }
    _editActionWindowController.parameterValue = dict[selectedKey][@"Text"];
    _editActionWindowController.action = [dict[selectedKey][@"Action"] intValue];
    [self presentEditActionSheet:_editActionWindowController];
}

- (IBAction)loadPresets:(id)sender {
    [_delegate keyMapping:self loadPresetsNamed:[[sender selectedItem] title]];
    [_tableView reloadData];
}

@end

//
//  iTermKeyMappingViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermKeyMappingViewController.h"
#import "DebugLogging.h"
#import "iTermKeyBindingMgr.h"
#import "iTermEditKeyActionWindowController.h"
#import "iTermPreferences.h"
#import "iTermPreferencesBaseViewController.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "PreferencePanel.h"

static NSString *const iTermTouchBarIDPrefix = @"touchbar:";
static NSString *const INTERCHANGE_KEY_MAPPING_DICT = @"Key Mappings";
static NSString *const INTERCHANGE_TOUCH_BAR_ITEMS = @"Touch Bar Items";

@implementation iTermKeyMappingViewController {
    IBOutlet NSButton *_addTouchBarItem;
    IBOutlet NSButton *_hapticFeedbackForEsc;
    IBOutlet NSButton *_soundForEsc;
    IBOutlet NSButton *_visualIndicatorForEsc;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_keyCombinationColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSButton *_removeMappingButton;
    IBOutlet NSPopUpButton *_presetsPopup;
    iTermEditKeyActionWindowController *_editActionWindowController;
    IBOutlet NSButton *_touchBarMitigationsButton;
    IBOutlet NSPanel *_touchBarMitigationsPanel;
    NSOpenPanel *_openPanel;
    NSSavePanel *_savePanel;
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

- (void)awakeFromNib {
    self.hapticFeedbackForEscEnabled = [iTermPreferences boolForKey:kPreferenceKeyEnableHapticFeedbackForEsc];
    self.soundForEscEnabled = [iTermPreferences boolForKey:kPreferenceKeyEnableSoundForEsc];
    self.visualIndicatorForEscEnabled = [iTermPreferences boolForKey:kPreferenceKeyVisualIndicatorForEsc];
}

- (void)setHapticFeedbackForEscEnabled:(BOOL)hapticFeedbackForEscEnabled {
    _hapticFeedbackForEsc.state = hapticFeedbackForEscEnabled ? NSOnState : NSOffState;
    [iTermPreferences setBool:hapticFeedbackForEscEnabled
                       forKey:kPreferenceKeyEnableHapticFeedbackForEsc];
}

- (BOOL)hapticFeedbackForEscEnabled {
    return _hapticFeedbackForEsc.state == NSOnState;
}

- (void)setSoundForEscEnabled:(BOOL)enabled {
    _soundForEsc.state = enabled ? NSOnState : NSOffState;
    [iTermPreferences setBool:enabled
                       forKey:kPreferenceKeyEnableSoundForEsc];
}

- (BOOL)soundForEscEnabled {
    return _soundForEsc.state == NSOnState;
}

- (void)setVisualIndicatorForEscEnabled:(BOOL)enabled {
    _visualIndicatorForEsc.state = enabled ? NSOnState : NSOffState;
    [iTermPreferences setBool:enabled
                       forKey:kPreferenceKeyVisualIndicatorForEsc];
}

- (BOOL)visualIndicatorForEscEnabled {
    return _visualIndicatorForEsc.state == NSOnState;
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
    }
    if (_presetsPopup.menu.itemArray.count) {
        [_presetsPopup.menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *item;
    item = [[NSMenuItem alloc] initWithTitle:@"Import…"
                                      action:@selector(importMenuItem:)
                               keyEquivalent:@""];
    item.target = self;
    [_presetsPopup.menu addItem:item];
    item = [[NSMenuItem alloc] initWithTitle:@"Export…"
                                      action:@selector(exportMenuItem:)
                               keyEquivalent:@""];
    item.target = self;
    [_presetsPopup.menu addItem:item];
}

- (void)hideAddTouchBarItem {
    _addTouchBarItem.hidden = YES;
    _touchBarMitigationsButton.hidden = YES;
}

- (void)addViewsToSearchIndex:(iTermPreferencesBaseViewController *)vc {
    [vc addViewToSearchIndex:_addTouchBarItem
                 displayName:@"Add touch bar item"
                     phrases:@[]
                         key:nil];
    [vc addViewToSearchIndex:_presetsPopup
                 displayName:@"Key binding presets"
                     phrases:@[]
                         key:nil];
    [vc addViewToSearchIndex:_touchBarMitigationsButton
                 displayName:@"Touch bar mitigations"
                     phrases:@[ @"Haptic feedback for esc key",
                                @"Key click sound for esc key",
                                @"Visual indicator for esc key" ]
                         key:_touchBarMitigationsButton.accessibilityIdentifier];
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
                 didChangeKey:editActionWindowController.identifier
               isTouchBarItem:editActionWindowController.mode == iTermEditKeyActionWindowControllerModeTouchBarItem
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
    editActionWindowController.mode = iTermEditKeyActionWindowControllerModeTouchBarItem;
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
    _editActionWindowController.mode = isTouchBarItem ? iTermEditKeyActionWindowControllerModeTouchBarItem : iTermEditKeyActionWindowControllerModeKeyboardShortcut;
    [self presentEditActionSheet:_editActionWindowController];
}

- (IBAction)loadPresets:(id)sender {
    [_delegate keyMapping:self loadPresetsNamed:[[sender selectedItem] title]];
    [_tableView reloadData];
}

- (IBAction)hapticFeedbackToggled:(id)sender {
    [iTermPreferences setBool:_hapticFeedbackForEsc.state == NSOnState
                       forKey:kPreferenceKeyEnableHapticFeedbackForEsc];
}

- (IBAction)soundForEscToggled:(id)sender {
    [iTermPreferences setBool:_soundForEsc.state == NSOnState
                       forKey:kPreferenceKeyEnableSoundForEsc];
}

- (IBAction)visualIndicatorForEscToggled:(id)sender {
    [iTermPreferences setBool:_visualIndicatorForEsc.state == NSOnState
                       forKey:kPreferenceKeyVisualIndicatorForEsc];
}

- (IBAction)showTouchBarMitigationsPanel:(id)sender {
    [self.view.window beginSheet:_touchBarMitigationsPanel completionHandler:nil];
}

- (IBAction)dismissTouchBarMitigations:(id)sender {
    [self.view.window endSheet:_touchBarMitigationsPanel];
}

#pragma mark - Import/Export

- (void)importMenuItem:(id)sender {
    _openPanel = [[NSOpenPanel alloc] init];
    _openPanel.canChooseFiles = YES;
    _openPanel.canChooseDirectories = NO;
    _openPanel.allowsMultipleSelection = NO;
    __weak __typeof(self) weakSelf = self;
    [_openPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [weakSelf importFromOpenPanel];
        }
    }];
}

- (void)importFromOpenPanel {
    NSURL *url = _openPanel.URL;
    _openPanel = nil;
    NSError *error = nil;
    NSString *const content = [NSString stringWithContentsOfURL:url
                                                       encoding:NSUTF8StringEncoding
                                                          error:&error];
    if (!content) {
        XLog(@"%@", error);
        NSBeep();
        return;
    }

    id decoded = [NSJSONSerialization it_objectForJsonString:content error:&error];
    if (!decoded) {
        XLog(@"%@", error);
        NSBeep();
        return;
    }

    NSDictionary *dict = [NSDictionary castFrom:decoded];
    NSDictionary *keymappings = [NSDictionary castFrom:dict[INTERCHANGE_KEY_MAPPING_DICT]];
    for (NSString *key in keymappings) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSDictionary *entry = [NSDictionary castFrom:keymappings[key]];

        NSNumber *action = [NSNumber castFrom:entry[iTermKeyBindingDictionaryKeyAction]];
        if (!action) {
            continue;
        }
        NSString *parameter = [NSString castFrom:entry[iTermKeyBindingDictionaryKeyParameter]];
        [self.delegate keyMapping:self
                     didChangeKey:key
                   isTouchBarItem:NO
                          atIndex:NSNotFound
                         toAction:[action intValue]
                        parameter:parameter
                            label:nil
                       isAddition:YES];
    }

    NSDictionary *touchbarItems = [NSDictionary castFrom:dict[INTERCHANGE_TOUCH_BAR_ITEMS]];
    for (id key in touchbarItems) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSDictionary *entry = [NSDictionary castFrom:touchbarItems[key]];
        if (!entry) {
            continue;
        }
        
        NSNumber *action = [NSNumber castFrom:entry[iTermKeyBindingDictionaryKeyAction]];
        if (!action) {
            continue;
        }
        NSString *label = [NSString castFrom:entry[iTermKeyBindingDictionaryKeyLabel]];
        NSString *parameter = [NSString castFrom:entry[iTermKeyBindingDictionaryKeyParameter]];
        [self.delegate keyMapping:self
                     didChangeKey:key
                   isTouchBarItem:YES
                          atIndex:NSNotFound
                         toAction:[action intValue]
                        parameter:parameter
                            label:label
                       isAddition:YES];
    }
}

- (void)exportMenuItem:(id)sender {
    _savePanel = [NSSavePanel savePanel];
    [_savePanel setAllowedFileTypes:@[ @"itermkeymap" ]];
    __weak __typeof(self) weakSelf = self;
    [_savePanel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            [weakSelf exportFromSavePanel];
        }
    }];
}

- (void)exportFromSavePanel {
    NSURL *url = _savePanel.URL;
    _savePanel = nil;

    NSDictionary *const keymappings = [self.delegate keyMappingDictionary:self];
    NSDictionary *const touchbarItems = [self.delegate keyMappingTouchBarItems];
    NSDictionary *const dict = @{ INTERCHANGE_KEY_MAPPING_DICT: keymappings ?: @{},
                                  INTERCHANGE_TOUCH_BAR_ITEMS: touchbarItems ?: @[] };
    NSString *json = [NSJSONSerialization it_jsonStringForObject:dict];
    NSError *error;
    [json writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        XLog(@"%@", error);
        NSBeep();
        return;
    }
}

@end

//
//  iTermKeyMappingViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermKeyMappingViewController.h"
#import "DebugLogging.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermEditKeyActionWindowController.h"
#import "iTermKeyBindingAction.h"
#import "iTermPreferences.h"
#import "iTermPreferencesBaseViewController.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSTextField+iTerm.h"
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
    // Index of row being edited. Valid after presenting the edit key mapping sheet.
    NSInteger _rowIndex;
}

- (instancetype)init {
    self = [super initWithNibName:@"iTermKeyMapping" bundle:[NSBundle bundleForClass:self.class]];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyBindingsChanged)
                                                     name:kKeyBindingsChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(leaderDidChange:)
                                                     name:iTermKeyMappingsLeaderDidChange
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
    _hapticFeedbackForEsc.state = hapticFeedbackForEscEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [iTermPreferences setBool:hapticFeedbackForEscEnabled
                       forKey:kPreferenceKeyEnableHapticFeedbackForEsc];
}

- (BOOL)hapticFeedbackForEscEnabled {
    return _hapticFeedbackForEsc.state == NSControlStateValueOn;
}

- (void)setSoundForEscEnabled:(BOOL)enabled {
    _soundForEsc.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [iTermPreferences setBool:enabled
                       forKey:kPreferenceKeyEnableSoundForEsc];
}

- (BOOL)soundForEscEnabled {
    return _soundForEsc.state == NSControlStateValueOn;
}

- (void)setVisualIndicatorForEscEnabled:(BOOL)enabled {
    _visualIndicatorForEsc.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [iTermPreferences setBool:enabled
                       forKey:kPreferenceKeyVisualIndicatorForEsc];
}

- (BOOL)visualIndicatorForEscEnabled {
    return _visualIndicatorForEsc.state == NSControlStateValueOn;
}

- (void)keyBindingsChanged {
    [_tableView reloadData];
}

- (void)leaderDidChange:(NSNotification *)notification {
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

- (void)reloadData {
    [_tableView reloadData];
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

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    static NSString *const identifier = @"KeyMappingTableViewIdentifier";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.lineBreakMode = NSLineBreakByTruncatingTail;
        result.usesSingleLineMode = YES;
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    result.stringValue = [self stringValueForColumn:tableColumn row:row];
    result.toolTip = result.stringValue;
    return result;
}

- (NSString *)keyCombinationStringForKeystroke:(iTermKeystroke *)keystroke {
    return [iTermKeystrokeFormatter stringForKeystroke:keystroke];
}

- (NSString *)descriptionForKeystroke:(iTermKeystroke *)keystroke
                    bindingDictionary:(NSDictionary *)dict {
    iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:[keystroke valueInBindingDictionary:dict]];
    return action.displayName;
}

- (NSString *)stringValueForKeyMappingOnRow:(NSInteger)rowIndex
                                     column:(NSTableColumn *)column
                          bindingDictionary:(NSDictionary *)dict {
    NSArray<iTermKeystroke *> *sortedKeystrokes = [_delegate keyMappingSortedKeystrokes:self];
    iTermKeystroke *keystroke = sortedKeystrokes[rowIndex];

    if (column == _keyCombinationColumn) {
        return [self keyCombinationStringForKeystroke:keystroke];
    }
    if (column == _actionColumn) {
        return [self descriptionForKeystroke:keystroke
                           bindingDictionary:dict];
    }
    return nil;
}

- (NSString *)labelForTouchBarItem:(NSDictionary *)dict {
    iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:dict];
    return action.label;
}

- (NSString *)actionForTouchBarItem:(NSDictionary *)dict {
    iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:dict];
    return action.displayName;
}

- (NSString *)stringValueForTouchBarMappingOnRow:(NSInteger)rowIndex
                                          column:(NSTableColumn *)column {
    NSDictionary *dict = [_delegate keyMappingTouchBarItems];
    NSArray<iTermTouchbarItem *> *sortedKeys = [_delegate keyMappingSortedTouchbarItems:self];
    iTermTouchbarItem *key = sortedKeys[rowIndex];

    if (column == _keyCombinationColumn) {
        return [self labelForTouchBarItem:dict[key.identifier]];
    }
    if (column == _actionColumn) {
        return [self actionForTouchBarItem:dict[key.identifier]];
    }
    return nil;
}

- (NSString *)stringValueForColumn:(NSTableColumn *)column
                               row:(NSInteger)rowIndex {
    // Try to handle as key mapping
    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    if (rowIndex < dict.count) {
        return [self stringValueForKeyMappingOnRow:rowIndex
                                            column:column
                                 bindingDictionary:dict];
    }

    return [self stringValueForTouchBarMappingOnRow:rowIndex - dict.count
                                             column:column];
}

#pragma mark - Modal Sheets

- (void)presentEditActionSheet:(iTermEditKeyActionWindowController *)editActionWindowController {
    _rowIndex = _tableView.selectedRow;
    [self.view.window beginSheet:editActionWindowController.window completionHandler:^(NSModalResponse returnCode) {
        [self editActionWindowCompletionHandler:editActionWindowController];
    }];
}

- (void)editActionWindowCompletionHandler:(iTermEditKeyActionWindowController *)editActionWindowController {
    if (editActionWindowController.ok) {
        [_delegate keyMapping:self
                didChangeItem:editActionWindowController.keystrokeOrTouchbarItem
                      atIndex:_rowIndex
                     toAction:[iTermKeyBindingAction withAction:editActionWindowController.action
                                                      parameter:editActionWindowController.parameterValue
                                                          label:editActionWindowController.label
                                                       escaping:editActionWindowController.escaping
                                                      applyMode:editActionWindowController.applyMode]
                   isAddition:editActionWindowController.isNewMapping];
    }
    [editActionWindowController close];
    [_tableView reloadData];
    [editActionWindowController.window close];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    const NSUInteger numberSelected = _tableView.selectedRowIndexes.count;
    _removeMappingButton.enabled = (numberSelected > 0);
}

#pragma mark - Actions

- (IBAction)addTouchBarItem:(id)sender {
    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp
                                                           mode:iTermEditKeyActionWindowControllerModeTouchBarItem];
    editActionWindowController.isNewMapping = YES;
    editActionWindowController.touchBarItemID = [iTermTouchBarIDPrefix stringByAppendingString:[NSString uuid]];
    [editActionWindowController setAction:KEY_ACTION_IGNORE parameter:@"" applyMode:iTermActionApplyModeCurrentSession];
    editActionWindowController.escaping = iTermSendTextEscapingCommon;
    [self presentEditActionSheet:editActionWindowController];
}

- (IBAction)addNewMapping:(id)sender {
    iTermEditKeyActionWindowController *editActionWindowController;
    editActionWindowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp
                                                           mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut];
    editActionWindowController.isNewMapping = YES;
    [editActionWindowController setAction:KEY_ACTION_IGNORE parameter:@"" applyMode:iTermActionApplyModeCurrentSession];
    editActionWindowController.escaping = iTermSendTextEscapingCommon;
    [self presentEditActionSheet:editActionWindowController];
}

- (IBAction)removeMapping:(id)sender {
    if (_tableView.selectedRowIndexes.count == 0) {
        return;
    }
    NSIndexSet *indexes = [_tableView.selectedRowIndexes copy];
    NSMutableSet<iTermKeystroke *> *regularKeystrokes = [NSMutableSet set];
    NSMutableSet<iTermTouchbarItem *> *touchbarItems = [NSMutableSet set];
    NSArray<iTermKeystroke *> *sortedRegularKeystrokes = [_delegate keyMappingSortedKeystrokes:self];
    NSArray<iTermTouchbarItem *> *sortedTouchbarItems = [_delegate keyMappingSortedTouchbarItems:self];

    [indexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL * _Nonnull stop) {
        if (row < sortedRegularKeystrokes.count) {
            [regularKeystrokes addObject:sortedRegularKeystrokes[row]];
        } else {
            [touchbarItems addObject:sortedTouchbarItems[row - sortedRegularKeystrokes.count]];
        }
    }];
    [_tableView beginUpdates];
    [_delegate keyMapping:self
         removeKeystrokes:regularKeystrokes
            touchbarItems:touchbarItems];
    [_tableView removeRowsAtIndexes:_tableView.selectedRowIndexes withAnimation:YES];
    [_tableView endUpdates];
    [_tableView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
}

- (void)doubleClick:(id)sender {
    NSInteger row = [_tableView clickedRow];
    if (row < 0) {
        return;
    }
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];

    int rowIndex = [_tableView selectedRow];
    if (rowIndex < 0) {
        [self addNewMapping:sender];
        return;
    }

    NSDictionary *dict = [_delegate keyMappingDictionary:self];
    NSArray<iTermKeystrokeOrTouchbarItem *> *sortedItems =
    [[_delegate keyMappingSortedKeystrokes:self] mapWithBlock:^id(iTermKeystroke *anObject) {
        return [iTermOr first:anObject];
    }];
    iTermKeystrokeOrTouchbarItem *selectedItem;
    if (rowIndex < sortedItems.count) {
        selectedItem = sortedItems[rowIndex];
    } else {
        rowIndex -= sortedItems.count;
        sortedItems = [[_delegate keyMappingSortedTouchbarItems:self] mapWithBlock:^id(iTermTouchbarItem *anObject) {
            return [iTermOr second:anObject];
        }];
        selectedItem = sortedItems[rowIndex];
        dict = [_delegate keyMappingTouchBarItems];
    }
    _editActionWindowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession | iTermVariablesSuggestionContextApp
                                                           mode:selectedItem.hasSecond ? iTermEditKeyActionWindowControllerModeTouchBarItem : iTermEditKeyActionWindowControllerModeKeyboardShortcut];
    __block NSDictionary *binding;
    [selectedItem whenFirst:
     ^(iTermKeystroke * _Nonnull keystroke) {
        _editActionWindowController.currentKeystroke = keystroke;
        binding = [keystroke valueInBindingDictionary:dict];
    }
                     second:
     ^(iTermTouchbarItem * _Nonnull touchbarItem) {
        iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:dict[touchbarItem.identifier]];
        _editActionWindowController.label = action.label ?: @"[bug]";
        _editActionWindowController.touchBarItemID = touchbarItem.identifier;
        binding = dict[touchbarItem.identifier];
    }];
    _editActionWindowController.isNewMapping = NO;

    [_editActionWindowController setAction:(KEY_ACTION)[binding[iTermKeyBindingDictionaryKeyAction] intValue]
                                 parameter:binding[iTermKeyBindingDictionaryKeyParameter]
                                 applyMode:[binding[iTermKeyBindingDictionaryKeyApplyMode] unsignedIntegerValue]];
    iTermSendTextEscaping escaping;
    if ([binding[iTermKeyBindingDictionaryKeyVersion] intValue] == 0) {
        escaping = iTermSendTextEscapingCompatibility;
    } else if (binding[iTermKeyBindingDictionaryKeyEscaping]) {
        escaping = [binding[iTermKeyBindingDictionaryKeyEscaping] unsignedIntegerValue];
    } else {
        escaping = iTermSendTextEscapingCommon;  // v1 migration path
    }
    _editActionWindowController.escaping = escaping;
    [self presentEditActionSheet:_editActionWindowController];
}

- (IBAction)loadPresets:(id)sender {
    [_delegate keyMapping:self loadPresetsNamed:[[sender selectedItem] title]];
    [_tableView reloadData];
}

- (IBAction)hapticFeedbackToggled:(id)sender {
    [iTermPreferences setBool:_hapticFeedbackForEsc.state == NSControlStateValueOn
                       forKey:kPreferenceKeyEnableHapticFeedbackForEsc];
}

- (IBAction)soundForEscToggled:(id)sender {
    [iTermPreferences setBool:_soundForEsc.state == NSControlStateValueOn
                       forKey:kPreferenceKeyEnableSoundForEsc];
}

- (IBAction)visualIndicatorForEscToggled:(id)sender {
    [iTermPreferences setBool:_visualIndicatorForEsc.state == NSControlStateValueOn
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
        XLog(@"Beep: %@", error);
        NSBeep();
        return;
    }

    id decoded = [NSJSONSerialization it_objectForJsonString:content error:&error];
    if (!decoded) {
        XLog(@"Beep: %@", error);
        NSBeep();
        return;
    }

    NSDictionary *dict = [NSDictionary castFrom:decoded];
    NSDictionary *keymappings = [NSDictionary castFrom:dict[INTERCHANGE_KEY_MAPPING_DICT]];
    NSSet<iTermKeystroke *> *keystrokesThatWillChange = [NSSet setWithArray:[keymappings.allKeys mapWithBlock:^id(id anObject) {
        return [[iTermKeystroke alloc] initWithSerialized:anObject];
    }]];

    if (![self.delegate keyMapping:self shouldImportKeystrokes:keystrokesThatWillChange]) {
        return;
    }

    for (id serialized in keymappings) {
        iTermKeystroke *keystroke = [[iTermKeystroke alloc] initWithSerialized:serialized];
        if (!keystroke.isValid) {
            continue;
        }

        NSDictionary *entry = [NSDictionary castFrom:[keystroke valueInBindingDictionary:keymappings]];
        iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:entry];
        if (!action) {
            continue;
        }
        [self.delegate keyMapping:self
                    didChangeItem:[iTermOr first:keystroke]
                          atIndex:NSNotFound
                         toAction:[iTermKeyBindingAction withAction:action.keyAction
                                                          parameter:action.parameter
                                                           escaping:action.escaping
                                                          applyMode:action.applyMode]
                       isAddition:YES];
    }

    NSDictionary *touchbarItems = [NSDictionary castFrom:dict[INTERCHANGE_TOUCH_BAR_ITEMS]];
    for (id identifier in touchbarItems) {
        iTermTouchbarItem *touchbarItem = [[iTermTouchbarItem alloc] initWithIdentifier:identifier];
        if (!touchbarItem) {
            continue;
        }
        NSDictionary *entry = [NSDictionary castFrom:touchbarItems[touchbarItem.identifier]];
        if (!entry) {
            continue;
        }

        iTermKeyBindingAction *action = [iTermKeyBindingAction withDictionary:entry];
        if (!action) {
            continue;
        }
        [self.delegate keyMapping:self
                    didChangeItem:[iTermOr second:touchbarItem]
                          atIndex:NSNotFound
                         toAction:[iTermKeyBindingAction withAction:action.keyAction
                                                          parameter:action.parameter
                                                              label:action.label
                                                           escaping:action.escaping
                                                          applyMode:action.applyMode]
                       isAddition:YES];
    }
}

- (NSNumber *)removeBeforeLoading:(NSString *)thing {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Remove all key mappings before %@?", thing]
                               actions:@[ @"Keep", @"Remove", @"Cancel" ]
                             accessory:nil
                            identifier:@"RemoveExistingGlobalKeyMappingsBeforeLoading"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Load Preset"
                                window:self.view.window];
    switch (selection) {
        case kiTermWarningSelection0:
            return @NO;
        case kiTermWarningSelection1:
            return @YES;
        case kiTermWarningSelection2:
            return nil;
        default:
            assert(NO);
    }
    return nil;
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
        XLog(@"Beep: %@", error);
        NSBeep();
        return;
    }
}

@end

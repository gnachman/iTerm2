//
//  iTermActionsEditingViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/20.
//

#import "iTermActionsEditingViewController.h"

#import "iTermActionsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermEditKeyActionWindowController.h"
#import "iTermPreferencesBaseViewController.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

#import <Carbon/Carbon.h>

static NSString *const iTermActionsEditingPasteboardType = @"com.googlecode.iterm2.iTermActionsEditingPasteboardType";

@interface iTermActionsEditingView: NSView
@end

@implementation iTermActionsEditingView
@end

@interface iTermActionsEditingViewController()<NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation iTermActionsEditingViewController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_titleColumn;
    IBOutlet NSTableColumn *_actionColumns;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;
    IBOutlet NSButton *_exportButton;
    IBOutlet NSButton *_importButton;
    iTermEditKeyActionWindowController *_editActionWindowController;
    NSArray<iTermAction *> *_actions;
}

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView {
    [containerView addSubview:self.view];
    containerView.autoresizesSubviews = YES;
    self.view.frame = containerView.bounds;
    _actions = [[[iTermActionsModel sharedInstance] actions] copy];
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    [self updateEnabled];
    [_tableView registerForDraggedTypes:@[ iTermActionsEditingPasteboardType ]];
    [_tableView reloadData];
    __weak __typeof(self) weakSelf = self;
    [iTermActionsDidChangeNotification subscribe:self
                                           block:^(iTermActionsDidChangeNotification * _Nonnull notification) {
                                               [weakSelf actionsDidChange:notification];
                                           }];
    [container addViewToSearchIndex:_tableView
                        displayName:@"Actions"
                            phrases:@[ @"Actions" ]
                                key:kPreferenceKeyActions];
}

#pragma mark - Private

- (NSArray<iTermAction *> *)selectedActions {
    NSArray<iTermAction *> *actions = [[iTermActionsModel sharedInstance] actions];
    return [[_tableView.selectedRowIndexes it_array] mapWithBlock:^id(NSNumber *indexNumber) {
        return actions[indexNumber.integerValue];
    }];
}

- (iTermEditKeyActionWindowController *)newEditKeyActionWindowControllerForAction:(iTermAction *)action {
    iTermEditKeyActionWindowController *windowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession
                                                           mode:iTermEditKeyActionWindowControllerModeUnbound];
    windowController.escaping = iTermSendTextEscapingCommon;
    if (action) {
        windowController.label = action.title;
        windowController.isNewMapping = NO;
    } else {
        windowController.isNewMapping = YES;
    }
    [windowController setAction:action.action
                      parameter:action.parameter
                      applyMode:action.applyMode];
    [self.view.window beginSheet:windowController.window completionHandler:^(NSModalResponse returnCode) {
        [self editActionDidComplete:action];
    }];
    return windowController;
}

- (void)editActionDidComplete:(iTermAction *)original {
    if (_editActionWindowController.ok) {
        [self pushUndo];
        if (original) {
            [[iTermActionsModel sharedInstance] replaceAction:original
                                                   withAction:_editActionWindowController.unboundAction];
        } else {
            [[iTermActionsModel sharedInstance] addAction:_editActionWindowController.unboundAction];
        }
    }
    [_editActionWindowController.window close];
    _editActionWindowController = nil;
}

- (void)setActions:(NSArray<iTermAction *> *)actions {
    [self pushUndo];
    [[iTermActionsModel sharedInstance] setActions:actions];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setActions:)
                                        object:_actions];
}

- (void)actionsDidChange:(iTermActionsDidChangeNotification *)notif {
    _actions = [[[iTermActionsModel sharedInstance] actions] copy];
    switch (notif.mutationType) {
        case iTermActionsDidChangeMutationTypeEdit: {
            [_tableView it_performUpdateBlock:^{
                [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                      columnIndexes:[NSIndexSet indexSetWithIndex:0]];
            }];
            break;
        }
        case iTermActionsDidChangeMutationTypeDeletion: {
            [_tableView it_performUpdateBlock:^{
                [_tableView removeRowsAtIndexes:notif.indexSet
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermActionsDidChangeMutationTypeInsertion: {
            [_tableView it_performUpdateBlock:^{
                [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermActionsDidChangeMutationTypeMove: {
            [_tableView it_performUpdateBlock:^{
                [_tableView removeRowsAtIndexes:notif.indexSet
                                  withAnimation:YES];
                NSMutableIndexSet *insertionIndexes = [NSMutableIndexSet indexSet];
                for (NSInteger i = 0; i < notif.indexSet.count; i++) {
                    [insertionIndexes addIndex:notif.index + i];
                }
                [_tableView insertRowsAtIndexes:insertionIndexes
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermActionsDidChangeMutationTypeFullReplacement:
            [_tableView reloadData];
            break;
    }
}

- (void)updateEnabled {
    const NSInteger numberOfRows = [[self selectedActions] count];
    _removeButton.enabled = numberOfRows > 0;
    _editButton.enabled = numberOfRows == 1;
    if (@available(macOS 10.16, *)) {
        _exportButton.enabled = numberOfRows > 0;
    } else {
        // This is just because we don't have SF Symbols and I don't have a nice asset to use here.
        _importButton.hidden = YES;
        _exportButton.hidden = YES;
    }
}

#pragma mark - Actions

- (void)doubleClickOnTableView:(id)sender {
    NSInteger row = [_tableView clickedRow];
    if (row < 0) {
        return;
    }
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self edit:nil];
}

- (IBAction)add:(id)sender {
    _editActionWindowController = [self newEditKeyActionWindowControllerForAction:nil];
}

- (IBAction)remove:(id)sender {
    NSArray<iTermAction *> *actions = [self selectedActions];
    [self pushUndo];
    [[iTermActionsModel sharedInstance] removeActions:actions];
}

- (IBAction)edit:(id)sender {
    iTermAction *action = [[self selectedActions] firstObject];
    if (action) {
        _editActionWindowController = [self newEditKeyActionWindowControllerForAction:action];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (_tableView.window.firstResponder == _tableView && event.keyCode == kVK_Delete) {
        [self remove:nil];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (IBAction)import:(id)sender {
    NSOpenPanel *panel = [[NSOpenPanel alloc] init];
    panel.allowedFileTypes = @[ @"it2actions" ];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    const NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) {
        return;
    }
    for (NSURL *url in panel.URLs) {
        [self importURL:url];
    }
}

- (IBAction)export:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ @"it2actions" ];

    const NSModalResponse response = [panel runModal];
    if (response != NSModalResponseOK) {
        return;
    }
    [self exportToURL:panel.URL];
}

#pragma mark - Import

- (void)importURL:(NSURL *)url {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:url.path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!content || error) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"While loading %@: %@", url.path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncImportActionsFailed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:[NSString stringWithFormat:@"Import Failed"]
                                    window:self.view.window];
        return;
    }

    id root = [NSJSONSerialization it_objectForJsonString:content error:&error];
    if (!root) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"While parsing %@: %@", url.path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncImportActionsFailed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:[NSString stringWithFormat:@"Import Failed"]
                                    window:self.view.window];
        return;
    }

    NSArray *array = [NSArray castFrom:root];
    if (!array) {
        [self showEncodingErrorForURL:url];
        return;
    }

    [self pushUndo];
    for (id element in array) {
        NSDictionary *dict = [NSDictionary castFrom:element];
        if (!dict) {
            [self showEncodingErrorForURL:url];
            return;
        }
        iTermAction *action = [[iTermAction alloc] initWithDictionary:dict];
        if (!action) {
            [self showEncodingErrorForURL:url];
            return;
        }
        [[iTermActionsModel sharedInstance] addAction:action];
    }
}

- (void)showEncodingErrorForURL:(NSURL *)url {
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Malformed file at %@", url.path]
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncActionEncodingError"
                           silenceable:kiTermWarningTypePersistent
                               heading:[NSString stringWithFormat:@"Import Failed"]
                                window:self.view.window];
}

#pragma mark - Export

- (void)exportToURL:(NSURL *)url {
    NSIndexSet *indexes = [_tableView selectedRowIndexes];
    NSMutableArray<NSDictionary *> *array = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        iTermAction *action = _actions[i];
        [array addObject:action.dictionaryValue];
    }];
    NSString *json = [NSJSONSerialization it_jsonStringForObject:array];
    NSError *error = nil;
    [json writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Error saving to %@: %@", url.path, error.localizedDescription]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"NoSyncActionWritingError"
                               silenceable:kiTermWarningTypePersistent
                                   heading:[NSString stringWithFormat:@"Export Failed"]
                                    window:self.view.window];
    }
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateEnabled];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _actions.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == _titleColumn) {
        return [self viewForTitleColumnOnRow:row];
    }
    if (tableColumn == _actionColumns) {
        return [self viewForActionColumnOnRow:row];
    }
    return nil;
}

- (NSView *)viewForTitleColumnOnRow:(NSInteger)row {
    static NSString *const identifier = @"PrefsActionsTitle";
    NSTextField *result = [_tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    result.stringValue = [_actions[row] title];
    return result;
}

- (NSView *)viewForActionColumnOnRow:(NSInteger)row {
    static NSString *const identifier = @"PrefsActionsAction";
    NSTextField *result = [_tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    result.stringValue = [_actions[row] displayString];
    return result;
}

#pragma mark Drag-Drop

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setPropertyList:@[ @(_actions[row].identifier) ] forType:iTermActionsEditingPasteboardType];
    return pbItem;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != aTableView) {
        return NSDragOperationNone;
    }

    // Add code here to validate the drop
    switch (operation) {
        case NSTableViewDropOn:
            return NSDragOperationNone;

        case NSTableViewDropAbove:
            return NSDragOperationMove;

        default:
            return NSDragOperationNone;
    }
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    [self pushUndo];
    NSMutableArray<NSNumber *> *allIdentifiers = [NSMutableArray array];
    [info enumerateDraggingItemsWithOptions:0 forView:aTableView classes:@[[NSPasteboardItem class]] searchOptions:@{} usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
        NSPasteboardItem *item = draggingItem.item;
        NSArray<NSNumber *> *identifiers = [item propertyListForType:iTermActionsEditingPasteboardType];
        [allIdentifiers addObjectsFromArray:identifiers];
    }];
    [[iTermActionsModel sharedInstance] moveActionsWithIdentifiers:allIdentifiers
                                                           toIndex:row];
    return YES;
}

@end

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
#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

#import <Carbon/Carbon.h>

static NSString *const iTermActionsEditingPasteboardType = @"iTermActionsEditingPasteboardType";

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
    windowController.useCompatibilityEscaping = NO;
    if (action) {
        windowController.label = action.title;
        windowController.isNewMapping = NO;
    } else {
        windowController.isNewMapping = YES;
    }
    windowController.parameterValue = action.parameter;
    windowController.action = action.action;
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

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard*)pboard {
    [pboard declareTypes:@[ iTermActionsEditingPasteboardType ]
                   owner:self];

    NSArray<NSNumber *> *plist = [rowIndexes.it_array mapWithBlock:^id(NSNumber *anObject) {
        return @(_actions[anObject.integerValue].identifier);
    }];
    [pboard setPropertyList:plist
                    forType:iTermActionsEditingPasteboardType];
    return YES;
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
    NSPasteboard *pboard = [info draggingPasteboard];
    NSArray<NSNumber *> *identifiers = [pboard propertyListForType:iTermActionsEditingPasteboardType];
    [[iTermActionsModel sharedInstance] moveActionsWithIdentifiers:identifiers
                                                           toIndex:row];
    return YES;
}

@end

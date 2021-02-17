//
//  iTermSnippetsEditingViewController.m
//  iTerm2
//
//  Created by George Nachman on 9/7/20.
//

#import "iTermSnippetsEditingViewController.h"

#import "iTermCompetentTableRowView.h"
#import "iTermEditSnippetWindowController.h"
#import "iTermPreferencesBaseViewController.h"
#import "iTermSnippetsModel.h"
#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

static NSString *const iTermSnippetsEditingPasteboardType = @"iTermSnippetsEditingPasteboardType";

@interface iTermSnippetsEditingView: NSView
@end

@implementation iTermSnippetsEditingView
@end

@interface iTermSnippetsEditingViewController ()<NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation iTermSnippetsEditingViewController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_titleColumn;
    IBOutlet NSTableColumn *_valueColumn;
    IBOutlet NSButton *_removeButton;
    IBOutlet NSButton *_editButton;

    NSArray<iTermSnippet *> *_snippets;
    iTermEditSnippetWindowController *_windowController;
}

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView {
    [containerView addSubview:self.view];
    containerView.autoresizesSubviews = YES;
    self.view.frame = containerView.bounds;
    _snippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    [self updateEnabled];
    [_tableView registerForDraggedTypes:@[ iTermSnippetsEditingPasteboardType ]];
    [_tableView reloadData];
    __weak __typeof(self) weakSelf = self;
    [iTermSnippetsDidChangeNotification subscribe:self
                                            block:^(iTermSnippetsDidChangeNotification * _Nonnull notification) {
        [weakSelf snippetsDidChange:notification];
    }];
    [container addViewToSearchIndex:_tableView
                        displayName:@"Snippets"
                            phrases:@[ @"Snippets" ]
                                key:kPreferenceKeySnippets];
}

#pragma mark - Private

- (NSArray<iTermSnippet *> *)selectedSnippets {
    NSArray<iTermSnippet *> *snippets = [[iTermSnippetsModel sharedInstance] snippets];
    return [[_tableView.selectedRowIndexes it_array] mapWithBlock:^id(NSNumber *indexNumber) {
        return snippets[indexNumber.integerValue];
    }];
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] setSnippets:snippets];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setSnippets:)
                                        object:_snippets];
}

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notif {
    _snippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
    switch (notif.mutationType) {
        case iTermSnippetsDidChangeMutationTypeEdit: {
            [_tableView it_performUpdateBlock:^{
                [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                      columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeDeletion: {
            [_tableView it_performUpdateBlock:^{
                [_tableView removeRowsAtIndexes:notif.indexSet
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeInsertion: {
            [_tableView it_performUpdateBlock:^{
                [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeMove: {
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
        case iTermSnippetsDidChangeMutationTypeFullReplacement:
            [_tableView reloadData];
            break;
    }
}

- (void)updateEnabled {
    const NSInteger numberOfRows = [[self selectedSnippets] count];
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
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:nil
                                                                       completion:^(iTermSnippet * _Nullable snippet) {
        if (!snippet) {
            return;
        }
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    }];
    [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (IBAction)remove:(id)sender {
    NSArray<iTermSnippet *> *snippets = [self selectedSnippets];
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] removeSnippets:snippets];
}

- (IBAction)edit:(id)sender {
    iTermSnippet *snippet = [[self selectedSnippets] firstObject];
    if (snippet) {
        _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:snippet
                                                                           completion:^(iTermSnippet * _Nullable updatedSnippet) {
            if (!updatedSnippet) {
                return;
            }
            [[iTermSnippetsModel sharedInstance] replaceSnippet:snippet withSnippet:updatedSnippet];
        }];
        [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
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
    return _snippets.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == _titleColumn) {
        return [self viewForTitleColumnOnRow:row];
    }
    return [self viewForValueColumnOnRow:row];
}

- (NSView *)viewForTitleColumnOnRow:(NSInteger)row {
    static NSString *const identifier = @"PrefsSnippetsTitle";
    NSTextField *result = [_tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        result.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    result.stringValue = [_snippets[row] trimmedTitle:256];
    return result;
}

- (NSView *)viewForValueColumnOnRow:(NSInteger)row {
    static NSString *const identifier = @"PrefsSnippetsValue";
    NSTextField *result = [_tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        result.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    result.stringValue = [_snippets[row] trimmedValue:256];
    return result;
}

#pragma mark Drag-Drop

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard*)pboard {
    [pboard declareTypes:@[ iTermSnippetsEditingPasteboardType ]
                   owner:self];

    NSArray<NSString *> *plist = [rowIndexes.it_array mapWithBlock:^id(NSNumber *anObject) {
        return _snippets[anObject.integerValue].guid;
    }];
    [pboard setPropertyList:plist
                    forType:iTermSnippetsEditingPasteboardType];
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
    NSArray<NSString *> *guids = [pboard propertyListForType:iTermSnippetsEditingPasteboardType];
    [[iTermSnippetsModel sharedInstance] moveSnippetsWithGUIDs:guids
                                                       toIndex:row];
    return YES;
}

@end

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
    BOOL _initialized;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _model = [iTermSnippetsModel sharedInstance];
    }
    return self;
}

- (void)setModel:(iTermSnippetsModel *)model {
    _model = model;
    [self loadFromModel];
}

- (void)loadFromModel {
    _snippets = [[_model snippets] copy];
    [self updateEnabled];
    [_tableView reloadData];
    [self finishInitialization];
}

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView {
    [containerView addSubview:self.view];
    containerView.autoresizesSubviews = YES;
    self.view.frame = containerView.bounds;
    [self loadFromModel];
    [container addViewToSearchIndex:_tableView
                        displayName:@"Snippets"
                            phrases:@[ @"Snippets" ]
                                key:kPreferenceKeySnippets];
}

- (void)finishInitialization {
    if (_initialized) {
        return;
    }
    _initialized = YES;
    [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
    [_tableView registerForDraggedTypes:@[ iTermSnippetsEditingPasteboardType ]];
    __weak __typeof(self) weakSelf = self;
    [iTermSnippetsDidChangeNotification subscribe:self
                                            block:^(iTermSnippetsDidChangeNotification * _Nonnull notification) {
        [weakSelf snippetsDidChange:notification];
    }];
}

#pragma mark - Private

- (NSArray<iTermSnippet *> *)selectedSnippets {
    NSArray<iTermSnippet *> *snippets = [_model snippets];
    return [[_tableView.selectedRowIndexes it_array] mapWithBlock:^id(NSNumber *indexNumber) {
        return snippets[indexNumber.integerValue];
    }];
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    [self pushUndo];
    [_model setSnippets:snippets];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setSnippets:)
                                        object:_snippets];
}

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notif {
    if (notif.model != _model) {
        return;
    }
    _snippets = [[_model snippets] copy];
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
    __weak __typeof(self) weakSelf = self;
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:nil
                                                                       completion:^(iTermSnippet * _Nullable snippet) {
        if (!snippet) {
            return;
        }
        [weakSelf.model addSnippet:snippet];
    }];
    [self.view.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (IBAction)remove:(id)sender {
    NSArray<iTermSnippet *> *snippets = [self selectedSnippets];
    [self pushUndo];
    [_model removeSnippets:snippets];
}

- (IBAction)edit:(id)sender {
    iTermSnippet *snippet = [[self selectedSnippets] firstObject];
    if (snippet) {
        __weak __typeof(self) weakSelf = self;
        _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:snippet
                                                                           completion:^(iTermSnippet * _Nullable updatedSnippet) {
            if (!updatedSnippet) {
                return;
            }
            [weakSelf.model replaceSnippet:snippet withSnippet:updatedSnippet];
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

    NSArray<NSNumber *> *plist = [rowIndexes.it_array mapWithBlock:^id(NSNumber *anObject) {
        return @(_snippets[anObject.integerValue].identifier);
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
    NSArray<NSNumber *> *identifiers = [pboard propertyListForType:iTermSnippetsEditingPasteboardType];
    [_model moveSnippetsWithIdentifiers:identifiers
                                toIndex:row];
    return YES;
}

@end

//
//  iTermToolActions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermToolActions.h"

#import "DebugLogging.h"
#import "iTermActionsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermEditKeyActionWindowController.h"

#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;
static NSString *const iTermToolActionsPasteboardType = @"iTermToolActionsPasteboardType";


@interface iTermToolActions() <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation iTermToolActions {
    NSScrollView *_scrollView;
    NSTableView *_tableView;

    NSButton *_applyButton;
    NSButton *_addButton;
    NSButton *_removeButton;
    NSButton *_editButton;

    iTermEditKeyActionWindowController *_editActionWindowController;
    NSArray<iTermAction *> *_actions;
}

static NSButton *iTermToolActionsNewButton(NSString *imageName, NSString *title, id target, SEL selector, NSRect frame) {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    [button setButtonType:NSMomentaryPushInButton];
    if (imageName) {
        button.image = [NSImage imageNamed:imageName];
    } else {
        button.title = title;
    }
    [button setTarget:target];
    [button setAction:selector];
    [button setBezelStyle:NSSmallSquareBezelStyle];
    [button sizeToFit];
    [button setAutoresizingMask:NSViewMinYMargin];

    return button;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _applyButton = iTermToolActionsNewButton(nil, @"Apply", self, @selector(apply:), frame);
        [self addSubview:_applyButton];
        _addButton = iTermToolActionsNewButton(NSImageNameAddTemplate, nil, self, @selector(add:), frame);
        [self addSubview:_addButton];
        _removeButton = iTermToolActionsNewButton(NSImageNameRemoveTemplate, nil, self, @selector(remove:), frame);
        [self addSubview:_removeButton];
        _editButton = iTermToolActionsNewButton(nil, @"✐", self, @selector(edit:), frame);
        [self addSubview:_editButton];

        _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.hasHorizontalScroller = NO;
        _scrollView.borderType = NSBezelBorder;
        NSSize contentSize = [_scrollView contentSize];
        [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        if (@available(macOS 10.14, *)) { } else {
            _scrollView.drawsBackground = NO;
        }

        _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;
        col = [[NSTableColumn alloc] initWithIdentifier:@"contents"];
        [col setEditable:NO];
        [_tableView addTableColumn:col];
        _tableView.headerView = nil;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.intercellSpacing = NSMakeSize(_tableView.intercellSpacing.width, 0);
        _tableView.rowHeight = 15;
        _tableView.allowsMultipleSelection = YES;
        [_tableView registerForDraggedTypes:@[ iTermToolActionsPasteboardType ]];

        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
        [_tableView setAutoresizingMask:NSViewWidthSizable];

        [_scrollView setDocumentView:_tableView];
        [self addSubview:_scrollView];

        [_tableView sizeToFit];
        [_tableView setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        [_tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
        _actions = [[[iTermActionsModel sharedInstance] actions] copy];
        [_tableView reloadData];

        __weak __typeof(self) weakSelf = self;
        [iTermActionsDidChangeNotification subscribe:self
                                               block:^(iTermActionsDidChangeNotification * _Nonnull notification) {
                                                   [weakSelf actionsDidChange:notification];
                                               }];
        [self relayout];
        [self updateEnabled];
    }
    return self;
}

#pragma mark - ToolbeltTool

- (void)shutdown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)relayout {
    NSRect frame = self.frame;
    [_applyButton sizeToFit];
    [_applyButton setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, _applyButton.frame.size.width, kButtonHeight)];

    CGFloat x = frame.size.width;
    for (NSButton *button in @[ _addButton, _removeButton, _editButton]) {
        [button sizeToFit];
        const CGFloat width = MAX(kButtonHeight, button.frame.size.width);
        x -= width - 1;
        button.frame = NSMakeRect(x,
                                  frame.size.height - kButtonHeight,
                                  width,
                                  kButtonHeight);
    }

    [_scrollView setFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
    NSSize contentSize = [self contentSize];
    [_tableView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (CGFloat)minimumHeight {
    return 60;
}

#pragma mark - NSView

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Actions

- (void)doubleClickOnTableView:(id)sender {
    [self applySelectedActions];
}

- (void)apply:(id)sender {
    [self applySelectedActions];
}

- (void)add:(id)sender {
    _editActionWindowController = [self newEditKeyActionWindowControllerForAction:nil];
}

- (void)remove:(id)sender {
    NSArray<iTermAction *> *actions = [self selectedActions];
    [self pushUndo];
    [[iTermActionsModel sharedInstance] removeActions:actions];
}

- (void)edit:(id)sender {
    iTermAction *action = [[self selectedActions] firstObject];
    if (action) {
        _editActionWindowController = [self newEditKeyActionWindowControllerForAction:action];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.keyCode == kVK_Delete) {
        [self remove:nil];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

#pragma mark - Private

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

- (void)applySelectedActions {
    for (iTermAction *action in [self selectedActions]) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        [wrapper.delegate.delegate toolbeltApplyActionToCurrentSession:action];
    }
}

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
    if (action) {
        windowController.label = action.title;
        windowController.isNewMapping = NO;
    } else {
        windowController.isNewMapping = YES;
    }
    windowController.parameterValue = action.parameter;
    windowController.action = action.action;
    [self.window beginSheet:windowController.window completionHandler:^(NSModalResponse returnCode) {
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

- (NSSize)contentSize {
    NSSize size = [_scrollView contentSize];
    size.height = [[_tableView headerView] frame].size.height;
    size.height += [_tableView numberOfRows] * ([_tableView rowHeight] + [_tableView intercellSpacing].height);
    return size;
}

- (NSString *)stringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    NSString *title = _actions[rowIndex].title;
    if (title.length) {
        return title;
    }
    return @"Untitled";
}

- (void)update {
    [_tableView reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[_tableView window] firstResponder];
    if (firstResponder != _tableView) {
        [_tableView scrollToEndOfDocument:nil];
    }
}

- (void)fixCursor {
    [self.toolWrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)updateEnabled {
    const NSInteger numberOfRows = [[self selectedActions] count];
    _applyButton.enabled = numberOfRows > 0;
    _removeButton.enabled = numberOfRows > 0;
    _editButton.enabled = numberOfRows == 1;
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolAction";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
    }

    NSString *value = [self stringForTableColumn:tableColumn row:row];
    result.stringValue = value;

    return result;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateEnabled];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return _actions.count;
}

#pragma mark Drag-Drop

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard*)pboard {
    [pboard declareTypes:@[ iTermToolActionsPasteboardType ]
                   owner:self];

    NSArray<NSNumber *> *plist = [rowIndexes.it_array mapWithBlock:^id(NSNumber *anObject) {
        return @(_actions[anObject.integerValue].identifier);
    }];
    [pboard setPropertyList:plist
                    forType:iTermToolActionsPasteboardType];
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
    NSArray<NSNumber *> *identifiers = [pboard propertyListForType:iTermToolActionsPasteboardType];
    [[iTermActionsModel sharedInstance] moveActionsWithIdentifiers:identifiers
                                                           toIndex:row];
    return YES;
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

@end

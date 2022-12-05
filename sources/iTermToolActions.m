//
//  iTermToolActions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermToolActions.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermActionsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermEditKeyActionWindowController.h"

#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;
static NSString *const iTermToolActionsPasteboardType = @"com.googlecode.iterm2.iTermToolActionsPasteboardType";


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
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    if (imageName) {
        if (@available(macOS 10.16, *)) {
            button.image = [NSImage it_imageForSymbolName:imageName accessibilityDescription:title];
        } else {
            button.image = [NSImage imageNamed:imageName];
        }
    } else {
        button.title = title;
    }
    [button setTarget:target];
    [button setAction:selector];
    if (@available(macOS 10.16, *)) {
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.bordered = NO;
        button.imageScaling = NSImageScaleProportionallyUpOrDown;
        button.imagePosition = NSImageOnly;
    } else {
        [button setBezelStyle:NSBezelStyleSmallSquare];
    }
    [button sizeToFit];
    [button setAutoresizingMask:NSViewMinYMargin];

    return button;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(macOS 10.16, *)) {
            _applyButton = iTermToolActionsNewButton(@"play", @"Apply", self, @selector(apply:), frame);
            _addButton = iTermToolActionsNewButton(@"plus", @"Add", self, @selector(add:), frame);
            _removeButton = iTermToolActionsNewButton(@"minus", @"Remove", self, @selector(remove:), frame);
            _editButton = iTermToolActionsNewButton(@"pencil", @"Edit", self, @selector(edit:), frame);
        } else {
            _applyButton = iTermToolActionsNewButton(nil, @"Apply", self, @selector(apply:), frame);
            _addButton = iTermToolActionsNewButton(NSImageNameAddTemplate, nil, self, @selector(add:), frame);
            _removeButton = iTermToolActionsNewButton(NSImageNameRemoveTemplate, nil, self, @selector(remove:), frame);
            _editButton = iTermToolActionsNewButton(nil, @"✐", self, @selector(edit:), frame);
        }
        [self addSubview:_applyButton];
        [self addSubview:_addButton];
        [self addSubview:_removeButton];
        [self addSubview:_editButton];

        _scrollView = [NSScrollView scrollViewWithTableViewForToolbeltWithContainer: self
                                                                             insets:NSEdgeInsetsMake(0, 0, 0, kButtonHeight + kMargin)
                                                                          rowHeight:[NSTableView heightForTextCellUsingFont:[NSFont it_toolbeltFont]]];
        _tableView = _scrollView.documentView;
        _tableView.doubleAction = @selector(doubleClickOnTableView:);
        _tableView.allowsMultipleSelection = YES;
        [_tableView registerForDraggedTypes:@[ iTermToolActionsPasteboardType ]];
        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];

        [_tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
        _actions = [[[iTermActionsModel sharedInstance] actions] copy];
        [_tableView reloadData];
        _tableView.backgroundColor = [NSColor clearColor];
        
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

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;
    [_applyButton sizeToFit];
    [_applyButton setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, _applyButton.frame.size.width, kButtonHeight)];

    CGFloat margin = -1;
    if (@available(macOS 10.16, *)) {
        margin = 2;
    }

    CGFloat x = frame.size.width;
    for (NSButton *button in @[ _addButton, _removeButton, _editButton]) {
        [button sizeToFit];
        CGFloat width;
        if (@available(macOS 10.16, *)) {
            width = NSWidth(button.frame);
        } else {
            width = MAX(kButtonHeight, button.frame.size.width);
        }
        x -= width + margin;
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
    if (_tableView.window.firstResponder == _tableView && event.keyCode == kVK_Delete) {
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
        windowController.escaping = action.escaping;
    } else {
        windowController.isNewMapping = YES;
        windowController.escaping = iTermSendTextEscapingCommon;
    }
    [windowController setAction:action.action
                      parameter:action.parameter
                      applyMode:action.applyMode];
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
    size.height = _tableView.intrinsicContentSize.height;
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

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolAction";
    NSTableCellView *cell = [tableView newTableCellViewWithTextFieldUsingIdentifier:identifier
                                                                               font:[NSFont it_toolbeltFont]
                                                                             string:[self stringForTableColumn:tableColumn row:row]];
    return cell;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateEnabled];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return _actions.count;
}

#pragma mark Drag-Drop

-(id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setPropertyList:@(_actions[row].identifier) forType:iTermToolActionsPasteboardType];
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

    NSMutableArray<NSNumber *> *identifiers = [NSMutableArray array];
    [info enumerateDraggingItemsWithOptions:0
                                    forView:aTableView
                                    classes:@[ [NSPasteboardItem class]]
                              searchOptions:@{}
                                 usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
        NSPasteboardItem *item = draggingItem.item;
        [identifiers addObject:[item propertyListForType:iTermToolActionsPasteboardType]];
    }];
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

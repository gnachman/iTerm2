//
//  iTermToolActions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermToolActions.h"

#import "iTermActionsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermEditKeyActionWindowController.h"

#import "NSTextField+iTerm.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

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
    [self applySelectedAction];
}

- (void)apply:(id)sender {
    [self applySelectedAction];
}

- (void)add:(id)sender {
    _editActionWindowController = [self newEditKeyActionWindowControllerForAction:nil];
}

- (void)remove:(id)sender {
    iTermAction *action = [self selectedAction];
    if (action) {
        [[iTermActionsModel sharedInstance] removeAction:action];
    }
}

- (void)edit:(id)sender {
    iTermAction *action = [self selectedAction];
    if (action) {
        _editActionWindowController = [self newEditKeyActionWindowControllerForAction:action];
    }
}

#pragma mark - Private

- (void)actionsDidChange:(iTermActionsDidChangeNotification *)notif {
    _actions = [[[iTermActionsModel sharedInstance] actions] copy];
    [_tableView beginUpdates];
    switch (notif.mutationType) {
        case iTermActionsDidChangeMutationTypeEdit:
            [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:0]];
            break;
        case iTermActionsDidChangeMutationTypeDeletion:
            [_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                              withAnimation:YES];
            break;
        case iTermActionsDidChangeMutationTypeInsertion:
            [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                              withAnimation:YES];
    }
    [_tableView endUpdates];
}

- (void)applySelectedAction {
    iTermAction *action = [self selectedAction];
    if (action) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        [wrapper.delegate.delegate toolbeltApplyActionToCurrentSession:action];
    }
}

- (iTermAction *)selectedAction {
    if (_tableView.selectedRow < 0) {
        return nil;
    }
    iTermAction *action = [[[iTermActionsModel sharedInstance] actions] objectAtIndex:_tableView.selectedRow];
    return action;
}

- (iTermEditKeyActionWindowController *)newEditKeyActionWindowControllerForAction:(iTermAction *)action {
    iTermEditKeyActionWindowController *windowController = [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession];
    if (action) {
        windowController.label = action.title;
        windowController.isNewMapping = NO;
    } else {
        windowController.isNewMapping = YES;
    }
    windowController.parameterValue = action.parameter;
    windowController.action = action.action;
    windowController.mode = iTermEditKeyActionWindowControllerModeUnbound;
    [self.window beginSheet:windowController.window completionHandler:^(NSModalResponse returnCode) {
        [self editActionDidComplete:action];
    }];
    return windowController;
}

- (void)editActionDidComplete:(iTermAction *)original {
    if (_editActionWindowController.ok) {
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
    const BOOL haveSelection = [self selectedAction] != nil;
    _applyButton.enabled = haveSelection;
    _removeButton.enabled = haveSelection;
    _editButton.enabled = haveSelection;
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


@end

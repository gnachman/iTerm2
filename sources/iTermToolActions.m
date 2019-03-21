//
//  iTermToolActions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermToolActions.h"
#import "iTermCompetentTableRowView.h"

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
}

static NSButton *iTermToolActionsNewButton(NSString *title, id target, SEL selector, NSRect frame) {
    NSButton *_applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    [_applyButton setButtonType:NSMomentaryPushInButton];
    [_applyButton setTitle:@"Apply"];
    [_applyButton setTarget:target];
    [_applyButton setAction:selector];
    [_applyButton setBezelStyle:NSSmallSquareBezelStyle];
    [_applyButton sizeToFit];
    [_applyButton setAutoresizingMask:NSViewMinYMargin];

    return _applyButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _applyButton = iTermToolActionsNewButton(@"Apply", self, @selector(apply:), frame);
        [self addSubview:_applyButton];
        _addButton = iTermToolActionsNewButton(@"+", self, @selector(add:), frame);
        [self addSubview:_addButton];
        _removeButton = iTermToolActionsNewButton(@"-", self, @selector(remove:), frame);
        [self addSubview:_removeButton];
        _applyButton = iTermToolActionsNewButton(@"✐", self, @selector(edit:), frame);
        [self addSubview:_applyButton];

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
        [_tableView reloadData];
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
        x -= button.frame.size.width;
        button.frame = NSMakeRect(x,
                                  frame.size.height - kButtonHeight,
                                  button.frame.size.width,
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
}

- (void)apply:(id)sender {

}

- (void)add:(id)sender {

}

- (void)remove:(id)sender {

}

- (void)edit:(id)sender {

}

#pragma mark - Private

- (NSSize)contentSize {
    NSSize size = [_scrollView contentSize];
    size.height = [[_tableView headerView] frame].size.height;
    size.height += [_tableView numberOfRows] * ([_tableView rowHeight] + [_tableView intercellSpacing].height);
    return size;
}

- (NSString *)stringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    return @"todo";
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

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
#warning this is sketch as hell
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

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return _actions.entries.count;
}


@end

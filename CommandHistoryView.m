//
//  CommandHistoryView.m
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import "CommandHistoryView.h"

static const CGFloat kRowHeight = 16;
static const CGFloat kHorizontalMargin = 16;

@interface CommandHistoryView () <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, retain) NSScrollView *scrollView;
@property(nonatomic, retain) NSTableView *tableView;
@property(nonatomic, retain) NSTableColumn *column;
@end

@implementation CommandHistoryView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.hasHorizontalScroller = NO;
        [self addSubview:_scrollView];
        
        NSSize tableViewSize =
            [NSScrollView contentSizeForFrameSize:_scrollView.frame.size
                            hasHorizontalScroller:NO
                              hasVerticalScroller:YES
                                       borderType:[_scrollView borderType]];
        
        NSRect tableViewFrame = NSMakeRect(0, 0, tableViewSize.width, tableViewSize.height);
        _tableView = [[NSTableView alloc] initWithFrame:tableViewFrame];
        _tableView.rowHeight = kRowHeight;
        _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleSourceList;
        _tableView.allowsColumnResizing = NO;
        _tableView.allowsColumnReordering = NO;
        _tableView.allowsColumnSelection = NO;
        _tableView.allowsEmptySelection = YES;
        _tableView.allowsMultipleSelection = NO;
        _tableView.allowsTypeSelect = NO;
        _tableView.backgroundColor = [NSColor whiteColor];
        
        _column = [[NSTableColumn alloc] initWithIdentifier:@"tags"];
        [_column setEditable:NO];
        [_tableView addTableColumn:_column];
        
        [_scrollView setDocumentView:_tableView];
        
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.headerView = nil;
        
        [_tableView sizeLastColumnToFit];
        _scrollView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    return self;
}

#pragma mark - NSTableViewDelegate

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return _commands.count;
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                row:(NSInteger)rowIndex {
    return _commands[rowIndex];
}

#pragma mark - APIs

- (void)setCommands:(NSArray *)commands {
    [_commands autorelease];
    _commands = [commands retain];
    [_tableView reloadData];
}

- (NSSize)desiredSize {
    NSSize size;
    size.height = [[_scrollView contentView] documentRect].size.height;
    size.width = 200;  // Seems impossible to get the ideal width for a column.
    return size;
}

- (BOOL)wantsKeyDown:(NSEvent *)event {
    return NO;  // TODO
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
    unsigned int modflag;
    unsigned short keycode;
    modflag = [theEvent modifierFlags];
    keycode = [theEvent keyCode];
    
    const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
    // TODO(georgen): Not getting normal keycodes here, but 125 and 126 are up and down arrows.
    // This is a pretty ugly hack. Also, calling keyDown from here is probably not cool.
    BOOL handled = NO;
    if (!(mask & modflag) && (keycode == 125 || keycode == 126)) {
        NSInteger index = [_tableView selectedRow];
        if (keycode == 126) {
            // up
            if (index >= 0) {
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index - 1] byExtendingSelection:NO];
            }
        } else {
            // down
            index++;
            if (index < _commands.count) {
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index ] byExtendingSelection:NO];
            }
        }
        return YES;
    } else {
        return NO;
    }
}

@end

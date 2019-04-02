//
//  iTermPreferencesSearchEngineResultsWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/19.
//

#import "iTermPreferencesSearchEngineResultsWindowController.h"
#import "NSTextField+iTerm.h"

@interface iTermPreferencesSearchEngineResultsWindowController ()<NSTableViewDelegate, NSTableViewDataSource>

@end

@implementation iTermPreferencesSearchEngineResultsWindowController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSVisualEffectView *_visualEffectView;
}

- (void)windowDidLoad {
    if (@available(macOS 10.14, *)) {
        _visualEffectView.material = NSVisualEffectMaterialContentBackground;
    }
    self.window.opaque = NO;
    self.window.backgroundColor = [NSColor clearColor];
    [self updateFrameAndAlpha];
}

- (void)setDocuments:(NSArray<iTermPreferencesSearchDocument *> *)documents {
    _documents = [documents copy];
    [_tableView reloadData];
    [self updateFrameAndAlpha];
}

- (void)updateFrameAndAlpha {
    NSRect frame = self.window.frame;
    NSInteger rows = _documents.count;
    const NSInteger MAX_ROWS = 20;
    const NSInteger rowsToShow = MIN(rows, MAX_ROWS);
    CGFloat desiredTableViewHeight = (_tableView.rowHeight + _tableView.intercellSpacing.height) * rowsToShow;
    NSScrollView *scrollView = _tableView.enclosingScrollView;
    const CGFloat desiredContentHeight = [NSScrollView frameSizeForContentSize:NSMakeSize(100, desiredTableViewHeight)
                                                       horizontalScrollerClass:nil
                                                         verticalScrollerClass:scrollView.verticalScroller.class
                                                                    borderType:scrollView.borderType
                                                                   controlSize:NSControlSizeRegular
                                                                 scrollerStyle:scrollView.scrollerStyle].height;
    CGFloat desiredHeight = [NSPanel frameRectForContentRect:NSMakeRect(0, 0, 100, desiredContentHeight)
                                                   styleMask:self.window.styleMask].size.height;
    if (_documents.count == 0) {
        self.window.alphaValue = 0;
        return;
    }
    const BOOL wasVisible = (self.window.alphaValue == 1);
    if (frame.size.height != desiredHeight) {
        CGFloat changeInHeight = desiredHeight - frame.size.height;
        frame.size.height = desiredHeight;
        frame.origin.y -= changeInHeight;

        [self.window setFrame:frame display:YES animate:NO];
    }
    if (!wasVisible) {
        self.window.alphaValue = 1;
    }
}

- (iTermPreferencesSearchDocument *)selectedDocument {
    NSInteger row = _tableView.selectedRow;
    if (row < 0) {
        return  nil;
    } else {
        return self.documents[row];
    }
}
#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _documents.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *const identifier = @"Search Result";
    NSTextField *view = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!view) {
        view = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        view.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    view.stringValue = _documents[row].displayName;
    return view;
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self.delegate preferencesSearchEngineResultsDidSelectDocument:self.selectedDocument];
}

#pragma mark - Actions

- (IBAction)action:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0) {
        [self.delegate preferencesSearchEngineResultsDidActivateDocument:self.documents[row]];
    }
}

- (void)moveDown:(id)sender {
    NSInteger row = _tableView.selectedRow + 1;
    if (row < _documents.count) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:row];
    }
}

- (void)moveUp:(id)sender {
    NSInteger row = _tableView.selectedRow - 1;
    if (row >= 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:row];
    }
}

- (void)insertNewline:(nullable id)sender {
    [self action:sender];
}

@end

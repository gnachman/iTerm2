//
//  NSTableView+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import "NSTableView+iTerm.h"

#import <AppKit/AppKit.h>
#import "NSTableColumn+iTerm.h"

@interface iTermTableCellViewWithTextField: NSTableCellView
@end

@implementation iTermTableCellViewWithTextField {
    NSString *_identifier;
}

- (instancetype)initWithFrame:(NSRect)frameRect
                   identifier:(NSString *)identifier
                         font:(NSFont *)font
                        value:(id)value {
    self = [super initWithFrame:frameRect];
    if (self) {
        _identifier = [identifier copy];
        [self setFont:font value:value];
    }
    return self;
}

- (void)setFont:(NSFont *)font value:(id)value {
    NSTextField *text = [[NSTextField alloc] init];
    if (font) {
        text.font = font;
    }
    text.bezeled = NO;
    text.editable = NO;
    text.selectable = NO;
    text.drawsBackground = NO;
    text.identifier = [_identifier stringByAppendingString:@"_TextField"];
    text.lineBreakMode = NSLineBreakByTruncatingTail;

    self.textField = text;
    [self addSubview:text];
    self.textField.frame = self.bounds;
    [self updateTextFieldFrame];
    if ([value isKindOfClass:[NSAttributedString class]]) {
        text.attributedStringValue = value;
        text.toolTip = [value string];
    } else if ([value isKindOfClass:[NSString class]]) {
        text.stringValue = value;
        text.toolTip = value;
    } else {
        assert(NO);
    }
}

- (NSSize)fittingSize {
    NSSize size = self.textField.fittingSize;
    size.height += 4;
    return size;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    [self updateTextFieldFrame];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self updateTextFieldFrame];
}

- (void)updateTextFieldFrame {
    const CGFloat verticalPadding = 2.0;
    CGFloat horizontalInset = 0;
    if (@available(macOS 10.16, *)) {
        horizontalInset = 0;
    } else {
        horizontalInset = 2;
    }
    NSRect frame = self.bounds;
    frame.origin.x += horizontalInset;
    frame.size.width -= horizontalInset * 2;
    frame.origin.y += verticalPadding;
    frame.size.height -= verticalPadding * 2;
    self.textField.frame = frame;
}

@end
@implementation NSTableView (iTerm)

+ (instancetype)toolbeltTableViewInScrollview:(NSScrollView *)scrollView
                               fixedRowHeight:(CGFloat)fixedRowHeight
                                        owner:(NSView<NSTableViewDelegate,NSTableViewDataSource> *)owner {
    NSSize contentSize = [scrollView contentSize];
    NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    if (@available(macOS 10.16, *)) {
        tableView.style = NSTableViewStyleInset;
    }
    NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
    [valueColumn setEditable:NO];
    [tableView addTableColumn:valueColumn];

    tableView.columnAutoresizingStyle = NSTableViewSequentialColumnAutoresizingStyle;

    tableView.headerView = nil;
    tableView.dataSource = owner;
    tableView.delegate = owner;
    tableView.intercellSpacing = NSMakeSize(tableView.intercellSpacing.width, 0);
    // I would like to use automatic row heights but it confuses autolayout and I am done with fighting with autolayout.
    if (fixedRowHeight) {
        tableView.rowHeight = fixedRowHeight;
    }

    [tableView setAutoresizingMask:NSViewWidthSizable];

    [scrollView setDocumentView:tableView];
    [owner addSubview:scrollView];

    [tableView sizeToFit];
    [tableView sizeLastColumnToFit];

    [tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
    tableView.backgroundColor = [NSColor clearColor];
    return tableView;
}

- (void)it_performUpdateBlock:(void (^NS_NOESCAPE)(void))block {
    [self beginUpdates];
    block();
    [self endUpdates];
}

- (NSTableCellView *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier font:(NSFont *)font string:(NSString *)string {
    return [self newTableCellViewWithTextFieldUsingIdentifier:identifier font:font value:string];
}

- (NSTableCellView *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier attributedString:(NSAttributedString *)attributedString {
    return [self newTableCellViewWithTextFieldUsingIdentifier:identifier font:nil value:attributedString];
}

- (NSTableCellView *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
                                                             font:(NSFont *)font
                                                            value:(id)value {
    iTermTableCellViewWithTextField *cell = [self makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[iTermTableCellViewWithTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 18)
                                                           identifier:identifier
                                                                 font:font
                                                                value:value];
    }
    if (cell.textField) {
        return cell;
    }
    [cell setFont:font value:value];
    return cell;
}

+ (CGFloat)heightForTextCellUsingFont:(NSFont *)font {
    NSTableCellView *cell = [[iTermTableCellViewWithTextField alloc] initWithFrame:NSZeroRect
                                                                        identifier:@"iTermPhonyCell"
                                                                              font:font
                                                                             value:@"M"];
    return [cell fittingSize].height;
}

@end

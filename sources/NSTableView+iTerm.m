//
//  NSTableView+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import "NSTableView+iTerm.h"

#import <AppKit/AppKit.h>
#import "NSTableColumn+iTerm.h"

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
    NSTableCellView *cell = [self makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 18)];
    }
    if (cell.textField) {
        return cell;
    }
    [NSTableView initializeTextCell:cell withIdentifier:identifier font:font value:value];
    return cell;
}

+ (CGFloat)heightForTextCellUsingFont:(NSFont *)font {
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    [NSTableView initializeTextCell:cell
                     withIdentifier:[NSString stringWithFormat:@"Measure font %@ %@", font.displayName, @(font.pointSize)]
                               font:font
                              value:@"M"];
    return [cell fittingSize].height;
}

+ (void)initializeTextCell:(NSTableCellView *)cell withIdentifier:(NSString *)identifier font:(NSFont *)font value:(id)value {
    NSTextField *text = [[NSTextField alloc] init];
    if (font) {
        text.font = font;
    }
    text.bezeled = NO;
    text.editable = NO;
    text.selectable = NO;
    text.drawsBackground = NO;
    text.identifier = [identifier stringByAppendingString:@"_TextField"];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.lineBreakMode = NSLineBreakByTruncatingTail;

    cell.textField = text;
    [cell addSubview:text];
    const CGFloat verticalPadding = 2.0;
    CGFloat horizontalInset = 0;
    if (@available(macOS 10.16, *)) {
        horizontalInset = 0;
    } else {
        horizontalInset = 2;
    }
    [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
                                                     attribute:NSLayoutAttributeTop
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:cell
                                                     attribute:NSLayoutAttributeTop
                                                    multiplier:1
                                                      constant:verticalPadding]];
    [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
                                                     attribute:NSLayoutAttributeBottom
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:cell
                                                     attribute:NSLayoutAttributeBottom
                                                    multiplier:1
                                                      constant:-verticalPadding]];
    [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
                                                     attribute:NSLayoutAttributeLeft
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:cell
                                                     attribute:NSLayoutAttributeLeft
                                                    multiplier:1
                                                      constant:horizontalInset]];
    [cell addConstraint:[NSLayoutConstraint constraintWithItem:text
                                                     attribute:NSLayoutAttributeRight
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:cell
                                                     attribute:NSLayoutAttributeRight
                                                    multiplier:1
                                                      constant:horizontalInset]];
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

@end

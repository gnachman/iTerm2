//
//  NSTableView+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import "NSTableView+iTerm.h"

#import <AppKit/AppKit.h>
#import "iTermKeyboardNavigatableTableView.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSView+RecursiveDescription.h"

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

@interface iTermToolbeltOutlineView: iTermAutomaticKeyboardNavigatableOutlineView
@end

// This just declares the selector so I can use @selector without it complaining. There is no implementation.
@interface iTermPlaceholderForNSButtonCellSelectors
- (NSRect)original_imageRectForBounds:(NSRect)rect;
@end

// Custom implementation for imageRectForBounds:
static NSRect iTermOutlineViewDisclosureButtonImageRectForBounds(id self, SEL _cmd, NSRect bounds) {
    NSRect (*originalFunc)(id, SEL, NSRect) = (void *)[self methodForSelector:@selector(original_imageRectForBounds:)];

    NSRect imageRect = originalFunc(self, _cmd, bounds);
    CGFloat verticalOffset = (NSHeight(bounds) - NSHeight(imageRect)) / 2.0;
    imageRect.origin.y = NSMinY(bounds) + verticalOffset;
    return imageRect;
}

@implementation iTermToolbeltOutlineView

// There has to be a better way to do outline views with attributed strings, but I can't find it.
// They don't draw the disclosure button vertically centered in the cell. You can't change the button's
// cell without breaking basic functionality (it uses a private subclass of NSButtonCell).
// All this silliness is just replacing NSOutlineButtonCell.imageRectForBounds(:_) with a replacement
// implementation that vertically centers the image using iTermOutlineViewDisclosureButtonImageRectForBounds.
- (__kindof NSView *)makeViewWithIdentifier:(NSUserInterfaceItemIdentifier)identifier owner:(id)owner {
    NSView *view = [super makeViewWithIdentifier:identifier owner:owner];
    if ([identifier isEqualToString:NSOutlineViewDisclosureButtonKey]) {
        NSButton *button = [NSButton castFrom:view];
        NSButtonCell *cell = button.cell;
        if (cell && ![cell respondsToSelector:@selector(original_imageRectForBounds:)]) {
            // Create a unique subclass name for this cell instance.
            NSString *subclassName = @"NSOutlineButtonCell_iTermCustomImageRect";
            Class subclass = NSClassFromString(subclassName);
            if (!subclass) {
                subclass = objc_allocateClassPair([cell class], [subclassName UTF8String], 0);
                SEL sel = @selector(imageRectForBounds:);
                Method method = class_getInstanceMethod([cell class], sel);
                const char *types = method_getTypeEncoding(method);
                IMP originalIMP = method_getImplementation(method);

                // Save the original IMP under a new selector.
                class_addMethod(subclass, @selector(original_imageRectForBounds:), originalIMP, types);
                // Add our custom implementation for imageRectForBounds:
                class_addMethod(subclass, sel, (IMP)iTermOutlineViewDisclosureButtonImageRectForBounds, types);
                objc_registerClassPair(subclass);
            }
            // Change only this cell's class.
            object_setClass(cell, subclass);
        }
    }
    return view;
}

@end


@implementation NSOutlineView(iTerm)

+ (instancetype)toolbeltOutlineViewInScrollview:(NSScrollView *)scrollView
                                 fixedRowHeight:(CGFloat)fixedRowHeight
                                          owner:(NSView<NSOutlineViewDelegate, NSOutlineViewDataSource> *)owner {
    NSSize contentSize = [scrollView contentSize];
    NSOutlineView *outlineView = [[iTermToolbeltOutlineView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    if (@available(macOS 10.16, *)) {
        outlineView.style = NSTableViewStyleInset;
    }
    NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
    [valueColumn setEditable:NO];
    [outlineView addTableColumn:valueColumn];

    outlineView.columnAutoresizingStyle = NSTableViewSequentialColumnAutoresizingStyle;

    outlineView.headerView = nil;
    outlineView.dataSource = owner;
    outlineView.delegate = owner;
    outlineView.intercellSpacing = NSMakeSize(outlineView.intercellSpacing.width, 0);
    // I would like to use automatic row heights but it confuses autolayout and I am done with fighting with autolayout.
    if (fixedRowHeight) {
        outlineView.rowHeight = fixedRowHeight;
    }

    [outlineView setAutoresizingMask:NSViewWidthSizable];

    [scrollView setDocumentView:outlineView];
    [owner addSubview:scrollView];

    [outlineView sizeToFit];
    [outlineView sizeLastColumnToFit];

    [outlineView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
    outlineView.backgroundColor = [NSColor clearColor];
    return outlineView;
}

@end

@implementation NSTableView (iTerm)

+ (instancetype)toolbeltTableViewInScrollview:(NSScrollView *)scrollView
                               fixedRowHeight:(CGFloat)fixedRowHeight
                                        owner:(NSView<NSTableViewDelegate,NSTableViewDataSource> *)owner {
    NSSize contentSize = [scrollView contentSize];
    NSTableView *tableView = [[self alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
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

- (iTermTableCellViewWithTextField *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier font:(NSFont *)font string:(NSString *)string {
    return [self newTableCellViewWithTextFieldUsingIdentifier:identifier font:font value:string];
}

- (iTermTableCellViewWithTextField *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier attributedString:(NSAttributedString *)attributedString {
    return [self newTableCellViewWithTextFieldUsingIdentifier:identifier font:nil value:attributedString];
}

- (iTermTableCellViewWithTextField *)newTableCellViewWithTextFieldUsingIdentifier:(NSString *)identifier
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

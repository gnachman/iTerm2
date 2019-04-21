//
//  TransferrableFileMenuItemView.m
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import "TransferrableFileMenuItemView.h"
#import "NSStringITerm.h"

const CGFloat rightMargin = 5;

@interface TransferrableFileMenuItemView ()
// This is used as part of the bug workaround in sanityCheckSiblings to ensure we don't try to
// redraw a view more than once.
@property(nonatomic, assign) BOOL drawPending;
@end

@implementation TransferrableFileMenuItemView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _progressIndicator = [[iTermProgressIndicator alloc] initWithFrame:NSMakeRect(5,
                                                                                      17,
                                                                                      frameRect.size.width - 10,
                                                                                      10)];
        [self addSubview:_progressIndicator];
    }
    return self;
}

- (void)dealloc {
    [_filename release];
    [_subheading release];
    [_statusMessage release];
    [_progressIndicator release];
    [super dealloc];
}

// Works around an OS bug. If the menu is closed with an item selected and then reopened, the
// item remains selected. If you then select a different item, the originally selected item won't
// get redrawn!
- (void)sanityCheckSiblings
{
    for (NSMenuItem *item in [[[self enclosingMenuItem] menu] itemArray]) {
        if (item.view == self) {
            continue;
        }
        if ([item.view isKindOfClass:[TransferrableFileMenuItemView class]]) {
            TransferrableFileMenuItemView *view = (TransferrableFileMenuItemView *)item.view;
            if (!view.drawPending &&
                view.lastDrawnHighlighted &&
                ![[view enclosingMenuItem] isHighlighted]) {
                view.drawPending = YES;
                [view setNeedsDisplay:YES];
            }
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
    NSColor *textColor;
    NSColor *grayColor;

    [self sanityCheckSiblings];
    self.drawPending = NO;
    if ([[self enclosingMenuItem] isHighlighted]) {
        self.lastDrawnHighlighted = YES;
        [[NSColor selectedMenuItemColor] set];
        textColor = [NSColor selectedMenuItemTextColor];
        if (@available(macOS 10.14, *)) {
            grayColor = [NSColor alternateSelectedControlTextColor];
        } else {
            grayColor = [NSColor lightGrayColor];
        }
    } else {
        self.lastDrawnHighlighted = NO;
        if (@available(macOS 10.14, *)) {
            textColor = [NSColor textColor];
            grayColor = [[NSColor textColor] colorWithAlphaComponent:0.8];
            [[NSColor clearColor] set];
        } else {
            textColor = [NSColor blackColor];
            grayColor = [NSColor grayColor];
            [[NSColor whiteColor] set];
        }
    }
    NSRectFill(dirtyRect);

    NSMutableParagraphStyle *leftAlignStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [leftAlignStyle setAlignment:NSTextAlignmentLeft];
    [leftAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    NSMutableParagraphStyle *rightAlignStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [rightAlignStyle setAlignment:NSTextAlignmentRight];
    [rightAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    const CGFloat leftMargin = 5;
    NSFont *theFont = [NSFont systemFontOfSize:14];
    NSFont *smallFont = [NSFont systemFontOfSize:10];
    NSDictionary *filenameAttributes = @{ NSParagraphStyleAttributeName: leftAlignStyle,
                                          NSFontAttributeName: theFont,
                                          NSForegroundColorAttributeName: textColor };
    NSDictionary *sizeAttributes = @{ NSParagraphStyleAttributeName: rightAlignStyle,
                                      NSFontAttributeName: smallFont,
                                      NSForegroundColorAttributeName: grayColor };
    NSDictionary *smallGrayAttributes = @{ NSForegroundColorAttributeName: grayColor,
                                           NSParagraphStyleAttributeName: leftAlignStyle,
                                           NSFontAttributeName: smallFont};
    const CGFloat textHeight = [_filename sizeWithAttributes:filenameAttributes].height;
    NSString *sizeString;
    if (_size >= 0) {
        sizeString =
            [NSString stringWithFormat:@"%@ of %@",
                [NSString it_formatBytes:_bytesTransferred],
                [NSString it_formatBytes:_size]];
    } else {
        sizeString = @"";
    }
    const CGFloat smallTextHeight = [sizeString sizeWithAttributes:sizeAttributes].height;

    [textColor set];

    CGFloat topMargin = 1;
    CGFloat topY = self.bounds.size.height - textHeight - topMargin;
    CGFloat bottomY = 1;

    // Draw file name
    NSRect filenameRect = NSMakeRect(leftMargin,
                                     topY,
                                     self.bounds.size.width - rightMargin,
                                     textHeight);

    [_filename drawInRect:filenameRect
           withAttributes:filenameAttributes];

    // Draw subheading
    NSRect subheadingRect = NSMakeRect(leftMargin,
                                       topY - smallTextHeight - 1,
                                       self.bounds.size.width - rightMargin,
                                       smallTextHeight);
    [_subheading drawInRect:subheadingRect withAttributes:smallGrayAttributes];

    // Draw status label
    if (_statusMessage) {
        [_statusMessage drawInRect:NSMakeRect(leftMargin,
                                              bottomY,
                                              self.bounds.size.width - rightMargin,
                                              smallTextHeight)
                    withAttributes:smallGrayAttributes];
    }

    // Draw size
    [sizeString drawInRect:NSMakeRect(0,
                                      bottomY,
                                      self.bounds.size.width - 5,
                                      smallTextHeight)
            withAttributes:sizeAttributes];
}

@end

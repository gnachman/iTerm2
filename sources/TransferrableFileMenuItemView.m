//
//  TransferrableFileMenuItemView.m
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import "TransferrableFileMenuItemView.h"
#import "NSStringITerm.h"

const CGFloat progressIndicatorHeight = 6;

static CGFloat TransferrableFileMenuItemViewLeftMargin(void) {
    if (@available(macOS 10.16, *)) {
        return 14;
    } else {
        return 20;
    }
}

static CGFloat TransferrableFileMenuItemViewRightMargin(void) {
    if (@available(macOS 10.16, *)) {
        return 14;
    } else {
        return 8;
    }
}

@interface TransferrableFileMenuItemView ()
// This is used as part of the bug workaround in sanityCheckSiblings to ensure we don't try to
// redraw a view more than once.
@property(nonatomic, assign) BOOL drawPending;
@end

@implementation TransferrableFileMenuItemView {
    __weak NSVisualEffectView *_effectView;
}

- (instancetype)initWithFrame:(NSRect)frameRect effectView:(NSVisualEffectView *)effectView {
    self = [super initWithFrame:frameRect];
    if (self) {
        _effectView = effectView;
        _progressIndicator = [[iTermProgressIndicator alloc] initWithFrame:NSMakeRect(TransferrableFileMenuItemViewLeftMargin(),
                                                                                      17,
                                                                                      frameRect.size.width - TransferrableFileMenuItemViewLeftMargin() - TransferrableFileMenuItemViewRightMargin(),
                                                                                      progressIndicatorHeight)];
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
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    NSColor *textColor;
    NSColor *grayColor;

    [self sanityCheckSiblings];
    self.drawPending = NO;

    if ([[self enclosingMenuItem] isHighlighted]) {
        self.lastDrawnHighlighted = YES;
        [[NSColor selectedMenuItemColor] set];
        textColor = [NSColor selectedMenuItemTextColor];
        grayColor = [NSColor alternateSelectedControlTextColor];
        _effectView.state = NSVisualEffectStateActive;
        _effectView.hidden = NO;
    } else {
        self.lastDrawnHighlighted = NO;
        textColor = [NSColor textColor];
        grayColor = [[NSColor textColor] colorWithAlphaComponent:0.8];
        [[NSColor clearColor] set];
        _effectView.state = NSVisualEffectStateInactive;
        _effectView.hidden = YES;
    }

    NSMutableParagraphStyle *leftAlignStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [leftAlignStyle setAlignment:NSTextAlignmentLeft];
    [leftAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    NSMutableParagraphStyle *rightAlignStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [rightAlignStyle setAlignment:NSTextAlignmentRight];
    [rightAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];

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

    CGFloat topMargin = 3;
    CGFloat topY = self.bounds.size.height - textHeight - topMargin;
    CGFloat bottomY = 3;

    // Draw file name
    NSRect filenameRect = NSMakeRect(TransferrableFileMenuItemViewLeftMargin(),
                                     topY,
                                     self.bounds.size.width - TransferrableFileMenuItemViewLeftMargin() - TransferrableFileMenuItemViewRightMargin(),
                                     textHeight);

    [_filename drawInRect:filenameRect
           withAttributes:filenameAttributes];

    // Draw subheading
    NSRect subheadingRect = NSMakeRect(TransferrableFileMenuItemViewLeftMargin(),
                                       topY - smallTextHeight - 1,
                                       self.bounds.size.width - TransferrableFileMenuItemViewLeftMargin() - TransferrableFileMenuItemViewRightMargin(),
                                       smallTextHeight);
    [_subheading drawInRect:subheadingRect withAttributes:smallGrayAttributes];

    // Draw status label
    if (_statusMessage) {
        [_statusMessage drawInRect:NSMakeRect(TransferrableFileMenuItemViewLeftMargin(),
                                              bottomY,
                                              self.bounds.size.width - TransferrableFileMenuItemViewLeftMargin() - TransferrableFileMenuItemViewRightMargin(),
                                              smallTextHeight)
                    withAttributes:smallGrayAttributes];
    }

    // Draw size
    [sizeString drawInRect:NSMakeRect(TransferrableFileMenuItemViewLeftMargin(),
                                      bottomY,
                                      self.bounds.size.width - TransferrableFileMenuItemViewRightMargin() - TransferrableFileMenuItemViewLeftMargin(),
                                      smallTextHeight)
            withAttributes:sizeAttributes];
}

@end

//
//  TransferrableFileMenuItemView.m
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import "TransferrableFileMenuItemView.h"

const CGFloat rightMargin = 50;

@implementation TransferrableFileMenuItemView

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(5, 15, frameRect.size.width - 10, 10)];
        [_progressIndicator setStyle:NSProgressIndicatorBarStyle];
        [_progressIndicator setIndeterminate:NO];
        [_progressIndicator setBezeled:YES];
        [_progressIndicator setMinValue:0];
        [_progressIndicator setMaxValue:1];
        _progressIndicator.frame = NSMakeRect(5,
                                              17,
                                              frameRect.size.width - 10,
                                              _progressIndicator.bounds.size.height);
        [self addSubview:_progressIndicator];
    }
    return self;
}

- (void)dealloc {
    [_filename release];
    [_statusMessage release];
    [_progressIndicator release];
    [super dealloc];
}

- (NSString *)formattedSize:(long long)size {
    if (size < 0) {
        return @"Unknown size";
    } else if (size < 1024) {
        return [NSString stringWithFormat:@"%lld bytes", size];
    } else if (size < 1024 * 1024) {
        return [NSString stringWithFormat:@"%lld KB", size / 1024];
    } else if (size < 1024 * 1024 * 1024) {
        return [NSString stringWithFormat:@"%0.1f MB", size / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%0.2f GB", size / (1024.0 * 1024.0 * 1024.0)];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
    NSColor *textColor;
    NSColor *grayColor;
    
    if ([[self enclosingMenuItem] isHighlighted]) {
        [[NSColor selectedMenuItemColor] set];
        textColor = [NSColor selectedMenuItemTextColor];
        grayColor = [NSColor lightGrayColor];
    } else {
        [[NSColor whiteColor] set];
        textColor = [NSColor blackColor];
        grayColor = [NSColor grayColor];
    }
    NSRectFill(dirtyRect);

    NSMutableParagraphStyle *leftAlignStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [leftAlignStyle setAlignment:NSLeftTextAlignment];

    NSMutableParagraphStyle *rightAlignStyle =
        [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [rightAlignStyle setAlignment:NSRightTextAlignment];

    // Draw filename label
    const CGFloat leftMargin = 5;
    const CGFloat y = NSMaxY(_progressIndicator.frame) + 5;
    NSFont *theFont = [NSFont systemFontOfSize:14];
    NSFont *smallFont = [NSFont systemFontOfSize:10];
    NSDictionary *filenameAttributes = @{ NSParagraphStyleAttributeName: leftAlignStyle,
                                          NSFontAttributeName: theFont,
                                          NSForegroundColorAttributeName: textColor };
    NSDictionary *sizeAttributes = @{ NSParagraphStyleAttributeName: rightAlignStyle,
                                      NSFontAttributeName: smallFont,
                                      NSForegroundColorAttributeName: grayColor };
    const CGFloat textHeight = [_filename sizeWithAttributes:filenameAttributes].height;
    NSString *sizeString =
        [NSString stringWithFormat:@"%@ of %@",
            [self formattedSize:_size * [_progressIndicator doubleValue]],
            [self formattedSize:_size]];
    const CGFloat smallTextHeight = [sizeString sizeWithAttributes:sizeAttributes].height;

    [[NSColor blackColor] set];

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

    // Draw status label
    if (_statusMessage) {
        [_statusMessage drawInRect:NSMakeRect(leftMargin,
                                              bottomY,
                                              self.bounds.size.width - rightMargin,
                                              smallTextHeight)
                    withAttributes:@{ NSForegroundColorAttributeName: grayColor,
                                      NSParagraphStyleAttributeName: leftAlignStyle,
                                      NSFontAttributeName: smallFont}];
    }
    
    // Draw size
    [sizeString drawInRect:NSMakeRect(0,
                                      bottomY,
                                      self.bounds.size.width - 5,
                                      smallTextHeight)
            withAttributes:sizeAttributes];
}

@end

//
//  iTermBadgeLabel.m
//  iTerm2
//
//  Created by George Nachman on 7/7/15.
//
//

#import "iTermBadgeLabel.h"
#import "DebugLogging.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"

@interface iTermBadgeLabel()
@property(nonatomic, retain) NSImage *image;
@end

@implementation iTermBadgeLabel {
    NSMutableDictionary<NSString *, NSImage *> *_images;
    BOOL _dirty;
    NSMutableParagraphStyle *_paragraphStyle;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        _paragraphStyle.alignment = NSTextAlignmentRight;
        _minimumPointSize = 4;
        _maximumPointSize = 100;
        _images = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setFillColor:(NSColor *)fillColor {
    if ([fillColor isEqual:_fillColor] || fillColor == _fillColor) {
        return;
    }
    _fillColor = fillColor;
    [self setDirty:YES];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    if ([backgroundColor isEqual:_backgroundColor] || backgroundColor == _backgroundColor) {
        return;
    }
    _backgroundColor = backgroundColor;
    [self setDirty:YES];
}

- (void)setStringValue:(NSString *)stringValue {
    if ([stringValue isEqual:_stringValue] || stringValue == _stringValue) {
        return;
    }
    _stringValue = [stringValue copy];
    [self setDirty:YES];
}

- (void)setViewSize:(NSSize)viewSize {
    if (NSEqualSizes(_viewSize, viewSize)) {
        return;
    }
    _viewSize = viewSize;
    [self setDirty:YES];
}

- (NSImage *)imageForColorSpace:(NSColorSpace *)colorSpace {
    if (!_fillColor) {
        return _images[colorSpace.localizedName];
    }
    if (!_stringValue) {
        return _images[colorSpace.localizedName];
    }
    if (NSEqualSizes(_viewSize, NSZeroSize)) {
        return _images[colorSpace.localizedName];
    }
    if (!_image) {
        _images[colorSpace.localizedName] = [self freshlyComputedImageForColorSpace:colorSpace];
    }
    return _images[colorSpace.localizedName];
}

#pragma mark - Private

- (void)setDirty:(BOOL)dirty {
    _dirty = dirty;
    if (dirty) {
        self.image = nil;
    }
}

// Compute the best point size and return a new image of the badge. Returns nil if the badge
// is empty or zero pixels.r
- (NSImage *)freshlyComputedImageForColorSpace:(NSColorSpace *)colorSpace {
    DLog(@"Recompute badge self=%p, label=“%@”, color=%@, view size=%@, colorSpace=%@. Called from:\n%@",
         self,
         _stringValue,
         _fillColor,
         NSStringFromSize(_viewSize),
         colorSpace,
         [NSThread callStackSymbols]);

    if ([_stringValue length]) {
        return [self imageWithPointSize:self.idealPointSize colorSpace:colorSpace];
    }

    return nil;
}

// Returns an image from the current text with the given |attributes|, or nil if the image would
// have 0 pixels.
- (NSImage *)imageWithPointSize:(CGFloat)pointSize colorSpace:(NSColorSpace *)colorSpace {
    NSDictionary *attributes = [self attributesWithPointSize:pointSize];
    NSMutableDictionary *temp = [attributes mutableCopy];
    temp[NSStrokeColorAttributeName] = [_backgroundColor colorWithAlphaComponent:1];
    BOOL truncated;
    NSSize sizeWithFont = [self sizeWithAttributes:temp truncated:&truncated];
    if (sizeWithFont.width <= 0 || sizeWithFont.height <= 0) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithSize:sizeWithFont];
    [image lockFocus];
    /*
    [_stringValue it_drawInRect:NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height)
                     attributes:temp
                          alpha:_fillColor.alphaComponent];
     */
    CGFloat cs[4] = { 0.25, 0.25, 0.25, 1.0 };
    [[NSColor colorWithColorSpace:[NSColorSpace sRGBColorSpace] components:cs count:4] set];
    NSRectFill(NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height));
    [image unlockFocus];
//    return [image it_imageInColorSpace:colorSpace];
    return image;
/*
    NSImage *wtf = [[NSImage alloc] initWithSize:sizeWithFont];
    [wtf lockFocus];
    [[NSColor colorWithSRGBRed:0.25 green:0.25 blue:0.25 alpha:0.9] set];
    NSRectFill(NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height));
    [[NSColor greenColor] set];
    NSFrameRect(NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height));
    [wtf unlockFocus];
    return [wtf it_imageInColorSpace:colorSpace];
 */
}

// Attributed string attributes for a given font point size.
- (NSDictionary *)attributesWithPointSize:(CGFloat)pointSize {
    NSDictionary *attributes = @{ NSFontAttributeName: [self.delegate badgeLabelFontOfSize:pointSize],
                                  NSForegroundColorAttributeName: _fillColor,
                                  NSParagraphStyleAttributeName: _paragraphStyle,
                                  NSStrokeWidthAttributeName: @-2 };
    return attributes;
}

// Size of the image resulting from drawing an attributed string with |attributes|.
- (NSSize)sizeWithAttributes:(NSDictionary *)attributes truncated:(BOOL *)truncated {
    NSSize size = self.maxSize;
    size.height = CGFLOAT_MAX;
    NSRect bounds = [_stringValue it_boundingRectWithSize:self.maxSize
                                               attributes:attributes
                                                truncated:truncated];
    return bounds.size;
}

// Max size of image in points within the containing view.
- (NSSize)maxSize {
    const NSSize fractions = [self.delegate badgeLabelSizeFraction];
    double maxWidth = MIN(1.0, MAX(0.01, fractions.width));
    double maxHeight = MIN(1.0, MAX(0.0, fractions.height));
    NSSize maxSize = _viewSize;
    maxSize.width *= maxWidth;
    maxSize.height *= maxHeight;
    return maxSize;
}

- (CGFloat)idealPointSize {
    DLog(@"Computing ideal point size for badge");
    NSSize maxSize = self.maxSize;

    // Perform a binary search for the point size that best fits |maxSize|.
    CGFloat min = self.minimumPointSize;
    CGFloat max = self.maximumPointSize;
    int points = (min + max) / 2;
    int prevPoints = -1;
    NSSize sizeWithFont = NSZeroSize;
    while (points != prevPoints) {
        BOOL truncated;
        sizeWithFont = [self sizeWithAttributes:[self attributesWithPointSize:points] truncated:&truncated];
        DLog(@"Point size of %@ gives label size of %@", @(points), NSStringFromSize(sizeWithFont));
        if (truncated ||
            sizeWithFont.width > maxSize.width ||
            sizeWithFont.height > maxSize.height) {
            max = points;
        } else if (sizeWithFont.width < maxSize.width &&
                   sizeWithFont.height < maxSize.height) {
            min = points;
        }
        prevPoints = points;
        points = (min + max) / 2;
    }
    DLog(@"Using point size %@", @(points));
    return points;
}

@end

//
//  iTermBadgeLabel.m
//  iTerm2
//
//  Created by George Nachman on 7/7/15.
//
//

#import "iTermBadgeLabel.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSStringITerm.h"

@interface iTermBadgeLabel()
@property(nonatomic, retain) NSImage *image;
@end

@implementation iTermBadgeLabel {
    BOOL _dirty;
    NSMutableParagraphStyle *_paragraphStyle;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        _paragraphStyle.alignment = NSRightTextAlignment;
    }
    return self;
}

- (void)dealloc {
    [_fillColor release];
    [_backgroundColor release];
    [_stringValue release];
    [_image release];
    [_paragraphStyle release];

    [super dealloc];
}

- (void)setFillColor:(NSColor *)fillColor {
    if ([fillColor isEqual:_fillColor] || fillColor == _fillColor) {
        return;
    }
    [_fillColor autorelease];
    _fillColor = [fillColor retain];
    [self setDirty:YES];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    if ([backgroundColor isEqual:_backgroundColor] || backgroundColor == _backgroundColor) {
        return;
    }
    [_backgroundColor autorelease];
    _backgroundColor = [backgroundColor retain];
    [self setDirty:YES];
}

- (void)setStringValue:(NSString *)stringValue {
    if ([stringValue isEqual:_stringValue] || stringValue == _stringValue) {
        return;
    }
    [_stringValue autorelease];
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

- (NSImage *)image {
    if (_fillColor && _stringValue && !NSEqualSizes(_viewSize, NSZeroSize) && !_image) {
        _image = [[self freshlyComputedImage] retain];
    }
    return _image;
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
- (NSImage *)freshlyComputedImage {
    DLog(@"Recompute badge self=%p, label=“%@”, color=%@, view size=%@. Called from:\n%@",
         self,
         _stringValue,
         _fillColor,
         NSStringFromSize(_viewSize),
         [NSThread callStackSymbols]);

    if ([_stringValue length]) {
        return [self imageWithPointSize:self.idealPointSize];
    }

    return nil;
}

// Returns an image from the current text with the given |attributes|, or nil if the image would
// have 0 pixels.
- (NSImage *)imageWithPointSize:(CGFloat)pointSize {
    NSDictionary *attributes = [self attributesWithPointSize:pointSize];
    NSMutableDictionary *temp = [[attributes mutableCopy] autorelease];
    temp[NSStrokeColorAttributeName] = [_backgroundColor colorWithAlphaComponent:1];
    BOOL truncated;
    NSSize sizeWithFont = [self sizeWithAttributes:temp truncated:&truncated];
    if (sizeWithFont.width <= 0 || sizeWithFont.height <= 0) {
        return nil;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:sizeWithFont] autorelease];
    [image lockFocus];
    [_stringValue it_drawInRect:NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height)
                     attributes:temp];
    [image unlockFocus];

    NSImage *reducedAlphaImage = [[[NSImage alloc] initWithSize:sizeWithFont] autorelease];
    [reducedAlphaImage lockFocus];
    [image drawInRect:NSMakeRect(0, 0, image.size.width, image.size.height)
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:_fillColor.alphaComponent];
    [reducedAlphaImage unlockFocus];

    return reducedAlphaImage;
}

// Attributed string attributes for a given font point size.
- (NSDictionary *)attributesWithPointSize:(CGFloat)pointSize {
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSString *fontName = [iTermAdvancedSettingsModel badgeFont];
    NSFont *font;

    font = [NSFont fontWithName:fontName size:pointSize];
    if (!font) {
        font = [NSFont fontWithName:@"Helvetica" size:pointSize];
    }
    if ([iTermAdvancedSettingsModel badgeFontIsBold]) {
      font = [fontManager convertFont:font
                          toHaveTrait:NSBoldFontMask];
    }

    NSDictionary *attributes = @{ NSFontAttributeName: font,
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
    double maxWidth = MIN(1.0, MAX(0.01, [iTermAdvancedSettingsModel badgeMaxWidthFraction]));
    double maxHeight = MIN(1.0, MAX(0.0, [iTermAdvancedSettingsModel badgeMaxHeightFraction]));
    NSSize maxSize = _viewSize;
    maxSize.width *= maxWidth;
    maxSize.height *= maxHeight;
    return maxSize;
}

- (CGFloat)idealPointSize {
    DLog(@"Computing ideal point size for badge");
    NSSize maxSize = self.maxSize;

    // Perform a binary search for the point size that best fits |maxSize|.
    CGFloat min = 4;
    CGFloat max = 100;
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

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
    DLog(@"Recompute badge self=%p, label=%@, color=%@, view size=%@. Called from:\n%@",
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
    NSSize sizeWithFont = [self sizeWithAttributes:temp];
    if (sizeWithFont.width <= 0 && sizeWithFont.height <= 0) {
        return nil;
    }

    NSImage *image = [[[NSImage alloc] initWithSize:sizeWithFont] autorelease];
    [image lockFocus];
    [_stringValue drawWithRect:NSMakeRect(0, 0, sizeWithFont.width, sizeWithFont.height)
                       options:NSStringDrawingUsesLineFragmentOrigin
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
    NSArray *fonts = [[NSFontManager sharedFontManager] availableFontFamilies];
    NSString *fontName = [iTermAdvancedSettingsModel badgeFont];
    NSFont *font;
    if (![fonts containsObject:fontName]) {
      fontName = @"Helvetica";
    }
    font = [NSFont fontWithName:fontName size:pointSize];
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
- (NSSize)sizeWithAttributes:(NSDictionary *)attributes {
    NSSize size = self.maxSize;
    size.height = CGFLOAT_MAX;
    NSRect bounds = [_stringValue boundingRectWithSize:self.maxSize
                                               options:NSStringDrawingUsesLineFragmentOrigin
                                            attributes:attributes];
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
    NSSize maxSize = self.maxSize;

    // Perform a binary search for the point size that best fits |maxSize|.
    CGFloat min = 4;
    CGFloat max = 100;
    int points = (min + max) / 2;
    int prevPoints = -1;
    NSSize sizeWithFont = NSZeroSize;
    while (points != prevPoints) {
        sizeWithFont = [self sizeWithAttributes:[self attributesWithPointSize:points]];
        if (sizeWithFont.width > maxSize.width ||
            sizeWithFont.height > maxSize.height) {
            max = points;
        } else if (sizeWithFont.width < maxSize.width &&
                   sizeWithFont.height < maxSize.height) {
            min = points;
        }
        prevPoints = points;
        points = (min + max) / 2;
    }
    return points;
}

@end

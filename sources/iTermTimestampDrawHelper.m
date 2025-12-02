//
//  iTermTimestampDrawHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTimestampDrawHelper.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSColor+iTerm.h"
#import "NSFont+iTerm.h"
#import "RegexKitLite.h"

const CGFloat iTermTimestampGradientWidth = 20;

// Date formatter cache indices
typedef NS_ENUM(NSInteger, iTermTimestampFormatterType) {
    iTermTimestampFormatterTypeWithinDay = 0,      // jj:mm:ss
    iTermTimestampFormatterTypeWithinWeek = 1,     // EEE jj:mm:ss
    iTermTimestampFormatterTypeWithinHalfYear = 2, // MMMd jj:mm:ss
    iTermTimestampFormatterTypeOlder = 3,          // yyyyMMMd jj:mm:ss
    iTermTimestampFormatterTypeCount = 4
};

static NSDateFormatter *sDateFormatterCache[iTermTimestampFormatterTypeCount];
static id sLocaleChangeObserver;

static void iTermTimestampDrawHelperInvalidateCache(void) {
    for (int i = 0; i < iTermTimestampFormatterTypeCount; i++) {
        sDateFormatterCache[i] = nil;
    }
}

static NSDateFormatter *iTermTimestampDrawHelperGetCachedFormatter(iTermTimestampFormatterType type) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sLocaleChangeObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSCurrentLocaleDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification * _Nonnull note) {
            iTermTimestampDrawHelperInvalidateCache();
        }];
    });

    NSDateFormatter *cached = sDateFormatterCache[type];
    if (cached) {
        return cached;
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    NSString *template;
    switch (type) {
        case iTermTimestampFormatterTypeWithinDay:
            template = @"jj:mm:ss";
            break;
        case iTermTimestampFormatterTypeWithinWeek:
            template = @"EEE jj:mm:ss";
            break;
        case iTermTimestampFormatterTypeWithinHalfYear:
            template = @"MMMd jj:mm:ss";
            break;
        case iTermTimestampFormatterTypeOlder:
            template = @"yyyyMMMd jj:mm:ss";
            break;
        default:
            template = @"jj:mm:ss";
            break;
    }
    [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:template
                                                       options:0
                                                        locale:[NSLocale currentLocale]]];
    sDateFormatterCache[type] = fmt;
    return fmt;
}

@interface iTermTimestampRow : NSObject
@property (nonatomic, strong) NSString *string;
@property (nonatomic) int line;
@property (nonatomic) NSTimeInterval delta;
@end

@implementation iTermTimestampRow
@end

@implementation iTermTimestampDrawHelper {
    NSColor *_bgColor;
    NSColor *_fgColor;
    NSTimeInterval _now;
    BOOL _useTestingTimezone;
    CGFloat _rowHeight;
    BOOL _isRetina;
    CGFloat _obscured;
    NSMutableArray<iTermTimestampRow *> *_rows;
    BOOL _fontIsFixedPitch;
    NSSize _fontPitch;
}

- (instancetype)initWithBackgroundColor:(NSColor *)backgroundColor
                              textColor:(NSColor *)textColor
                                    now:(NSTimeInterval)now
                     useTestingTimezone:(BOOL)useTestingTimezone
                              rowHeight:(CGFloat)rowHeight
                                 retina:(BOOL)isRetina
                                   font:(NSFont *)font
                               obscured:(CGFloat)obscured {
    self = [super init];
    if (self) {
        _bgColor = backgroundColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
        _fgColor = textColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
        _now = now;
        _useTestingTimezone = useTestingTimezone;
        _rowHeight = rowHeight;
        _isRetina = isRetina;
        _rows = [NSMutableArray array];
        _obscured = obscured;
        self.font = font ?: [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
    }
    return self;
}

#pragma mark - Private

- (void)cacheFontPitch {
    _fontPitch = [self.font it_pitch];
}

#pragma mark - APIs

- (void)setFont:(NSFont *)font {
    _font = font;
    _fontIsFixedPitch = font.isFixedPitch;
    if (_fontIsFixedPitch) {
        [self cacheFontPitch];
    }
}

- (void)setDate:(NSDate *)timestamp forLine:(int)line {
    NSTimeInterval delta = 0;
    NSString *string = [self stringForTimestamp:timestamp
                                            now:_now
                             useTestingTimezone:_useTestingTimezone
                                          delta:&delta];
    const NSRect textFrame = [self frameForString:string line:line maxX:0 virtualOffset:0];
    _maximumWidth = MAX(_maximumWidth, NSWidth(textFrame));

    iTermTimestampRow *row = [[iTermTimestampRow alloc] init];
    row.string = string;
    row.line = line;
    row.delta = delta;
    [_rows addObject:row];
}

- (void)drawInContext:(NSGraphicsContext *)context
                frame:(NSRect)frame
        virtualOffset:(CGFloat)virtualOffset {
    [_rows enumerateObjectsUsingBlock:^(iTermTimestampRow * _Nonnull row, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRect stringFrame = [self frameForStringGivenWidth:self->_maximumWidth
                                                     height:[self fontHeight]
                                                       line:row.line
                                                       maxX:NSMaxX(frame)
                                              virtualOffset:virtualOffset];
        [self drawBackgroundInFrame:[self backgroundFrameForTextFrame:stringFrame]
                            bgColor:self->_bgColor
                            context:context];
    }];
    [_rows enumerateObjectsUsingBlock:^(iTermTimestampRow * _Nonnull row, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRect stringFrame = [self frameForStringGivenWidth:self->_maximumWidth
                                                     height:[self fontHeight]
                                                       line:row.line
                                                       maxX:NSMaxX(frame)
                                              virtualOffset:virtualOffset];
        [self drawString:row.string row:idx frame:stringFrame delta:row.delta];
    }];
}

- (void)drawRow:(int)index
      inContext:(NSGraphicsContext *)context
          frame:(NSRect)frameWithGradient
  virtualOffset:(CGFloat)virtualOffset {
    NSRect frame = frameWithGradient;
    frame.origin.x += iTermTimestampGradientWidth;
    frame.size.width -= iTermTimestampGradientWidth;

    iTermTimestampRow *row = _rows[index];
    NSRect stringFrame = [self frameForStringGivenWidth:_maximumWidth
                                                 height:[self fontHeight]
                                                   line:0
                                                   maxX:NSMaxX(frame)
                                          virtualOffset:virtualOffset];
    stringFrame.origin.y += frame.origin.y;
    [self drawBackgroundInFrame:[self backgroundFrameForTextFrame:stringFrame]
                        bgColor:_bgColor
                        context:context];
    [self drawString:row.string row:index frame:stringFrame delta:row.delta];
}

- (BOOL)rowIsRepeat:(int)index {
    if (index == 0) {
        return NO;
    }
    if (_rows[index - 1].string.length == 0) {
        return NO;
    }
    if (_obscured > 0 && _rowHeight * index <= _obscured) {
        return NO;
    }
    return [_rows[index - 1].string isEqual:_rows[index].string];
}

- (NSString *)stringForRow:(int)index {
    return _rows[index].string;
}

- (CGFloat)suggestedWidth {
    return _maximumWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins] + iTermTimestampGradientWidth;
}

#pragma mark - Draw Methods

- (void)drawBackgroundInFrame:(NSRect)frame
                      bgColor:(NSColor *)bgColor
                      context:(NSGraphicsContext *)context {
    const CGFloat alpha = 0.9;
    NSGradient *gradient =
    [[NSGradient alloc] initWithStartingColor:[bgColor colorWithAlphaComponent:0]
                                  endingColor:[bgColor colorWithAlphaComponent:alpha]];
    [context setCompositingOperation:NSCompositingOperationSourceOver];
    NSRect gradientFrame = frame;
    gradientFrame.size.width = iTermTimestampGradientWidth;
    [gradient drawInRect:gradientFrame
                   angle:0];

    NSRect solidFrame = frame;
    solidFrame.origin.x += iTermTimestampGradientWidth;
    solidFrame.size.width -= iTermTimestampGradientWidth;
    [[bgColor colorWithAlphaComponent:alpha] set];
    [context setCompositingOperation:NSCompositingOperationSourceOver];
    NSRectFillUsingOperation(solidFrame, NSCompositingOperationSourceOver);
}

- (NSColor *)tintedColor:(NSColor *)baseColor delta:(NSTimeInterval)delta {
    const CGFloat x = fabs(delta);
    // This is a "finite Prony series". It converges montonotically to 1 as x->infinity. The slope
    // is positive for x>=0 and the slope itself is strictly decreasing.
    // It is also globally concave.
    // It also doesn't get NaNs or infinities for big x.
    // Furthermore it gets us nice values in the domain we care most about:
    // f(0) = 0
    // f(60) ≅ 0.25
    // f(86400) ≅ 0.5
    // f(2,500,000) ≅ 0.9
    const CGFloat amount = 1.0 - 0.35755 * exp(-0.02 * x) - 0.20831 * exp(-0.00001 * x) - 0.43413 * exp(-0.0000006 * x);
    if (delta > 0) {
        return [baseColor colorByShiftingTowardsColor:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] amount:amount];
    } else {
        return [baseColor colorByShiftingTowardsColor:[NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1] amount:amount];
    }
}

- (void)drawString:(NSString *)s
               row:(int)index
             frame:(NSRect)frame
             delta:(NSTimeInterval)delta {
    NSColor *color = _fgColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
    NSDictionary *attributes = [self attributesForTextColor:[self tintedColor:color delta:delta]
                                                     shadow:[self shadowForTextColor:color ?: [NSColor colorWithRed:1 green:1 blue:1 alpha:1]]
                                                     retina:_isRetina];
    const BOOL repeat = [self rowIsRepeat:index];
    if (s.length && repeat) {
        [color set];
        const CGFloat center = NSMinX(frame) + 10;
        const NSRect backgroundFrame = [self backgroundFrameForTextFrame:frame];
        NSRectFill(NSMakeRect(center - 1, NSMinY(backgroundFrame), 1, _rowHeight));
        NSRectFill(NSMakeRect(center + 1, NSMinY(backgroundFrame), 1, _rowHeight));
    } else {
        [NSGraphicsContext saveGraphicsState];
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
        CGContextSetShouldSmoothFonts(ctx, NO);
        [s drawAtPoint:frame.origin withAttributes:attributes];
        [NSGraphicsContext restoreGraphicsState];
    }
}

#pragma mark - Pixel Arithmetic

- (NSRect)backgroundFrameForTextFrame:(NSRect)frame {
    return NSMakeRect(NSMinX(frame) - iTermTimestampGradientWidth,
                      NSMinY(frame) - [self retinaRound:(_rowHeight - [self fontHeight]) / 2.0],
                      NSWidth(frame) + iTermTimestampGradientWidth,
                      NSHeight(frame));
}

- (NSRect)frameForString:(NSString *)s line:(int)line maxX:(CGFloat)maxX virtualOffset:(CGFloat)virtualOffset {
    NSSize size;
    if (_fontIsFixedPitch) {
        size = NSMakeSize(_fontPitch.width * s.length, _fontPitch.height);
    } else {
        NSDictionary *attributes = @{ NSFontAttributeName: _font };
        NSString *widest = [s stringByReplacingOccurrencesOfRegex:@"[\\d\\p{Alphabetic}]" withString:@"M"];
        size = [widest it_cachingSizeWithAttributes:attributes];
    }

    return [self frameForStringGivenWidth:size.width
                                   height:[self fontHeight]
                                     line:line
                                     maxX:maxX
                            virtualOffset:virtualOffset];
}

- (CGFloat)fontHeight {
    return self.font.capHeight - self.font.descender;
}

- (NSRect)frameForStringGivenWidth:(CGFloat)width
                            height:(CGFloat)height
                              line:(int)line
                              maxX:(CGFloat)maxX
                     virtualOffset:(CGFloat)virtualOffset {
    const int w = width + [iTermPreferences intForKey:kPreferenceKeySideMargins];
    const int x = MAX(0, maxX - w);
    const CGFloat y = line * _rowHeight - virtualOffset + [self retinaRound:(_rowHeight - height) / 2.0];

    return NSMakeRect(x, y, w, _rowHeight);
}

- (CGFloat)retinaRound:(CGFloat)y {
    if (_isRetina) {
        return round(y * 2.0) / 2.0;
    }
    return round(y);
}

#pragma mark - String Diddling

- (NSDateFormatter *)dateFormatterWithTimeDelta:(NSTimeInterval)timeDelta
                             useTestingTimezone:(BOOL)useTestingTimezone {
    const NSTimeInterval day = -86400;
    iTermTimestampFormatterType type;
    if (timeDelta < day * 180) {
        // More than 180 days ago: include year
        // I tried using 365 but it was pretty confusing to see tomorrow's date.
        type = iTermTimestampFormatterTypeOlder;
    } else if (timeDelta < day * 6) {
        // 6 days to 180 days ago: include date without year
        type = iTermTimestampFormatterTypeWithinHalfYear;
    } else if (timeDelta < day) {
        // 1 day to 6 days ago: include day of week
        type = iTermTimestampFormatterTypeWithinWeek;
    } else {
        // In last 24 hours, just show time
        type = iTermTimestampFormatterTypeWithinDay;
    }

    if (useTestingTimezone) {
        // Don't cache testing timezone formatters - this code path is rarely used
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:[iTermTimestampDrawHelperGetCachedFormatter(type) dateFormat]];
        fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        return fmt;
    }

    return iTermTimestampDrawHelperGetCachedFormatter(type);
}

- (NSString *)relativeStringForTimestamp:(NSTimeInterval)timestamp {
    const NSTimeInterval delta = timestamp - self.timestampBaseline;
    return [NSDateFormatter highResolutionCompactRelativeTimeStringFromSeconds:delta];
}

- (NSString *)stringForTimestamp:(NSDate *)timestamp
                             now:(NSTimeInterval)now
              useTestingTimezone:(BOOL)useTestingTimezone
                           delta:(NSTimeInterval *)deltaPtr {
    *deltaPtr = 0;
    if (!timestamp) {
        return @"";
    }
    if (self.timestampBaseline != 0) {
        *deltaPtr = timestamp.timeIntervalSinceReferenceDate - self.timestampBaseline;
        return [self relativeStringForTimestamp:timestamp.timeIntervalSinceReferenceDate];
    }
    const NSTimeInterval timeSinceReference = round(timestamp.timeIntervalSinceReferenceDate);
    if (!timeSinceReference) {
        return @"";
    }
    const NSTimeInterval timeDelta = timeSinceReference - now;
    *deltaPtr = timeDelta;
    NSDateFormatter *fmt = [self dateFormatterWithTimeDelta:timeDelta
                                         useTestingTimezone:useTestingTimezone];
    NSDate *rounded = [NSDate dateWithTimeIntervalSinceReferenceDate:timeSinceReference];
    NSString *formattedString = [fmt stringFromDate:rounded];
    DLog(@"%@ -> %@", timestamp, formattedString);
    return formattedString;
}

- (NSDictionary *)attributesForTextColor:(NSColor *)fgColor shadow:(NSShadow *)shadow retina:(BOOL)retina {
    NSDictionary *attributes;
    if (retina) {
        attributes = @{ NSFontAttributeName: self.font ?: [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]],
                        NSForegroundColorAttributeName: fgColor,
                        NSShadowAttributeName: shadow };
    } else {
        NSFont *defaultFont = [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
        NSFont *font = self.font ?: defaultFont;
        font = [[NSFontManager sharedFontManager] fontWithFamily:font.familyName
                                                          traits:NSBoldFontMask
                                                          weight:0
                                                            size:font.pointSize];
        attributes = @{ NSFontAttributeName: font ?: defaultFont,
                        NSForegroundColorAttributeName: fgColor ?: [NSColor colorWithDisplayP3Red:1 green:1 blue:1 alpha:1] };
    }

    return attributes;
}

#pragma mark - Colors

- (NSColor *)shadowColorForTextColor:(NSColor *)fgColor {
    if ([fgColor isDark]) {
        return [NSColor whiteColor];
    } else {
        return [NSColor blackColor];
    }
}

- (NSShadow *)shadowForTextColor:(NSColor *)fgColor {
    NSColor *shadowColor = [self shadowColorForTextColor:fgColor];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = shadowColor;
    shadow.shadowBlurRadius = 0.2f;
    shadow.shadowOffset = CGSizeMake(0.5, -0.5);
    return shadow;
}

@end

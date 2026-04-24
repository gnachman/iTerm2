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
#import "iTermCache.h"
#import "iTermPreferences.h"
#import "iTermVirtualOffset.h"
#import "NSColor+iTerm.h"
#import "NSFont+iTerm.h"
#import "PTYFontInfo.h"
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
static iTermCache<NSNumber *, NSString *> *sTimestampStringCache[iTermTimestampFormatterTypeCount];
static id sLocaleChangeObserver;

static void iTermTimestampDrawHelperInvalidateCache(void) {
    for (int i = 0; i < iTermTimestampFormatterTypeCount; i++) {
        sDateFormatterCache[i] = nil;
        sTimestampStringCache[i] = nil;
    }
}

static void iTermTimestampDrawHelperInitializeIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (int i = 0; i < iTermTimestampFormatterTypeCount; i++) {
            sTimestampStringCache[i] = [[iTermCache alloc] initWithCapacity:1000];
        }
        sLocaleChangeObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSCurrentLocaleDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification * _Nonnull note) {
            iTermTimestampDrawHelperInvalidateCache();
        }];
    });
}

static iTermTimestampFormatterType iTermTimestampFormatterTypeForTimeDelta(NSTimeInterval timeDelta) {
    const NSTimeInterval day = -86400;
    if (timeDelta < day * 180) {
        return iTermTimestampFormatterTypeOlder;
    } else if (timeDelta < day * 6) {
        return iTermTimestampFormatterTypeWithinHalfYear;
    } else if (timeDelta < day) {
        return iTermTimestampFormatterTypeWithinWeek;
    } else {
        return iTermTimestampFormatterTypeWithinDay;
    }
}

static NSDateFormatter *iTermTimestampDrawHelperGetCachedFormatter(iTermTimestampFormatterType type) {
    iTermTimestampDrawHelperInitializeIfNeeded();

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

// Returns a cached formatted string for the given timestamp rounded to seconds.
// The cache is partitioned by formatter type to handle timestamps aging across format boundaries.
static NSString *iTermTimestampDrawHelperGetCachedString(NSTimeInterval roundedTimestamp,
                                                          iTermTimestampFormatterType type) {
    iTermTimestampDrawHelperInitializeIfNeeded();

    NSNumber *key = @(roundedTimestamp);
    NSString *cached = sTimestampStringCache[type][key];
    if (cached) {
        return cached;
    }

    NSDateFormatter *fmt = iTermTimestampDrawHelperGetCachedFormatter(type);
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:roundedTimestamp];
    NSString *formatted = [fmt stringFromDate:date];
    sTimestampStringCache[type][key] = formatted;
    return formatted;
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
    CGFloat _rowHeightWithoutSpacing;
    BOOL _isRetina;
    CGFloat _obscured;
    NSMutableArray<iTermTimestampRow *> *_rows;
    BOOL _fontIsFixedPitch;
    NSSize _fontPitch;
    CGFloat _baselineOffset;
}

- (instancetype)initWithBackgroundColor:(NSColor *)backgroundColor
                              textColor:(NSColor *)textColor
                                    now:(NSTimeInterval)now
                     useTestingTimezone:(BOOL)useTestingTimezone
                              rowHeight:(CGFloat)rowHeight
              rowHeightWithoutSpacing:(CGFloat)rowHeightWithoutSpacing
                                 retina:(BOOL)isRetina
                               fontInfo:(PTYFontInfo *)fontInfo
                               obscured:(CGFloat)obscured {
    self = [super init];
    if (self) {
        _bgColor = backgroundColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
        _fgColor = textColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
        _now = now;
        _useTestingTimezone = useTestingTimezone;
        _rowHeight = rowHeight;
        _rowHeightWithoutSpacing = rowHeightWithoutSpacing;
        _isRetina = isRetina;
        _rows = [NSMutableArray array];
        _obscured = obscured;
        _baselineOffset = fontInfo.baselineOffset;
        self.font = fontInfo.font ?: [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
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
    const NSRect textFrame = [self frameForString:string line:line maxX:0];
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
                                                       maxX:NSMaxX(frame)];
        [self drawBackgroundInFrame:[self backgroundFrameForTextFrame:stringFrame]
                            bgColor:self->_bgColor
                            context:context
                      virtualOffset:virtualOffset];
    }];
    [_rows enumerateObjectsUsingBlock:^(iTermTimestampRow * _Nonnull row, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRect stringFrame = [self frameForStringGivenWidth:self->_maximumWidth
                                                     height:[self fontHeight]
                                                       line:row.line
                                                       maxX:NSMaxX(frame)];
        [self drawString:row.string row:idx frame:stringFrame delta:row.delta virtualOffset:virtualOffset];
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
                                                   maxX:NSMaxX(frame)];
    stringFrame.origin.y += frame.origin.y;
    [self drawBackgroundInFrame:[self backgroundFrameForTextFrame:stringFrame]
                        bgColor:_bgColor
                        context:context
                  virtualOffset:virtualOffset];
    [self drawString:row.string row:index frame:stringFrame delta:row.delta virtualOffset:virtualOffset];
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
                      context:(NSGraphicsContext *)context
                virtualOffset:(CGFloat)virtualOffset {
    const CGFloat alpha = 0.9;
    NSGradient *gradient =
    [[NSGradient alloc] initWithStartingColor:[bgColor colorWithAlphaComponent:0]
                                  endingColor:[bgColor colorWithAlphaComponent:alpha]];
    [context setCompositingOperation:NSCompositingOperationSourceOver];
    NSRect gradientFrame = NSRectSubtractingVirtualOffset(frame, virtualOffset);
    gradientFrame.size.width = iTermTimestampGradientWidth;
    [gradient drawInRect:gradientFrame
                   angle:0];

    NSRect solidFrame = NSRectSubtractingVirtualOffset(frame, virtualOffset);
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
             delta:(NSTimeInterval)delta
     virtualOffset:(CGFloat)virtualOffset {
    NSColor *color = _fgColor ?: [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
    NSDictionary *attributes = [self attributesForTextColor:[self tintedColor:color delta:delta]
                                                     shadow:[self shadowForTextColor:color ?: [NSColor colorWithRed:1 green:1 blue:1 alpha:1]]
                                                     retina:_isRetina];
    const BOOL repeat = [self rowIsRepeat:index];
    if (s.length && repeat) {
        [color set];
        const CGFloat center = NSMinX(frame) + 10;
        const NSRect backgroundFrame = [self backgroundFrameForTextFrame:frame];
        iTermRectFill(NSMakeRect(center - 1, NSMinY(backgroundFrame), 1, _rowHeight), virtualOffset);
        iTermRectFill(NSMakeRect(center + 1, NSMinY(backgroundFrame), 1, _rowHeight), virtualOffset);
    } else {
        [NSGraphicsContext saveGraphicsState];
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
        CGContextSetShouldSmoothFonts(ctx, NO);
        [s it_drawAtPoint:frame.origin withAttributes:attributes virtualOffset:virtualOffset];
        [NSGraphicsContext restoreGraphicsState];
    }
}

#pragma mark - Pixel Arithmetic

- (CGFloat)lineRelativeOffset {
    const CGFloat spacingAdjustment = round((_rowHeight - _rowHeightWithoutSpacing) / 2.0);
    const CGFloat fontHeight = self.font.ascender - self.font.descender;
    return _rowHeight + _baselineOffset - fontHeight - spacingAdjustment;
}

- (NSRect)backgroundFrameForTextFrame:(NSRect)frame {
    const CGFloat rowTop = frame.origin.y - self.lineRelativeOffset;

    return NSMakeRect(NSMinX(frame) - iTermTimestampGradientWidth,
                      rowTop,
                      NSWidth(frame) + iTermTimestampGradientWidth,
                      _rowHeight);
}

- (NSRect)frameForString:(NSString *)s line:(int)line maxX:(CGFloat)maxX {
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
                                     maxX:maxX];
}

- (CGFloat)fontHeight {
    return self.font.ascender - self.font.descender;
}

- (NSRect)frameForStringGivenWidth:(CGFloat)width
                            height:(CGFloat)height
                              line:(int)line
                              maxX:(CGFloat)maxX {
    const int w = width + [iTermPreferences intForKey:kPreferenceKeySideMargins];
    const int x = MAX(0, maxX - w);
    const CGFloat y = line * _rowHeight + self.lineRelativeOffset;

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
    iTermTimestampFormatterType type = iTermTimestampFormatterTypeForTimeDelta(timeDelta);

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

    if (useTestingTimezone) {
        // Don't use cache for testing timezone - this code path is rarely used
        NSDateFormatter *fmt = [self dateFormatterWithTimeDelta:timeDelta
                                             useTestingTimezone:useTestingTimezone];
        NSDate *rounded = [NSDate dateWithTimeIntervalSinceReferenceDate:timeSinceReference];
        NSString *formattedString = [fmt stringFromDate:rounded];
        DLog(@"%@ -> %@", timestamp, formattedString);
        return formattedString;
    }

    iTermTimestampFormatterType type = iTermTimestampFormatterTypeForTimeDelta(timeDelta);
    NSString *formattedString = iTermTimestampDrawHelperGetCachedString(timeSinceReference, type);
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
